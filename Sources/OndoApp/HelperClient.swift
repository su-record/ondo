import Foundation
import OndoShared
import ServiceManagement

/// Registers the privileged helper with SMAppService and talks to it over XPC.
@MainActor
final class HelperClient {
    enum Status: String {
        case enabled, requiresApproval, notRegistered, notFound
    }

    /// How long one helper call may take before the app gives up on it.
    static let callTimeout: TimeInterval = 5

    private let service = SMAppService.daemon(plistName: Identity.helperPlistName)
    private var connection: NSXPCConnection?
    /// Called when the helper process went away mid-session (it restores sleep when it restarts).
    var onInterrupted: (() -> Void)?
    /// Keep the connection open between calls. Required while sleep is disabled: the helper restores
    /// sleep when this connection ends. Otherwise each call closes it, so an idle helper can exit.
    var holdConnection = false

    var status: Status {
        switch service.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .notRegistered
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }

    /// Registers the helper if needed. Returns the resulting status; the first registration needs the
    /// user's approval in System Settings › General › Login Items.
    func ensureRegistered() -> (Status, String?) {
        guard status == .notRegistered || status == .notFound else { return (status, nil) }
        do {
            try service.register()
        } catch {
            return (status, error.localizedDescription)
        }
        return (status, nil)
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func unregister() async -> String? {
        closeConnection()
        do { try await service.unregister() } catch { return error.localizedDescription }
        return nil
    }

    func setSleepDisabled(_ disabled: Bool) async -> String? {
        await call { $0.setSleepDisabled(disabled, reply: $1) }
    }

    func scheduleWake(at date: Date) async -> String? {
        await call { $0.scheduleWake(at: date, reply: $1) }
    }

    func cancelWakes() async -> String? {
        await call { $0.cancelWakes(reply: $1) }
    }

    /// Runs one helper call with a timeout. Returns an error message, or nil on success.
    private func call(_ body: @escaping (OndoHelperProtocol, @escaping (Bool, String?) -> Void) -> Void) async -> String? {
        guard status == .enabled else { return "helper not enabled (\(status.rawValue))" }
        let connection = currentConnection()
        let result: String? = await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.callTimeout) { once.resume("helper did not answer") }
            let proxy = connection.remoteObjectProxyWithErrorHandler { once.resume($0.localizedDescription) }
            guard let helper = proxy as? OndoHelperProtocol else { return once.resume("helper interface mismatch") }
            body(helper) { ok, error in once.resume(ok ? nil : (error ?? "helper call failed")) }
        }
        if !holdConnection { closeConnection() }
        return result
    }

    private func closeConnection() {
        connection?.invalidate()
        connection = nil
    }

    private func currentConnection() -> NSXPCConnection {
        if let connection { return connection }
        let connection = NSXPCConnection(machServiceName: Identity.helperID, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: OndoHelperProtocol.self)
        if let requirement = Identity.sameTeamRequirement(identifier: Identity.helperID) {
            connection.setCodeSigningRequirement(requirement)
        }
        connection.invalidationHandler = { [weak self] in Task { @MainActor in self?.connection = nil } }
        connection.interruptionHandler = { [weak self] in Task { @MainActor in self?.onInterrupted?() } }
        connection.resume()
        self.connection = connection
        return connection
    }
}

/// Resumes a continuation once; later calls (a late reply after a timeout) are ignored.
private final class ResumeOnce: @unchecked Sendable {
    private var continuation: CheckedContinuation<String?, Never>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: String?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

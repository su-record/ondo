import Foundation
import OndoShared

/// Accepts connections only from ondo.app signed by the same team, and remembers which connection
/// disabled sleep so that losing it restores sleep.
///
/// With no connection and sleep allowed, the helper exits after `idleExit`; launchd starts it again on the
/// next call. That way an updated app always talks to the helper binary it shipped with.
final class Helper: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    static let idleExit: TimeInterval = 10

    private let requirement: String
    /// Serializes pmset calls and the state below.
    private let queue = DispatchQueue(label: "\(Identity.helperID).state")
    private var holder: ObjectIdentifier?
    private var connections = 0
    private var idleTimer: DispatchWorkItem?

    init(requirement: String) {
        self.requirement = requirement
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: OndoHelperProtocol.self)
        let id = ObjectIdentifier(connection)
        connection.exportedObject = Session(helper: self, connection: id)
        connection.invalidationHandler = { [weak self] in self?.connectionEnded(id) }
        queue.sync {
            connections += 1
            idleTimer?.cancel()
        }
        connection.resume()
        return true
    }

    /// Starts the idle countdown, for a start with no caller (boot).
    func start() {
        queue.async { self.scheduleIdleExit() }
    }

    func setSleepDisabled(_ disabled: Bool, by connection: ObjectIdentifier) -> String? {
        queue.sync {
            let error = Power.setSleepDisabled(disabled)
            if error == nil { holder = disabled ? connection : nil }
            log.notice("sleep \(disabled ? "disabled" : "allowed", privacy: .public)\(error.map { ": \($0)" } ?? "", privacy: .public)")
            return error
        }
    }

    private func connectionEnded(_ connection: ObjectIdentifier) {
        queue.sync {
            connections -= 1
            if holder == connection {
                holder = nil
                let error = Power.setSleepDisabled(false)
                log.notice("app connection ended; sleep allowed\(error.map { ": \($0)" } ?? "", privacy: .public)")
            }
            scheduleIdleExit()
        }
    }

    /// Runs on `queue`.
    private func scheduleIdleExit() {
        guard connections == 0, holder == nil else { return }
        idleTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in
            guard let self, self.connections == 0, self.holder == nil else { return }
            log.notice("idle; exiting")
            exit(0)
        }
        idleTimer = timer
        queue.asyncAfter(deadline: .now() + Self.idleExit, execute: timer)
    }
}

/// One connection's view of the helper.
final class Session: NSObject, OndoHelperProtocol {
    private let helper: Helper
    private let connection: ObjectIdentifier

    init(helper: Helper, connection: ObjectIdentifier) {
        self.helper = helper
        self.connection = connection
    }

    func setSleepDisabled(_ disabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        let error = helper.setSleepDisabled(disabled, by: connection)
        reply(error == nil, error)
    }

    func scheduleWake(at date: Date, reply: @escaping (Bool, String?) -> Void) {
        let error = Power.scheduleWake(at: date)
        log.notice("wake at \(date, privacy: .public)\(error.map { ": \($0)" } ?? "", privacy: .public)")
        reply(error == nil, error)
    }

    func cancelWakes(reply: @escaping (Bool, String?) -> Void) {
        let error = Power.cancelWakes()
        reply(error == nil, error)
    }

    func version(reply: @escaping (String) -> Void) {
        reply(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")
    }
}

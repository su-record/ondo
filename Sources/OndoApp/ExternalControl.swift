import Foundation
import OndoCore
import OndoSensors

/// Requests from the CLI, the MCP server and ondo:// links. They can turn staying awake on and off,
/// schedule wakes and read state; settings stay in the app.
extension Controller {
    func handle(_ request: ControlRequest) async -> ControlResponse {
        switch request.command {
        case .status:
            await refreshIfStale()
            return ControlResponse(ok: true, status: status())
        case .on:
            let end: EndTime?
            do { end = try request.endTime() } catch { return ControlResponse(ok: false, error: "\(error)") }
            return response(for: await start(end ?? settings.defaultEnd))
        case .off:
            await stop(.user)
            return ControlResponse(ok: !awake, error: awake ? notice : nil, status: status())
        case .sensors:
            return ControlResponse(ok: true, sensors: await allSensorReadings())
        case .displayOff:
            let error = SystemInfo.displayOff()
            return ControlResponse(ok: error == nil, error: error)
        case .wake:
            return await wake(request)
        }
    }

    private func wake(_ request: ControlRequest) async -> ControlResponse {
        if request.cancel == true {
            await cancelWake()
            return ControlResponse(ok: true, status: status())
        }
        let date: Date?
        do {
            date = try request.endTime()?.date(from: Date())
        } catch {
            return ControlResponse(ok: false, error: "\(error)")
        }
        guard let date else { return ControlResponse(ok: false, error: "wake needs minutes, until or cancel") }
        let error = await scheduleWake(at: date)
        return ControlResponse(ok: error == nil, error: error, status: status())
    }

    private func response(for result: StartResult) -> ControlResponse {
        switch result {
        case .started: return ControlResponse(ok: true, status: status())
        case .refused(let reason): return ControlResponse(ok: false, refusal: reason, status: status())
        case .needsHelperApproval:
            return ControlResponse(ok: false, error: "allow ondo in System Settings › General › Login Items", status: status())
        case .failed(let error): return ControlResponse(ok: false, error: error, status: status())
        }
    }

    func status() -> OndoStatus {
        OndoStatus(awake: awake, endsAt: endsAt, cpu: temperatures?.cpu, battery: temperatures?.battery,
                   cpuLimit: settings.cpuLimit, batteryLimit: settings.batteryLimit, power: power, lidClosed: lidClosed,
                   warning: warning?.reason, secondsUntilStop: warning?.secondsUntilStop, helper: helperStatus.rawValue,
                   wakeAt: wakePlan?.at, lastStop: lastStop, simulated: simulation != nil)
    }

    /// ondo://on?for=90m, ondo://on?until=07:30, ondo://off, ondo://display-off,
    /// ondo://wake?in=30m, ondo://wake?at=07:00, ondo://wake?cancel
    func handle(url: URL) async {
        guard url.scheme == "ondo", let request = Self.request(from: url) else {
            return note("ignored link: \(url.absoluteString)")
        }
        let response = await handle(request)
        guard !response.ok else { return }
        let reason = response.refusal.map(L.reason) ?? response.error ?? L.t("실패", "Failed")
        notice = reason
        Notifier.shared.post(id: "link", title: L.t("ondo · 요청을 처리하지 못함", "ondo · Request not done"), body: reason)
    }

    static func request(from url: URL) -> ControlRequest? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch url.host {
        case "on":
            let text = value("for")
            let minutes = text.flatMap(EndTime.minutes(from:))
            // A duration that is present but unreadable rejects the link rather than falling back to the default.
            if text != nil && minutes == nil { return nil }
            return ControlRequest(command: .on, minutes: minutes, until: value("until"))
        case "off":
            return ControlRequest(command: .off)
        case "display-off":
            return ControlRequest(command: .displayOff)
        case "wake":
            if items.contains(where: { $0.name == "cancel" }) { return ControlRequest(command: .wake, cancel: true) }
            let text = value("in")
            let minutes = text.flatMap(EndTime.minutes(from:))
            if text != nil && minutes == nil { return nil }
            return ControlRequest(command: .wake, minutes: minutes, until: value("at"))
        default:
            return nil
        }
    }
}

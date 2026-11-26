import AppKit
import Foundation
import OndoCore
import OndoSensors
import OndoShared
import os

/// The app's state: whether the Mac is kept awake, the latest readings and what protection decided.
/// Turning on and off lives here; monitoring, wake plans and external control are extensions in other files.
@MainActor
final class Controller: ObservableObject {
    static let tickInterval: TimeInterval = 2
    /// Polling while off with the menu closed: enough to keep the menu bar thermometer current.
    static let idleTickInterval: TimeInterval = 10
    static let logLimit = 50
    static let settingsKey = "settings"

    struct Warning: Equatable {
        let reason: StopReason
        let secondsUntilStop: Int?
        let processes: [SystemInfo.BusyProcess]
    }

    enum StartResult: Equatable {
        case started
        case refused(StopReason)
        case needsHelperApproval
        case failed(String)
    }

    @Published private(set) var awake = false
    @Published var endsAt: Date?
    /// The end the menu's picker shows; while awake, changing it moves the end.
    @Published var endChoice: EndTime {
        didSet { if awake { endsAt = endChoice.date(from: Date()) } }
    }
    @Published var temperatures: Temperatures?
    @Published var power = SystemInfo.power()
    @Published var lidClosed = SystemInfo.lidClosed()
    @Published var warning: Warning?
    @Published var lastStop: StopReason?
    /// The latest refusal or error, shown in the menu until the next successful action.
    @Published var notice: String?
    @Published var helperStatus: HelperClient.Status
    @Published var wakePlan: WakePlan?
    @Published var simulation: Simulation?
    @Published private(set) var log: [String] = []
    @Published var settings: Settings {
        didSet { saveSettings() }
    }
    var menuOpen = false {
        didSet { updateTimer() }
    }

    let helper = HelperClient()
    let reader = SensorReader()
    let sensorQueue = DispatchQueue(label: "\(Identity.appBundleID).sensors")
    var cpuGuard = HeatGuard()
    var batteryGuard = HeatGuard()
    var previousPower: PowerState?
    var lastTick: Date?
    var lastRefresh: Date?
    var ticking = false
    private var timer: Timer?
    private let logger = Logger(subsystem: Identity.appBundleID, category: "app")

    init() {
        let stored = UserDefaults.standard.data(forKey: Self.settingsKey)
        let settings = stored.flatMap { try? JSONDecoder().decode(Settings.self, from: $0) }?.clamped() ?? Settings()
        self.settings = settings
        self.endChoice = settings.defaultEnd
        self.helperStatus = helper.status
        helper.onInterrupted = { [weak self] in self?.helperInterrupted() }
    }

    /// At launch: restore sleep if an earlier run left it disabled, and drop wakes no running app will handle.
    func launch() async {
        Notifier.shared.setUp()
        if helper.status == .enabled {
            if SystemInfo.sleepDisabled() {
                note("sleep was still disabled at launch; restoring")
                if let error = await helper.setSleepDisabled(false) { note("restore failed: \(error)") }
            }
            _ = await helper.cancelWakes()
        }
        await refresh()
    }

    // MARK: Turning on and off

    /// Starts with `end` and shows it in the menu's picker, so a later change there moves this session's end.
    func start(_ end: EndTime) async -> StartResult {
        let result = await start(endsAt: end.date(from: Date()))
        if result == .started { endChoice = end }
        return result
    }

    func start(endsAt requested: Date?) async -> StartResult {
        await refresh()
        if let refusal = Protection.startRefusal(cpu: temperatures?.cpu, battery: temperatures?.battery, power: power, settings: settings) {
            notice = L.t("켤 수 없음: ", "Cannot turn on: ") + L.reason(refusal)
            note("start refused: \(refusal.rawValue)")
            return .refused(refusal)
        }
        let (status, registerError) = helper.ensureRegistered()
        helperStatus = status
        guard status == .enabled else {
            notice = L.t("시스템 설정 › 일반 › 로그인 항목에서 ondo를 허용해 주세요.",
                         "Allow ondo in System Settings › General › Login Items.")
            note("helper \(status.rawValue)\(registerError.map { ": \($0)" } ?? "")")
            // Waiting for approval makes register() throw "Operation not permitted"; that is not a failure.
            if status == .requiresApproval { return .needsHelperApproval }
            return registerError.map { .failed($0) } ?? .needsHelperApproval
        }
        // The open connection is the helper's sign that ondo is alive; it restores sleep if it closes.
        helper.holdConnection = true
        if let error = await helper.setSleepDisabled(true) {
            helper.holdConnection = false
            notice = error
            note("start failed: \(error)")
            return .failed(error)
        }
        awake = true
        endsAt = requested
        previousPower = power
        cpuGuard.reset()
        batteryGuard.reset()
        warning = nil
        lastStop = nil
        notice = nil
        if case .afterOverheat = wakePlan?.kind { await cancelWake() }
        note("on" + (requested.map { " until \(L.clock($0))" } ?? ", no end"))
        updateTimer()
        return .started
    }

    func stop(_ reason: StopReason) async {
        guard awake else { return }
        let sessionEnd = endsAt
        helper.holdConnection = false
        if let error = await helper.setSleepDisabled(false) {
            // Closing the connection makes the helper restore sleep if it is alive; stay "on" so the next
            // tick checks again, and say so.
            helper.holdConnection = true
            notice = L.t("잠자기 설정을 되돌리지 못했습니다: ", "Could not restore sleep: ") + error
            note("stop (\(reason.rawValue)) failed: \(error)")
            return
        }
        awake = false
        endsAt = nil
        warning = nil
        lastStop = reason
        cpuGuard.reset()
        batteryGuard.reset()
        note("off: \(reason.rawValue)")
        if reason != .user && reason != .quit { announceStop(reason) }
        if reason.isOverheat, settings.resumeAfterOverheat { await planResume(attempt: 1, endsAt: sessionEnd) }
        if reason.putsClosedMacToSleep, SystemInfo.lidClosed() == true { sleepNow() }
        updateTimer()
    }

    /// Before quitting or powering off: allow sleep and drop wakes nobody will handle.
    func shutdown() async {
        if helper.status == .enabled, awake || SystemInfo.sleepDisabled() {
            helper.holdConnection = false
            if let error = await helper.setSleepDisabled(false) { note("restore at quit failed: \(error)") }
            awake = false
        }
        if wakePlan != nil { await cancelWake() }
    }

    func sleepNow() {
        if let error = SystemInfo.sleepNow() { note(error) } else { note("put to sleep") }
    }

    private func announceStop(_ reason: StopReason) {
        let lid = SystemInfo.lidClosed() == true
        let body = lid ? L.t("뚜껑이 닫혀 있어 맥을 재웁니다.", "The lid is closed, so the Mac goes to sleep.")
                       : L.t("깨어있기를 껐습니다. 이제 평소대로 잠들 수 있습니다.", "Staying awake is off; the Mac can sleep as usual.")
        Notifier.shared.post(id: "stop", title: "ondo · " + L.reason(reason), body: body)
    }

    private func helperInterrupted() {
        note("helper connection interrupted")
        guard awake else { return }
        // The helper restores sleep when it restarts; ask again so staying awake continues.
        Task { if let error = await helper.setSleepDisabled(true) { note("re-enable after interruption failed: \(error)") } }
    }

    // MARK: Timer, settings, log

    func updateTimer() {
        let interval = (awake || menuOpen || simulation != nil) ? Self.tickInterval : Self.idleTickInterval
        if timer?.timeInterval == interval { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        if menuOpen { Task { await refresh() } }
    }

    private func saveSettings() {
        let clamped = settings.clamped()
        guard clamped == settings else { settings = clamped; return }
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: Self.settingsKey) }
    }

    func note(_ text: String) {
        logger.notice("\(text, privacy: .public)")
        log.append("\(L.clock(Date())) \(text)")
        if log.count > Self.logLimit { log.removeFirst(log.count - Self.logLimit) }
    }
}

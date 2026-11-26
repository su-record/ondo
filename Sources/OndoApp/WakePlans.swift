import Foundation
import OndoCore

/// A scheduled system wake and what to do when it comes.
struct WakePlan: Equatable {
    enum Kind: Equatable {
        /// The user asked to wake the Mac and keep it awake again.
        case scheduled
        /// ondo stopped for heat; check again and resume if the Mac has cooled.
        case afterOverheat(attempt: Int, endsAt: Date?)
    }

    /// A wake can land slightly before its time; treat it as due within this margin.
    /// Must stay well under the shortest wait (1 minute), or a plan would count as due the moment it is made.
    static let earlyMargin: TimeInterval = 5

    let at: Date
    let kind: Kind
}

extension Controller {
    func scheduleWake(at date: Date) async -> String? {
        let (status, error) = helper.ensureRegistered()
        helperStatus = status
        guard status == .enabled else { return error ?? "helper not enabled (\(status.rawValue))" }
        _ = await helper.cancelWakes()
        if let error = await helper.scheduleWake(at: date) {
            note("wake not scheduled: \(error)")
            return error
        }
        wakePlan = WakePlan(at: date, kind: .scheduled)
        note("wake scheduled at \(L.clock(date))")
        updateTimer()
        return nil
    }

    func cancelWake() async {
        if let error = await helper.cancelWakes() { note("cancel wake failed: \(error)") }
        wakePlan = nil
        updateTimer()
    }

    /// After an overheat stop: wake later to check whether the Mac has cooled.
    func planResume(attempt: Int, endsAt: Date?) async {
        let at = Date().addingTimeInterval(TimeInterval(settings.resumeWaitMinutes * 60))
        if let endsAt, endsAt <= at { return note("no resume: the session would have ended by then") }
        // One plan at a time: drop any earlier ondo wake before adding this one.
        _ = await helper.cancelWakes()
        if let error = await helper.scheduleWake(at: at) { return note("resume wake not scheduled: \(error)") }
        wakePlan = WakePlan(at: at, kind: .afterOverheat(attempt: attempt, endsAt: endsAt))
        note("resume check \(attempt)/\(Protection.maxResumeAttempts) at \(L.clock(at))")
        updateTimer()
    }

    func didWake() async {
        note("system woke")
        lastTick = nil
        await refresh()
        await checkWakePlan(now: Date())
    }

    /// Runs a due wake plan, whether the Mac was woken by it or was already awake.
    func checkWakePlan(now: Date) async {
        guard let plan = wakePlan, now >= plan.at.addingTimeInterval(-WakePlan.earlyMargin) else { return }
        wakePlan = nil
        // The plan's wake event may still be pending if the Mac was already awake; it has done its job.
        _ = await helper.cancelWakes()
        updateTimer()
        switch plan.kind {
        case .scheduled:
            guard !awake else { return }
            let result = await start(settings.defaultEnd)
            if result != .started { announceResumeFailure(result) }
        case .afterOverheat(let attempt, let endsAt):
            await resumeAfterOverheat(attempt: attempt, endsAt: endsAt, now: now)
        }
    }

    private func resumeAfterOverheat(attempt: Int, endsAt: Date?, now: Date) async {
        if let endsAt, endsAt <= now { return note("no resume: the session's end time has passed") }
        await refresh()
        if Protection.cooledEnoughToResume(cpu: temperatures?.cpu, battery: temperatures?.battery, settings: settings) {
            let result = await start(endsAt: endsAt)
            if result == .started {
                Notifier.shared.post(id: "resume", title: L.t("ondo · 다시 깨어있기", "ondo · Awake again"),
                                     body: L.t("식은 것을 확인하고 다시 켰습니다.", "The Mac has cooled down, so staying awake is back on."))
            } else {
                announceResumeFailure(result)
            }
            return
        }
        if attempt < Protection.maxResumeAttempts {
            await planResume(attempt: attempt + 1, endsAt: endsAt)
        } else {
            note("gave up resuming after \(attempt) checks")
            Notifier.shared.post(id: "resume", title: L.t("ondo · 다시 켜지 않음", "ondo · Not resuming"),
                                 body: L.t("\(attempt)번 확인했지만 충분히 식지 않았습니다.", "Checked \(attempt) times; the Mac did not cool down enough."))
        }
        if SystemInfo.lidClosed() == true { sleepNow() }
    }

    private func announceResumeFailure(_ result: StartResult) {
        let reason: String
        switch result {
        case .refused(let stop): reason = L.reason(stop)
        case .needsHelperApproval: reason = L.t("도우미 허용 필요", "Helper needs approval")
        case .failed(let error): reason = error
        case .started: return
        }
        note("resume failed: \(reason)")
        Notifier.shared.post(id: "resume", title: L.t("ondo · 다시 켜지 못함", "ondo · Could not resume"), body: reason)
        if SystemInfo.lidClosed() == true { sleepNow() }
    }
}

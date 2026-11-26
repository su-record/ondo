import Foundation

/// What the root helper accepts. There is no way to pass a command: each method maps to one fixed action.
@objc public protocol OndoHelperProtocol {
    /// Runs `pmset -a disablesleep 1` or `0`.
    func setSleepDisabled(_ disabled: Bool, reply: @escaping (_ ok: Bool, _ error: String?) -> Void)
    /// Schedules a system wake. The helper accepts only future times within `HelperLimits.maxWakeAhead`.
    func scheduleWake(at date: Date, reply: @escaping (_ ok: Bool, _ error: String?) -> Void)
    /// Cancels every wake ondo scheduled.
    func cancelWakes(reply: @escaping (_ ok: Bool, _ error: String?) -> Void)
    func version(reply: @escaping (String) -> Void)
}

public enum HelperLimits {
    public static let maxWakeAhead: TimeInterval = 24 * 60 * 60
    /// The scheduler name ondo's wake events carry, so ondo cancels only its own.
    public static let wakeScheduler = Identity.appBundleID
}

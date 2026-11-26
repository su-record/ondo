import Foundation

public struct PowerState: Codable, Equatable, Sendable {
    public var onAC: Bool
    /// Nil on a Mac without a battery.
    public var batteryPercent: Int?

    public init(onAC: Bool, batteryPercent: Int?) {
        self.onAC = onAC
        self.batteryPercent = batteryPercent
    }
}

/// Why staying awake ended, or why turning it on was refused.
public enum StopReason: String, Codable, Sendable {
    case user, timer, cpuHot, batteryHot, unplugged, batteryLow, quit

    /// Stops made by ondo's protection or timer; after these a closed Mac is put to sleep.
    public var putsClosedMacToSleep: Bool {
        switch self {
        case .timer, .cpuHot, .batteryHot, .unplugged, .batteryLow: return true
        case .user, .quit: return false
        }
    }

    public var isOverheat: Bool { self == .cpuHot || self == .batteryHot }
}

public enum Protection {
    /// Power changes that end staying awake. The unplug rule needs a change from AC to battery,
    /// so staying awake that started on battery is limited only by the battery floor.
    public static func powerStop(previous: PowerState?, current: PowerState, settings: Settings) -> StopReason? {
        if settings.stopOnUnplug, previous?.onAC == true, !current.onAC { return .unplugged }
        if !current.onAC, let percent = current.batteryPercent, percent < settings.batteryFloor { return .batteryLow }
        return nil
    }

    /// Why turning on must be refused right now, if at all.
    public static func startRefusal(cpu: Double?, battery: Double?, power: PowerState, settings: Settings) -> StopReason? {
        if let cpu, cpu >= settings.cpuLimit { return .cpuHot }
        if let battery, battery >= settings.batteryLimit { return .batteryHot }
        if !power.onAC, let percent = power.batteryPercent, percent < settings.batteryFloor { return .batteryLow }
        return nil
    }

    /// After an overheat stop, resume only once both temperatures are this far below their limits.
    public static let resumeMargin = 10.0
    public static let maxResumeAttempts = 3

    public static func cooledEnoughToResume(cpu: Double?, battery: Double?, settings: Settings) -> Bool {
        guard let cpu else { return false }
        if cpu > settings.cpuLimit - resumeMargin { return false }
        if let battery, battery > settings.batteryLimit - resumeMargin { return false }
        return true
    }
}

import Foundation

/// User settings. Values outside the ranges are clamped, so a stored or external value can never weaken protection
/// beyond what the settings screen allows.
public struct Settings: Codable, Equatable, Sendable {
    public static let cpuLimitRange = 60.0...105.0
    public static let batteryLimitRange = 35.0...60.0
    public static let sustainRange = 10...600
    public static let batteryFloorRange = 5...80
    public static let resumeWaitRange = 1...240

    /// °C. Above this for `sustainSeconds` ondo warns; for twice as long it stops staying awake.
    public var cpuLimit = 85.0
    public var batteryLimit = 45.0
    public var sustainSeconds = 60
    /// Percent. Below this on battery power ondo stops staying awake.
    public var batteryFloor = 20
    public var stopOnUnplug = true
    public var defaultEnd = EndTime.unlimited
    /// After an overheat stop, wake the Mac later and resume if it has cooled down.
    public var resumeAfterOverheat = false
    public var resumeWaitMinutes = 30

    public init() {}

    public func clamped() -> Settings {
        var s = self
        s.cpuLimit = s.cpuLimit.clamped(to: Self.cpuLimitRange)
        s.batteryLimit = s.batteryLimit.clamped(to: Self.batteryLimitRange)
        s.sustainSeconds = s.sustainSeconds.clamped(to: Self.sustainRange)
        s.batteryFloor = s.batteryFloor.clamped(to: Self.batteryFloorRange)
        s.resumeWaitMinutes = s.resumeWaitMinutes.clamped(to: Self.resumeWaitRange)
        if case .after(let minutes) = s.defaultEnd, !EndTime.minutesRange.contains(minutes) { s.defaultEnd = .unlimited }
        return s
    }

    /// Missing keys keep their defaults, so settings saved by an older version still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        cpuLimit = try c.decodeIfPresent(Double.self, forKey: .cpuLimit) ?? d.cpuLimit
        batteryLimit = try c.decodeIfPresent(Double.self, forKey: .batteryLimit) ?? d.batteryLimit
        sustainSeconds = try c.decodeIfPresent(Int.self, forKey: .sustainSeconds) ?? d.sustainSeconds
        batteryFloor = try c.decodeIfPresent(Int.self, forKey: .batteryFloor) ?? d.batteryFloor
        stopOnUnplug = try c.decodeIfPresent(Bool.self, forKey: .stopOnUnplug) ?? d.stopOnUnplug
        defaultEnd = try c.decodeIfPresent(EndTime.self, forKey: .defaultEnd) ?? d.defaultEnd
        resumeAfterOverheat = try c.decodeIfPresent(Bool.self, forKey: .resumeAfterOverheat) ?? d.resumeAfterOverheat
        resumeWaitMinutes = try c.decodeIfPresent(Int.self, forKey: .resumeWaitMinutes) ?? d.resumeWaitMinutes
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

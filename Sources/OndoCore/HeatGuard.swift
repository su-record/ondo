import Foundation

/// Tracks how long one temperature has stayed at or above its limit.
///
/// Time counts only while the reading is at or above the limit. Between the limit and
/// `limit - hysteresis` the count pauses, so a reading that hovers at the edge does not
/// warn again and again. Below that band the count resets.
public struct HeatGuard: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        /// Hot for `sustain` seconds.
        case warn
        /// Hot for twice `sustain` seconds: stop staying awake.
        case stop
        /// Cooled below the band after a warning.
        case cooled
    }

    public static let hysteresis = 3.0

    public private(set) var hotSeconds: TimeInterval = 0
    public private(set) var warned = false

    public init() {}

    /// Seconds left before `stop`, once warned.
    public func secondsUntilStop(sustain: TimeInterval) -> TimeInterval? {
        warned ? max(0, 2 * sustain - hotSeconds) : nil
    }

    /// `elapsed` is the time since the previous reading. A nil temperature (unreadable) changes nothing.
    public mutating func update(celsius: Double?, limit: Double, sustain: TimeInterval, elapsed: TimeInterval) -> Event? {
        guard let celsius else { return nil }
        if celsius >= limit {
            hotSeconds += elapsed
        } else if celsius < limit - Self.hysteresis {
            let wasWarned = warned
            reset()
            return wasWarned ? .cooled : nil
        }
        if hotSeconds >= 2 * sustain { return .stop }
        if hotSeconds >= sustain, !warned {
            warned = true
            return .warn
        }
        return nil
    }

    public mutating func reset() {
        hotSeconds = 0
        warned = false
    }
}

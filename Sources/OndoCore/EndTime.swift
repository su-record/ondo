import Foundation

/// When staying awake ends. Durations and clock times are in whole minutes.
public enum EndTime: Codable, Equatable, Sendable {
    case unlimited
    case after(minutes: Int)
    case at(hour: Int, minute: Int)

    public static let minutesRange = 1...(24 * 60)

    /// The moment it ends, counted from `now`; a clock time that has passed today means tomorrow.
    public func date(from now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .unlimited:
            return nil
        case .after(let minutes):
            return now.addingTimeInterval(TimeInterval(minutes * 60))
        case .at(let hour, let minute):
            let match = DateComponents(hour: hour, minute: minute, second: 0)
            return calendar.nextDate(after: now, matching: match, matchingPolicy: .nextTime)
        }
    }

    /// Accepts "90", "90m", "2h", "1h30m" and "1h30". Returns minutes within `minutesRange`.
    public static func minutes(from text: String) -> Int? {
        var rest = Substring(text.lowercased().trimmingCharacters(in: .whitespaces))
        var total = 0
        if let h = rest.firstIndex(of: "h") {
            guard let hours = Int(rest[..<h]), hours >= 0 else { return nil }
            total = hours * 60
            rest = rest[rest.index(after: h)...]
        }
        if rest.hasSuffix("m") { rest = rest.dropLast() }
        if !rest.isEmpty {
            guard let minutes = Int(rest), minutes >= 0 else { return nil }
            total += minutes
        }
        return minutesRange.contains(total) ? total : nil
    }

    /// Accepts "7:30" and "07:30" (24-hour clock).
    public static func clock(from text: String) -> EndTime? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, parts[1].count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return .at(hour: hour, minute: minute)
    }
}

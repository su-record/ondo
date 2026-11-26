import Foundation
import OndoCore
import OndoSensors

/// Plain-text output for people; `--json` prints the structures instead.
enum Describe {
    static func response(_ response: ControlResponse, for command: ControlCommand) -> String {
        if let refusal = response.refusal { return "refused: \(reason(refusal))" }
        if let error = response.error { return "error: \(error)" }
        if command == .sensors, let sensors = response.sensors {
            return sensorsText(sensors)
        }
        guard let status = response.status else { return "ok" }
        return statusText(status)
    }

    static func statusText(_ s: OndoStatus) -> String {
        var lines: [String] = []
        if s.awake {
            lines.append("awake: on" + (s.endsAt.map { ", until \(clock($0)) (\(remaining(until: $0)) left)" } ?? ", no end time"))
        } else {
            lines.append("awake: off" + (s.lastStop.map { " (last stop: \(reason($0)))" } ?? ""))
        }
        lines.append(temperatures(cpu: s.cpu, battery: s.battery) + (s.simulated ? " (CPU simulated)" : ""))
        lines.append("limits: CPU \(degrees(s.cpuLimit)), battery \(degrees(s.batteryLimit))")
        lines.append("power: " + (s.power.onAC ? "charger" : "battery") + (s.power.batteryPercent.map { ", \($0)%" } ?? ""))
        if let lid = s.lidClosed { lines.append("lid: " + (lid ? "closed" : "open")) }
        if let warning = s.warning {
            lines.append("warning: \(reason(warning))" + (s.secondsUntilStop.map { ", stopping in \($0) s" } ?? ""))
        }
        if let wake = s.wakeAt { lines.append("wake scheduled: \(clock(wake))") }
        if s.helper != "enabled" { lines.append("helper: \(s.helper) — allow ondo in System Settings › General › Login Items") }
        return lines.joined(separator: "\n")
    }

    static func temperatures(cpu: Double?, battery: Double?) -> String {
        "CPU \(cpu.map(degrees) ?? "unavailable"), battery \(battery.map(degrees) ?? "unavailable")"
    }

    static func sensors(_ readings: [SensorReading], chosen: Temperatures) -> String {
        var lines = [temperatures(cpu: chosen.cpu, battery: chosen.battery)]
        lines.append("CPU from: " + names(chosen.cpuSensors))
        lines.append("battery from: " + names(chosen.batterySensors))
        lines.append("")
        lines.append(sensorsText(readings))
        return lines.joined(separator: "\n")
    }

    static func sensorsText(_ readings: [SensorReading]) -> String {
        readings.map { r in
            let value = r.isPlausible ? degrees(r.celsius) : "\(String(format: "%.1f", r.celsius)) (ignored)"
            return "\(r.source.rawValue)\t\(r.name)\t\(value)"
        }.joined(separator: "\n")
    }

    static func reason(_ reason: StopReason) -> String {
        switch reason {
        case .user: return "turned off"
        case .timer: return "end time reached"
        case .cpuHot: return "CPU too hot"
        case .batteryHot: return "battery too hot"
        case .unplugged: return "charger unplugged"
        case .batteryLow: return "battery below the floor"
        case .quit: return "app quit"
        }
    }

    private static func names(_ readings: [SensorReading]) -> String {
        guard !readings.isEmpty else { return "none" }
        let unique = Array(Set(readings.map { "\($0.source.rawValue):\($0.name)" })).sorted()
        return unique.count > 4 ? unique.prefix(4).joined(separator: ", ") + " … (\(unique.count))" : unique.joined(separator: ", ")
    }

    private static func degrees(_ celsius: Double) -> String { String(format: "%.1f°C", celsius) }

    private static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func remaining(until date: Date) -> String {
        let minutes = max(0, Int((date.timeIntervalSinceNow / 60).rounded(.up)))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

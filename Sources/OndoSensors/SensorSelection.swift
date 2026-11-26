import Foundation

/// Chooses which sensors stand for the CPU and the battery. Sensor names differ by chip,
/// so each group lists sources from most to least specific and the first non-empty one wins.
public enum SensorSelection {
    /// Apple silicon CPU die sensors over HID (measured on M5 Pro: PMU tdie1…tdie14).
    static let hidCPUPrefix = "PMU tdie"
    /// Apple silicon SMC CPU keys: Tp* (performance and M1/M2 cores) and Te* (M3/M4 efficiency cores).
    static let smcAppleCPUPrefixes = ["Tp", "Te"]
    /// Intel SMC CPU keys: die, proximity and package sensors.
    static let smcIntelCPUKeys: Set<String> = ["TC0D", "TC0E", "TC0F", "TC0P", "TCXC"]
    static let smcBatteryKeys: Set<String> = ["TB0T", "TB1T", "TB2T"]
    static let hidBatteryName = "gas gauge battery"

    /// SMC keys worth reading on every tick; everything else is only read by a full scan.
    public static func isCandidateSMCKey(_ key: String) -> Bool {
        smcAppleCPUPrefixes.contains { key.hasPrefix($0) } || smcIntelCPUKeys.contains(key) || smcBatteryKeys.contains(key)
    }

    public static func temperatures(from readings: [SensorReading]) -> Temperatures {
        let plausible = readings.filter(\.isPlausible)
        let cpu = firstGroup(in: plausible, [
            { $0.source == .hid && $0.name.hasPrefix(hidCPUPrefix) },
            { r in r.source == .smc && smcAppleCPUPrefixes.contains { r.name.hasPrefix($0) } },
            { $0.source == .smc && smcIntelCPUKeys.contains($0.name) },
        ])
        let battery = firstGroup(in: plausible, [
            { $0.source == .smc && smcBatteryKeys.contains($0.name) },
            { $0.source == .hid && $0.name == hidBatteryName },
        ])
        return Temperatures(cpu: cpu.map(\.celsius).max(), battery: battery.map(\.celsius).max(),
                            cpuSensors: cpu, batterySensors: battery)
    }

    private static func firstGroup(in readings: [SensorReading], _ matchers: [(SensorReading) -> Bool]) -> [SensorReading] {
        for matches in matchers {
            let group = readings.filter(matches)
            if !group.isEmpty { return group }
        }
        return []
    }
}

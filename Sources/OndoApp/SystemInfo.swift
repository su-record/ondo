import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import OndoCore

/// Reads and actions that need no root: power source, lid, sleep state, busy processes, sleep and display off.
enum SystemInfo {
    static func power() -> PowerState {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        let percent = sources.lazy.compactMap { source -> Int? in
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0
            else { return nil }
            return current * 100 / max
        }.first
        return PowerState(onAC: providing == kIOPMACPowerKey, batteryPercent: percent)
    }

    /// Nil on a Mac without a lid or when the state cannot be read.
    static func lidClosed() -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
    }

    /// Whether `pmset -a disablesleep 1` is in effect. `pmset -g` lists SleepDisabled only when it is set.
    static func sleepDisabled() -> Bool {
        let output = run("/usr/bin/pmset", ["-g"]).output
        return output.split(separator: "\n").contains { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            return fields.count >= 2 && fields[0] == "SleepDisabled" && fields[1] == "1"
        }
    }

    /// "Apple M5 Pro, Mac17,7, macOS 27.0.1" for sensor reports.
    static func machineDescription() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let os = "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        return [sysctlString("machdep.cpu.brand_string"), sysctlString("hw.model"), os].compactMap { $0 }.joined(separator: ", ")
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    struct BusyProcess: Equatable, Sendable {
        let name: String
        let cpuPercent: Double
    }

    /// The processes using the most CPU, from `ps` (its %CPU is a short moving average).
    static func topProcesses(count: Int) -> [BusyProcess] {
        let output = run("/bin/ps", ["-Aceo", "pcpu=,comm=", "-r"]).output
        return output.split(separator: "\n").lazy.compactMap { line -> BusyProcess? in
            let fields = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            guard fields.count == 2, let cpu = Double(fields[0]) else { return nil }
            let name = String(fields[1]).trimmingCharacters(in: .whitespaces)
            return name == "ps" ? nil : BusyProcess(name: name, cpuPercent: cpu)
        }.prefix(count).map { $0 }
    }

    /// Puts the Mac to sleep. IOPMSleepSystem is allowed for the console user; `pmset sleepnow` is the fallback.
    static func sleepNow() -> String? {
        let port = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
        if port != 0 {
            let result = IOPMSleepSystem(port)
            IOServiceClose(port)
            if result == kIOReturnSuccess { return nil }
        }
        let fallback = run("/usr/bin/pmset", ["sleepnow"])
        return fallback.status == 0 ? nil : "cannot sleep: \(fallback.output)"
    }

    static func displayOff() -> String? {
        let result = run("/usr/bin/pmset", ["displaysleepnow"])
        return result.status == 0 ? nil : "pmset displaysleepnow failed: \(result.output)"
    }

    private static func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

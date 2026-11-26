import Foundation
import IOKit.pwr_mgt
import OndoShared

/// The only system changes the helper makes. Each returns an error message, or nil on success.
enum Power {
    static let pmset = URL(fileURLWithPath: "/usr/bin/pmset")

    /// `pmset -a disablesleep 1|0` with fixed arguments; no shell, no caller-supplied text.
    static func setSleepDisabled(_ disabled: Bool) -> String? {
        let process = Process()
        process.executableURL = pmset
        process.arguments = ["-a", "disablesleep", disabled ? "1" : "0"]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        do { try process.run() } catch { return "cannot run pmset: \(error.localizedDescription)" }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return "pmset exited with \(process.terminationStatus): \(message.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        return nil
    }

    static func scheduleWake(at date: Date) -> String? {
        let ahead = date.timeIntervalSinceNow
        guard ahead > 0, ahead <= HelperLimits.maxWakeAhead else { return "wake time must be in the next 24 hours" }
        let result = IOPMSchedulePowerEvent(date as CFDate, HelperLimits.wakeScheduler as CFString, kIOPMAutoWake as CFString)
        return result == kIOReturnSuccess ? nil : "IOPMSchedulePowerEvent failed (\(result))"
    }

    /// Cancels the wake events ondo scheduled; other apps' events are left alone.
    static func cancelWakes() -> String? {
        guard let events = IOPMCopyScheduledPowerEvents()?.takeRetainedValue() as? [[String: Any]] else { return nil }
        var failures: [String] = []
        for event in events where event[kIOPMPowerEventAppNameKey] as? String == HelperLimits.wakeScheduler {
            guard let time = event[kIOPMPowerEventTimeKey] as? Date, let type = event[kIOPMPowerEventTypeKey] as? String else { continue }
            let result = IOPMCancelScheduledPowerEvent(time as CFDate, HelperLimits.wakeScheduler as CFString, type as CFString)
            if result != kIOReturnSuccess { failures.append("\(time): \(result)") }
        }
        return failures.isEmpty ? nil : "cannot cancel wake events: " + failures.joined(separator: ", ")
    }
}

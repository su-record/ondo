import Foundation
import OndoCore
import OndoSensors

/// Debug override of the CPU reading, to try the overheat rules without heating the Mac.
struct Simulation: Equatable {
    static let length: TimeInterval = 10 * 60
    var celsius: Double
    var endsAt: Date
}

extension Controller {
    /// One monitoring step: read, then apply the timer, power and temperature rules.
    func tick() async {
        guard !ticking else { return }
        ticking = true
        defer { ticking = false }
        await refresh()
        await evaluate(now: Date())
        await checkWakePlan(now: Date())
    }

    func refresh() async {
        let reader = self.reader
        let measured = await withCheckedContinuation { continuation in
            sensorQueue.async { continuation.resume(returning: reader.temperatures()) }
        }
        if let simulation, simulation.endsAt <= Date() { self.simulation = nil; note("simulation ended") }
        temperatures = simulation.map { sim in
            Temperatures(cpu: sim.celsius, battery: measured.battery, cpuSensors: measured.cpuSensors, batterySensors: measured.batterySensors)
        } ?? measured
        power = SystemInfo.power()
        lidClosed = SystemInfo.lidClosed()
        helperStatus = helper.status
        lastRefresh = Date()
    }

    /// Every sensor, for the debug window and `ondo sensors` through the app.
    func allSensorReadings() async -> [SensorReading] {
        let reader = self.reader
        return await withCheckedContinuation { continuation in
            sensorQueue.async { continuation.resume(returning: reader.allReadings()) }
        }
    }

    func refreshIfStale() async {
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < Self.tickInterval { return }
        await refresh()
    }

    func evaluate(now: Date) async {
        // A long gap (the Mac slept, the timer was off) must not count as time spent hot.
        let elapsed = min(now.timeIntervalSince(lastTick ?? now), 2 * Self.tickInterval)
        lastTick = now
        guard awake else { return }
        if let endsAt, now >= endsAt { return await stop(.timer) }
        if let reason = Protection.powerStop(previous: previousPower, current: power, settings: settings) { return await stop(reason) }
        previousPower = power

        let sustain = TimeInterval(settings.sustainSeconds)
        let cpuEvent = cpuGuard.update(celsius: temperatures?.cpu, limit: settings.cpuLimit, sustain: sustain, elapsed: elapsed)
        let batteryEvent = batteryGuard.update(celsius: temperatures?.battery, limit: settings.batteryLimit, sustain: sustain, elapsed: elapsed)
        if cpuEvent == .stop { return await stop(.cpuHot) }
        if batteryEvent == .stop { return await stop(.batteryHot) }
        updateWarning(sustain: sustain)
        if cpuEvent == .warn { announceWarning(.cpuHot, celsius: temperatures?.cpu, limit: settings.cpuLimit) }
        if batteryEvent == .warn { announceWarning(.batteryHot, celsius: temperatures?.battery, limit: settings.batteryLimit) }
    }

    /// The warning shown in the menu, with fresh busy processes while it lasts.
    private func updateWarning(sustain: TimeInterval) {
        let hot: (StopReason, HeatGuard)? = cpuGuard.warned ? (.cpuHot, cpuGuard) : batteryGuard.warned ? (.batteryHot, batteryGuard) : nil
        guard let (reason, guard_) = hot else { warning = nil; return }
        let seconds = guard_.secondsUntilStop(sustain: sustain).map { Int($0.rounded(.up)) }
        warning = Warning(reason: reason, secondsUntilStop: seconds, processes: SystemInfo.topProcesses(count: 3))
    }

    private func announceWarning(_ reason: StopReason, celsius: Double?, limit: Double) {
        let processes = warning?.processes ?? SystemInfo.topProcesses(count: 3)
        let busy = processes.map { "\($0.name) \(Int($0.cpuPercent))%" }.joined(separator: ", ")
        let seconds = settings.sustainSeconds
        note("warning: \(reason.rawValue) at \(L.degrees(celsius)); top: \(busy)")
        Notifier.shared.post(
            id: "warning",
            title: "ondo · " + L.reason(reason) + " " + L.degrees(celsius),
            body: L.t("\(Int(limit))°C를 넘었습니다. \(seconds)초 더 넘으면 깨어있기를 끕니다. CPU 상위: \(busy)",
                      "Above \(Int(limit))°C. Staying awake ends after \(seconds) more seconds. Top CPU: \(busy)"))
    }

    func setSimulation(celsius: Double?) {
        simulation = celsius.map { Simulation(celsius: $0, endsAt: Date().addingTimeInterval(Simulation.length)) }
        note(celsius.map { "simulating CPU \(Int($0))°C for 10 min" } ?? "simulation off")
        updateTimer()
    }
}

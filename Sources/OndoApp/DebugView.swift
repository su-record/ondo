import AppKit
import OndoSensors
import SwiftUI

/// Sensor values on this Mac, the temperature simulation and the recent log.
struct DebugView: View {
    @ObservedObject var controller: Controller
    @State private var readings: [SensorReading] = []
    @State private var simulatedCelsius = 90.0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox(L.t("센서", "Sensors")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(summary).font(.callout)
                        Spacer()
                        Button(L.t("새로 읽기", "Read Again")) { Task { await load() } }
                        Button(L.t("복사", "Copy")) { copy(report) }
                    }
                    List(Array(readings.enumerated()), id: \.offset) { _, r in
                        HStack {
                            Text(r.source.rawValue).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
                            Text(r.name)
                            Spacer()
                            if used(r) { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                            Text(r.isPlausible ? String(format: "%.1f°C", r.celsius) : L.t("무시", "ignored"))
                                .monospacedDigit().foregroundStyle(r.isPlausible ? .primary : .secondary)
                        }
                        .font(.system(.caption, design: .monospaced))
                    }
                    .frame(minHeight: 220)
                }
            }
            GroupBox(L.t("온도 시뮬레이션", "Temperature simulation")) {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(L.t("CPU 온도를 이 값으로 바꾸기 (10분 뒤 자동으로 꺼짐)", "Replace the CPU reading with this value (turns off after 10 min)"),
                           isOn: Binding(get: { controller.simulation != nil },
                                         set: { controller.setSimulation(celsius: $0 ? simulatedCelsius : nil) }))
                    HStack {
                        Slider(value: $simulatedCelsius, in: 40...110, step: 1)
                        Text("\(Int(simulatedCelsius))°C").monospacedDigit().frame(width: 48)
                    }
                    .onChange(of: simulatedCelsius) { value in
                        if controller.simulation != nil { controller.setSimulation(celsius: value) }
                    }
                }
            }
            GroupBox(L.t("상태 로그", "Log")) {
                VStack(alignment: .trailing) {
                    ScrollView {
                        Text(controller.log.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 120)
                    Button(L.t("복사", "Copy")) { copy(controller.log.joined(separator: "\n")) }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 640)
        .task { await load() }
    }

    private var chosen: Temperatures { SensorSelection.temperatures(from: readings) }

    private var summary: String {
        "CPU \(L.degrees(chosen.cpu)) · " + L.t("배터리", "Battery") + " \(L.degrees(chosen.battery)) · " + L.t("센서 \(readings.count)개", "\(readings.count) sensors")
    }

    private func used(_ reading: SensorReading) -> Bool {
        chosen.cpuSensors.contains(reading) || chosen.batterySensors.contains(reading)
    }

    /// Text for an issue report: the machine, what ondo chose and every reading.
    private var report: String {
        var lines = ["ondo sensors · \(SystemInfo.machineDescription())", summary, ""]
        lines += readings.map { "\($0.source.rawValue)\t\($0.name)\t\(String(format: "%.2f", $0.celsius))\(used($0) ? "\tused" : "")" }
        return lines.joined(separator: "\n")
    }

    private func load() async {
        readings = await controller.allSensorReadings()
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

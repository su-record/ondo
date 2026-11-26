import AppKit
import OndoCore
import SwiftUI

struct MenuBarIcon: View {
    @ObservedObject var controller: Controller

    var body: some View {
        Image(nsImage: MenuBarGlyph.image(heat: Heat(celsius: controller.temperatures?.cpu, limit: controller.settings.cpuLimit),
                                          awake: controller.awake))
            .accessibilityLabel(controller.awake ? L.t("ondo: 깨어있기 켜짐", "ondo: staying awake") : L.t("ondo: 꺼짐", "ondo: off"))
    }
}

/// The menu panel. Every state has the same height: the end-time group and the overheat warning share one slot,
/// and messages replace the header's status line instead of adding rows. Mockup: design/mockups/astryx-direction.html
struct MenuView: View {
    @ObservedObject var controller: Controller
    let windows: Windows

    static let width: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            MenuHeader(controller: controller)
            Group {
                if let warning = controller.warning {
                    WarningBanner(warning: warning)
                } else {
                    EndPicker(end: $controller.endChoice)
                }
            }
            .frame(height: DS.endSlotHeight, alignment: .top)
            TemperatureCard(controller: controller)
            VStack(spacing: DS.Space.sm) {
                WakeRow(controller: controller)
                Rectangle().fill(DS.Palette.border).frame(height: 1).padding(.horizontal, -DS.Space.lg)
                VStack(spacing: 0) {
                    ListRow(L.t("화면만 끄기", "Turn Off Display"), action: { _ = SystemInfo.displayOff() })
                    ListRow(L.t("디버그…", "Debug…"), action: { windows.showDebug() })
                    ListRow(L.t("설정…", "Settings…"), action: { windows.showSettings() }, trailing: { shortcut("⌘,") })
                    ListRow(L.t("종료", "Quit"), action: { NSApp.terminate(nil) }, trailing: { shortcut("⌘Q") })
                }
            }
            .padding(.horizontal, -DS.Space.sm)
        }
        .padding(DS.Space.lg)
        .frame(width: Self.width)
        .background {
            // Keyboard shortcuts for the panel; the visible rows above are plain views.
            Button("") { windows.showSettings() }.keyboardShortcut(",").hidden()
            Button("") { NSApp.terminate(nil) }.keyboardShortcut("q").hidden()
        }
        .onAppear { controller.menuOpen = true }
        .onDisappear { controller.menuOpen = false }
    }

    private func shortcut(_ text: String) -> some View {
        Text(text).font(DS.Font.supporting).foregroundStyle(.secondary)
    }
}

private struct MenuHeader: View {
    @ObservedObject var controller: Controller

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("닫아도 깨어있기", "Stay Awake, Lid Closed")).font(DS.Font.title)
                statusLine
            }
            Spacer()
            Toggle("", isOn: Binding(get: { controller.awake }, set: toggle))
                .toggleStyle(.switch)
                .tint(DS.Palette.accent)
                .labelsHidden()
        }
    }

    /// One line: a pending message (refusal, error, approval needed) or the current state.
    @ViewBuilder private var statusLine: some View {
        if let notice = controller.notice {
            Text(notice)
                .font(DS.Font.supporting).foregroundStyle(DS.Palette.warningText).lineLimit(1)
                .help(notice)
                .onTapGesture { if controller.helperStatus == .requiresApproval { controller.helper.openApprovalSettings() } }
        } else {
            Text(stateText)
                .font(DS.Font.supporting).foregroundStyle(controller.awake ? DS.Palette.accent : Color.secondary).lineLimit(1)
        }
    }

    private var stateText: String {
        guard controller.awake else {
            return L.t("꺼짐", "Off") + (controller.lastStop.map { " · " + L.reason($0) } ?? "")
        }
        guard let endsAt = controller.endsAt else { return L.t("켜짐 · 끄는 시간 없음", "On · no end time") }
        return L.t("켜짐 · \(L.remaining(until: endsAt)) 남음 · \(L.clock(endsAt))에 꺼짐",
                   "On · \(L.remaining(until: endsAt)) left · off at \(L.clock(endsAt))")
    }

    private func toggle(_ on: Bool) {
        Task {
            guard on else { return await controller.stop(.user) }
            if await controller.start(controller.endChoice) == .needsHelperApproval { controller.helper.openApprovalSettings() }
        }
    }
}

private struct WarningBanner: View {
    let warning: Controller.Warning

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L.reason(warning.reason) + (warning.secondsUntilStop.map { L.t(" · \($0)초 뒤 해제", " · stopping in \($0) s") } ?? ""),
                  systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
            Text(L.t("CPU를 많이 쓰는 프로그램", "Programs using the most CPU")).font(DS.Font.supporting).opacity(0.8)
            ForEach(warning.processes, id: \.name) { process in
                HStack {
                    Text(process.name).lineLimit(1)
                    Spacer()
                    Text("CPU \(Int(process.cpuPercent))%").monospacedDigit()
                }
                .font(DS.Font.supporting)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(DS.Palette.warningText)
        .padding(DS.Space.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.element).fill(DS.Palette.warningFill))
    }
}

private struct TemperatureCard: View {
    @ObservedObject var controller: Controller

    var body: some View {
        let settings = controller.settings
        let t = controller.temperatures
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.simulation == nil ? "CPU" : L.t("CPU · 시뮬레이션", "CPU · simulated")).font(DS.Font.label).foregroundStyle(.secondary)
                    Text(L.degrees(t?.cpu)).font(DS.Font.display)
                        .foregroundStyle((t?.cpu ?? 0) >= settings.cpuLimit ? DS.Palette.danger : Color.primary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L.t("배터리", "Battery")).font(DS.Font.label).foregroundStyle(.secondary)
                    Text(L.degrees(t?.battery)).font(DS.Font.large)
                        .foregroundStyle((t?.battery ?? 0) >= settings.batteryLimit ? DS.Palette.danger : Color.secondary)
                }
            }
            HeatGauge(celsius: t?.cpu, limit: settings.cpuLimit, scale: Settings.cpuLimitRange.upperBound)
            HStack {
                Text(L.t("기준 \(Int(settings.cpuLimit))°C · 배터리 \(Int(settings.batteryLimit))°C",
                         "Limit \(Int(settings.cpuLimit))°C · battery \(Int(settings.batteryLimit))°C"))
                Spacer()
                Text(powerText)
            }
            .font(DS.Font.supporting).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(DS.Space.md)
        .background(RoundedRectangle(cornerRadius: DS.Radius.element).fill(DS.Palette.fill))
        .help(t != nil && t?.cpu == nil ? L.t("CPU 온도를 읽지 못해 과열 보호가 동작하지 않습니다.", "CPU temperature is unavailable, so overheat protection is off.") : "")
    }

    private var powerText: String {
        let power = controller.power
        let percent = power.batteryPercent.map { "\($0)%" } ?? ""
        return power.onAC ? L.t("충전기 연결 · \(percent)", "Charger · \(percent)") : L.t("배터리 사용 · \(percent)", "Battery · \(percent)")
    }
}

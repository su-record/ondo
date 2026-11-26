import AppKit
import OndoCore
import OndoShared
import ServiceManagement
import SwiftUI

/// Settings: a tab bar in the title bar area and grouped cards of 44 pt rows. Mockup: design/mockups/astryx-direction.html
struct SettingsView: View {
    @ObservedObject var controller: Controller
    @State private var tab = Tab.general

    static let size = CGSize(width: 600, height: 540)

    enum Tab: CaseIterable {
        case general, protection, external, about

        var title: String {
            switch self {
            case .general: return L.t("일반", "General")
            case .protection: return L.t("보호", "Protection")
            case .external: return L.t("외부 제어", "External Control")
            case .about: return L.t("정보", "About")
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .protection: return "thermometer.medium"
            case .external: return "terminal"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.xs) {
                ForEach(Tab.allCases, id: \.self) { item in
                    Button { tab = item } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.system(size: 13, weight: tab == item ? .semibold : .regular))
                            .foregroundStyle(tab == item ? Color.primary : Color.secondary)
                            .padding(.horizontal, DS.Space.md)
                            .frame(height: DS.Height.md)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.inner).fill(tab == item ? DS.Palette.fill : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(DS.Palette.card)
            .overlay(alignment: .bottom) { Rectangle().fill(DS.Palette.border).frame(height: 1) }
            ScrollView {
                VStack(spacing: DS.Space.xl) { content }.padding(DS.Space.xl)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(DS.Palette.windowBody)
        .ignoresSafeArea()
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .general: GeneralTab(controller: controller)
        case .protection: ProtectionTab(controller: controller)
        case .external: ExternalTab()
        case .about: AboutTab()
        }
    }
}

private struct GeneralTab: View {
    @ObservedObject var controller: Controller
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var message: String?

    var body: some View {
        FormCard(title: L.t("시작", "Startup")) {
            FormRow(title: L.t("로그인 시 자동 실행", "Open at login"), divider: false) {
                Toggle("", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin)).toggleStyle(.switch).labelsHidden()
            }
        }
        FormCard(title: L.t("켤 때 기본으로 끄는 시점", "Default end when turning on")) {
            EndPicker(end: $controller.settings.defaultEnd).padding(DS.Space.md)
        }
        FormCard(title: L.t("관리자 권한 도우미", "Administrator helper")) {
            FormRow(title: helperTitle, detail: helperDetail) {
                if controller.helperStatus != .enabled {
                    Button(L.t("허용하러 가기", "Allow")) {
                        _ = controller.helper.ensureRegistered()
                        controller.helper.openApprovalSettings()
                    }
                }
            }
            FormRow(title: L.t("도우미 제거", "Remove helper"), detail: L.t("앱을 지우기 전에 누르세요.", "Do this before deleting the app."), divider: false) {
                Button(L.t("제거", "Remove")) {
                    Task { message = await controller.helper.unregister() ?? L.t("제거했습니다.", "Removed.") }
                }
            }
        }
        if let message { Text(message).font(DS.Font.supporting).foregroundStyle(.secondary) }
    }

    private var helperTitle: String {
        controller.helperStatus == .enabled ? L.t("허용됨", "Allowed") : L.t("허용 필요", "Needs approval")
    }

    private var helperDetail: String {
        switch controller.helperStatus {
        case .enabled: return L.t("깨어있기를 켜고 끌 때 비밀번호를 묻지 않습니다.", "Turning on and off needs no password.")
        case .requiresApproval: return L.t("시스템 설정 › 일반 › 로그인 항목에서 ondo를 허용해 주세요.", "Allow ondo in System Settings › General › Login Items.")
        case .notRegistered, .notFound: return L.t("처음 켤 때 등록합니다.", "ondo registers it the first time you turn it on.")
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            message = nil
        } catch {
            message = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

private struct ProtectionTab: View {
    @ObservedObject var controller: Controller

    var body: some View {
        let s = controller.settings
        FormCard(title: L.t("과열", "Overheat")) {
            FormRow(title: L.t("CPU 기준", "CPU limit"), detail: L.t("넘으면 경고하고, 오래 넘으면 깨어있기를 끕니다.", "Above it ondo warns; for longer it stops staying awake.")) {
                FieldBox(value: Int(s.cpuLimit), range: intRange(Settings.cpuLimitRange), unit: "°C") { controller.settings.cpuLimit = Double($0) }
            }
            FormRow(title: L.t("배터리 기준", "Battery limit")) {
                FieldBox(value: Int(s.batteryLimit), range: intRange(Settings.batteryLimitRange), unit: "°C") { controller.settings.batteryLimit = Double($0) }
            }
            FormRow(title: L.t("지속 시간", "Duration"),
                    detail: L.t("\(s.sustainSeconds)초 넘으면 경고, \(s.sustainSeconds * 2)초면 해제", "Alert after \(s.sustainSeconds) s, stop after \(s.sustainSeconds * 2) s"),
                    divider: false) {
                FieldBox(value: s.sustainSeconds, range: Settings.sustainRange, unit: L.t("초", "s")) { controller.settings.sustainSeconds = $0 }
            }
        }
        FormCard(title: L.t("전원", "Power")) {
            FormRow(title: L.t("충전기가 빠지면 끄기", "Stop when the charger is unplugged")) {
                Toggle("", isOn: $controller.settings.stopOnUnplug).toggleStyle(.switch).labelsHidden()
            }
            FormRow(title: L.t("배터리 하한", "Battery floor"), detail: L.t("배터리로 쓰는 중 이 값 아래로 내려가면 끕니다.", "On battery, below this ondo stops."), divider: false) {
                FieldBox(value: s.batteryFloor, range: Settings.batteryFloorRange, unit: "%") { controller.settings.batteryFloor = $0 }
            }
        }
        FormCard(title: L.t("과열 뒤 다시 켜기", "Resume after overheating")) {
            FormRow(title: L.t("식으면 맥을 깨워 다시 켜기", "Wake the Mac and resume once cooled"),
                    detail: L.t("두 온도가 기준보다 \(Int(Protection.resumeMargin))°C 낮을 때, 최대 \(Protection.maxResumeAttempts)번",
                                "When both are \(Int(Protection.resumeMargin))°C under their limits, up to \(Protection.maxResumeAttempts) checks")) {
                Toggle("", isOn: $controller.settings.resumeAfterOverheat).toggleStyle(.switch).labelsHidden()
            }
            FormRow(title: L.t("확인까지 기다릴 시간", "Wait before checking"), divider: false) {
                FieldBox(value: s.resumeWaitMinutes, range: Settings.resumeWaitRange, unit: L.t("분", "min")) { controller.settings.resumeWaitMinutes = $0 }
            }
            .disabled(!s.resumeAfterOverheat)
            .opacity(s.resumeAfterOverheat ? 1 : 0.5)
        }
    }

    private func intRange(_ range: ClosedRange<Double>) -> ClosedRange<Int> { Int(range.lowerBound)...Int(range.upperBound) }
}

private struct ExternalTab: View {
    private var cliPath: String { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ondo").path }

    var body: some View {
        FormCard(title: L.t("터미널 명령", "Terminal command")) {
            FormRow(title: L.t("ondo 명령 연결", "Link the ondo command"),
                    detail: L.t("Homebrew로 설치했다면 이미 있습니다.", "Homebrew installs it already."), divider: false) {
                CopyButton(text: "sudo ln -sf \"\(cliPath)\" /usr/local/bin/ondo")
            }
        }
        FormCard(title: L.t("AI 에이전트 (MCP)", "AI agents (MCP)")) {
            FormRow(title: "Claude Code", detail: "claude mcp add ondo -- ondo mcp") {
                CopyButton(text: "claude mcp add ondo -- \"\(cliPath)\" mcp")
            }
            FormRow(title: L.t("다른 MCP 앱", "Other MCP apps"), detail: L.t("명령 \(cliPath), 인자 mcp", "Command \(cliPath), argument mcp"), divider: false) {
                CopyButton(text: cliPath)
            }
        }
        FormCard(title: L.t("링크", "Links")) {
            FormRow(title: "ondo://on?for=1h30m") { CopyButton(text: "ondo://on?for=1h30m") }
            FormRow(title: "ondo://off", divider: false) { CopyButton(text: "ondo://off") }
        }
        Text(L.t("외부에서는 켜기·끄기·상태 보기·화면 끄기·깨우기 예약만 할 수 있습니다. 보호 기준은 이 창에서만 바꿀 수 있습니다.",
                 "External callers can turn staying awake on and off, read status, turn off the display and schedule wakes. Protection limits change only here."))
            .font(DS.Font.supporting).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button(copied ? L.t("복사됨", "Copied") : L.t("복사", "Copy")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
        }
        .help(text)
    }
}

private struct AboutTab: View {
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }

    var body: some View {
        VStack(spacing: DS.Space.sm) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("ondo").font(.system(size: 24, weight: .semibold))
            Text(L.t("버전 \(version)", "Version \(version)")).font(DS.Font.supporting).foregroundStyle(.secondary)
            Text("Made by Tory Labs").font(DS.Font.body).padding(.top, DS.Space.sm)
            Link("torylabs.dev/ondo", destination: Identity.website).font(DS.Font.body)
            Text(L.t("MIT 라이선스 오픈소스", "Open source under the MIT License")).font(DS.Font.supporting).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Space.xl)
    }
}

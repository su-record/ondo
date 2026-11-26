import OndoCore
import SwiftUI

/// One row: schedule a wake that turns staying awake back on, or show and cancel a pending one.
/// Picking a time opens a popover, so the menu keeps its height; errors go to the header's status line.
struct WakeRow: View {
    @ObservedObject var controller: Controller
    @State private var choosingTime = false
    @State private var time = Date().addingTimeInterval(3600)

    static let quickMinutes = [30, 60, 120]

    var body: some View {
        ListRow(title, trailing: {
            if controller.wakePlan != nil {
                Button(L.t("취소", "Cancel")) { Task { await controller.cancelWake() } }.controlSize(.small)
            } else {
                scheduleMenu
            }
        })
        .help(L.t("정한 시각에 맥을 깨우고 깨어있기를 다시 켭니다.", "Wakes the Mac at that time and keeps it awake again."))
        .popover(isPresented: $choosingTime, arrowEdge: .bottom) { timePicker }
    }

    private var title: String {
        guard let plan = controller.wakePlan else { return L.t("잠든 뒤 다시 켜기", "Wake and Resume") }
        switch plan.kind {
        case .scheduled:
            return L.t("\(L.clock(plan.at))에 깨워 다시 켬", "Wake and resume at \(L.clock(plan.at))")
        case .afterOverheat(let attempt, _):
            return L.t("식는 중 · \(L.clock(plan.at))에 확인 (\(attempt)/\(Protection.maxResumeAttempts))",
                       "Cooling · check at \(L.clock(plan.at)) (\(attempt)/\(Protection.maxResumeAttempts))")
        }
    }

    private var scheduleMenu: some View {
        Menu(L.t("예약", "Schedule")) {
            ForEach(Self.quickMinutes, id: \.self) { minutes in
                Button(L.t("\(L.duration(minutes: minutes)) 뒤", "In \(L.duration(minutes: minutes))")) {
                    schedule(Date().addingTimeInterval(TimeInterval(minutes * 60)))
                }
            }
            Divider()
            Button(L.t("시각 지정…", "At a Time…")) { choosingTime = true }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(.secondary)
    }

    private var timePicker: some View {
        HStack(spacing: DS.Space.sm) {
            DatePicker("", selection: $time, displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
            Button(L.t("예약", "Schedule")) {
                choosingTime = false
                let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                if let date = EndTime.at(hour: c.hour ?? 0, minute: c.minute ?? 0).date(from: Date()) { schedule(date) }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(DS.Space.md)
    }

    private func schedule(_ date: Date) {
        Task {
            guard let error = await controller.scheduleWake(at: date) else { return }
            controller.notice = error
            if controller.helperStatus == .requiresApproval { controller.helper.openApprovalSettings() }
        }
    }
}

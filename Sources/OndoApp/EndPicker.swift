import OndoCore
import SwiftUI

/// Chooses when staying awake ends, to the minute: no end, after hours and minutes, or at a clock time.
/// Every mode shows the same rows at the same height, so switching modes never resizes the menu.
struct EndPicker: View {
    @Binding var end: EndTime

    static let quickMinutes = [30, 60, 120, 240, 480]

    private enum Mode: Hashable { case unlimited, after, at }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text(L.t("끄는 시점", "Turn off")).font(DS.Font.label).foregroundStyle(.secondary).frame(height: 16)
            SegmentedControl(options: [(Mode.unlimited, L.t("무제한", "No end")), (Mode.after, L.t("시간 뒤", "After")), (Mode.at, L.t("시각에", "At"))],
                             selection: modeBinding)
            Group { firstRow }.frame(height: DS.Height.sm, alignment: .leading)
            Group { secondRow }.frame(height: DS.Height.sm, alignment: .leading)
        }
    }

    @ViewBuilder private var firstRow: some View {
        switch end {
        case .unlimited:
            Text(L.t("끌 때까지 계속 깨어 있습니다.", "Stays awake until turned off.")).font(DS.Font.supporting).foregroundStyle(.secondary)
        case .after(let minutes):
            HStack(spacing: DS.Space.sm) {
                FieldBox(value: minutes / 60, range: 0...24, unit: L.t("시간", "h")) { setDuration(hours: $0, minutes: minutes % 60) }
                FieldBox(value: minutes % 60, range: 0...59, unit: L.t("분", "min")) { setDuration(hours: minutes / 60, minutes: $0) }
            }
        case .at:
            DatePicker("", selection: clockBinding, displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
        }
    }

    @ViewBuilder private var secondRow: some View {
        switch end {
        case .unlimited:
            Color.clear
        case .after(let minutes):
            HStack(spacing: 6) {
                ForEach(Self.quickMinutes, id: \.self) { quick in
                    Chip(title: L.duration(minutes: quick), selected: minutes == quick) { end = .after(minutes: quick) }
                }
            }
        case .at:
            Text(nextEndText).font(DS.Font.supporting).foregroundStyle(.secondary)
        }
    }

    private var nextEndText: String {
        guard let date = end.date(from: Date()) else { return "" }
        return Calendar.current.isDateInToday(date)
            ? L.t("오늘 \(L.clock(date))에 끕니다.", "Turns off today at \(L.clock(date)).")
            : L.t("내일 \(L.clock(date))에 끕니다.", "Turns off tomorrow at \(L.clock(date)).")
    }

    private var modeBinding: Binding<Mode> {
        Binding(get: {
            switch end {
            case .unlimited: return .unlimited
            case .after: return .after
            case .at: return .at
            }
        }, set: { mode in
            switch mode {
            case .unlimited: end = .unlimited
            case .after: end = .after(minutes: 60)
            case .at:
                let next = Calendar.current.dateComponents([.hour], from: Date().addingTimeInterval(3600))
                end = .at(hour: next.hour ?? 0, minute: 0)
            }
        })
    }

    private var clockBinding: Binding<Date> {
        Binding(get: {
            guard case .at(let hour, let minute) = end else { return Date() }
            return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            end = .at(hour: c.hour ?? 0, minute: c.minute ?? 0)
        })
    }

    /// Keeps the total inside 1 minute to 24 hours.
    private func setDuration(hours: Int, minutes: Int) {
        let total = min(max(hours * 60 + minutes, EndTime.minutesRange.lowerBound), EndTime.minutesRange.upperBound)
        end = .after(minutes: total)
    }
}

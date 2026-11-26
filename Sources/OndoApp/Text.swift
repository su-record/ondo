import Foundation
import OndoCore

/// UI text in Korean or English, chosen by the user's first preferred language.
enum L {
    static let korean = Locale.preferredLanguages.first?.hasPrefix("ko") ?? false

    static func t(_ ko: String, _ en: String) -> String { korean ? ko : en }

    static func reason(_ reason: StopReason) -> String {
        switch reason {
        case .user: return t("직접 끔", "Turned off")
        case .timer: return t("끄는 시간이 됨", "End time reached")
        case .cpuHot: return t("CPU 과열", "CPU too hot")
        case .batteryHot: return t("배터리 과열", "Battery too hot")
        case .unplugged: return t("충전기 분리", "Charger unplugged")
        case .batteryLow: return t("배터리 부족", "Battery low")
        case .quit: return t("앱 종료", "App quit")
        }
    }

    static func degrees(_ celsius: Double?) -> String {
        guard let celsius else { return t("측정 불가", "Unavailable") }
        return String(format: "%.0f°C", celsius)
    }

    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        switch (h, m) {
        case (0, _): return t("\(m)분", "\(m) min")
        case (_, 0): return t("\(h)시간", "\(h) h")
        default: return t("\(h)시간 \(m)분", "\(h) h \(m) min")
        }
    }

    static func remaining(until date: Date, now: Date = Date()) -> String {
        duration(minutes: max(0, Int((date.timeIntervalSince(now) / 60).rounded(.up))))
    }
}

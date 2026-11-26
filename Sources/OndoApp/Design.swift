import AppKit
import SwiftUI

/// Design tokens adapted from Astryx (meta/astryx, theme-neutral): a 4 pt spacing scale, corner radius by role,
/// shared control heights and type roles. The accent is Tory Labs violet; other colors carry meaning only.
/// Mockup: design/mockups/astryx-direction.html
enum DS {
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
    }

    /// Inner content, controls, containers: nested corners stay concentric.
    enum Radius {
        static let inner: CGFloat = 6
        static let element: CGFloat = 10
        static let container: CGFloat = 12
    }

    enum Height {
        static let sm: CGFloat = 28
        static let md: CGFloat = 32
        static let row: CGFloat = 44
    }

    enum Font {
        static let title = SwiftUI.Font.system(size: 17, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 14)
        static let label = SwiftUI.Font.system(size: 12, weight: .medium)
        static let supporting = SwiftUI.Font.system(size: 12)
        static let display = SwiftUI.Font.system(size: 29, weight: .semibold).monospacedDigit()
        static let large = SwiftUI.Font.system(size: 17, weight: .medium).monospacedDigit()
    }

    enum Palette {
        static let accent = Color(light: rgb(0x5b4bd6), dark: rgb(0x8b7cf6))
        static let accentMuted = Color(light: rgb(0xece9fb), dark: rgb(0x8b7cf6, 0.22))
        /// Fill for inset surfaces (segment track, temperature card, chips) on top of the menu's material.
        static let fill = Color(light: rgb(0x000000, 0.05), dark: rgb(0xffffff, 0.08))
        static let card = Color(light: rgb(0xffffff), dark: rgb(0x2a2a2d))
        static let windowBody = Color(light: rgb(0xf1f1f1), dark: rgb(0x1c1c1e))
        static let border = Color(light: rgb(0x000000, 0.078), dark: rgb(0xffffff, 0.10))
        static let fieldBorder = Color(light: rgb(0xd4d4d4), dark: rgb(0xffffff, 0.18))
        static let warningFill = Color(light: rgb(0xfff1e0), dark: rgb(0xd97706, 0.20))
        static let warningText = Color(light: rgb(0x8a4b00), dark: rgb(0xffb35c))
        static let danger = Color(light: rgb(0xc0262c), dark: rgb(0xff6b6b))
    }

    /// Height of the menu slot shared by the end-time group and the overheat warning, so a warning never resizes the menu.
    static let endSlotHeight: CGFloat = 16 + 3 * Height.sm + 3 * Space.sm
}

/// How hot a reading is, from cooled down to the limit; drives the menu bar thermometer and the gauge.
/// User decision 2026-11-26: blue up to 40°C, then a gradient that moves toward red as the temperature rises.
struct Heat {
    /// At or below this the Mac counts as cooled down ("쿨링상태는 40도").
    static let coolBelow = 40.0
    /// Colors along the way from `coolBelow` (0) to the limit (1); readings between stops blend.
    static let stops: [(level: Double, color: UInt32)] = [
        (0, 0x0a7cf0), (0.35, 0x2e9e45), (0.65, 0xe0b000), (0.85, 0xf07a10), (1, 0xd9292e),
    ]

    /// 0 at or below `coolBelow`, 1 at or above the limit; nil when the temperature cannot be read.
    let level: Double?

    init(celsius: Double?, limit: Double) {
        level = celsius.map { min(max(($0 - Self.coolBelow) / max(limit - Self.coolBelow, 1), 0), 1) }
    }

    var color: NSColor {
        guard let level else { return .secondaryLabelColor }
        let upper = Self.stops.firstIndex { $0.level >= level } ?? Self.stops.count - 1
        let b = Self.stops[upper], a = Self.stops[max(upper - 1, 0)]
        let t = b.level > a.level ? (level - a.level) / (b.level - a.level) : 1
        return rgb(a.color).blended(withFraction: t, of: rgb(b.color)) ?? rgb(b.color)
    }

    /// The mercury height repeats the color's meaning for people who cannot tell the colors apart.
    var symbol: String {
        guard let level else { return "thermometer.low" }
        return level < 1.0 / 3 ? "thermometer.low" : level < 2.0 / 3 ? "thermometer.medium" : "thermometer.high"
    }
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

extension Color {
    /// A color that follows the light or dark appearance of the view it is drawn in.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil ? dark : light
        })
    }
}

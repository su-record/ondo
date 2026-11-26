import AppKit

/// The menu bar icon: a closed laptop with a thermometer on it. The mercury always shows the CPU's heat level
/// in color and height; the laptop is solid while ondo keeps the Mac awake and dimmed while off.
enum MenuBarGlyph {
    static let size = NSSize(width: 22, height: 20)
    static let thermometerPointSize: CGFloat = 9.5

    static func image(heat: Heat, awake: Bool) -> NSImage {
        // Drawn on demand, so `labelColor` resolves against the menu bar's own appearance.
        let image = NSImage(size: size, flipped: false) { _ in
            let ink = awake ? NSColor.labelColor : NSColor.labelColor.withAlphaComponent(0.5)
            ink.setFill()
            NSBezierPath(roundedRect: NSRect(x: 2, y: 1.5, width: 18, height: 2.6), xRadius: 1.3, yRadius: 1.3).fill()
            ink.withAlphaComponent(awake ? 0.6 : 0.35).setFill()
            NSBezierPath(roundedRect: NSRect(x: 3.5, y: 4.6, width: 15, height: 1.6), xRadius: 0.8, yRadius: 0.8).fill()

            let config = NSImage.SymbolConfiguration(pointSize: thermometerPointSize, weight: .bold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [heat.color, NSColor.labelColor]))
            if let thermometer = NSImage(systemSymbolName: heat.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let origin = NSPoint(x: (size.width - thermometer.size.width) / 2, y: 6.6)
                thermometer.draw(in: NSRect(origin: origin, size: thermometer.size))
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}

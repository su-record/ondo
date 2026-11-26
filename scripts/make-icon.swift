// Draws ondo's app icon (a closed laptop with a thermometer) and writes Resources/AppIcon.icns,
// plus the 1024 px master for review. Chosen design: option C in design/mockups/astryx-direction.html.
// Run: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let canvas: CGFloat = 1024
/// Apple's macOS icon grid: an 824 pt rounded square centred on a 1024 pt canvas.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185
/// The website's violet (--glow #7c6cf0 to --accent #5b4bd6), a little deeper at the bottom.
let top = NSColor(srgbRed: 0x86 / 255, green: 0x77 / 255, blue: 0xf4 / 255, alpha: 1)
let bottom = NSColor(srgbRed: 0x4f / 255, green: 0x40 / 255, blue: 0xc8 / 255, alpha: 1)

/// The mercury is warm orange, the menu bar glyph's "warm" color; the tube is white.
let mercury = NSColor(srgbRed: 0xff / 255, green: 0x8a / 255, blue: 0x3d / 255, alpha: 1)

func thermometer(pointSize: CGFloat) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [mercury, .white]))
    guard let symbol = NSImage(systemSymbolName: "thermometer.medium", accessibilityDescription: nil)?.withSymbolConfiguration(config) else {
        fatalError("missing SF Symbol thermometer.medium")
    }
    return symbol
}

func drawIcon() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let shape = NSBezierPath(roundedRect: body, xRadius: cornerRadius, yRadius: cornerRadius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    bottom.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: top, ending: bottom)!.draw(in: shape, angle: -90)

    // A closed laptop seen from the side: base and lid.
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 232, y: 300, width: 560, height: 56), xRadius: 28, yRadius: 28).fill()
    NSColor.white.withAlphaComponent(0.78).setFill()
    NSBezierPath(roundedRect: NSRect(x: 262, y: 362, width: 500, height: 34), xRadius: 17, yRadius: 17).fill()
    let gauge = thermometer(pointSize: 330)
    gauge.draw(at: NSPoint(x: (canvas - gauge.size.width) / 2, y: (canvas - gauge.size.height) / 2 + 150), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let master = root.appendingPathComponent("Resources/AppIcon-1024.png")
try drawIcon().representation(using: .png, properties: [:])!.write(to: master)

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        let pixels = size * scale
        let resize = Process()
        resize.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        resize.arguments = ["-z", "\(pixels)", "\(pixels)", master.path, "--out", iconset.appendingPathComponent(name).path]
        resize.standardOutput = FileHandle.nullDevice
        try resize.run()
        resize.waitUntilExit()
    }
}
let icns = Process()
icns.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
icns.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try icns.run()
icns.waitUntilExit()
print(icns.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")

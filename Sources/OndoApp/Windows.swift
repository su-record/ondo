import AppKit
import SwiftUI

/// Opens the settings and debug windows, one of each.
@MainActor
final class Windows {
    private let controller: Controller
    private var open: [String: NSWindow] = [:]

    init(controller: Controller) {
        self.controller = controller
    }

    func showSettings() {
        show(id: "settings", title: L.t("ondo 설정", "ondo Settings"), SettingsView(controller: controller)) { window in
            // The tab bar sits in the title bar area, as in the mockup.
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.styleMask.remove(.resizable)
        }
    }

    /// The menu panel in a window, for when the menu bar hides ondo's icon (a crowded bar or a menu bar organizer).
    func showPanel() {
        show(id: "panel", title: "ondo", MenuView(controller: controller, windows: self)) { window in
            window.styleMask.remove(.resizable)
            window.styleMask.remove(.miniaturizable)
        }
    }

    func showDebug() {
        show(id: "debug", title: L.t("ondo 디버그", "ondo Debug"), DebugView(controller: controller))
    }

    private func show<Content: View>(id: String, title: String, _ content: Content, configure: (NSWindow) -> Void = { _ in }) {
        let window = open[id] ?? {
            let window = NSWindow(contentViewController: NSHostingController(rootView: content))
            window.title = title
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            configure(window)
            window.center()
            open[id] = window
            return window
        }()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

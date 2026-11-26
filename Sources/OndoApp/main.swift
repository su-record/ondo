import AppKit
import OndoCore
import OndoShared
import SwiftUI

/// SwiftUI owns the menu bar item; the settings and debug windows are plain AppKit windows opened on demand,
/// so nothing opens at launch.
struct OndoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(controller: delegate.controller, windows: delegate.windows)
        } label: {
            MenuBarIcon(controller: delegate.controller)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = Controller()
    lazy var windows = Windows(controller: controller)
    private let server = ControlServer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await controller.launch() }
        let controller = self.controller
        do {
            try server.start { request in await controller.handle(request) }
        } catch {
            controller.note("control socket unavailable: \(error)")
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await controller.didWake() }
        }
        workspace.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await controller.shutdown() }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        server.stop()
        Task {
            await controller.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Opening ondo again (Spotlight, Finder, `open -a ondo`) shows the menu panel in a window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.showPanel()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { Task { await controller.handle(url: url) } }
    }
}

OndoApp.main()

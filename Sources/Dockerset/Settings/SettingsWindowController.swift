import AppKit
import SwiftUI

/// Owns the Settings window so it can be opened from anywhere: the menu bar, the Dock's right-click menu,
/// a dockerset://settings URL, or reopening the app from Finder.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let root = SettingsView()
                .environmentObject(AppState.shared)
                .frame(minWidth: 780, minHeight: 540)
            let controller = NSHostingController(rootView: root)
            controller.sizingOptions = [.minSize]
            let window = NSWindow(contentViewController: controller)
            window.title = "Dockerset Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 900, height: 600))
            window.center()
            window.setFrameAutosaveName("DockersetSettings")
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

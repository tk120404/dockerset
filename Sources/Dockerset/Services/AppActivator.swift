import AppKit

/// Brings an app forward the way the macOS Dock does.
@MainActor
enum AppActivator {
    static func open(appAt path: String) {
        let url = URL(fileURLWithPath: path)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        guard let app = RunningApps.shared.app(at: path) else {
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return
        }
        if app.isHidden { app.unhide() }
        // The Dock panel never makes Dockerset the active app, and since macOS 14 an inactive app can't activate
        // another one. So take activation from the user's click, then hand it to the app with all its windows.
        NSApp.activate()
        app.activate(from: .current, options: [.activateAllWindows])
        // Fallback through Launch Services, which also handles apps that ignore the hand-off.
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)

        // Like the Dock: when every window is minimized, bring the most recent one back.
        let pid = app.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !hasVisibleWindow(pid), let window = MinimizedWindows.shared.windows.first(where: { $0.pid == pid }) {
                MinimizedWindows.shared.restore(window)
            }
        }
    }

    private static func hasVisibleWindow(_ pid: pid_t) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
        }
    }
}

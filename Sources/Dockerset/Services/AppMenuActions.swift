import AppKit

/// App actions for the Dock's app menu. The items an app adds to the macOS Dock's own menu come from a
/// private Dock channel, so for Chromium browsers they're rebuilt with the browser's command-line switches.
enum AppMenuActions {
    private static let chromium: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi",
    ]

    static func isChromium(_ bundleID: String?) -> Bool { bundleID.map(chromium.contains) ?? false }

    /// Runs the browser with switches; a running browser receives them and opens the window itself.
    static func launchChromium(_ appURL: URL, _ arguments: [String]) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    /// New window: browser switch for Chromium, otherwise ⌘N sent to the app (needs Accessibility).
    static func newWindow(_ app: NSRunningApplication) {
        if isChromium(app.bundleIdentifier), let url = app.bundleURL {
            launchChromium(url, ["--new-window"])
            return
        }
        NSApp.activate()
        app.activate(from: .current, options: [])
        let pid = app.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let source = CGEventSource(stateID: .hidSystemState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0x2D, keyDown: down) // N
                event?.flags = .maskCommand
                event?.postToPid(pid)
            }
        }
    }
}

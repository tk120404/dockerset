import AppKit
import ApplicationServices

struct MinimizedWindow: Identifiable {
    let id: String
    let pid: pid_t
    let title: String
    let appPath: String?
    let element: AXUIElement
}

/// Finds minimized windows through the Accessibility API so the Dock can restore them.
@MainActor
final class MinimizedWindows: ObservableObject {
    static let shared = MinimizedWindows()

    @Published private(set) var windows: [MinimizedWindow] = []
    @Published private(set) var trusted = AXIsProcessTrusted()

    private let queue = DispatchQueue(label: "dockerset.minimized", qos: .utility)
    private var timer: Timer?
    private var scanning = false

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
    }

    func refresh() {
        trusted = AXIsProcessTrusted()
        let config = AppState.shared.config
        guard trusted, config.appearance.showMinimized, config.mode != .native else {
            if !windows.isEmpty { windows = [] }
            return
        }
        guard !scanning else { return }
        scanning = true
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID }
            .map { (pid: $0.processIdentifier, path: $0.bundleURL?.path, name: $0.localizedName ?? "Window") }

        queue.async {
            let found = Self.scan(apps)
            Task { @MainActor in
                self.scanning = false
                if found.map(\.id) != self.windows.map(\.id) { self.windows = found }
            }
        }
    }

    func restore(_ window: MinimizedWindow) {
        AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: window.pid)?.activate()
        windows.removeAll { $0.id == window.id }
    }

    private nonisolated static func scan(_ apps: [(pid: pid_t, path: String?, name: String)]) -> [MinimizedWindow] {
        var result: [MinimizedWindow] = []
        for app in apps {
            let axApp = AXUIElementCreateApplication(app.pid)
            // A hung app must not stall the scan for the default 6 seconds.
            AXUIElementSetMessagingTimeout(axApp, 0.25)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }
            for (index, window) in windows.enumerated() {
                var minimized: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
                guard (minimized as? Bool) == true else { continue }
                var title: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
                let name = (title as? String).flatMap { $0.isEmpty ? nil : $0 } ?? app.name
                result.append(MinimizedWindow(
                    id: "\(app.pid)-\(index)-\(name)", pid: app.pid, title: name, appPath: app.path, element: window
                ))
            }
        }
        return result
    }
}

/// One window of an app, for the Dock's right-click window list.
struct AppWindow: Identifiable {
    let id: Int
    let title: String
    let minimized: Bool
    /// The app's main (frontmost) window, ticked in the menu like the macOS Dock does.
    let main: Bool
    let element: AXUIElement
}

extension MinimizedWindows {
    /// The app's standard windows (all of them, including minimized ones). Needs Accessibility access.
    /// Cached for 2 seconds: SwiftUI may rebuild menu contents whenever the Dock redraws.
    static func windows(of pid: pid_t) -> [AppWindow] {
        if let cached = windowCache[pid], Date().timeIntervalSince(cached.date) < 2 { return cached.windows }
        let windows = readWindows(of: pid)
        windowCache[pid] = (Date(), windows)
        return windows
    }

    private static var windowCache: [pid_t: (date: Date, windows: [AppWindow])] = [:]

    private nonisolated static func readWindows(of pid: pid_t) -> [AppWindow] {
        guard AXIsProcessTrusted() else { return [] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement] else { return [] }
        return elements.enumerated().compactMap { index, window in
            func attribute(_ name: String) -> CFTypeRef? {
                var v: CFTypeRef?
                AXUIElementCopyAttributeValue(window, name as CFString, &v)
                return v
            }
            guard (attribute(kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole else { return nil }
            let title = (attribute(kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled"
            return AppWindow(id: index, title: title, minimized: (attribute(kAXMinimizedAttribute) as? Bool) == true,
                             main: (attribute(kAXMainAttribute) as? Bool) == true, element: window)
        }
    }

    /// Restores (if minimized), raises and focuses one window, switching desktops if it's on another one.
    static func focus(_ window: AppWindow, pid: pid_t) {
        if window.minimized {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        NSApp.activate()
        NSRunningApplication(processIdentifier: pid)?.activate(from: .current, options: [])
    }
}

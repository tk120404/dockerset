import AppKit

/// Tracks which app bundles are running, for the Dock's running indicators.
@MainActor
final class RunningApps: ObservableObject {
    static let shared = RunningApps()

    @Published private(set) var paths: Set<String> = []

    private init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    private func refresh() {
        paths = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.standardizedFileURL.path })
    }

    func isRunning(_ path: String) -> Bool {
        paths.contains(URL(fileURLWithPath: path).standardizedFileURL.path)
    }

    func app(at path: String) -> NSRunningApplication? {
        let target = URL(fileURLWithPath: path).standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL.path == target }
    }
}

import Foundation
import CoreGraphics

/// Reads and writes the macOS Dock's preferences (com.apple.dock) and restarts the Dock to apply them.
enum NativeDock {
    private static let domain = "com.apple.dock" as CFString
    private static let snapshotKeys = [
        "persistent-apps", "persistent-others", "tilesize", "orientation",
        "autohide", "autohide-delay", "magnification", "largesize",
    ]
    private static let finderPath = "/System/Library/CoreServices/Finder.app"
    private static let hiddenFlag = "nativeDockHiddenByDockerset"
    private static let autohideBeforeKey = "nativeDockAutohideBefore"

    static var originalBackupURL: URL { Store.dir.appendingPathComponent("original-dock.plist") }
    static var hasOriginalBackup: Bool { FileManager.default.fileExists(atPath: originalBackupURL.path) }

    // MARK: Raw preferences

    static func value(_ key: String) -> Any? {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key as CFString, domain)
    }

    static func set(_ key: String, _ value: Any?) {
        CFPreferencesSetAppValue(key as CFString, value.map { $0 as AnyObject }, domain)
    }

    /// Flushes preferences and relaunches the Dock so it picks them up.
    static func restart() {
        CFPreferencesAppSynchronize(domain)
        _ = Shell.run("/usr/bin/killall", ["Dock"])
    }

    // MARK: Snapshots

    static func snapshot() -> Data? {
        var dict: [String: Any] = [:]
        for key in snapshotKeys {
            if let v = value(key) { dict[key] = v }
        }
        return try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
    }

    static func restore(_ data: Data) {
        guard let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return }
        for key in snapshotKeys { set(key, dict[key]) }
        UserDefaults.standard.removeObject(forKey: hiddenFlag)
        UserDefaults.standard.removeObject(forKey: autohideBeforeKey)
        restart()
    }

    /// Saves the user's Dock exactly once, before Dockerset changes it for the first time.
    static func ensureOriginalBackup() {
        guard !hasOriginalBackup, let data = snapshot() else { return }
        try? data.write(to: originalBackupURL, options: .atomic)
    }

    static func restoreOriginal() {
        guard let data = try? Data(contentsOf: originalBackupURL) else { return }
        restore(data)
    }

    // MARK: Layouts

    /// Items currently in the macOS Dock (Finder first, Trash omitted).
    static func currentItems() -> [DockItem] {
        var items: [DockItem] = [.app(URL(fileURLWithPath: finderPath))]
        let apps = value("persistent-apps") as? [[String: Any]] ?? []
        let others = value("persistent-others") as? [[String: Any]] ?? []
        for tile in apps + others {
            let type = tile["tile-type"] as? String ?? ""
            let data = tile["tile-data"] as? [String: Any] ?? [:]
            switch type {
            case "small-spacer-tile":
                items.append(.spacer(small: true))
            case "spacer-tile", "flex-spacer-tile":
                items.append(.spacer())
            case "file-tile", "directory-tile":
                guard let url = fileURL(data["file-data"]) else { continue }
                let label = data["file-label"] as? String ?? url.deletingPathExtension().lastPathComponent
                if url.pathExtension == "app" {
                    items.append(DockItem(kind: .app, label: label, path: url.path))
                } else {
                    items.append(DockItem(kind: .folder, label: label, path: url.path))
                }
            case "url-tile":
                guard let urlData = data["url"] as? [String: Any], let s = urlData["_CFURLString"] as? String else { continue }
                items.append(.link(data["label"] as? String ?? s, s))
            default:
                continue
            }
        }
        return items
    }

    /// Writes a layout into the macOS Dock. Widgets have no native equivalent and are skipped.
    /// Call `restart()` afterwards.
    static func write(layout: Layout) {
        ensureOriginalBackup()
        var apps: [[String: Any]] = []
        var others: [[String: Any]] = []
        for item in layout.items {
            switch item.kind {
            case .app:
                guard let path = item.path, path != finderPath else { continue }
                apps.append([
                    "tile-type": "file-tile",
                    "tile-data": [
                        "file-label": item.label,
                        "file-type": 41,
                        "file-data": fileData(path),
                    ] as [String: Any],
                ])
            case .spacer:
                apps.append(["tile-type": item.smallSpacer ? "small-spacer-tile" : "spacer-tile", "tile-data": [String: Any]()])
            case .folder:
                guard let path = item.path else { continue }
                others.append([
                    "tile-type": "directory-tile",
                    "tile-data": [
                        "file-label": item.label,
                        "file-type": 2,
                        "file-data": fileData(path),
                        "arrangement": 2, // date added
                        "displayas": 0,   // stack
                        "showas": 0,      // automatic
                    ] as [String: Any],
                ])
            case .link:
                guard let url = item.url else { continue }
                others.append([
                    "tile-type": "url-tile",
                    "tile-data": [
                        "label": item.label,
                        "url": ["_CFURLString": url, "_CFURLStringType": 15] as [String: Any],
                    ] as [String: Any],
                ])
            case .widget:
                continue
            }
        }
        // Spacers that only separated apps from widgets would be dangling gaps in the macOS Dock.
        while let last = apps.last?["tile-type"] as? String, last.hasSuffix("spacer-tile") { apps.removeLast() }
        set("persistent-apps", apps)
        set("persistent-others", others)
    }

    /// Size (16–128) and edge of the macOS Dock. Call `restart()` afterwards.
    static func writeAppearance(tileSize: Int, orientation: DockPosition) {
        ensureOriginalBackup()
        set("tilesize", tileSize)
        set("orientation", orientation.rawValue)
    }

    /// Where the macOS Dock sits, used to keep the custom Dock out of its way.
    struct Geometry: Equatable {
        var orientation: DockPosition
        var tileSize: Int
        var autohide: Bool

        static var current: Geometry {
            Geometry(orientation: NativeDock.orientation, tileSize: NativeDock.tileSize,
                     autohide: (NativeDock.value("autohide") as? Bool) ?? false)
        }

        /// Approximate thickness of the Dock, including its margin from the screen edge.
        var footprint: CGFloat { CGFloat(tileSize) * 1.25 + 18 }
    }

    static var tileSize: Int { (value("tilesize") as? NSNumber)?.intValue ?? 48 }
    static var orientation: DockPosition { DockPosition(rawValue: value("orientation") as? String ?? "") ?? .bottom }

    // MARK: Hiding (custom Dock only)

    static var isHiddenByUs: Bool { UserDefaults.standard.bool(forKey: hiddenFlag) }

    /// Effectively hides the macOS Dock: auto-hide with a reveal delay nobody will ever wait out.
    /// Returns true if the Dock's preferences changed (and it needs a restart).
    @discardableResult
    static func hide() -> Bool {
        guard !isHiddenByUs else { return false }
        ensureOriginalBackup()
        UserDefaults.standard.set((value("autohide") as? Bool) ?? false, forKey: autohideBeforeKey)
        UserDefaults.standard.set(true, forKey: hiddenFlag)
        set("autohide", true)
        set("autohide-delay", 1000.0)
        return true
    }

    @discardableResult
    static func unhide() -> Bool {
        guard isHiddenByUs else { return false }
        set("autohide", UserDefaults.standard.bool(forKey: autohideBeforeKey))
        set("autohide-delay", nil)
        UserDefaults.standard.removeObject(forKey: hiddenFlag)
        UserDefaults.standard.removeObject(forKey: autohideBeforeKey)
        return true
    }

    private static var watchdogStarted = false

    /// Starts a tiny shell process that outlives Dockerset. If Dockerset exits while the macOS Dock is still
    /// hidden (a crash, a force quit), it puts the Dock back. On a normal quit the flag is already cleared.
    static func startWatchdog() {
        guard !watchdogStarted, let bundleID = Bundle.main.bundleIdentifier else { return }
        watchdogStarted = true
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 2; done
        if [ "$(defaults read \(bundleID) \(hiddenFlag) 2>/dev/null)" = "1" ]; then
          if [ "$(defaults read \(bundleID) \(autohideBeforeKey) 2>/dev/null)" = "1" ]; then
            defaults write com.apple.dock autohide -bool true
          else
            defaults write com.apple.dock autohide -bool false
          fi
          defaults delete com.apple.dock autohide-delay
          defaults delete \(bundleID) \(hiddenFlag)
          defaults delete \(bundleID) \(autohideBeforeKey)
          killall Dock
        fi
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    // MARK: Helpers

    private static func fileData(_ path: String) -> [String: Any] {
        ["_CFURLString": URL(fileURLWithPath: path).absoluteString, "_CFURLStringType": 15]
    }

    private static func fileURL(_ fileData: Any?) -> URL? {
        guard let d = fileData as? [String: Any], let s = d["_CFURLString"] as? String else { return nil }
        // Type 0 is a plain path, 15 is a file:// URL string.
        if (d["_CFURLStringType"] as? Int) == 0 { return URL(fileURLWithPath: s) }
        guard let url = URL(string: s), url.isFileURL else { return nil }
        return url
    }
}

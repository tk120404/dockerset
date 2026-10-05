import Foundation

/// Lists and runs macOS Shortcuts through the `shortcuts` command-line tool.
enum ShortcutsService {
    static func list() async -> [String] {
        let out = await Shell.runAsync("/usr/bin/shortcuts", ["list"]) ?? ""
        return out.split(separator: "\n").map(String.init).filter { !$0.isEmpty }.sorted()
    }

    @discardableResult
    static func run(_ name: String) async -> Bool {
        await Shell.runAsync("/usr/bin/shortcuts", ["run", name]) != nil
    }
}

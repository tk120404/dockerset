import Foundation

/// Persists the configuration in ~/Library/Application Support/Dockerset.
enum Store {
    static let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Dockerset", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var configURL: URL { dir.appendingPathComponent("config.json") }

    static func load() -> Config? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            // Keep the unreadable file around instead of silently overwriting it.
            let aside = dir.appendingPathComponent("config.unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: configURL, to: aside)
            NSLog("Dockerset: could not read config (\(error)); moved to \(aside.path)")
            return nil
        }
    }

    static func save(_ config: Config) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(config).write(to: configURL, options: .atomic)
        } catch {
            NSLog("Dockerset: failed to save config: \(error)")
        }
    }

    // MARK: Backups

    struct Backup: Codable {
        var version = 1
        var created = Date()
        var config: Config
        /// Binary plist snapshot of the macOS Dock preferences.
        var nativeDock: Data?
    }

    static func exportBackup(_ config: Config, includeNative: Bool, to url: URL) throws {
        let backup = Backup(config: config, nativeDock: includeNative ? NativeDock.snapshot() : nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(backup).write(to: url, options: .atomic)
    }

    static func importBackup(from url: URL) throws -> Backup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Backup.self, from: Data(contentsOf: url))
    }
}

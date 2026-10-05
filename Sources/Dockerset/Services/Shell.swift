import Foundation

enum Shell {
    /// Runs a command synchronously and returns trimmed stdout, or nil on failure. Don't call on the main thread
    /// for anything slow.
    @discardableResult
    static func run(_ path: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func runAsync(_ path: String, _ args: [String]) async -> String? {
        await Task.detached { run(path, args) }.value
    }
}

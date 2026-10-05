import Foundation

/// Reads Claude plan limits through Claude Code's status line. Claude Code passes a `rate_limits` object
/// (five_hour / seven_day: used_percentage, resets_at) to the status-line command for Pro and Max plans, after
/// the session's first response. Connecting installs a small script as that command: it saves only
/// `rate_limits` and then runs the user's previous status-line command, so their status line keeps working.
enum ClaudeLimitsBridge {
    private static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }
    static var scriptURL: URL { Store.dir.appendingPathComponent("claude-statusline.sh") }
    static var limitsURL: URL { Store.dir.appendingPathComponent("claude-rate-limits.json") }
    /// The user's previous `statusLine` value (JSON), restored on disconnect.
    private static var previousURL: URL { Store.dir.appendingPathComponent("claude-statusline-previous.json") }
    /// The previous command alone, which the script runs after saving the limits.
    private static var previousCommandURL: URL { Store.dir.appendingPathComponent("claude-statusline-previous-command") }

    private static var command: String { "\"\(scriptURL.path)\"" }

    static var isConnected: Bool {
        guard let line = settings()?["statusLine"] else { return false }
        let cmd = (line as? [String: Any])?["command"] as? String ?? line as? String
        return cmd == command
    }

    // MARK: Connect / disconnect

    static func connect() throws {
        var s = settings() ?? [:]
        guard !isConnected else { return }
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            let backup = Store.dir.appendingPathComponent("claude-settings-backup-\(Int(Date().timeIntervalSince1970)).json")
            try FileManager.default.copyItem(at: settingsURL, to: backup)
        }

        let previous = s["statusLine"]
        let previousCommand = (previous as? [String: Any])?["command"] as? String ?? previous as? String ?? ""
        try JSONSerialization.data(withJSONObject: ["value": previous ?? NSNull()]).write(to: previousURL, options: .atomic)
        try previousCommand.write(to: previousCommandURL, atomically: true, encoding: .utf8)
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        // Keep the user's other status-line options (padding, refreshInterval…); only the command changes.
        var line = previous as? [String: Any] ?? [:]
        line["type"] = "command"
        line["command"] = command
        s["statusLine"] = line
        try write(s)
    }

    /// Restores the previous status line, unless the user has since replaced ours with something else.
    static func disconnect() throws {
        guard isConnected, var s = settings() else { return }
        let saved = (try? Data(contentsOf: previousURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        if let previous = saved?["value"], !(previous is NSNull) {
            s["statusLine"] = previous
        } else {
            s.removeValue(forKey: "statusLine")
        }
        try write(s)
        try? FileManager.default.removeItem(at: limitsURL)
    }

    // MARK: Reading

    static func read() -> AIProviderLimits {
        guard isConnected else {
            return AIProviderLimits(message: "Turn on “Connect Claude Code” in Settings → Widgets → AI, then send a message in Claude Code.")
        }
        guard let data = try? Data(contentsOf: limitsURL),
              let limits = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return AIProviderLimits(message: "Connected. Send a message in a signed-in Claude Code session; limits appear for Pro and Max plans.")
        }
        let updated = (try? limitsURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let windows: [AILimitWindow] = [("five_hour", "5-hour"), ("seven_day", "Weekly"), ("spend_limit", "Spend limit")]
            .compactMap { key, name in
                guard let w = limits[key] as? [String: Any], let used = (w["used_percentage"] as? NSNumber)?.doubleValue else { return nil }
                let reset = (w["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
                return AILimitWindow(id: key, name: name, usedPercent: used, resetsAt: reset)
            }
        if windows.isEmpty {
            return AIProviderLimits(updated: updated, message: "Claude Code didn't include limits in its last update. This happens on plans without them.")
        }
        return AIProviderLimits(windows: windows, updated: updated)
    }

    // MARK: Helpers

    private static func settings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func write(_ s: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: s, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }

    private static var script: String {
        """
        #!/bin/sh
        # Installed by Dockerset. Saves only Claude Code's `rate_limits` for the AI Limits widget,
        # then runs your previous status-line command so your status line is unchanged.
        dir="$HOME/Library/Application Support/Dockerset"
        input=$(cat)
        if limits=$(printf '%s' "$input" | plutil -extract rate_limits json -o - - 2>/dev/null); then
          printf '%s' "$limits" > "$dir/claude-rate-limits.json.tmp" && mv "$dir/claude-rate-limits.json.tmp" "$dir/claude-rate-limits.json"
        fi
        previous=$(cat "$dir/claude-statusline-previous-command" 2>/dev/null)
        if [ -n "$previous" ]; then
          printf '%s' "$input" | sh -c "$previous"
        fi

        """
    }
}

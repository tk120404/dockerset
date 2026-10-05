import Foundation

struct AILimitWindow: Identifiable, Equatable {
    let id: String
    let name: String
    let usedPercent: Double
    let resetsAt: Date?
}

struct AIProviderLimits: Equatable {
    var windows: [AILimitWindow] = []
    var plan: String?
    var updated: Date?
    /// Setup instructions or the error when there are no windows to show.
    var message: String?

    /// The window closest to running out: what the Dock shows.
    var headline: AILimitWindow? { windows.max { $0.usedPercent < $1.usedPercent } }
}

struct AIDay: Equatable {
    var tokens = 0
    var sessions: Set<String> = []
    var toolCalls = 0

    mutating func merge(_ other: AIDay) {
        tokens += other.tokens
        sessions.formUnion(other.sessions)
        toolCalls += other.toolCalls
    }
}

/// AI allowance windows and local token activity. All reading happens on a background queue.
@MainActor
final class AIUsageModel: ObservableObject {
    static let shared = AIUsageModel()

    @Published private(set) var limits: [AIProvider: AIProviderLimits] = [:]
    /// Provider → local day ("yyyy-MM-dd") → activity.
    @Published private(set) var activity: [AIProvider: [String: AIDay]] = [:]
    @Published private(set) var refreshing = false

    private let queue = DispatchQueue(label: "dockerset.ai", qos: .utility)
    private var timer: Timer?
    private var lastSlowRefresh: Date?

    func start() {
        refresh(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(force: false) }
        }
    }

    /// Local sources every call; Copilot (a network call) at most every 5 minutes unless forced.
    func refresh(force: Bool) {
        let slow = force || lastSlowRefresh.map { Date().timeIntervalSince($0) > 300 } ?? true
        if slow { lastSlowRefresh = Date() }
        refreshing = true
        queue.async {
            var found: [AIProvider: AIProviderLimits] = [
                .codex: Self.codexLimits(),
                .claude: ClaudeLimitsBridge.read(),
            ]
            if slow { found[.copilot] = Self.copilotLimits() }
            let history: [AIProvider: [String: AIDay]] = [
                .claude: Self.activity(root: ".claude/projects", parse: Self.parseClaude),
                .codex: Self.activity(root: ".codex/sessions", parse: Self.parseCodex),
            ]
            Task { @MainActor in
                var merged = self.limits
                for (provider, value) in found { merged[provider] = value }
                if merged != self.limits { self.limits = merged }
                if history != self.activity { self.activity = history }
                self.refreshing = false
            }
        }
    }

    // MARK: Activity queries

    /// Day starts covered by a range, oldest first. "Today" still charts the last 7 days for context.
    static func chartDays(_ range: AIRange) -> [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let count: Int = switch range {
        case .today, .last7: 7
        case .last30: 30
        case .month: cal.component(.day, from: today)
        }
        return (0..<count).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
    }

    static func totalDays(_ range: AIRange) -> [Date] {
        range == .today ? [Calendar.current.startOfDay(for: Date())] : chartDays(range)
    }

    func series(_ provider: AIProvider, _ range: AIRange) -> [(date: Date, tokens: Int)] {
        let days = activity[provider] ?? [:]
        return Self.chartDays(range).map { ($0, days[Self.dayKey($0)]?.tokens ?? 0) }
    }

    /// Sessions are counted once across the whole range.
    func total(_ provider: AIProvider, _ range: AIRange) -> AIDay {
        let days = activity[provider] ?? [:]
        var sum = AIDay()
        for day in Self.totalDays(range) {
            if let d = days[Self.dayKey(day)] { sum.merge(d) }
        }
        return sum
    }

    func day(_ provider: AIProvider, _ date: Date) -> AIDay {
        activity[provider]?[Self.dayKey(date)] ?? AIDay()
    }

    nonisolated static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: Local activity (Claude Code, Codex)

    /// Per-file results, reused while a file's size and modification date are unchanged. Queue-only.
    nonisolated(unsafe) private static var fileCache: [String: (modified: Date, size: Int, days: [String: AIDay])] = [:]

    private nonisolated static func activity(root: String, parse: (URL) -> [String: AIDay]) -> [String: AIDay] {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(root)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: keys) else { return [:] }
        let cutoff = Date().addingTimeInterval(-32 * 86_400) // covers L30 and any month-to-date
        var result: [String: AIDay] = [:]
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  let modified = v.contentModificationDate, modified > cutoff else { continue }
            let size = v.fileSize ?? 0
            let days: [String: AIDay]
            if let cached = fileCache[url.path], cached.modified == modified, cached.size == size {
                days = cached.days
            } else {
                days = parse(url)
                fileCache[url.path] = (modified, size, days)
            }
            for (key, day) in days { result[key, default: AIDay()].merge(day) }
        }
        return result
    }

    private nonisolated static func lines(_ url: URL) -> [Substring] {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true)
    }

    private nonisolated static func json(_ line: Substring) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    }

    private nonisolated static func timestamp(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// Claude Code: assistant messages carry `usage` (including cache tokens); a streamed message repeats
    /// the same usage on several lines, so each message id is counted once. Tool calls are `tool_use` blocks.
    private nonisolated static func parseClaude(_ url: URL) -> [String: AIDay] {
        var days: [String: AIDay] = [:]
        var seen = Set<String>()
        for line in lines(url) where line.contains("\"assistant\"") {
            guard let d = json(line), d["type"] as? String == "assistant",
                  let message = d["message"] as? [String: Any], let date = timestamp(d["timestamp"]) else { continue }
            let key = dayKey(date)
            if let session = d["sessionId"] as? String { days[key, default: AIDay()].sessions.insert(session) }
            let blocks = message["content"] as? [[String: Any]] ?? []
            days[key, default: AIDay()].toolCalls += blocks.filter { $0["type"] as? String == "tool_use" }.count
            let id = "\(message["id"] as? String ?? "")|\(d["requestId"] as? String ?? "")"
            guard let usage = message["usage"] as? [String: Any], seen.insert(id).inserted else { continue }
            let tokens = ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
                .reduce(0) { $0 + ((usage[$1] as? Int) ?? 0) }
            days[key, default: AIDay()].tokens += tokens
        }
        return days
    }

    /// Codex: `token_count` events give each turn's tokens; tool calls are function/shell call items.
    private nonisolated static func parseCodex(_ url: URL) -> [String: AIDay] {
        var days: [String: AIDay] = [:]
        let session = url.deletingPathExtension().lastPathComponent
        let toolTypes: Set<String> = ["function_call", "custom_tool_call", "local_shell_call"]
        for line in lines(url) {
            guard line.contains("token_count") || line.contains("_call\"") else { continue }
            guard let d = json(line), let payload = d["payload"] as? [String: Any],
                  let date = timestamp(d["timestamp"]) else { continue }
            let key = dayKey(date)
            let type = payload["type"] as? String ?? ""
            if type == "token_count" {
                let info = payload["info"] as? [String: Any]
                let last = info?["last_token_usage"] as? [String: Any]
                days[key, default: AIDay()].tokens += (last?["total_tokens"] as? Int) ?? 0
                days[key, default: AIDay()].sessions.insert(session)
            } else if toolTypes.contains(type) {
                days[key, default: AIDay()].toolCalls += 1
                days[key, default: AIDay()].sessions.insert(session)
            }
        }
        return days
    }

    // MARK: Limits

    nonisolated(unsafe) private static var codexCache: (newest: Date, limits: AIProviderLimits)?

    /// Codex records the ChatGPT plan's windows in `token_count` events; the newest one wins.
    private nonisolated static func codexLimits() -> AIProviderLimits {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return AIProviderLimits(message: "Install Codex and sign in with your ChatGPT account (run `codex login`).")
        }
        let files = (walker.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "jsonl" }
            .map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
        guard let newest = files.first?.1 else {
            return AIProviderLimits(message: "No Codex sessions yet. Use Codex signed in with ChatGPT, then refresh.")
        }
        if let cached = codexCache, cached.newest == newest { return cached.limits }

        var result = AIProviderLimits(message: "No limits reported yet. Codex reports them for ChatGPT logins (not API keys) after a task.")
        search: for (url, _) in files.prefix(40) {
            for line in lines(url).reversed() where line.contains("\"rate_limits\":{") {
                guard let d = json(line), let payload = d["payload"] as? [String: Any],
                      let limits = payload["rate_limits"] as? [String: Any] else { continue }
                let updated = timestamp(d["timestamp"])
                let windows: [AILimitWindow] = ["primary", "secondary"].compactMap { key in
                    guard let w = limits[key] as? [String: Any], let used = (w["used_percent"] as? NSNumber)?.doubleValue else { return nil }
                    let minutes = (w["window_minutes"] as? NSNumber)?.intValue ?? 0
                    var reset = (w["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
                    if reset == nil, let inSeconds = (w["resets_in_seconds"] as? NSNumber)?.doubleValue, let updated {
                        reset = updated.addingTimeInterval(inSeconds)
                    }
                    return AILimitWindow(id: key, name: windowName(minutes), usedPercent: used, resetsAt: reset)
                }
                guard !windows.isEmpty else { continue }
                result = AIProviderLimits(windows: windows, plan: (limits["plan_type"] as? String)?.capitalized, updated: updated)
                break search
            }
        }
        codexCache = (newest, result)
        return result
    }

    nonisolated static func windowName(_ minutes: Int) -> String {
        switch minutes {
        case 300: "5-hour"
        case 1440: "Daily"
        case 10080: "Weekly"
        case 0: "Limit"
        default: minutes % 1440 == 0 ? "\(minutes / 1440)-day" : "\(minutes / 60)-hour"
        }
    }

    /// GitHub Copilot quotas through the GitHub CLI's existing login. Uses GitHub's internal
    /// `copilot_internal/user` endpoint (what Copilot's own clients call), so it may change without notice.
    private nonisolated static func copilotLimits() -> AIProviderLimits {
        guard let gh = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"].first(where: FileManager.default.isExecutableFile) else {
            return AIProviderLimits(message: "Install GitHub CLI and run `gh auth login` with the account that has Copilot.")
        }
        guard let out = Shell.run(gh, ["api", "/copilot_internal/user"]),
              let d = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any] else {
            return AIProviderLimits(message: "Couldn't read Copilot quotas. Run `gh auth login` with the GitHub account that has Copilot, then refresh.")
        }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        let reset = (d["quota_reset_date"] as? String).flatMap(parser.date)
        let snapshots = d["quota_snapshots"] as? [String: [String: Any]] ?? [:]
        let windows: [AILimitWindow] = [("premium_interactions", "Premium requests"), ("chat", "Chat"), ("completions", "Completions")]
            .compactMap { key, name in
                // Unlimited or absent allowances aren't turned into invented percentages.
                guard let s = snapshots[key], s["unlimited"] as? Bool != true,
                      ((s["entitlement"] as? NSNumber)?.doubleValue ?? 0) > 0,
                      let left = (s["percent_remaining"] as? NSNumber)?.doubleValue else { return nil }
                return AILimitWindow(id: key, name: name, usedPercent: 100 - left, resetsAt: reset)
            }
        if windows.isEmpty { return AIProviderLimits(message: "This GitHub account reports no limited Copilot quotas.") }
        return AIProviderLimits(windows: windows, plan: (d["copilot_plan"] as? String)?.capitalized, updated: Date())
    }
}

func formatTokens(_ n: Int) -> String {
    switch n {
    case 1_000_000_000...: String(format: "%.1fB", Double(n) / 1e9)
    case 1_000_000...: String(format: "%.1fM", Double(n) / 1e6)
    case 1_000...: String(format: "%.1fK", Double(n) / 1e3)
    default: "\(n)"
    }
}

func formatResetsIn(_ date: Date?) -> String? {
    guard let date else { return nil }
    let seconds = Int(date.timeIntervalSinceNow)
    // A passed reset time doesn't mean the allowance is full again; we just don't know yet.
    guard seconds > 0 else { return "reset time passed" }
    let days = seconds / 86_400, hours = seconds / 3600 % 24, minutes = seconds / 60 % 60
    if days > 0 { return "resets in \(days)d \(hours)h" }
    if hours > 0 { return "resets in \(hours)h \(minutes)m" }
    return "resets in \(max(1, minutes))m"
}

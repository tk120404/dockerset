import AppKit
import SwiftUI

/// Polls Spotify and Apple Music over AppleScript (osascript, off the main thread).
@MainActor
final class NowPlaying: ObservableObject {
    static let shared = NowPlaying()

    enum Player: String {
        case spotify = "com.spotify.client"
        case music = "com.apple.Music"
    }

    struct Track: Equatable {
        var player: Player
        var title: String
        var artist: String
        var playing: Bool
        var artworkURL: URL?
    }

    @Published private(set) var track: Track?

    private let queue = DispatchQueue(label: "dockerset.nowplaying", qos: .utility)
    private var timer: Timer?
    private nonisolated static let separator = "|~|"

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private var candidates: [Player] {
        switch AppState.shared.config.widgets.player {
        case .auto: [.spotify, .music]
        case .spotify: [.spotify]
        case .music: [.music]
        }
    }

    func poll() {
        // Only talk to players that are already running; AppleScript would otherwise launch them.
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let players = candidates.filter { running.contains($0.rawValue) }
        queue.async {
            var best: Track?
            for player in players {
                guard let t = Self.query(player) else { continue }
                if t.playing { best = t; break }
                if best == nil { best = t }
            }
            Task { @MainActor in
                if self.track != best { self.track = best }
            }
        }
    }

    /// Sends a player command such as "playpause", "next track" or "previous track".
    func send(_ command: String) {
        let player = track?.player ?? (candidates.first == .spotify ? .spotify : .music)
        queue.async {
            Shell.run("/usr/bin/osascript", ["-e", "tell application id \"\(player.rawValue)\" to \(command)"])
            Task { @MainActor in self.poll() }
        }
    }

    private nonisolated static func query(_ player: Player) -> Track? {
        let artwork = player == .spotify ? " & \"\(separator)\" & (artwork url of current track)" : ""
        let script = """
        tell application id "\(player.rawValue)"
            if player state is stopped then return ""
            return (player state as string) & "\(separator)" & (name of current track) & "\(separator)" & (artist of current track)\(artwork)
        end tell
        """
        guard let out = Shell.run("/usr/bin/osascript", ["-e", script]), !out.isEmpty else { return nil }
        let parts = out.components(separatedBy: separator)
        guard parts.count >= 3 else { return nil }
        return Track(
            player: player,
            title: parts[1],
            artist: parts[2],
            playing: parts[0] == "playing",
            artworkURL: parts.count > 3 ? URL(string: parts[3]) : nil
        )
    }
}

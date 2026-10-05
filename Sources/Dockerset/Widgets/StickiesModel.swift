import AppKit
import SwiftUI

struct StickyNote: Identifiable, Equatable {
    let id: String
    let text: String
    let red: Double
    let green: Double
    let blue: Double
    let modified: Date

    var color: Color { Color(red: red, green: green, blue: blue) }
}

/// Reads the notes of Apple's Stickies app (read-only) so the Dock can show them directly.
@MainActor
final class StickiesModel: ObservableObject {
    static let shared = StickiesModel()

    @Published private(set) var notes: [StickyNote] = []
    /// Stickies' folder exists but macOS refused to let Dockerset read it.
    @Published private(set) var accessDenied = false

    nonisolated static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/com.apple.Stickies/Data/Library/Stickies", isDirectory: true)

    private let queue = DispatchQueue(label: "dockerset.stickies", qos: .utility)
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        queue.async {
            let (found, denied) = Self.read()
            Task { @MainActor in
                if self.notes != found { self.notes = found }
                if self.accessDenied != denied { self.accessDenied = denied }
            }
        }
    }

    private nonisolated static func read() -> ([StickyNote], Bool) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else { return ([], false) }
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return ([], true)
        }
        let colors = noteColors()
        let notes: [StickyNote] = files.filter { $0.pathExtension == "rtfd" }.compactMap { note in
            let rtf = note.appendingPathComponent("TXT.rtf")
            guard let text = try? NSAttributedString(url: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                     documentAttributes: nil).string else { return nil }
            let id = note.deletingPathExtension().lastPathComponent
            let modified = (try? rtf.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            // Stickies' classic yellow when the note's colour isn't recorded.
            let c = colors[id] ?? (0.996, 0.957, 0.612)
            return StickyNote(id: id, text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                              red: c.0, green: c.1, blue: c.2, modified: modified)
        }
        return (notes.sorted { $0.modified > $1.modified }, false)
    }

    /// Note UUID → background colour, from Stickies' saved window state.
    private nonisolated static func noteColors() -> [String: (Double, Double, Double)] {
        let url = folder.appendingPathComponent(".SavedStickiesState")
        guard let data = try? Data(contentsOf: url),
              let states = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [[String: Any]] else { return [:] }
        var result: [String: (Double, Double, Double)] = [:]
        for state in states {
            guard let id = state["UUID"] as? String, let c = state["StickyColor"] as? [String: Double],
                  let r = c["Red"], let g = c["Green"], let b = c["Blue"] else { continue }
            result[id] = (r, g, b)
        }
        return result
    }

    func openStickies() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Stickies.app"), configuration: .init())
    }
}

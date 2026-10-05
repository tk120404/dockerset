import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var config: Config {
        didSet { if config != oldValue { Store.save(config) } }
    }

    let isFirstLaunch: Bool

    /// Shrink factor the Dock applies when it wouldn't fit on screen, like the macOS Dock. Not saved.
    @Published var fitScale: Double = 1

    /// The appearance the Dock actually draws with: the user's settings, shrunk to fit if needed.
    var dockAppearance: Appearance {
        var a = config.appearance
        a.iconSize = (a.iconSize * fitScale).rounded()
        return a
    }

    private init() {
        if let saved = Store.load() {
            config = saved
            isFirstLaunch = false
        } else {
            config = .initial()
            isFirstLaunch = true
            Store.save(config)
        }
    }

    var activeLayout: Layout? {
        config.layouts.first { $0.id == config.activeLayoutID } ?? config.layouts.first
    }

    private var activeIndex: Int? {
        guard let id = activeLayout?.id else { return nil }
        return config.layouts.firstIndex { $0.id == id }
    }

    // MARK: Switching

    func activateLayout(_ id: UUID) {
        guard let layout = config.layouts.first(where: { $0.id == id }) else { return }
        config.activeLayoutID = id
        if config.mode != .custom && config.syncNativeOnSwitch {
            NativeDock.write(layout: layout)
            NativeDock.restart()
        }
    }

    @discardableResult
    func activateLayout(named name: String) -> Bool {
        guard let layout = config.layouts.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            return false
        }
        activateLayout(layout.id)
        return true
    }

    func activateNextLayout() {
        guard let i = activeIndex, !config.layouts.isEmpty else { return }
        activateLayout(config.layouts[(i + 1) % config.layouts.count].id)
    }

    func setMode(_ mode: DockMode) {
        guard mode != config.mode else { return }
        config.mode = mode
        let changed = mode == .custom ? NativeDock.hide() : NativeDock.unhide()
        if changed { NativeDock.restart() }
    }

    func applyModeOnLaunch() {
        if config.mode == .custom && NativeDock.hide() {
            NativeDock.restart()
        }
    }

    /// Never leave the user without a Dock once Dockerset isn't running.
    func restoreNativeOnQuit() {
        if NativeDock.unhide() {
            NativeDock.restart()
        }
    }

    func applyToNative(_ layout: Layout) {
        NativeDock.write(layout: layout)
        NativeDock.restart()
    }

    // MARK: Editing

    @discardableResult
    func captureNativeDock() -> UUID {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let layout = Layout(name: "macOS Dock (\(formatter.string(from: Date())))", items: NativeDock.currentItems())
        config.layouts.append(layout)
        return layout.id
    }

    @discardableResult
    func addLayout() -> UUID {
        let layout = Layout(name: "New Layout", items: [])
        config.layouts.append(layout)
        return layout.id
    }

    @discardableResult
    func duplicateLayout(_ id: UUID) -> UUID? {
        guard let source = config.layouts.first(where: { $0.id == id }) else { return nil }
        let copy = Layout(name: source.name + " Copy", items: source.items.map { $0.copy() })
        config.layouts.append(copy)
        return copy.id
    }

    func deleteLayout(_ id: UUID) {
        guard config.layouts.count > 1 else { return }
        config.layouts.removeAll { $0.id == id }
        if config.activeLayoutID == id { config.activeLayoutID = config.layouts.first?.id }
    }

    func addToActive(_ items: [DockItem]) {
        guard let i = activeIndex else { return }
        config.layouts[i].items.append(contentsOf: items)
    }

    /// Inserts a spacer after the given item of the active layout, or at the end when nil.
    func insertSpacer(after itemID: UUID?, small: Bool) {
        guard let i = activeIndex else { return }
        let items = config.layouts[i].items
        let position = itemID.flatMap { id in items.firstIndex { $0.id == id }.map { $0 + 1 } } ?? items.count
        config.layouts[i].items.insert(.spacer(small: small), at: position)
    }

    func setSpacerSize(_ itemID: UUID, small: Bool) {
        guard let i = activeIndex, let j = config.layouts[i].items.firstIndex(where: { $0.id == itemID }) else { return }
        config.layouts[i].items[j].smallSpacer = small
        config.layouts[i].items[j].label = small ? "Small Spacer" : "Spacer"
    }

    func removeItem(_ itemID: UUID) {
        guard let i = activeIndex else { return }
        config.layouts[i].items.removeAll { $0.id == itemID }
    }

    func restoreBackup(_ backup: Store.Backup, includeNative: Bool) {
        let previousMode = config.mode
        config = backup.config
        if includeNative, let native = backup.nativeDock {
            NativeDock.restore(native)
        }
        if config.mode != previousMode {
            let changed = config.mode == .custom ? NativeDock.hide() : NativeDock.unhide()
            if changed { NativeDock.restart() }
        }
    }
}

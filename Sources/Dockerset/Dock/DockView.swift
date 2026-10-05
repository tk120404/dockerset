import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DockView: View {
    /// Reports the Dock's ideal size whenever it changes (items added, icon size, widgets loading…).
    var onSize: (CGSize) -> Void
    @EnvironmentObject private var state: AppState
    @ObservedObject private var minimized = MinimizedWindows.shared

    var body: some View {
        let a = state.dockAppearance
        let items = state.activeLayout?.items ?? []
        let vertical = a.position != .bottom
        let stack = vertical ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))

        // Scroll-area items are gathered into one strip, placed where the first of them sits.
        let regular = items.filter { !($0.inScroll && $0.canScroll) }
        let scrolling = items.filter { $0.inScroll && $0.canScroll }
        let split = items.firstIndex { $0.inScroll && $0.canScroll }
            .map { i in items[..<i].filter { !($0.inScroll && $0.canScroll) }.count } ?? regular.count

        stack {
            ForEach(Array(regular.prefix(split))) { DockTile(item: $0) }
            if !scrolling.isEmpty { ScrollStrip(items: scrolling) }
            ForEach(Array(regular.dropFirst(split))) { DockTile(item: $0) }
            if items.isEmpty {
                Text("Drop apps here").foregroundStyle(.secondary).padding(8)
            }
            if a.showMinimized && !minimized.windows.isEmpty {
                Rectangle()
                    .fill(.secondary.opacity(0.5))
                    .frame(width: vertical ? a.iconSize * 0.8 : 1, height: vertical ? 1 : a.iconSize * 0.8)
                    .padding(vertical ? .vertical : .horizontal, 4)
                ForEach(minimized.windows) { MinimizedTile(window: $0) }
            }
        }
        .padding(10)
        .background { DockBackground(appearance: a) }
        // Right-clicking the Dock's background (tiles have their own menus).
        .contextMenu { DockBackgroundMenu() }
        // Transparent headroom so magnified icons aren't clipped by the panel.
        .padding(headroomEdge(a.position), a.magnification ? a.iconSize * 0.45 : 0)
        .padding(10)
        .fixedSize()
        .onGeometryChange(for: CGSize.self, of: { $0.size }, action: onSize)
        .onDrop(of: [.fileURL, .url], isTargeted: nil, perform: handleDrop)
    }

    private func headroomEdge(_ position: DockPosition) -> Edge.Set {
        switch position {
        case .bottom: .top
        case .left: .trailing
        case .right: .leading
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                let item: DockItem = if url.isFileURL {
                    url.pathExtension == "app" ? .app(url) : .folder(url)
                } else {
                    .link(url.host() ?? url.absoluteString, url.absoluteString)
                }
                Task { @MainActor in AppState.shared.addToActive([item]) }
            }
        }
        return true
    }
}

struct DockBackgroundMenu: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Menu("Layout") {
            ForEach(state.config.layouts) { layout in
                Toggle(layout.name, isOn: Binding(
                    get: { layout.id == state.activeLayout?.id },
                    set: { if $0 { state.activateLayout(layout.id) } }
                ))
            }
        }
        Menu("Add Spacer") {
            Button("Small") { state.insertSpacer(after: nil, small: true) }
            Button("Regular") { state.insertSpacer(after: nil, small: false) }
        }
        Divider()
        Button("Dockerset Settings…") { SettingsWindowController.shared.show() }
        Button("Quit Dockerset") { NSApp.terminate(nil) }
    }
}

struct DockBackground: View {
    let appearance: Appearance

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: appearance.cornerRadius, style: .continuous)
        Group {
            switch appearance.material {
            case .glass:
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(.regular, in: shape).opacity(appearance.opacity)
                } else {
                    blur(.hudWindow)
                }
            case .solid:
                shape.fill(Color(nsColor: .windowBackgroundColor)).opacity(appearance.opacity)
            default:
                blur(appearance.material.nsMaterial)
            }
        }
        .overlay(shape.strokeBorder(.white.opacity(0.18 * max(appearance.opacity, 0.3)), lineWidth: 0.5))
    }

    // Behind-window blur is composited by the window server, so SwiftUI's clipShape and opacity don't
    // reach it; the rounding and opacity have to be set on the NSVisualEffectView itself.
    private func blur(_ material: NSVisualEffectView.Material) -> some View {
        VisualEffectView(material: material, cornerRadius: appearance.cornerRadius, opacity: appearance.opacity)
    }
}

extension DockMaterial {
    var nsMaterial: NSVisualEffectView.Material {
        switch self {
        case .hud, .glass: .hudWindow
        case .popover: .popover
        case .menu: .menu
        case .sidebar: .sidebar
        case .underWindow: .underWindowBackground
        case .solid: .windowBackground
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    var cornerRadius: CGFloat = 0
    var opacity: Double = 1

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.maskImage = Self.mask(radius: cornerRadius)
        view.alphaValue = opacity
    }

    /// A stretchable rounded-rectangle mask: corners stay fixed, the middle stretches.
    private static func mask(radius: CGFloat) -> NSImage? {
        guard radius > 0 else { return nil }
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

// MARK: Tiles

/// A fixed-length strip of icons with ‹ › arrows; also scrolls with the trackpad or mouse wheel.
struct ScrollStrip: View {
    let items: [DockItem]
    @EnvironmentObject private var state: AppState
    @State private var position: Int?

    var body: some View {
        let a = state.dockAppearance
        let vertical = a.position != .bottom
        let visible = max(1, min(a.scrollVisible, items.count))
        let spacing: CGFloat = 6
        let extent = CGFloat(visible) * a.iconSize + CGFloat(visible - 1) * spacing
        let lastStart = items.count - visible
        let current = min(position ?? 0, lastStart)
        let stack = vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
        let row = vertical ? AnyLayout(VStackLayout(spacing: spacing)) : AnyLayout(HStackLayout(spacing: spacing))
        // Room for the running-indicator dots, which would otherwise be clipped by the scroll view.
        let dotRoom: Edge.Set = vertical ? .horizontal : .vertical

        stack {
            if lastStart > 0 {
                arrow(vertical ? "chevron.up" : "chevron.left", size: a.iconSize, enabled: current > 0) {
                    position = max(0, current - visible)
                }
            }
            ScrollView(vertical ? .vertical : .horizontal) {
                row {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        DockTile(item: item, magnify: false).id(index)
                    }
                }
                .padding(dotRoom, 9)
                .scrollTargetLayout()
            }
            .scrollPosition(id: $position, anchor: vertical ? .top : .leading)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            // Exact size: the strip's length, and one icon plus the dot room across. The negative padding
            // then hands that dot room back so the strip is no thicker than the other icons.
            .frame(width: vertical ? a.iconSize + 18 : extent, height: vertical ? extent : a.iconSize + 18)
            .padding(dotRoom, -9)
            if lastStart > 0 {
                arrow(vertical ? "chevron.down" : "chevron.right", size: a.iconSize, enabled: current < lastStart) {
                    position = min(lastStart, current + visible)
                }
            }
        }
    }

    private func arrow(_ symbol: String, size: CGFloat, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.25), action) } label: {
            Image(systemName: symbol)
                .font(.system(size: max(12, size * 0.32), weight: .medium))
                .frame(width: size * 0.5, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? .primary : .tertiary)
        .disabled(!enabled)
    }
}

struct DockTile: View {
    let item: DockItem
    /// Off inside the scroll area, where a magnified icon would be clipped.
    var magnify = true
    @EnvironmentObject private var state: AppState
    @ObservedObject private var running = RunningApps.shared
    @State private var hovering = false
    @State private var showStack = false

    var body: some View {
        let a = state.dockAppearance
        switch item.kind {
        case .spacer:
            let gap = item.smallSpacer ? a.iconSize * 0.4 : a.iconSize
            Color.clear.frame(width: gap, height: gap)
                .contentShape(Rectangle())
                .contextMenu {
                    Section("Spacer Size") {
                        Toggle("Small", isOn: Binding(get: { item.smallSpacer }, set: { if $0 { state.setSpacerSize(item.id, small: true) } }))
                        Toggle("Regular", isOn: Binding(get: { !item.smallSpacer }, set: { if $0 { state.setSpacerSize(item.id, small: false) } }))
                    }
                    Divider()
                    removeButton
                }
        case .widget:
            WidgetHost(kind: item.widget ?? .weather, size: a.iconSize)
                .contextMenu {
                    addSpacerMenu
                    Divider()
                    removeButton
                }
        case .app, .folder, .link:
            iconTile(a)
        }
    }

    private func iconTile(_ a: Appearance) -> some View {
        let anchor: UnitPoint = switch a.position {
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
        let indicator: Alignment = switch a.position {
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
        let offset: CGSize = switch a.position {
        case .bottom: CGSize(width: 0, height: 7)
        case .left: CGSize(width: -7, height: 0)
        case .right: CGSize(width: 7, height: 0)
        }
        let isRunning = item.kind == .app && item.path.map(running.isRunning) == true

        return TileIcon(item: item, size: a.iconSize, showInitial: a.folderInitials, tagColors: a.folderTagColors)
            .scaleEffect(hovering && a.magnification && magnify ? 1.4 : 1, anchor: anchor)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: hovering)
            .overlay(alignment: indicator) {
                if isRunning {
                    Circle().fill(.primary.opacity(0.75)).frame(width: 4, height: 4).offset(offset)
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: open)
            .help(item.label)
            .contextMenu { menu }
            .popover(isPresented: $showStack) { FolderStack(path: item.path ?? "") }
            .zIndex(hovering ? 1 : 0)
    }

    private func open() {
        switch item.kind {
        case .app:
            guard let path = item.path else { return }
            AppActivator.open(appAt: path)
        case .folder:
            guard let path = item.path else { return }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                showStack.toggle()
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
        case .link:
            if let s = item.url, let url = URL(string: s) { NSWorkspace.shared.open(url) }
        case .spacer, .widget:
            break
        }
    }

    @ViewBuilder private var menu: some View {
        switch item.kind {
        case .app:
            // Same layout as the macOS Dock: windows, the app's own items, Options, then Show All / Hide / Quit.
            if let path = item.path, let app = running.isRunning(path) ? running.app(at: path) : nil {
                AppDockMenu(app: app, appURL: URL(fileURLWithPath: path)) { optionsMenu(path) }
            } else if let path = item.path {
                Button("Open") { open() }
                Divider()
                optionsMenu(path)
            }
        case .folder:
            if let path = item.path {
                Button("Open in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
            }
        case .link:
            Button("Open Link") { open() }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url ?? "", forType: .string)
            }
        case .spacer, .widget:
            EmptyView()
        }
        if item.kind != .app {
            Divider()
            addSpacerMenu
            removeButton
        }
    }

    private func optionsMenu(_ path: String) -> some View {
        Menu("Options") {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
            addSpacerMenu
            Divider()
            removeButton
        }
    }

    private var addSpacerMenu: some View {
        Menu("Add Spacer") {
            Button("Small") { state.insertSpacer(after: item.id, small: true) }
            Button("Regular") { state.insertSpacer(after: item.id, small: false) }
        }
    }

    private var removeButton: some View {
        Button("Remove from Dock", role: .destructive) { state.removeItem(item.id) }
    }
}

/// A running app's right-click menu, laid out like the macOS Dock's.
struct AppDockMenu<Options: View>: View {
    let app: NSRunningApplication
    let appURL: URL
    @ViewBuilder var options: () -> Options

    var body: some View {
        let pid = app.processIdentifier
        if AXIsProcessTrusted() {
            ForEach(MinimizedWindows.windows(of: pid)) { window in
                Toggle(isOn: Binding(get: { window.main }, set: { _ in MinimizedWindows.focus(window, pid: pid) })) {
                    Label(window.title, systemImage: window.minimized ? "minus.rectangle" : "macwindow")
                }
            }
        } else {
            Button("Allow Accessibility to List Windows…") { MinimizedWindows.shared.requestAccess() }
        }
        Divider()

        Button("New Window") { AppMenuActions.newWindow(app) }
        if AppMenuActions.isChromium(app.bundleIdentifier) {
            Button("New Incognito Window") { AppMenuActions.launchChromium(appURL, ["--incognito"]) }
        }
        Divider()
        options()
        Divider()
        Button("Show All Windows") {
            NSApp.activate()
            app.activate(from: .current, options: [.activateAllWindows])
        }
        Button(app.isHidden ? "Show" : "Hide") { if app.isHidden { app.unhide() } else { app.hide() } }
        Button("Quit") { app.terminate() }
    }
}

struct TileIcon: View {
    let item: DockItem
    let size: CGFloat
    var showInitial = false
    var tagColors = true

    var body: some View {
        switch item.kind {
        case .link:
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .top, endPoint: .bottom))
                .overlay(Image(systemName: "globe").font(.system(size: size * 0.45)).foregroundStyle(.white))
                .frame(width: size * 0.84, height: size * 0.84)
                .frame(width: size, height: size)
        default:
            if let path = item.path, FileManager.default.fileExists(atPath: path) {
                Image(nsImage: icon(for: path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
                    .overlay {
                        if showInitial, item.kind == .folder, Self.isPlainFolder(path), let letter = item.label.first {
                            Text(String(letter).uppercased())
                                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                                .offset(y: size * 0.07) // centre on the folder's body, below the tab
                        }
                    }
            } else {
                // Missing on this Mac, e.g. after restoring a backup from another machine.
                Image(systemName: "questionmark.app.dashed")
                    .font(.system(size: size * 0.7))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            }
        }
    }
}

extension TileIcon {
    private func icon(for path: String) -> NSImage {
        let base = NSWorkspace.shared.icon(forFile: path)
        guard tagColors, item.kind == .folder, Self.isPlainFolder(path), let color = Self.tagColor(path) else { return base }
        return Self.tinted(base, color)
    }

    /// Finder's colour for the folder's first coloured tag, using today's Finder palette.
    static func tagColor(_ path: String) -> NSColor? {
        let label = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.labelNumberKey]))?.labelNumber ?? 0
        return switch label {
        case 1: .systemGray
        case 2: .systemGreen
        case 3: .systemPurple
        case 4: .systemBlue
        case 5: .systemYellow
        case 6: .systemRed
        case 7: .systemOrange
        default: nil
        }
    }

    /// Recolours the icon: the tag colour, masked to the icon's shape, keeping its shading.
    static func tinted(_ base: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
            base.draw(in: rect)
            color.withAlphaComponent(0.85).set()
            rect.fill(using: .sourceAtop)
            base.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
    }

    /// A real folder, not a file or a package such as an .app bundle.
    static func isPlainFolder(_ path: String) -> Bool {
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }
}

struct FolderStack: View {
    let path: String

    var body: some View {
        let url = URL(fileURLWithPath: path)
        let files = Self.contents(of: url)
        VStack(alignment: .leading, spacing: 10) {
            Text(url.lastPathComponent).font(.headline)
            if files.isEmpty {
                Text("Empty folder").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(80)), count: 4), spacing: 10) {
                        ForEach(files, id: \.self) { file in
                            Button { NSWorkspace.shared.open(file) } label: {
                                VStack(spacing: 4) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                                        .resizable()
                                        .frame(width: 48, height: 48)
                                    Text(file.lastPathComponent)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(width: 80)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onDrag { NSItemProvider(contentsOf: file) ?? NSItemProvider() }
                        }
                    }
                }
                .frame(height: min(320, CGFloat((files.count + 3) / 4) * 90))
            }
            Button("Open in Finder") { NSWorkspace.shared.open(url) }
        }
        .padding()
        .frame(width: 370)
    }

    /// Newest first, like a Dock stack sorted by date added.
    private static func contents(of url: URL) -> [URL] {
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        )) ?? []
        func date(_ u: URL) -> Date {
            let v = try? u.resourceValues(forKeys: Set(keys))
            return v?.addedToDirectoryDate ?? v?.contentModificationDate ?? .distantPast
        }
        return Array(files.map { ($0, date($0)) }.sorted { $0.1 > $1.1 }.map(\.0).prefix(60))
    }
}

struct MinimizedTile: View {
    let window: MinimizedWindow
    @EnvironmentObject private var state: AppState

    var body: some View {
        let size = state.dockAppearance.iconSize
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.14))
                .frame(width: size, height: size * 0.72)
                .overlay(Image(systemName: "macwindow").font(.system(size: size * 0.32)).foregroundStyle(.secondary))
                .frame(width: size, height: size)
            if let path = window.appPath {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .frame(width: size * 0.45, height: size * 0.45)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .help(window.title)
        .onTapGesture { MinimizedWindows.shared.restore(window) }
    }
}

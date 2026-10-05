import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            LayoutsTab().tabItem { Label("Layouts", systemImage: "square.stack.3d.up") }
            AppearanceTab().tabItem { Label("Appearance", systemImage: "paintbrush") }
            WidgetsTab().tabItem { Label("Widgets", systemImage: "square.grid.2x2") }
            FocusTab().tabItem { Label("Focus", systemImage: "moon") }
            BackupTab().tabItem { Label("Backup", systemImage: "externaldrive") }
        }
        .padding()
    }
}

// MARK: Layouts

struct LayoutsTab: View {
    @EnvironmentObject private var state: AppState
    @State private var selection: UUID?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                List(selection: $selection) {
                    ForEach(state.config.layouts) { layout in
                        HStack {
                            Text(layout.name)
                            Spacer()
                            if layout.id == state.activeLayout?.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Active layout")
                            }
                        }
                        .tag(layout.id)
                    }
                    .onMove { state.config.layouts.move(fromOffsets: $0, toOffset: $1) }
                }
                HStack(spacing: 4) {
                    Button { selection = state.addLayout() } label: { Image(systemName: "plus") }
                        .help("New layout")
                    Button { if let s = selection { selection = state.duplicateLayout(s) } } label: {
                        Image(systemName: "plus.square.on.square")
                    }
                    .help("Duplicate layout")
                    .disabled(selection == nil)
                    Button {
                        if let s = selection {
                            state.deleteLayout(s)
                            selection = state.activeLayout?.id
                        }
                    } label: { Image(systemName: "minus") }
                    .help("Delete layout")
                    .disabled(selection == nil || state.config.layouts.count <= 1)
                }
                Button("Capture Current macOS Dock") { selection = state.captureNativeDock() }
            }
            .padding(.trailing, 8)
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)

            Group {
                if let id = selection, let binding = layoutBinding(id) {
                    LayoutEditor(layout: binding)
                } else {
                    Text("Select a layout").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 440)
        }
        .onAppear { selection = selection ?? state.activeLayout?.id }
    }

    /// Binding by id rather than index, so deleting a layout can't leave a dangling index.
    private func layoutBinding(_ id: UUID) -> Binding<Layout>? {
        guard state.config.layouts.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { state.config.layouts.first { $0.id == id } ?? Layout(name: "", items: []) },
            set: { new in
                if let i = state.config.layouts.firstIndex(where: { $0.id == id }) { state.config.layouts[i] = new }
            }
        )
    }
}

struct LayoutEditor: View {
    @EnvironmentObject private var state: AppState
    @Binding var layout: Layout
    @State private var showLinkSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Layout name", text: $layout.name)
                    .textFieldStyle(.plain)
                    .font(.title2.bold())
                Spacer()
                Button("Activate") { state.activateLayout(layout.id) }
                    .disabled(layout.id == state.activeLayout?.id)
                Button("Apply to macOS Dock") { state.applyToNative(layout) }
                    .help("Rewrites the macOS Dock with this layout's apps, folders and links. Widgets are skipped.")
            }
            List {
                ForEach($layout.items) { $item in
                    ItemRow(item: $item) { layout.items.removeAll { $0.id == item.id } }
                }
                .onMove { layout.items.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            HStack {
                Button("Add Apps…") { layout.items += pick(apps: true).map(DockItem.app) }
                Button("Add Folders…") { layout.items += pick(apps: false).map(DockItem.folder) }
                Button("Add Link…") { showLinkSheet = true }
                Menu("Add Spacer") {
                    Button("Small") { layout.items.append(.spacer(small: true)) }
                    Button("Regular") { layout.items.append(.spacer()) }
                }
                .fixedSize()
                Menu("Add Widget") {
                    ForEach(WidgetKind.allCases) { kind in
                        Button { layout.items.append(.widget(kind)) } label: { Label(kind.title, systemImage: kind.symbol) }
                    }
                }
                .fixedSize()
            }
            Text("Drag rows to reorder. Tick “Scroll area” to put an item in the Dock's scrolling strip. You can also drop apps, folders and links straight onto the Dock.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 8)
        .sheet(isPresented: $showLinkSheet) {
            LinkSheet { name, url in layout.items.append(.link(name, url)) }
        }
    }

    private func pick(apps: Bool) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = !apps
        if apps {
            panel.allowedContentTypes = [.application]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }
        return panel.runModal() == .OK ? panel.urls : []
    }
}

struct ItemRow: View {
    @Binding var item: DockItem
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Group {
                switch item.kind {
                case .spacer: Image(systemName: "arrow.left.and.right").foregroundStyle(.secondary)
                case .widget: Image(systemName: item.widget?.symbol ?? "square").foregroundStyle(.tint)
                default: TileIcon(item: item, size: 22)
                }
            }
            .frame(width: 24, height: 24)
            if item.kind == .spacer || item.kind == .widget {
                Text(item.label)
            } else {
                TextField("Label", text: $item.label).textFieldStyle(.plain)
            }
            Spacer()
            if item.kind == .spacer {
                Picker("Size", selection: $item.smallSpacer) {
                    Text("Small").tag(true)
                    Text("Regular").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            if item.canScroll {
                Toggle("Scroll area", isOn: $item.inScroll)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .help("Show this item in the Dock's scroll area, with ‹ › arrows")
            }
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Remove")
        }
    }

    private var detail: String {
        switch item.kind {
        case .app, .folder:
            guard let path = item.path else { return "" }
            return FileManager.default.fileExists(atPath: path) ? path : "Missing: \(path)"
        case .link: return item.url ?? ""
        case .spacer: return "Spacer"
        case .widget: return "Widget"
        }
    }
}

struct LinkSheet: View {
    var onAdd: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = "https://"

    private var parsed: URL? {
        guard let u = URL(string: url.trimmingCharacters(in: .whitespaces)), u.scheme != nil, u.host() != nil else { return nil }
        return u
    }

    var body: some View {
        Form {
            TextField("Name", text: $name)
            TextField("URL", text: $url)
        }
        .padding()
        .frame(width: 380)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    guard let u = parsed else { return }
                    onAdd(name.isEmpty ? (u.host() ?? u.absoluteString) : name, u.absoluteString)
                    dismiss()
                }
                .disabled(parsed == nil)
            }
        }
    }
}

// MARK: Appearance

struct AppearanceTab: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var minimized = MinimizedWindows.shared
    @State private var nativeSize = Double(NativeDock.tileSize)
    @State private var nativePosition = NativeDock.orientation
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Which Dock") {
                Picker("Show", selection: Binding(get: { state.config.mode }, set: { state.setMode($0) })) {
                    ForEach(DockMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(modeHelp).font(.caption).foregroundStyle(.secondary)
                Toggle("Update the macOS Dock when switching layouts", isOn: $state.config.syncNativeOnSwitch)
                    .disabled(state.config.mode == .custom)
            }
            Section("Dockerset Dock") {
                Picker("Position", selection: $state.config.appearance.position) {
                    ForEach(DockPosition.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Icon size") {
                    Slider(value: $state.config.appearance.iconSize, in: 28...96, step: 2)
                    Text("\(Int(state.config.appearance.iconSize)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                if state.fitScale < 1 {
                    Text("The Dock doesn't fit on screen at this size, so icons are shrunk to \(Int(state.dockAppearance.iconSize)) pt. Remove items or use the scroll area to make room.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Magnify on hover", isOn: $state.config.appearance.magnification)
                Toggle("Show the first letter on folder icons", isOn: $state.config.appearance.folderInitials)
                Toggle("Colour folders by their Finder tag", isOn: $state.config.appearance.folderTagColors)
                Toggle("Automatically hide and show", isOn: $state.config.appearance.autoHide)
            }
            Section("Scroll Area") {
                Stepper("Shows \(state.config.appearance.scrollVisible) icon(s) at a time",
                        value: $state.config.appearance.scrollVisible, in: 1...12)
                Text("Tick “Scroll area” next to apps, folders or links in Layouts to move them into a strip with ‹ › arrows. Arrows appear only when there are more items than fit.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Material") {
                Picker("Material", selection: $state.config.appearance.material) {
                    ForEach(DockMaterial.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Opacity") {
                    Slider(value: $state.config.appearance.opacity, in: 0...1)
                    Text("\(Int(state.config.appearance.opacity * 100))%").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                LabeledContent("Corner radius") {
                    Slider(value: $state.config.appearance.cornerRadius, in: 0...32)
                    Text("\(Int(state.config.appearance.cornerRadius))").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
            }
            Section("Minimized Windows") {
                Toggle("Show minimized windows in the Dock", isOn: $state.config.appearance.showMinimized)
                if !minimized.trusted {
                    HStack {
                        Text("Needs Accessibility access to find and restore minimized windows.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Grant Access…") { minimized.requestAccess() }
                    }
                }
            }
            Section("macOS Dock") {
                LabeledContent("Size") {
                    Slider(value: $nativeSize, in: 16...128, step: 1)
                    Text("\(Int(nativeSize)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                Picker("Position", selection: $nativePosition) {
                    ForEach(DockPosition.allCases) { Text($0.title).tag($0) }
                }
                Button("Apply to macOS Dock") {
                    NativeDock.writeAppearance(tileSize: Int(nativeSize), orientation: nativePosition)
                    NativeDock.restart()
                }
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
    }

    private var modeHelp: String {
        switch state.config.mode {
        case .native: "Only the macOS Dock. Switching layouts rewrites it."
        case .custom: "Only the Dockerset Dock. The macOS Dock is hidden while Dockerset runs and comes back when you quit."
        case .both: "The Dockerset Dock sits next to the macOS Dock. Handy for keeping widgets above your apps."
        }
    }
}

// MARK: Widgets

struct WidgetsTab: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var calendar = CalendarModel.shared
    @ObservedObject private var location = LocationProvider.shared
    @ObservedObject private var stickies = StickiesModel.shared
    @ObservedObject private var battery = BatteryModel.shared
    @ObservedObject private var ai = AIUsageModel.shared
    @State private var claudeConnected = ClaudeLimitsBridge.isConnected
    @State private var claudeError: String?
    @State private var query = ""
    @State private var places: [WeatherModel.Place] = []
    @State private var searchError: String?
    @State private var allShortcuts: [String] = []
    @State private var loadingShortcuts = true

    var body: some View {
        Form {
            Section("Weather") {
                Toggle("Use current location", isOn: $state.config.widgets.weather.useCurrentLocation)
                if state.config.widgets.weather.useCurrentLocation && location.denied {
                    HStack {
                        Text("Location access is off, so \(state.config.widgets.weather.city) is shown instead.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Privacy Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                        }
                    }
                }
                LabeledContent(state.config.widgets.weather.useCurrentLocation ? "Fallback city" : "City",
                               value: state.config.widgets.weather.city)
                HStack {
                    TextField("Search for a city", text: $query).onSubmit(search)
                    Button("Search", action: search).disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(places) { place in
                    Button(place.displayName) {
                        state.config.widgets.weather.city = place.name
                        state.config.widgets.weather.latitude = place.latitude
                        state.config.widgets.weather.longitude = place.longitude
                        state.config.widgets.weather.useCurrentLocation = false
                        places = []
                        query = ""
                    }
                    .buttonStyle(.link)
                }
                if let searchError { Text(searchError).font(.caption).foregroundStyle(.red) }
                Picker("Units", selection: $state.config.widgets.weather.fahrenheit) {
                    Text("Celsius").tag(false)
                    Text("Fahrenheit").tag(true)
                }
                .pickerStyle(.segmented)
                Stepper("Forecast width: \(state.config.widgets.weather.forecastDays) days",
                        value: $state.config.widgets.weather.forecastDays, in: 0...7)
                Toggle("Show background", isOn: $state.config.widgets.weather.showBackground)
            }
            Section("Calendar & Reminders") {
                LabeledContent("Calendar", value: calendar.eventAccess ? "Allowed" : "Not allowed")
                LabeledContent("Reminders", value: calendar.reminderAccess ? "Allowed" : "Not allowed")
                if !calendar.eventAccess || !calendar.reminderAccess {
                    HStack {
                        Button("Request Access") { Task { await calendar.requestAccess() } }
                        Button("Open Privacy Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                        }
                    }
                }
                Stepper("Look ahead: \(state.config.widgets.calendar.daysAhead) day(s)",
                        value: $state.config.widgets.calendar.daysAhead, in: 1...14)
                Toggle("Show reminders", isOn: $state.config.widgets.calendar.showReminders)
                Text("Join buttons appear for Zoom, Google Meet, Teams, Webex, Whereby and FaceTime links.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .onChange(of: state.config.widgets.calendar) { calendar.refresh() }
            Section("Shortcuts") {
                if loadingShortcuts {
                    ProgressView().controlSize(.small)
                } else if allShortcuts.isEmpty {
                    Text("No shortcuts found. Create some in the Shortcuts app.").foregroundStyle(.secondary)
                } else {
                    ForEach(allShortcuts, id: \.self) { name in
                        Toggle(name, isOn: Binding(
                            get: { state.config.widgets.shortcuts.contains(name) },
                            set: { on in
                                if on { state.config.widgets.shortcuts.append(name) }
                                else { state.config.widgets.shortcuts.removeAll { $0 == name } }
                            }
                        ))
                    }
                }
            }
            Section("Battery") {
                Toggle("Include this Mac", isOn: $state.config.widgets.batteryIncludeMac)
                LabeledContent("Devices now", value: battery.devices.isEmpty ? "None" : battery.devices.map(\.name).joined(separator: ", "))
                Text("Shows this Mac plus connected AirPods, headphones, keyboards, mice and trackpads. Devices appear while they're connected.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Sticky Notes") {
                Stepper("Notes shown: \(state.config.widgets.stickiesShown)", value: $state.config.widgets.stickiesShown, in: 1...4)
                LabeledContent("Notes found", value: stickies.accessDenied ? "No access" : "\(stickies.notes.count)")
                Text("Shows your newest notes from the Stickies app, in their colours. Click a note to open Stickies and edit it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Focus Timer") {
                Stepper("Focus: \(state.config.widgets.focusMinutes) min", value: $state.config.widgets.focusMinutes, in: 5...120, step: 5)
                Stepper("Break: \(state.config.widgets.breakMinutes) min", value: $state.config.widgets.breakMinutes, in: 1...60)
                Text("Click the widget to start or pause; right-click to skip or reset. Breaks start on their own after a focus session.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Hydration") {
                Stepper("Remind every \(state.config.widgets.hydrationMinutes) min", value: $state.config.widgets.hydrationMinutes, in: 10...180, step: 5)
                Stepper("Daily goal: \(state.config.widgets.hydrationGoal) glasses", value: $state.config.widgets.hydrationGoal, in: 1...20)
                Text("Click the widget after each drink to log it and restart the countdown.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("AI Limits") {
                ForEach(AIProvider.allCases) { provider in
                    Toggle("Show \(provider.title)", isOn: Binding(
                        get: { state.config.widgets.ai.limitProviders.contains(provider) },
                        set: { on in
                            if on { state.config.widgets.ai.limitProviders.append(provider) }
                            else { state.config.widgets.ai.limitProviders.removeAll { $0 == provider } }
                        }
                    ))
                    if state.config.widgets.ai.limitProviders.contains(provider) {
                        Text(setup(provider)).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Toggle("Connect Claude Code", isOn: $claudeConnected)
                    .onChange(of: claudeConnected) { _, on in
                        do {
                            if on { try ClaudeLimitsBridge.connect() } else { try ClaudeLimitsBridge.disconnect() }
                            claudeError = nil
                        } catch {
                            claudeError = error.localizedDescription
                        }
                        claudeConnected = ClaudeLimitsBridge.isConnected
                        ai.refresh(force: false)
                    }
                Text("Sets Claude Code's status line to a small Dockerset script that saves only your plan's rate limits, then runs your previous status-line command. Turning this off restores your previous setting. It doesn't sign you out of Claude.")
                    .font(.caption).foregroundStyle(.secondary)
                if let claudeError { Text(claudeError).font(.caption).foregroundStyle(.red) }
                Picker("Style", selection: $state.config.widgets.ai.limitStyle) {
                    ForEach(AILimitStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker("Show", selection: $state.config.widgets.ai.showRemaining) {
                    Text("Remaining").tag(true)
                    Text("Used").tag(false)
                }
                .pickerStyle(.segmented)
                Text("The Dock shows the first three selected providers, each with its limit closest to running out. Click the widget for every window and reset time.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Refresh Now") { ai.refresh(force: true) }
            }
            Section("AI Activity") {
                Picker("Provider", selection: $state.config.widgets.ai.activityProvider) {
                    ForEach(AIProvider.allCases.filter(\.hasActivity)) { Text($0.title).tag($0) }
                }
                Picker("Range", selection: $state.config.widgets.ai.activityRange) {
                    ForEach(AIRange.allCases) { Text($0.title).tag($0) }
                }
                Picker("Style", selection: $state.config.widgets.ai.activityStyle) {
                    ForEach(AIActivityStyle.allCases) { Text($0.title).tag($0) }
                }
                Text("Token history from local Claude Code and Codex session logs, checked once a minute. Copilot only reports limits.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Now Playing") {
                Picker("Player", selection: $state.config.widgets.player) {
                    ForEach(PreferredPlayer.allCases) { Text($0.title).tag($0) }
                }
                Text("Controls Spotify and Apple Music. macOS asks once for permission to control each app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            allShortcuts = await ShortcutsService.list()
            loadingShortcuts = false
        }
    }

    private func setup(_ provider: AIProvider) -> String {
        switch provider {
        case .claude: "Claude Code (Pro or Max): turn on Connect Claude Code below, then send a message in a signed-in `claude` session."
        case .codex: "Sign in to Codex with your ChatGPT account (`codex login`). Limits come from Codex's own session logs; API-key logins don't report them."
        case .copilot: "Install GitHub CLI and run `gh auth login` with the account that has Copilot. Refreshes every 5 minutes."
        }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        Task {
            do {
                places = try await WeatherModel.search(q)
                searchError = places.isEmpty ? "No matches for “\(q)”." : nil
            } catch {
                searchError = "Search failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: Focus

struct FocusTab: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section {
                Text("Switch your Dock automatically with a macOS Focus.")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Open Shortcuts → Automation → New Automation → Focus.")
                    Text("2. Pick a Focus, choose “When Turning On”, and set it to Run Immediately.")
                    Text("3. Add the “Open URLs” action and paste the layout's URL from below.")
                    Text("4. Optionally add a “When Turning Off” automation that opens your default layout.")
                }
                .font(.callout)
                Button("Open Shortcuts") {
                    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Shortcuts.app"), configuration: .init())
                }
            }
            Section("Layout URLs") {
                ForEach(state.config.layouts) { layout in
                    let url = Self.url(for: layout)
                    HStack {
                        Text(layout.name)
                        Spacer()
                        Text(url).font(.system(.caption, design: .monospaced)).textSelection(.enabled).foregroundStyle(.secondary)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url, forType: .string)
                        }
                        Button("Test") { NSWorkspace.shared.open(URL(string: url)!) }
                    }
                }
            }
            Section("Other URLs") {
                ForEach(["dockerset://settings", "dockerset://next", "dockerset://mode/native", "dockerset://mode/custom", "dockerset://mode/both"], id: \.self) {
                    Text($0).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }

    static func url(for layout: Layout) -> String {
        let name = layout.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? layout.name
        return "dockerset://layout/\(name)"
    }
}

// MARK: Backup

struct BackupTab: View {
    @EnvironmentObject private var state: AppState
    @State private var includeNative = true
    @State private var message: String?

    var body: some View {
        Form {
            Section("Back Up") {
                Text("Saves your layouts, appearance and widget settings to a file. Use it to restore later or to move to another Mac.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("Include macOS Dock settings", isOn: $includeNative)
                Button("Export Backup…", action: exportBackup)
            }
            Section("Restore") {
                Button("Import Backup…", action: importBackup)
                Text("Apps that aren't installed on this Mac show a dashed icon until you install them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("macOS Dock") {
                Button("Restore the macOS Dock From Before Dockerset") {
                    NativeDock.restoreOriginal()
                    if state.config.mode == .custom { state.config.mode = .both }
                    message = "macOS Dock restored."
                }
                .disabled(!NativeDock.hasOriginalBackup)
                Text("Dockerset saved your Dock the first time it changed it.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Show Data Folder in Finder") { NSWorkspace.shared.open(Store.dir) }
            }
            if let message {
                Text(message).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Dockerset Backup \(Date().formatted(.iso8601.year().month().day())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Store.exportBackup(state.config, includeNative: includeNative, to: url)
            message = "Backup saved to \(url.lastPathComponent)."
        } catch {
            message = "Couldn't save backup: \(error.localizedDescription)"
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let backup = try Store.importBackup(from: url)
            var restoreNative = false
            if backup.nativeDock != nil {
                let alert = NSAlert()
                alert.messageText = "Restore the macOS Dock too?"
                alert.informativeText = "This backup includes macOS Dock settings from \(backup.created.formatted(date: .abbreviated, time: .shortened))."
                alert.addButton(withTitle: "Restore Both")
                alert.addButton(withTitle: "Dockerset Only")
                restoreNative = alert.runModal() == .alertFirstButtonReturn
            }
            state.restoreBackup(backup, includeNative: restoreNative)
            message = "Restored \(backup.config.layouts.count) layout(s)."
        } catch {
            message = "Couldn't read backup: \(error.localizedDescription)"
        }
    }
}

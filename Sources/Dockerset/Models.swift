import Foundation

enum DockItemKind: String, Codable {
    case app, folder, link, spacer, widget
}

enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case nowPlaying, calendar, weather, shortcuts, battery, stickies, focusTimer, hydration, aiLimits, aiActivity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nowPlaying: "Now Playing"
        case .calendar: "Calendar & Reminders"
        case .weather: "Weather"
        case .shortcuts: "Shortcuts"
        case .battery: "Battery"
        case .stickies: "Sticky Notes"
        case .focusTimer: "Focus Timer"
        case .hydration: "Hydration"
        case .aiLimits: "AI Limits"
        case .aiActivity: "AI Activity"
        }
    }

    var symbol: String {
        switch self {
        case .nowPlaying: "music.note"
        case .calendar: "calendar"
        case .weather: "cloud.sun"
        case .shortcuts: "square.2.layers.3d"
        case .battery: "battery.75percent"
        case .stickies: "note.text"
        case .focusTimer: "timer"
        case .hydration: "drop.fill"
        case .aiLimits: "gauge.with.dots.needle.33percent"
        case .aiActivity: "chart.bar.xaxis"
        }
    }
}

struct DockItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: DockItemKind
    var label: String
    /// File system path for apps and folders/files.
    var path: String? = nil
    /// Absolute URL string for links.
    var url: String? = nil
    var widget: WidgetKind? = nil
    /// Shown in the Dock's scroll area (with ‹ › arrows) instead of inline.
    var inScroll = false
    /// Spacers only: half-width gap instead of a full icon's width.
    var smallSpacer = false

    /// Widgets have their own widths, so only icon tiles can go in the scroll area.
    var canScroll: Bool { kind == .app || kind == .folder || kind == .link }

    static func app(_ url: URL) -> DockItem {
        DockItem(kind: .app, label: url.deletingPathExtension().lastPathComponent, path: url.path)
    }

    static func folder(_ url: URL) -> DockItem {
        DockItem(kind: .folder, label: url.lastPathComponent, path: url.path)
    }

    static func link(_ label: String, _ url: String) -> DockItem {
        DockItem(kind: .link, label: label, url: url)
    }

    static func spacer(small: Bool = false) -> DockItem {
        DockItem(kind: .spacer, label: small ? "Small Spacer" : "Spacer", smallSpacer: small)
    }

    static func widget(_ kind: WidgetKind) -> DockItem {
        DockItem(kind: .widget, label: kind.title, widget: kind)
    }

    /// Same item with a fresh identity, for copying between layouts.
    func copy() -> DockItem {
        var c = self
        c.id = UUID()
        return c
    }
}

extension DockItem {
    // Missing keys fall back to defaults, so adding a field never makes an existing config unreadable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(DockItemKind.self, forKey: .kind)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        path = try c.decodeIfPresent(String.self, forKey: .path)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        widget = try c.decodeIfPresent(WidgetKind.self, forKey: .widget)
        inScroll = try c.decodeIfPresent(Bool.self, forKey: .inScroll) ?? false
        // Spacers saved before sizes existed were drawn small, so they keep that look.
        smallSpacer = try c.decodeIfPresent(Bool.self, forKey: .smallSpacer) ?? (kind == .spacer)
    }
}

struct Layout: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var items: [DockItem]
}

enum DockMode: String, Codable, CaseIterable, Identifiable {
    case native, custom, both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .native: "macOS Dock"
        case .custom: "Dockerset Dock"
        case .both: "Both"
        }
    }
}

enum DockPosition: String, Codable, CaseIterable, Identifiable {
    case bottom, left, right

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum DockMaterial: String, Codable, CaseIterable, Identifiable {
    case glass, hud, popover, menu, sidebar, underWindow, solid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: "Liquid Glass"
        case .hud: "Dark HUD"
        case .popover: "Popover"
        case .menu: "Menu"
        case .sidebar: "Sidebar"
        case .underWindow: "Under Window"
        case .solid: "Solid"
        }
    }
}

struct Appearance: Codable, Equatable {
    var iconSize: Double = 48
    var position: DockPosition = .bottom
    var material: DockMaterial = .hud
    var opacity: Double = 1
    var cornerRadius: Double = 18
    var magnification = true
    var autoHide = false
    var showMinimized = true
    /// Draw the folder name's first letter on folder icons.
    var folderInitials = true
    /// How many icons the scroll area shows at once.
    var scrollVisible = 4
    /// Colour folder icons with their Finder tag, like Finder does.
    var folderTagColors = true
}

extension Appearance {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Appearance()
        iconSize = try c.decodeIfPresent(Double.self, forKey: .iconSize) ?? d.iconSize
        position = try c.decodeIfPresent(DockPosition.self, forKey: .position) ?? d.position
        material = try c.decodeIfPresent(DockMaterial.self, forKey: .material) ?? d.material
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? d.opacity
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? d.cornerRadius
        magnification = try c.decodeIfPresent(Bool.self, forKey: .magnification) ?? d.magnification
        autoHide = try c.decodeIfPresent(Bool.self, forKey: .autoHide) ?? d.autoHide
        showMinimized = try c.decodeIfPresent(Bool.self, forKey: .showMinimized) ?? d.showMinimized
        folderInitials = try c.decodeIfPresent(Bool.self, forKey: .folderInitials) ?? d.folderInitials
        scrollVisible = try c.decodeIfPresent(Int.self, forKey: .scrollVisible) ?? d.scrollVisible
        folderTagColors = try c.decodeIfPresent(Bool.self, forKey: .folderTagColors) ?? d.folderTagColors
    }
}

struct WeatherSettings: Codable, Equatable {
    /// Follow the Mac's location; the city below is the fallback and the manual choice.
    var useCurrentLocation = true
    var city = "Cupertino"
    var latitude = 37.3230
    var longitude = -122.0322
    var fahrenheit = false
    /// Number of forecast days shown next to current conditions (0 = current only).
    var forecastDays = 3
    var showBackground = true
}

extension WeatherSettings {
    // Missing keys fall back to defaults, so adding a setting never makes an existing config unreadable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WeatherSettings()
        useCurrentLocation = try c.decodeIfPresent(Bool.self, forKey: .useCurrentLocation) ?? d.useCurrentLocation
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? d.city
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude) ?? d.latitude
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude) ?? d.longitude
        fahrenheit = try c.decodeIfPresent(Bool.self, forKey: .fahrenheit) ?? d.fahrenheit
        forecastDays = try c.decodeIfPresent(Int.self, forKey: .forecastDays) ?? d.forecastDays
        showBackground = try c.decodeIfPresent(Bool.self, forKey: .showBackground) ?? d.showBackground
    }
}

struct CalendarSettings: Codable, Equatable {
    var daysAhead = 1
    var showReminders = true
}

enum PreferredPlayer: String, Codable, CaseIterable, Identifiable {
    case auto, spotify, music

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Automatic"
        case .spotify: "Spotify"
        case .music: "Apple Music"
        }
    }
}

struct WidgetSettings: Codable, Equatable {
    var weather = WeatherSettings()
    var calendar = CalendarSettings()
    var shortcuts: [String] = []
    var player = PreferredPlayer.auto
    /// How many Stickies notes the Sticky Notes widget shows side by side.
    var stickiesShown = 1
    var batteryIncludeMac = true
    var focusMinutes = 25
    var breakMinutes = 5
    var hydrationMinutes = 30
    var hydrationGoal = 8
    var ai = AISettings()
}

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case claude, codex, copilot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .copilot: "Copilot"
        }
    }

    /// Providers whose local logs give token activity.
    var hasActivity: Bool { self != .copilot }
}

enum AILimitStyle: String, Codable, CaseIterable, Identifiable {
    case numbers, rings, bars
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum AIActivityStyle: String, Codable, CaseIterable, Identifiable {
    case sparkline, bars, totals
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum AIRange: String, Codable, CaseIterable, Identifiable {
    case today, last7, last30, month
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .last7: "Last 7 days"
        case .last30: "Last 30 days"
        case .month: "This month"
        }
    }

    var short: String {
        switch self {
        case .today: "Today"
        case .last7: "L7"
        case .last30: "L30"
        case .month: "MTD"
        }
    }
}

struct AISettings: Codable, Equatable {
    var limitProviders: [AIProvider] = [.claude, .codex, .copilot]
    var limitStyle = AILimitStyle.rings
    /// Show what's left rather than what's used.
    var showRemaining = true
    var activityProvider = AIProvider.claude
    var activityStyle = AIActivityStyle.sparkline
    var activityRange = AIRange.last7

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AISettings()
        limitProviders = try c.decodeIfPresent([AIProvider].self, forKey: .limitProviders) ?? d.limitProviders
        limitStyle = try c.decodeIfPresent(AILimitStyle.self, forKey: .limitStyle) ?? d.limitStyle
        showRemaining = try c.decodeIfPresent(Bool.self, forKey: .showRemaining) ?? d.showRemaining
        activityProvider = try c.decodeIfPresent(AIProvider.self, forKey: .activityProvider) ?? d.activityProvider
        activityStyle = try c.decodeIfPresent(AIActivityStyle.self, forKey: .activityStyle) ?? d.activityStyle
        activityRange = try c.decodeIfPresent(AIRange.self, forKey: .activityRange) ?? d.activityRange
    }
}

extension WidgetSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WidgetSettings()
        weather = try c.decodeIfPresent(WeatherSettings.self, forKey: .weather) ?? d.weather
        calendar = try c.decodeIfPresent(CalendarSettings.self, forKey: .calendar) ?? d.calendar
        shortcuts = try c.decodeIfPresent([String].self, forKey: .shortcuts) ?? d.shortcuts
        player = try c.decodeIfPresent(PreferredPlayer.self, forKey: .player) ?? d.player
        stickiesShown = try c.decodeIfPresent(Int.self, forKey: .stickiesShown) ?? d.stickiesShown
        batteryIncludeMac = try c.decodeIfPresent(Bool.self, forKey: .batteryIncludeMac) ?? d.batteryIncludeMac
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? d.focusMinutes
        breakMinutes = try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? d.breakMinutes
        hydrationMinutes = try c.decodeIfPresent(Int.self, forKey: .hydrationMinutes) ?? d.hydrationMinutes
        hydrationGoal = try c.decodeIfPresent(Int.self, forKey: .hydrationGoal) ?? d.hydrationGoal
        ai = try c.decodeIfPresent(AISettings.self, forKey: .ai) ?? d.ai
    }
}

struct Config: Codable, Equatable {
    var layouts: [Layout]
    var activeLayoutID: UUID?
    var mode: DockMode = .both
    var appearance = Appearance()
    var widgets = WidgetSettings()
    /// Rewrite the macOS Dock whenever the active layout changes (when the macOS Dock is in use).
    var syncNativeOnSwitch = true
}

extension Config {
    static func initial() -> Config {
        var apps = NativeDock.currentItems()
        if apps.count <= 1 {
            apps = [
                "/System/Library/CoreServices/Finder.app",
                "/Applications/Safari.app",
                "/System/Applications/Mail.app",
                "/System/Applications/Calendar.app",
                "/System/Applications/Notes.app",
                "/System/Applications/System Settings.app",
            ]
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { DockItem.app(URL(fileURLWithPath: $0)) }
        }
        let standard = Layout(
            name: "Default",
            items: apps + [.spacer(), .widget(.nowPlaying), .widget(.calendar), .widget(.weather)]
        )
        let work = Layout(
            name: "Work",
            items: apps.map { $0.copy() } + [.spacer(), .widget(.calendar), .widget(.shortcuts)]
        )
        return Config(layouts: [standard, work], activeLayoutID: standard.id)
    }
}

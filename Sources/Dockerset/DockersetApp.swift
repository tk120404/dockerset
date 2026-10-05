import AppKit
import SwiftUI

@main
struct DockersetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra("Dockerset", systemImage: "dock.rectangle") {
            MenuContent().environmentObject(state)
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Section("Layouts") {
            ForEach(state.config.layouts) { layout in
                Toggle(layout.name, isOn: Binding(
                    get: { layout.id == state.activeLayout?.id },
                    set: { if $0 { state.activateLayout(layout.id) } }
                ))
            }
        }
        Divider()
        Picker("Show", selection: Binding(get: { state.config.mode }, set: { state.setMode($0) })) {
            ForEach(DockMode.allCases) { Text($0.title).tag($0) }
        }
        Divider()
        Button("Settings…") { SettingsWindowController.shared.show() }
        .keyboardShortcut(",")
        Button("Quit Dockerset") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dock: DockPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = AppState.shared
        NativeDock.startWatchdog()
        dock = DockPanelController(state: state)
        _ = RunningApps.shared
        MinimizedWindows.shared.start()
        NowPlaying.shared.start()
        CalendarModel.shared.start()
        WeatherModel.shared.start()
        BatteryModel.shared.start()
        StickiesModel.shared.start()
        HydrationModel.shared.start()
        AIUsageModel.shared.start()
        state.applyModeOnLaunch()
        if state.isFirstLaunch { SettingsWindowController.shared.show() }
    }

    /// Opening Dockerset again from Finder, Spotlight or Launchpad while it's running shows Settings,
    /// so it stays reachable even when the menu bar icon is hidden behind the notch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.restoreNativeOnQuit()
    }

    /// dockerset://layout/<name>, dockerset://next, dockerset://mode/<native|custom|both>, dockerset://settings
    func application(_ application: NSApplication, open urls: [URL]) {
        let state = AppState.shared
        for url in urls where url.scheme == "dockerset" {
            let argument = url.pathComponents.dropFirst().joined(separator: "/")
            switch url.host() {
            case "layout":
                if !state.activateLayout(named: argument) {
                    NSLog("Dockerset: no layout named \(argument)")
                }
            case "next":
                state.activateNextLayout()
            case "mode":
                if let mode = DockMode(rawValue: argument) { state.setMode(mode) }
            case "settings":
                SettingsWindowController.shared.show()
            default:
                NSLog("Dockerset: unknown URL \(url)")
            }
        }
    }
}

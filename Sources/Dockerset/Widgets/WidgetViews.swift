import AppKit
import EventKit
import SwiftUI

struct WidgetHost: View {
    let kind: WidgetKind
    let size: CGFloat

    var body: some View {
        Group {
            switch kind {
            case .nowPlaying: NowPlayingWidget(size: size)
            case .calendar: CalendarWidget(size: size)
            case .weather: WeatherWidget(size: size)
            case .shortcuts: ShortcutsWidget(size: size)
            case .battery: BatteryWidget(size: size)
            case .stickies: StickiesWidget(size: size)
            case .focusTimer: FocusTimerWidget(size: size)
            case .hydration: HydrationWidget(size: size)
            case .aiLimits: AILimitsWidget(size: size)
            case .aiActivity: AIActivityWidget(size: size)
            }
        }
        .frame(height: size)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: min(14, size * 0.25), style: .continuous).fill(.white.opacity(0.08)))
    }
}

private func scaled(_ size: CGFloat, _ scale: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: max(9, size * scale), weight: weight)
}

// MARK: Now Playing

struct NowPlayingWidget: View {
    let size: CGFloat
    @ObservedObject private var model = NowPlaying.shared

    var body: some View {
        HStack(spacing: 8) {
            artwork
                .frame(width: size * 0.8, height: size * 0.8)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(model.track?.title ?? "Not Playing").font(scaled(size, 0.24, .semibold)).lineLimit(1)
                Text(model.track?.artist ?? "Spotify · Apple Music").font(scaled(size, 0.2)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: size * 2.6, alignment: .leading)
            HStack(spacing: 2) {
                control("backward.fill", "previous track")
                control(model.track?.playing == true ? "pause.fill" : "play.fill", "playpause")
                control("forward.fill", "next track")
            }
        }
    }

    @ViewBuilder private var artwork: some View {
        if let url = model.track?.artworkURL {
            AsyncImage(url: url) { $0.resizable() } placeholder: { playerIcon }
        } else {
            playerIcon
        }
    }

    @ViewBuilder private var playerIcon: some View {
        if let track = model.track, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: track.player.rawValue) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable()
        } else {
            LinearGradient(colors: [.pink, .red], startPoint: .top, endPoint: .bottom)
                .overlay(Image(systemName: "music.note").font(scaled(size, 0.35, .semibold)).foregroundStyle(.white))
        }
    }

    private func control(_ symbol: String, _ command: String) -> some View {
        Button { model.send(command) } label: {
            Image(systemName: symbol)
                .font(scaled(size, 0.24))
                .frame(width: size * 0.45, height: size * 0.45)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.track == nil && command != "playpause")
    }
}

// MARK: Calendar & Reminders

struct CalendarWidget: View {
    let size: CGFloat
    @EnvironmentObject private var state: AppState
    @ObservedObject private var model = CalendarModel.shared
    @State private var showDetails = false

    var body: some View {
        HStack(spacing: 8) {
            dateBadge
            if !model.eventAccess {
                Button("Allow Calendar Access") { Task { await model.requestAccess() } }
                    .font(scaled(size, 0.2))
            } else if let event = model.nextEvent {
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title ?? "Event").font(scaled(size, 0.22, .semibold)).lineLimit(1)
                    Text(model.timeDescription(event)).font(scaled(size, 0.19)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(width: size * 2.4, alignment: .leading)
                if let url = CalendarModel.meetingURL(event) {
                    Button("Join") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            } else {
                Text("No upcoming events").font(scaled(size, 0.2)).foregroundStyle(.secondary)
            }
            if state.config.widgets.calendar.showReminders && model.reminderAccess && !model.reminders.isEmpty {
                Label("\(model.reminders.count)", systemImage: "checklist")
                    .font(scaled(size, 0.2, .medium))
                    .foregroundStyle(.orange)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showDetails.toggle() }
        .popover(isPresented: $showDetails) { CalendarDetail().environmentObject(state) }
    }

    private var dateBadge: some View {
        VStack(spacing: 0) {
            Text(Date().formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(scaled(size, 0.15, .bold)).foregroundStyle(.red)
            Text(Date().formatted(.dateTime.day())).font(scaled(size, 0.36, .medium)).foregroundStyle(.black)
        }
        .frame(width: size * 0.8, height: size * 0.8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white))
    }
}

struct CalendarDetail: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var model = CalendarModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Upcoming").font(.headline)
            if model.events.isEmpty {
                Text(model.eventAccess ? "Nothing scheduled." : "Calendar access not granted.").foregroundStyle(.secondary)
            }
            ForEach(model.events.prefix(8), id: \.calendarItemIdentifier) { event in
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(cgColor: event.calendar.cgColor))
                        .frame(width: 4, height: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title ?? "Event").lineLimit(1)
                        Text(model.timeDescription(event)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let url = CalendarModel.meetingURL(event) {
                        Button("Join") { NSWorkspace.shared.open(url) }.controlSize(.small)
                    }
                }
            }
            if state.config.widgets.calendar.showReminders {
                Divider()
                Text("Reminders").font(.headline)
                if !model.reminderAccess {
                    Text("Reminders access not granted.").foregroundStyle(.secondary)
                } else if model.reminders.isEmpty {
                    Text("All done.").foregroundStyle(.secondary)
                }
                ForEach(model.reminders.prefix(8), id: \.calendarItemIdentifier) { reminder in
                    HStack {
                        Button { model.complete(reminder) } label: { Image(systemName: "circle") }
                            .buttonStyle(.plain)
                        Text(reminder.title ?? "Reminder").lineLimit(1)
                        Spacer()
                        if let due = reminder.dueDateComponents?.date {
                            Text(due.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            HStack {
                Button("Open Calendar") { open("/System/Applications/Calendar.app") }
                Button("Open Reminders") { open("/System/Applications/Reminders.app") }
            }
            .controlSize(.small)
        }
        .padding()
        .frame(width: 320)
    }

    private func open(_ path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
    }
}

// MARK: Weather

struct WeatherWidget: View {
    let size: CGFloat
    @EnvironmentObject private var state: AppState
    @ObservedObject private var model = WeatherModel.shared

    var body: some View {
        let settings = state.config.widgets.weather
        let unit = settings.fahrenheit ? "°F" : "°C"
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: WeatherModel.symbol(model.code ?? 0))
                    .symbolRenderingMode(.multicolor)
                    .font(scaled(size, 0.42))
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.temperature.map { "\(Int($0.rounded()))\(unit)" } ?? "--")
                        .font(scaled(size, 0.3, .semibold))
                    Text(model.error ?? model.placeName ?? "Locating…").font(scaled(size, 0.17)).lineLimit(1).opacity(0.8)
                }
            }
            ForEach(model.days.prefix(settings.forecastDays)) { day in
                VStack(spacing: 1) {
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated))).font(scaled(size, 0.16, .medium))
                    Image(systemName: WeatherModel.symbol(day.code)).symbolRenderingMode(.multicolor).font(scaled(size, 0.24))
                    Text("\(Int(day.high.rounded()))°/\(Int(day.low.rounded()))°").font(scaled(size, 0.15)).opacity(0.85)
                }
            }
        }
        .padding(.horizontal, settings.showBackground ? 8 : 0)
        .frame(maxHeight: .infinity)
        .background {
            if settings.showBackground {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(WeatherModel.gradient(model.code ?? 0))
            }
        }
        .foregroundStyle(settings.showBackground ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
        .task(id: settings) { await model.refresh(settings) }
        .onTapGesture {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Weather.app"), configuration: .init())
        }
    }
}

// MARK: Shortcuts

struct ShortcutsWidget: View {
    let size: CGFloat
    @EnvironmentObject private var state: AppState
    @State private var running: String?
    @State private var failed: String?

    var body: some View {
        let names = state.config.widgets.shortcuts
        HStack(spacing: 6) {
            if names.isEmpty {
                Label("Pick shortcuts in Settings", systemImage: "square.2.layers.3d")
                    .font(scaled(size, 0.2))
                    .foregroundStyle(.secondary)
            }
            ForEach(names, id: \.self) { name in
                Button { run(name) } label: {
                    VStack(spacing: 2) {
                        if running == name {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: failed == name ? "exclamationmark.triangle.fill" : "square.2.layers.3d.fill")
                                .font(scaled(size, 0.3))
                                .foregroundStyle(failed == name ? .orange : .primary)
                        }
                        Text(name).font(scaled(size, 0.17)).lineLimit(1)
                    }
                    .frame(width: size * 1.3, height: size * 0.85)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.1)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(running != nil)
                .help("Run “\(name)”")
            }
        }
    }

    private func run(_ name: String) {
        running = name
        failed = nil
        Task {
            let ok = await ShortcutsService.run(name)
            running = nil
            if !ok { failed = name }
        }
    }
}

// MARK: Battery

struct BatteryWidget: View {
    let size: CGFloat
    @EnvironmentObject private var state: AppState
    @ObservedObject private var model = BatteryModel.shared

    var body: some View {
        let devices = model.devices.filter { state.config.widgets.batteryIncludeMac || $0.id != "mac" }
        HStack(spacing: size * 0.25) {
            if devices.isEmpty {
                Label("No devices", systemImage: "battery.0percent")
                    .font(scaled(size, 0.2))
                    .foregroundStyle(.secondary)
            }
            ForEach(devices) { device in
                BatteryRing(device: device, size: size)
            }
        }
        .onTapGesture { model.refresh() }
    }
}

private struct BatteryRing: View {
    let device: BatteryDevice
    let size: CGFloat

    var body: some View {
        let ring = size * 0.62
        let color: Color = device.percent <= 10 ? .red : device.percent <= 20 ? .orange : .green
        VStack(spacing: 1) {
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: max(2, size * 0.07))
                Circle()
                    .trim(from: 0, to: CGFloat(device.percent) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: max(2, size * 0.07), lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: device.symbol)
                    .font(.system(size: ring * 0.36, weight: .medium))
            }
            .overlay(alignment: .topTrailing) {
                if device.charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: ring * 0.26, weight: .bold))
                        .foregroundStyle(.yellow)
                        .offset(x: ring * 0.08, y: -ring * 0.04)
                }
            }
            .frame(width: ring, height: ring)
            Text("\(device.percent)%")
                .font(scaled(size, 0.2))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .help("\(device.name): \(device.percent)%\(device.charging ? ", charging" : "")")
    }
}

// MARK: Sticky Notes

struct StickiesWidget: View {
    let size: CGFloat
    @EnvironmentObject private var state: AppState
    @ObservedObject private var model = StickiesModel.shared

    var body: some View {
        let notes = model.notes.prefix(max(1, state.config.widgets.stickiesShown))
        HStack(spacing: 6) {
            if model.accessDenied {
                Button("Allow access to Stickies…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                }
                .font(scaled(size, 0.2))
            } else if notes.isEmpty {
                Button { model.openStickies() } label: {
                    Label("New sticky note", systemImage: "note.text.badge.plus").font(scaled(size, 0.2))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            ForEach(notes) { note in
                Text(note.text.isEmpty ? " " : note.text)
                    .font(scaled(size, 0.21, .medium))
                    .foregroundStyle(.black.opacity(0.85))
                    .multilineTextAlignment(.leading)
                    .frame(width: size * 3.2, height: size - 8, alignment: .topLeading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: min(12, size * 0.25), style: .continuous).fill(note.color))
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture { model.openStickies() }
                    .help(note.text)
            }
        }
    }
}

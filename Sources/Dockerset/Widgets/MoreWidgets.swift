import AppKit
import SwiftUI

private func scaled(_ size: CGFloat, _ scale: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: max(9, size * scale), weight: weight)
}

private func usageColor(_ used: Double) -> Color {
    used >= 90 ? .red : used >= 70 ? .orange : .green
}

// MARK: Focus Timer

struct FocusTimerWidget: View {
    let size: CGFloat
    @EnvironmentObject private var state: AppState
    @ObservedObject private var model = FocusTimerModel.shared

    var body: some View {
        let tint: Color = model.phase == .focus ? .orange : .green
        HStack(spacing: size * 0.22) {
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: max(3, size * 0.1))
                Circle()
                    .trim(from: 0, to: model.progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: max(3, size * 0.1), lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.9), value: model.progress)
                Image(systemName: model.running ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 0.2))
                    .opacity(0.8)
            }
            .frame(width: size * 0.62, height: size * 0.62)
            VStack(alignment: .leading, spacing: 0) {
                Text(formatClock(model.remaining))
                    .font(scaled(size, 0.36, .semibold))
                    .monospacedDigit()
                Text(model.phase == .focus ? (model.running ? "Focus" : "Focus · paused") : "Break")
                    .font(scaled(size, 0.19))
                    .foregroundStyle(.secondary)
            }
            .frame(width: size * 1.9, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.toggle() }
        .help("Click to start or pause. Right-click to reset or skip.")
        .contextMenu {
            Button(model.running ? "Pause" : "Start") { model.toggle() }
            Button(model.phase == .focus ? "Skip to Break" : "Skip to Focus") { model.skip() }
            Button("Reset") { model.reset() }
        }
        .onChange(of: state.config.widgets.focusMinutes) { model.settingsChanged() }
        .onChange(of: state.config.widgets.breakMinutes) { model.settingsChanged() }
    }
}

// MARK: Hydration

struct HydrationWidget: View {
    let size: CGFloat
    @EnvironmentObject private var state: AppState
    @ObservedObject private var model = HydrationModel.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: min(12, size * 0.25), style: .continuous)
        VStack(spacing: 0) {
            Text(model.due ? "Drink now" : formatClock(model.remaining))
                .font(scaled(size, 0.34, .semibold))
                .monospacedDigit()
            Text(model.due ? "Click after your drink" : "Next drink · \(model.drinksToday)/\(state.config.widgets.hydrationGoal)")
                .font(scaled(size, 0.18))
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(width: size * 2.6, height: size - 4)
        .background {
            // Water level drains as the next drink comes due.
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Color(red: 0.16, green: 0.36, blue: 0.62)
                    LinearGradient(colors: [Color(red: 0.42, green: 0.70, blue: 0.98), Color(red: 0.25, green: 0.52, blue: 0.90)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: geo.size.height * max(0.06, model.level))
                        .animation(.easeInOut(duration: 0.8), value: model.level)
                }
            }
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(model.due ? Color.cyan : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { model.logDrink() }
        .help("Click when you've had a drink.")
        .contextMenu {
            Button("Log a Drink") { model.logDrink() }
            Button("Restart Countdown") { model.restart() }
            Button("Undo Last Drink") { model.undoDrink() }.disabled(model.drinksToday == 0)
        }
    }
}

// MARK: AI Limits

struct AILimitsWidget: View {
    let size: CGFloat
    @EnvironmentObject private var state: AppState
    @ObservedObject private var model = AIUsageModel.shared
    @State private var showDetail = false

    var body: some View {
        let ai = state.config.widgets.ai
        let providers = Array(ai.limitProviders.prefix(3))
        HStack(spacing: size * 0.22) {
            if providers.isEmpty {
                Text("Pick providers in Settings").font(scaled(size, 0.2)).foregroundStyle(.secondary)
            }
            ForEach(providers) { provider in
                LimitTile(provider: provider, limits: model.limits[provider], style: ai.limitStyle,
                          remaining: ai.showRemaining, size: size)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showDetail.toggle() }
        .popover(isPresented: $showDetail) { AILimitsDetail().environmentObject(state) }
    }
}

private struct LimitTile: View {
    let provider: AIProvider
    let limits: AIProviderLimits?
    let style: AILimitStyle
    let remaining: Bool
    let size: CGFloat

    var body: some View {
        let window = limits?.headline
        let used = window?.usedPercent ?? 0
        let shown = remaining ? 100 - used : used
        // A dash means unavailable, never zero.
        let value = window.map { _ in "\(Int(shown.rounded()))%" } ?? "—"
        let label = window.map { "\(provider.title) · \($0.name)" } ?? provider.title
        Group {
            switch style {
            case .rings:
                VStack(spacing: 1) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.15), lineWidth: max(2, size * 0.07))
                        if window != nil {
                            Circle()
                                .trim(from: 0, to: shown / 100)
                                .stroke(usageColor(used), style: StrokeStyle(lineWidth: max(2, size * 0.07), lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        Text(value).font(scaled(size, 0.17, .semibold)).monospacedDigit()
                    }
                    .frame(width: size * 0.62, height: size * 0.62)
                    Text(provider.title).font(scaled(size, 0.17)).foregroundStyle(.secondary)
                }
            case .bars:
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(provider.title).font(scaled(size, 0.18, .medium))
                        Spacer()
                        Text(value).font(scaled(size, 0.18)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Capsule().fill(.white.opacity(0.15))
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule().fill(usageColor(used)).frame(width: geo.size.width * shown / 100)
                            }
                        }
                        .frame(height: max(4, size * 0.1))
                        .opacity(window == nil ? 0.4 : 1)
                }
                .frame(width: size * 1.7)
            case .numbers:
                VStack(spacing: 0) {
                    Text(value).font(scaled(size, 0.34, .semibold)).monospacedDigit()
                        .foregroundStyle(window == nil ? Color.secondary : usageColor(used))
                    Text(provider.title).font(scaled(size, 0.17)).foregroundStyle(.secondary)
                }
                .frame(minWidth: size * 0.9)
            }
        }
        .help(window.map { "\(label): \(Int(used.rounded()))% used\(formatResetsIn($0.resetsAt).map { ", \($0)" } ?? "")" }
              ?? "\(provider.title): \(limits?.message ?? "Updating…")")
    }
}

struct AILimitsDetail: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var model = AIUsageModel.shared

    var body: some View {
        let ai = state.config.widgets.ai
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI Limits").font(.headline)
                Spacer()
                if model.refreshing { ProgressView().controlSize(.small) }
                Button { model.refresh(force: true) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Refresh now")
            }
            if ai.limitProviders.isEmpty {
                Text("No providers selected. Choose them in Settings → Widgets → AI.").foregroundStyle(.secondary)
            }
            ForEach(ai.limitProviders) { provider in
                let limits = model.limits[provider]
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(provider.title).font(.subheadline.bold())
                        if let plan = limits?.plan { Text(plan).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if let updated = limits?.updated {
                            Text("updated \(updated.formatted(.relative(presentation: .named)))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    if let windows = limits?.windows, !windows.isEmpty {
                        ForEach(windows) { window in
                            let shown = ai.showRemaining ? 100 - window.usedPercent : window.usedPercent
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(window.name).font(.caption)
                                    Spacer()
                                    Text("\(Int(shown.rounded()))% \(ai.showRemaining ? "left" : "used")")
                                        .font(.caption).monospacedDigit()
                                }
                                ProgressView(value: min(100, max(0, shown)), total: 100)
                                    .tint(usageColor(window.usedPercent))
                                if let reset = formatResetsIn(window.resetsAt) {
                                    Text(reset).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        Text(limits?.message ?? "Updating…").font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Button("AI Settings…") { SettingsWindowController.shared.show() }.controlSize(.small)
        }
        .padding()
        .frame(width: 320)
    }
}

// MARK: AI Activity

struct AIActivityWidget: View {
    let size: CGFloat
    @EnvironmentObject private var state: AppState
    @ObservedObject private var model = AIUsageModel.shared
    @State private var showDetail = false

    var body: some View {
        let ai = state.config.widgets.ai
        let total = model.total(ai.activityProvider, ai.activityRange)
        let series = model.series(ai.activityProvider, ai.activityRange).map(\.tokens)
        HStack(spacing: size * 0.2) {
            VStack(alignment: .leading, spacing: 0) {
                Text(formatTokens(total.tokens)).font(scaled(size, 0.32, .semibold)).monospacedDigit()
                Text("\(ai.activityProvider.title) · \(ai.activityRange.short)").font(scaled(size, 0.18)).foregroundStyle(.secondary)
            }
            switch ai.activityStyle {
            case .sparkline:
                Sparkline(values: series).frame(width: size * 1.8, height: size * 0.5)
            case .bars:
                MiniBars(values: series).frame(width: size * 1.8, height: size * 0.5)
            case .totals:
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(total.sessions.count) sessions").font(scaled(size, 0.18))
                    Text("\(total.toolCalls) tool calls").font(scaled(size, 0.18))
                }
                .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showDetail.toggle() }
        .popover(isPresented: $showDetail) { AIActivityDetail().environmentObject(state) }
    }
}

private struct Sparkline: View {
    let values: [Int]

    var body: some View {
        GeometryReader { geo in
            let peak = max(1, values.max() ?? 1)
            let step = values.count > 1 ? geo.size.width / CGFloat(values.count - 1) : 0
            let points = values.enumerated().map { i, v in
                CGPoint(x: CGFloat(i) * step, y: geo.size.height * (1 - CGFloat(v) / CGFloat(peak)))
            }
            ZStack {
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: CGPoint(x: first.x, y: geo.size.height))
                    points.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: points.last!.x, y: geo.size.height))
                }
                .fill(LinearGradient(colors: [.orange.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                Path { p in p.addLines(points) }
                    .stroke(.orange, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private struct MiniBars: View {
    let values: [Int]

    var body: some View {
        GeometryReader { geo in
            let peak = max(1, values.max() ?? 1)
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.orange)
                        .frame(height: max(1, geo.size.height * CGFloat(v) / CGFloat(peak)))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct AIActivityDetail: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var model = AIUsageModel.shared

    var body: some View {
        let ai = state.config.widgets.ai
        let total = model.total(ai.activityProvider, ai.activityRange)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Provider", selection: $state.config.widgets.ai.activityProvider) {
                    ForEach(AIProvider.allCases.filter(\.hasActivity)) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button { model.refresh(force: false) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
            }
            Picker("Range", selection: $state.config.widgets.ai.activityRange) {
                ForEach(AIRange.allCases) { Text($0.short).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack(spacing: 16) {
                stat(formatTokens(total.tokens), "tokens")
                stat("\(total.sessions.count)", "sessions")
                stat("\(total.toolCalls)", "tool calls")
            }
            if ai.activityRange == .today {
                Text("Totals are for today; the chart shows the last 7 days.").font(.caption2).foregroundStyle(.secondary)
            }
            Sparkline(values: model.series(ai.activityProvider, ai.activityRange).map(\.tokens)).frame(height: 60)
            Divider()
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(AIUsageModel.chartDays(ai.activityRange).reversed(), id: \.self) { date in
                        let day = model.day(ai.activityProvider, date)
                        HStack {
                            Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).font(.caption)
                            Spacer()
                            Text(formatTokens(day.tokens)).font(.caption).monospacedDigit()
                            Text("\(day.sessions.count) s · \(day.toolCalls) t").font(.caption2).foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .trailing)
                        }
                    }
                }
            }
            .frame(maxHeight: 160)
            Text(source(ai.activityProvider)).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(width: 320)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func source(_ provider: AIProvider) -> String {
        switch provider {
        case .claude: "From Claude Code session logs on this Mac (~/.claude/projects). Tokens include cached input."
        case .codex: "From Codex session logs on this Mac (~/.codex/sessions). Not all ChatGPT conversations are included."
        case .copilot: "Copilot doesn't provide activity history."
        }
    }
}

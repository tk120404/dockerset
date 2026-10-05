import Foundation

/// Pomodoro-style focus timer: focus, then a break, then focus again.
@MainActor
final class FocusTimerModel: ObservableObject {
    static let shared = FocusTimerModel()

    enum Phase { case focus, rest }

    @Published private(set) var phase = Phase.focus
    @Published private(set) var running = false
    /// Seconds left, kept while paused.
    @Published private(set) var remaining: TimeInterval
    private var endDate: Date?
    private var timer: Timer?

    private init() {
        remaining = TimeInterval(AppState.shared.config.widgets.focusMinutes * 60)
    }

    var duration: TimeInterval {
        let w = AppState.shared.config.widgets
        return TimeInterval((phase == .focus ? w.focusMinutes : w.breakMinutes) * 60)
    }

    var progress: Double { duration > 0 ? remaining / duration : 0 }

    func toggle() {
        if running { pause() } else { start() }
    }

    func start() {
        Notifier.requestPermission()
        endDate = Date().addingTimeInterval(remaining)
        running = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func pause() {
        tick()
        running = false
        timer?.invalidate()
        endDate = nil
    }

    func reset() {
        pause()
        phase = .focus
        remaining = duration
    }

    /// Ends the current phase now and moves to the next one, paused.
    func skip() {
        pause()
        phase = phase == .focus ? .rest : .focus
        remaining = duration
    }

    /// Re-reads the length when it's changed in Settings and the timer isn't running.
    func settingsChanged() {
        if !running { remaining = duration }
    }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow.rounded())
        guard remaining == 0 else { return }
        let finished = phase
        phase = finished == .focus ? .rest : .focus
        remaining = duration
        if finished == .focus {
            Notifier.post("Focus session done", "Time for a \(AppState.shared.config.widgets.breakMinutes)-minute break.")
            start() // breaks start on their own
        } else {
            Notifier.post("Break's over", "Click the Focus Timer when you're ready to focus again.")
            running = false
            timer?.invalidate()
            self.endDate = nil
        }
    }
}

/// Counts down to the next glass of water and tracks today's count.
@MainActor
final class HydrationModel: ObservableObject {
    static let shared = HydrationModel()

    @Published private(set) var nextDrink: Date
    @Published private(set) var drinksToday: Int
    @Published private(set) var now = Date()
    private var notified = false
    private var timer: Timer?

    private static let countKey = "hydrationCount"
    private static let dayKey = "hydrationDay"

    private init() {
        nextDrink = Date().addingTimeInterval(TimeInterval(AppState.shared.config.widgets.hydrationMinutes * 60))
        let today = Self.dayString(Date())
        drinksToday = UserDefaults.standard.string(forKey: Self.dayKey) == today ? UserDefaults.standard.integer(forKey: Self.countKey) : 0
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    var interval: TimeInterval { TimeInterval(AppState.shared.config.widgets.hydrationMinutes * 60) }
    var remaining: TimeInterval { max(0, nextDrink.timeIntervalSince(now)) }
    /// 1 right after a drink, draining to 0 when the next one is due.
    var level: Double { interval > 0 ? remaining / interval : 0 }
    var due: Bool { remaining == 0 }

    func logDrink() {
        rollOverDay()
        drinksToday += 1
        UserDefaults.standard.set(drinksToday, forKey: Self.countKey)
        UserDefaults.standard.set(Self.dayString(Date()), forKey: Self.dayKey)
        restart()
    }

    func restart() {
        Notifier.requestPermission()
        nextDrink = Date().addingTimeInterval(interval)
        now = Date()
        notified = false
    }

    func undoDrink() {
        drinksToday = max(0, drinksToday - 1)
        UserDefaults.standard.set(drinksToday, forKey: Self.countKey)
    }

    private func tick() {
        now = Date()
        rollOverDay()
        if due && !notified {
            notified = true
            Notifier.post("Time for some water", "Click the Hydration widget after your drink.")
        }
    }

    private func rollOverDay() {
        let today = Self.dayString(Date())
        if UserDefaults.standard.string(forKey: Self.dayKey) != today {
            UserDefaults.standard.set(today, forKey: Self.dayKey)
            UserDefaults.standard.set(0, forKey: Self.countKey)
            drinksToday = 0
        }
    }

    private static func dayString(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }
}

func formatClock(_ seconds: TimeInterval) -> String {
    let s = Int(seconds)
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
}

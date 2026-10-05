import AppKit
import EventKit

@MainActor
final class CalendarModel: ObservableObject {
    static let shared = CalendarModel()

    let store = EKEventStore()
    @Published private(set) var events: [EKEvent] = []
    @Published private(set) var reminders: [EKReminder] = []
    @Published private(set) var eventAccess = false
    @Published private(set) var reminderAccess = false
    /// Bumped every minute so relative times ("in 5 min") re-render.
    @Published private(set) var tick = Date()

    private var timer: Timer?

    func start() {
        updateStatus()
        refresh()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick = Date()
                self?.refresh()
            }
        }
    }

    func updateStatus() {
        eventAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        reminderAccess = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    var eventsDenied: Bool { EKEventStore.authorizationStatus(for: .event) == .denied }

    func requestAccess() async {
        _ = try? await store.requestFullAccessToEvents()
        _ = try? await store.requestFullAccessToReminders()
        updateStatus()
        refresh()
    }

    func refresh() {
        let settings = AppState.shared.config.widgets.calendar
        if eventAccess {
            let now = Date()
            let start = now.addingTimeInterval(-12 * 3600)
            let end = Calendar.current.date(byAdding: .day, value: max(1, settings.daysAhead), to: Calendar.current.startOfDay(for: now))!
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            events = store.events(matching: predicate)
                .filter { $0.endDate > now }
                .sorted { ($0.isAllDay ? 1 : 0, $0.startDate) < ($1.isAllDay ? 1 : 0, $1.startDate) }
        }
        if reminderAccess && settings.showReminders {
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            store.fetchReminders(matching: predicate) { [weak self] found in
                let sorted = (found ?? []).sorted {
                    ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture)
                }
                Task { @MainActor in self?.reminders = Array(sorted.prefix(20)) }
            }
        }
    }

    var nextEvent: EKEvent? { events.first { !$0.isAllDay } ?? events.first }

    func complete(_ reminder: EKReminder) {
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
        reminders.removeAll { $0.calendarItemIdentifier == reminder.calendarItemIdentifier }
    }

    func timeDescription(_ event: EKEvent) -> String {
        if event.isAllDay { return "All day" }
        let now = Date()
        let time = event.startDate.formatted(date: .omitted, time: .shortened)
        if event.startDate <= now {
            return "Now · until \(event.endDate.formatted(date: .omitted, time: .shortened))"
        }
        let minutes = Int(event.startDate.timeIntervalSince(now) / 60)
        if minutes < 60 { return "in \(max(1, minutes)) min" }
        if Calendar.current.isDateInToday(event.startDate) { return time }
        return event.startDate.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private static let meetingPattern = try! NSRegularExpression(
        pattern: #"https?://[^\s<>"]*(zoom\.us/(j|my|w)|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com|whereby\.com|facetime\.apple\.com|around\.co)[^\s<>"]*"#,
        options: .caseInsensitive
    )

    /// Video-call link found in the event's URL, location or notes.
    static func meetingURL(_ event: EKEvent) -> URL? {
        for text in [event.url?.absoluteString, event.location, event.notes].compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = meetingPattern.firstMatch(in: text, range: range), let r = Range(match.range, in: text) {
                return URL(string: String(text[r]))
            }
        }
        return nil
    }
}

import EventKit
import Foundation

@MainActor
final class CalendarWatch {
    private let store = EKEventStore()
    private var events: [(start: Date, end: Date, allDay: Bool)] = []
    private var timer: Timer?
    private(set) var available = false

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        refresh()
    }

    func refresh() {
        Task { [weak self] in
            guard let self else { return }
            let granted: Bool
            if #available(macOS 14.0, *) { granted = (try? await store.requestFullAccessToEvents()) ?? false }
            else { granted = (try? await store.requestAccess(to: .event)) ?? false }
            available = granted
            guard granted else { events = []; return }
            let start = Calendar.current.startOfDay(for: Date()), end = start.addingTimeInterval(86400)
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            events = store.events(matching: predicate).map { ($0.startDate, $0.endDate ?? $0.startDate.addingTimeInterval(3600), $0.isAllDay) }
        }
    }

    var inMeeting: Bool {
        let now = Date()
        return events.contains { !$0.allDay && $0.start <= now && now < $0.end }
    }

    func eventWithin(minutes: Double) -> Bool {
        let now = Date()
        return events.contains { !$0.allDay && $0.start > now && $0.start <= now.addingTimeInterval(minutes * 60) }
    }
}

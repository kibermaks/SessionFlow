import Foundation
import EventKit
import SwiftUI
import AppKit

struct CalendarDescriptor: Equatable {
    let name: String
    let identifier: String?
}

// MARK: - Calendar Service
/// Manages all interactions with macOS Calendar via EventKit
class CalendarService: ObservableObject {
    private static let excludedCalendarsDefaultsKey = "SessionFlow.ExcludedCalendars"
    private let eventStore = EKEventStore()
    private var notificationObserver: NSObjectProtocol?
    private var ekChangeTask: Task<Void, Never>?

    /// Resolves a session tag in notes to its corresponding SessionType.
    static func sessionType(fromNotes notes: String?) -> SessionType? {
        SessionFlowEventSemantics.sessionType(fromNotes: notes)
    }
    
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var availableCalendars: [EKCalendar] = []
    @Published var busySlots: [BusyTimeSlot] = []
    @Published var isLoading = false
    @Published var lastRefresh: Date = Date()
    @Published private(set) var fetchedDate: Date?
    @Published var excludedCalendarIDs: Set<String> = []

    /// Last EventKit failure — not observed by any view today; assignments are kept
    /// as a hook for a future error banner and to preserve the message at the moment
    /// of failure for debug logs.
    var errorMessage: String?
    
    // Store the current date for auto-refresh
    private var currentFetchDate: Date?

    /// Set from ContentView to match SchedulingEngine.scheduleEndHour.
    /// When > 24, fetches/counts/deletes extend into the next calendar day.
    var scheduleEndHour: Int = 24

    /// Calculates effective end-of-day for a given date, respecting scheduleEndHour.
    private func effectiveEndOfDay(for date: Date) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .hour, value: scheduleEndHour, to: startOfDay) ?? date
    }
    
    init() {
        excludedCalendarIDs = Set(
            UserDefaults.standard.stringArray(forKey: Self.excludedCalendarsDefaultsKey) ?? []
        )
        checkAuthorizationStatus()
        setupNotificationObserver()
    }
    
    deinit {
        ekChangeTask?.cancel()
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Notification Observer

    private func setupNotificationObserver() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // Debounce: cancel any in-flight task and schedule a new one so only
            // the last notification in a burst fires, and reset+fetch run in a
            // single serial chain on the main actor (EKEventStore is not
            // thread-safe — concurrent reset() + events(matching:) can crash).
            self.ekChangeTask?.cancel()
            self.ekChangeTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
                guard let self = self, let date = self.currentFetchDate else { return }
                await MainActor.run {
                    self.eventStore.reset()
                }
                await self.fetchEvents(for: date)
            }
        }
    }
    
    // MARK: - Authorization
    
    func checkAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        if authorizationStatus == .fullAccess {
            loadCalendars()
        }
    }
    
    func requestAccess() async -> Bool {
        do {
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }
            
            await MainActor.run {
                self.authorizationStatus = granted ? .fullAccess : .denied
                if granted {
                    self.loadCalendars()
                }
            }
            return granted
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to request calendar access: \(error.localizedDescription)"
            }
            return false
        }
    }
    
    // MARK: - Calendar Loading
    
    func loadCalendars() {
        let eventCalendars = eventStore.calendars(for: .event).filter { calendar in
            calendar.type != .birthday
        }
        availableCalendars = eventCalendars.filter { $0.allowsContentModifications }
        pruneExcludedCalendars(using: eventCalendars)
    }
    
    func getCalendar(named name: String) -> EKCalendar? {
        return availableCalendars.first { $0.title == name }
    }
    
    func getCalendar(identifier: String?) -> EKCalendar? {
        guard let identifier else { return nil }
        return availableCalendars.first { $0.calendarIdentifier == identifier }
    }
    
    func calendarNames() -> [String] {
        return availableCalendars.map { $0.title }.sorted()
    }
    
    private func calendar(from descriptor: CalendarDescriptor) -> EKCalendar? {
        if let identifier = descriptor.identifier,
           let calendar = getCalendar(identifier: identifier) {
            return calendar
        }
        return getCalendar(named: descriptor.name)
    }
    
    private func calendars(from descriptors: [CalendarDescriptor]) -> [EKCalendar] {
        descriptors.compactMap { calendar(from: $0) }
    }

    private func eventContainsSessionTag(_ event: EKEvent) -> Bool {
        SessionFlowEventSemantics.isSessionFlowOwned(event.notes)
    }
    
    struct CalendarInfo: Identifiable {
        let id: String
        let identifier: String
        let name: String
        let color: Color
        let isExcluded: Bool
        
        init(calendar: EKCalendar, isExcluded: Bool) {
            let calendarId = calendar.calendarIdentifier
            self.id = calendarId
            self.identifier = calendarId
            self.name = calendar.title
            self.isExcluded = isExcluded
            if let cgColor = calendar.cgColor,
               let nsColor = NSColor(cgColor: cgColor) {
                self.color = Color(nsColor: nsColor)
            } else {
                self.color = Color.gray
            }
        }
    }
    
    func calendarInfoList(includeExcluded: Bool = true) -> [CalendarInfo] {
        return availableCalendars
            .filter { includeExcluded || isCalendarIncluded($0) }
            .sorted { $0.title < $1.title }
            .map { calendar in
                CalendarInfo(
                    calendar: calendar,
                    isExcluded: isCalendarExcluded(identifier: calendar.calendarIdentifier)
                )
            }
    }
    
    /// Returns every calendar that supports event entities (read-only + editable).
    private func includedEventCalendars() -> [EKCalendar] {
        return eventStore.calendars(for: .event)
            .filter { $0.type != .birthday }
            .filter { isCalendarIncluded($0) }
    }
    
    private func isCalendarIncluded(_ calendar: EKCalendar) -> Bool {
        return !excludedCalendarIDs.contains(calendar.calendarIdentifier)
    }
    
    func isCalendarExcluded(identifier: String) -> Bool {
        return excludedCalendarIDs.contains(identifier)
    }
    
    func setCalendar(_ calendar: EKCalendar, included: Bool) {
        let identifier = calendar.calendarIdentifier
        var changed = false
        
        if included {
            if excludedCalendarIDs.contains(identifier) {
                excludedCalendarIDs.remove(identifier)
                changed = true
            }
        } else {
            if !excludedCalendarIDs.contains(identifier) {
                excludedCalendarIDs.insert(identifier)
                changed = true
            }
        }
        
        if changed {
            persistExcludedCalendars()
            if included {
                refreshCurrentEvents()
            } else {
                removeBusySlots(for: identifier)
            }
        }
    }
    
    private func persistExcludedCalendars() {
        UserDefaults.standard.set(
            Array(excludedCalendarIDs),
            forKey: Self.excludedCalendarsDefaultsKey
        )
    }
    
    private func pruneExcludedCalendars(using calendars: [EKCalendar]) {
        let validIDs = Set(calendars.map { $0.calendarIdentifier })
        let filtered = excludedCalendarIDs.filter { validIDs.contains($0) }
        if filtered.count != excludedCalendarIDs.count {
            excludedCalendarIDs = Set(filtered)
            persistExcludedCalendars()
        }
    }
    
    private func removeBusySlots(for identifier: String) {
        busySlots.removeAll { slot in
            slot.calendarIdentifier == identifier
        }
    }
    
    func refreshCurrentEvents() {
        guard let date = currentFetchDate else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.fetchEvents(for: date)
        }
    }

    func busySlotsForFetchedDate(_ date: Date) -> [BusyTimeSlot] {
        guard let fetchedDate,
              Calendar.current.isDate(fetchedDate, inSameDayAs: date) else {
            return []
        }

        let start = Calendar.current.startOfDay(for: date)
        let end = effectiveEndOfDay(for: date)
        return busySlots.filter { slot in
            slot.endTime > start && slot.startTime < end
        }
    }
    
    // MARK: - Event Fetching
    
    func fetchEvents(for date: Date) async {
        // Keep all EKEventStore access on the main actor — EKEventStore is not
        // thread-safe, and previously the events(matching:) call ran on a Task
        // cooperative thread while reset() could fire concurrently from the
        // change debounce.
        await MainActor.run {
            self.isLoading = true
            self.currentFetchDate = date
            self.fetchedDate = date

            let startOfDay = Calendar.current.startOfDay(for: date)
            let endOfDay = self.effectiveEndOfDay(for: date)
            let calendars = self.includedEventCalendars()
            let slots: [BusyTimeSlot]
            if calendars.isEmpty {
                slots = []
            } else {
                let predicate = self.eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: calendars)
                let nearAlldayThreshold: TimeInterval = 23 * 60 * 60
                slots = self.eventStore.events(matching: predicate)
                    .filter { !$0.isAllDay && $0.endDate.timeIntervalSince($0.startDate) < nearAlldayThreshold }
                    .map { BusyTimeSlot(from: $0) }
            }

            self.busySlots = slots
            self.isLoading = false
            self.lastRefresh = Date()
        }
    }
    
    /// Fetch events around now: any currently active event plus upcoming events until end of day.
    /// Used by SessionAwarenessService to always track the current session regardless of selected day.
    func fetchNowSlots(referenceTime: Date? = nil) -> [BusyTimeSlot] {
        let now = referenceTime ?? Date()
        // Look back 12 hours to catch events that started earlier and are still running
        let windowStart = now.addingTimeInterval(-12 * 3600)
        let endOfDay = effectiveEndOfDay(for: now)

        let calendars = includedEventCalendars()
        guard !calendars.isEmpty else { return [] }

        let predicate = eventStore.predicateForEvents(withStart: windowStart, end: endOfDay, calendars: calendars)
        let events = eventStore.events(matching: predicate)

        let nearAlldayThreshold: TimeInterval = 23 * 60 * 60
        // Include events that ended up to 1h ago (needed for rest detection between sessions)
        let recentCutoff = now.addingTimeInterval(-3600)
        return events
            .filter { !$0.isAllDay && $0.endDate.timeIntervalSince($0.startDate) < nearAlldayThreshold }
            .filter { $0.endDate > recentCutoff }
            .map { BusyTimeSlot(from: $0) }
    }

    // MARK: - Event Creation
    
    @discardableResult
    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        calendar: CalendarDescriptor,
        notes: String? = nil,
        url: URL? = nil
    ) -> Bool {
        guard let destination = self.calendar(from: calendar) else {
            errorMessage = "Calendar '\(calendar.name)' not found"
            return false
        }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = destination
        event.notes = notes
        event.url = url
        
        do {
            try eventStore.save(event, span: .thisEvent)
            return true
        } catch {
            errorMessage = "Failed to create event: \(error.localizedDescription)"
            return false
        }
    }

    /// Creates a calendar event and returns its identifier, or nil on failure.
    func createEventReturningId(
        title: String,
        startDate: Date,
        endDate: Date,
        calendar: CalendarDescriptor,
        notes: String? = nil,
        url: URL? = nil
    ) -> String? {
        guard let destination = self.calendar(from: calendar) else {
            errorMessage = "Calendar '\(calendar.name)' not found"
            return nil
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = destination
        event.notes = notes
        event.url = url

        do {
            try eventStore.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            errorMessage = "Failed to create event: \(error.localizedDescription)"
            return nil
        }
    }

    /// Restores a deleted event from snapshot. Returns new event identifier on success.
    func restoreEvent(_ snapshot: EventDeleteSnapshot) -> String? {
        guard let destination = calendar(from: CalendarDescriptor(name: snapshot.calendarName, identifier: snapshot.calendarIdentifier)) else {
            return nil
        }
        let event = EKEvent(eventStore: eventStore)
        event.title = snapshot.title
        event.startDate = snapshot.startDate
        event.endDate = snapshot.endDate
        event.calendar = destination
        event.notes = snapshot.notes
        event.url = snapshot.url
        do {
            try eventStore.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            errorMessage = "Failed to restore event: \(error.localizedDescription)"
            return nil
        }
    }
    
    /// Copies an event to a target date. Returns (success, newEventId, targetStartTime).
    func copyEventToDay(eventId: String, targetDate: Date) -> (success: Bool, newEventId: String?, targetStartTime: Date?) {
        guard let source = eventStore.event(withIdentifier: eventId) else {
            errorMessage = "Event not found"
            return (false, nil, nil)
        }

        let calendar = Calendar.current
        guard let sourceStart = source.startDate, let sourceEnd = source.endDate else {
            errorMessage = "Event has no start/end date"
            return (false, nil, nil)
        }
        let duration = sourceEnd.timeIntervalSince(sourceStart)

        let startComps = calendar.dateComponents([.hour, .minute, .second], from: sourceStart)
        guard let newStart = calendar.date(bySettingHour: startComps.hour ?? 0,
                                           minute: startComps.minute ?? 0,
                                           second: startComps.second ?? 0,
                                           of: targetDate) else {
            errorMessage = "Failed to calculate target date"
            return (false, nil, nil)
        }
        let newEnd = newStart.addingTimeInterval(duration)

        let notes = SessionAlignment.stripAlignmentTags(
            SessionRating.stripFeedbackTags(source.notes)
        ) ?? ""

        let copy = EKEvent(eventStore: eventStore)
        copy.title = source.title
        copy.startDate = newStart
        copy.endDate = newEnd
        copy.calendar = source.calendar
        copy.notes = notes.isEmpty ? nil : notes
        copy.url = source.url

        do {
            try eventStore.save(copy, span: .thisEvent)
            return (true, copy.eventIdentifier, newStart)
        } catch {
            errorMessage = "Failed to copy event: \(error.localizedDescription)"
            return (false, nil, nil)
        }
    }

    /// Duplicates an event onto the same day at the same time as the original.
    func duplicateEvent(eventId: String) -> (success: Bool, newEventId: String?, targetStartTime: Date?) {
        guard let source = eventStore.event(withIdentifier: eventId) else {
            errorMessage = "Event not found"
            return (false, nil, nil)
        }
        guard let sourceStart = source.startDate, let sourceEnd = source.endDate else {
            errorMessage = "Event has no start/end date"
            return (false, nil, nil)
        }

        let newStart = sourceStart
        let newEnd = sourceEnd

        let notes = SessionAlignment.stripAlignmentTags(
            SessionRating.stripFeedbackTags(source.notes)
        ) ?? ""

        let copy = EKEvent(eventStore: eventStore)
        copy.title = source.title
        copy.startDate = newStart
        copy.endDate = newEnd
        copy.calendar = source.calendar
        copy.notes = notes.isEmpty ? nil : notes
        copy.url = source.url

        do {
            try eventStore.save(copy, span: .thisEvent)
            return (true, copy.eventIdentifier, newStart)
        } catch {
            errorMessage = "Failed to duplicate event: \(error.localizedDescription)"
            return (false, nil, nil)
        }
    }

    /// Deletes a single event by identifier. Returns true if deleted successfully.
    func deleteEvent(identifier: String) -> Bool {
        guard let event = eventStore.event(withIdentifier: identifier) else { return false }
        do {
            try eventStore.remove(event, span: .thisEvent)
            return true
        } catch {
            errorMessage = "Failed to delete event: \(error.localizedDescription)"
            return false
        }
    }

    /// Returns the current duration in minutes for an event, or nil if the event no longer exists.
    func eventDurationMinutes(identifier: String) -> Int? {
        guard let event = eventStore.event(withIdentifier: identifier) else { return nil }
        guard let start = event.startDate, let end = event.endDate else { return nil }
        return Int(end.timeIntervalSince(start) / 60)
    }

    func createSessions(_ sessions: [ScheduledSession]) -> (success: Int, failed: Int, eventIds: [String]) {
        var successCount = 0
        var failCount = 0
        var eventIds: [String] = []
        var savedNames: Set<String> = [] // Track unique names saved per type

        for session in sessions {
            if let eventId = createEventReturningId(
                title: session.title,
                startDate: session.startTime,
                endDate: session.endTime,
                calendar: CalendarDescriptor(
                    name: session.calendarName,
                    identifier: session.calendarIdentifier
                ),
                notes: session.notes
            ) {
                successCount += 1
                eventIds.append(eventId)
                // Save session name to history when successfully created (only once per unique name per batch)
                let nameKey = "\(session.type.rawValue):\(session.title)"
                if !savedNames.contains(nameKey) {
                    SessionNameHistory.shared.addName(session.title, for: session.type)
                    savedNames.insert(nameKey)
                }
            } else {
                failCount += 1
            }
        }

        return (successCount, failCount, eventIds)
    }
    
    // MARK: - Event Update
    
    /// Updates an existing calendar event by its identifier
    /// - Parameters:
    ///   - eventId: The event identifier
    ///   - title: New title (nil = don't change)
    ///   - notes: New notes (nil = don't change)
    ///   - url: New URL (only used when updateURL is true)
    ///   - updateURL: If true, update the URL field (can set to nil to clear)
    func updateEvent(eventId: String, title: String?, notes: String?, url: URL?, updateURL: Bool = false) -> Bool {
        guard let event = eventStore.event(withIdentifier: eventId) else {
            errorMessage = "Event not found"
            return false
        }
        
        // Update properties only if provided
        if let title = title {
            event.title = title
        }
        if let notes = notes {
            event.notes = notes
        }
        // Only update URL when explicitly requested
        if updateURL {
            event.url = url
        }
        
        do {
            try eventStore.save(event, span: .thisEvent)
            return true
        } catch {
            errorMessage = "Failed to update event: \(error.localizedDescription)"
            return false
        }
    }

    func eventIsFlexible(identifier: String) -> Bool? {
        guard let event = eventStore.event(withIdentifier: identifier) else { return nil }
        return FlowFlexibilityNotes.isFlexible(event.notes)
    }

    func setEventFlexible(eventId: String, isFlexible: Bool) -> Bool {
        guard let event = eventStore.event(withIdentifier: eventId) else {
            errorMessage = "Event not found"
            return false
        }

        event.notes = FlowFlexibilityNotes.applyingFlexible(isFlexible, to: event.notes)

        do {
            try eventStore.save(event, span: .thisEvent)
            return true
        } catch {
            errorMessage = "Failed to update event flexibility: \(error.localizedDescription)"
            return false
        }
    }
    
    // MARK: - Feedback Tag

    /// Atomically reads event notes, replaces any feedback tag, and saves
    @discardableResult
    func setFeedbackTag(eventId: String, rating: SessionRating) -> Bool {
        guard let event = eventStore.event(withIdentifier: eventId) else { return false }
        event.notes = rating.applyTo(notes: event.notes)
        do {
            try eventStore.save(event, span: .thisEvent)
            return true
        } catch {
            errorMessage = "Failed to save feedback: \(error.localizedDescription)"
            return false
        }
    }

    /// Atomically reads event notes, replaces any alignment tag, and saves
    @discardableResult
    func setAlignmentTag(eventId: String, alignment: SessionAlignment) -> Bool {
        guard let event = eventStore.event(withIdentifier: eventId) else { return false }
        event.notes = alignment.applyTo(notes: event.notes)
        do {
            try eventStore.save(event, span: .thisEvent)
            return true
        } catch {
            errorMessage = "Failed to save alignment: \(error.localizedDescription)"
            return false
        }
    }

    /// Atomically applies both review axes, preserving other event notes.
    @discardableResult
    func setReviewTags(eventId: String, rating: SessionRating, alignment: SessionAlignment) -> Bool {
        guard let event = eventStore.event(withIdentifier: eventId) else { return false }
        let withRating = rating.applyTo(notes: event.notes)
        event.notes = alignment.applyTo(notes: withRating)
        do {
            try eventStore.save(event, span: .thisEvent)
            return true
        } catch {
            errorMessage = "Failed to save session review: \(error.localizedDescription)"
            return false
        }
    }

    /// Removes any feedback tag from event notes
    @discardableResult
    func clearFeedbackTag(eventId: String) -> Bool {
        guard let event = eventStore.event(withIdentifier: eventId) else { return false }
        let notes = SessionRating.stripFeedbackTags(event.notes) ?? ""
        event.notes = notes.isEmpty ? nil : notes
        do {
            try eventStore.save(event, span: .thisEvent)
            return true
        } catch {
            return false
        }
    }

    /// Removes any alignment tag from event notes
    @discardableResult
    func clearAlignmentTag(eventId: String) -> Bool {
        guard let event = eventStore.event(withIdentifier: eventId) else { return false }
        let notes = SessionAlignment.stripAlignmentTags(event.notes) ?? ""
        event.notes = notes.isEmpty ? nil : notes
        do {
            try eventStore.save(event, span: .thisEvent)
            return true
        } catch {
            return false
        }
    }

    /// Counts feedback ratings across all events in a date range (inclusive)
    func feedbackStats(from startDate: Date, to endDate: Date) -> [SessionRating: Int] {
        let calendars = includedEventCalendars()
        guard !calendars.isEmpty else { return [:] }

        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        let events = eventStore.events(matching: predicate)

        var counts: [SessionRating: Int] = [:]
        for event in events {
            if let rating = SessionRating.fromNotes(event.notes) {
                counts[rating, default: 0] += 1
            }
        }
        return counts
    }

    func hasProductivityFeedback(inLastDays days: Int, endingAt referenceDate: Date = Date()) -> Bool {
        let calendar = Calendar.current
        let dayCount = max(1, days)
        let end = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: referenceDate)
        ) ?? referenceDate
        let start = calendar.date(
            byAdding: .day,
            value: -(dayCount - 1),
            to: calendar.startOfDay(for: referenceDate)
        ) ?? referenceDate

        return hasProductivityFeedback(from: start, to: end)
    }

    func hasProductivityFeedback(from startDate: Date, to endDate: Date) -> Bool {
        let calendars = includedEventCalendars()
        guard !calendars.isEmpty else { return false }

        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        let nearAlldayThreshold: TimeInterval = 23 * 60 * 60
        return eventStore.events(matching: predicate).contains { event in
            guard !event.isAllDay, event.endDate.timeIntervalSince(event.startDate) < nearAlldayThreshold else {
                return false
            }
            return SessionRating.fromNotes(event.notes) != nil || SessionAlignment.fromNotes(event.notes) != nil
        }
    }

    struct DaySessionReview: Identifiable {
        let id: String
        let title: String
        let startDate: Date
        let endDate: Date
        let rating: SessionRating
        let alignment: SessionAlignment?
        let alignmentCountsTowardScore: Bool
        let durationMinutes: Int
        let focusMinutes: Int
    }

    /// Per-day stats: feedback counts + total events (for computing unrated)
    struct DayFeedbackStats {
        var counts: [SessionRating: Int] = [:]
        var alignmentCounts: [SessionAlignment: Int] = [:]
        var sessionReviews: [DaySessionReview] = []
        var totalEvents: Int = 0
        var spentMinutes: Double = 0
        var focusMinutes: Double = 0
        var alignedFocusMinutes: Double = 0
        var alignmentEligibleFocusMinutes: Double = 0
        var alignmentEligibleRated: Int = 0
        var unrated: Int { totalEvents - counts.values.reduce(0, +) }
        var alignmentRated: Int { alignmentCounts.values.reduce(0, +) }
        var alignmentMissing: Int { max(0, alignmentEligibleRated - alignmentRated) }
    }

    /// Returns per-day feedback stats for a given month
    func monthlyFeedbackStats(
        year: Int,
        month: Int,
        weights: FocusWeights = .init(),
        alignmentWeights: AlignmentWeights = .init(),
        sessionType: SessionType? = nil
    ) -> [Int: DayFeedbackStats] {
        let cal = Calendar.current
        guard let monthStart = cal.date(from: DateComponents(year: year, month: month, day: 1)),
              let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else { return [:] }

        let calendars = includedEventCalendars()
        guard !calendars.isEmpty else { return [:] }

        let predicate = eventStore.predicateForEvents(withStart: monthStart, end: monthEnd, calendars: calendars)
        let allEvents = eventStore.events(matching: predicate)

        // Filter out all-day events
        let nearAlldayThreshold: TimeInterval = 23 * 60 * 60
        var events = allEvents.filter { !$0.isAllDay && $0.endDate.timeIntervalSince($0.startDate) < nearAlldayThreshold }

        // Filter by session type if specified
        if let sessionType = sessionType {
            events = events.filter { event in
                CalendarService.sessionType(fromNotes: event.notes) == sessionType
            }
        }
        events.sort {
            if $0.startDate == $1.startDate {
                return ($0.title ?? "") < ($1.title ?? "")
            }
            return $0.startDate < $1.startDate
        }

        var result: [Int: DayFeedbackStats] = [:]
        for event in events {
            let day = cal.component(.day, from: event.startDate)
            result[day, default: DayFeedbackStats()].totalEvents += 1
            if let rating = SessionRating.fromNotes(event.notes) {
                result[day, default: DayFeedbackStats()].counts[rating, default: 0] += 1
                let minutes = event.endDate.timeIntervalSince(event.startDate) / 60
                let focusMinutes = minutes * weights.multiplier(for: rating)
                let spentMinutes = rating == .skipped ? 0 : minutes
                let alignmentEligibleMinutes = rating == .procrastinated ? minutes : max(0, focusMinutes)
                let alignment = SessionAlignment.fromNotes(event.notes)
                let countsTowardAlignment = FlowFlexibilityNotes.countsTowardAlignmentScore(
                    event.notes,
                    alignment: alignment,
                    eligibleMinutes: alignmentEligibleMinutes
                )
                result[day, default: DayFeedbackStats()].spentMinutes += spentMinutes
                result[day, default: DayFeedbackStats()].focusMinutes += focusMinutes
                if countsTowardAlignment {
                    result[day, default: DayFeedbackStats()].alignmentEligibleFocusMinutes += alignmentEligibleMinutes
                    result[day, default: DayFeedbackStats()].alignmentEligibleRated += 1
                }
                result[day, default: DayFeedbackStats()].sessionReviews.append(DaySessionReview(
                    id: event.eventIdentifier ?? "\(event.startDate.timeIntervalSince1970)-\(event.title ?? "")",
                    title: event.title ?? "Untitled",
                    startDate: event.startDate,
                    endDate: event.endDate,
                    rating: rating,
                    alignment: alignment,
                    alignmentCountsTowardScore: countsTowardAlignment,
                    durationMinutes: Int(minutes.rounded()),
                    focusMinutes: Int(focusMinutes.rounded())
                ))
                if let alignment {
                    result[day, default: DayFeedbackStats()].alignmentCounts[alignment, default: 0] += 1
                    result[day, default: DayFeedbackStats()].alignedFocusMinutes += focusMinutes * alignmentWeights.multiplier(for: alignment)
                }
            }
        }
        return result
    }

    /// Returns today's feedback stats (total events + focus minutes)
    func todayFeedbackStats(
        weights: FocusWeights = .init(),
        alignmentWeights: AlignmentWeights = .init()
    ) -> DayFeedbackStats {
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        let day = cal.component(.day, from: now)
        let stats = monthlyFeedbackStats(year: year, month: month, weights: weights, alignmentWeights: alignmentWeights)
        return stats[day] ?? DayFeedbackStats()
    }

    /// Returns per-session-type event counts for a given month
    func monthlySessionTypeCounts(year: Int, month: Int) -> [SessionType: Int] {
        let cal = Calendar.current
        guard let monthStart = cal.date(from: DateComponents(year: year, month: month, day: 1)),
              let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else { return [:] }

        let calendars = includedEventCalendars()
        guard !calendars.isEmpty else { return [:] }

        let predicate = eventStore.predicateForEvents(withStart: monthStart, end: monthEnd, calendars: calendars)
        let nearAlldayThreshold: TimeInterval = 23 * 60 * 60
        let events = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate.timeIntervalSince($0.startDate) < nearAlldayThreshold }

        var result: [SessionType: Int] = [:]
        for event in events {
            if let type = CalendarService.sessionType(fromNotes: event.notes) {
                result[type, default: 0] += 1
            }
        }
        return result
    }

    // MARK: - Event Time Update

    /// Updates the start and end time of an existing calendar event.
    func updateEventTime(eventId: String, newStart: Date, newEnd: Date) -> Bool {
        guard let event = eventStore.event(withIdentifier: eventId) else {
            errorMessage = "Event not found"
            return false
        }

        event.startDate = newStart
        event.endDate = newEnd

        do {
            try eventStore.save(event, span: .thisEvent)
            return true
        } catch {
            errorMessage = "Failed to update event time: \(error.localizedDescription)"
            return false
        }
    }

    /// Updates several event times and commits them to EventKit together.
    func updateEventTimes(_ updates: [(eventId: String, newStart: Date, newEnd: Date)]) -> Bool {
        guard !updates.isEmpty else { return true }

        var resolved: [(event: EKEvent, newStart: Date, newEnd: Date)] = []
        resolved.reserveCapacity(updates.count)

        for update in updates {
            guard let event = eventStore.event(withIdentifier: update.eventId) else {
                errorMessage = "Event not found"
                eventStore.reset()
                return false
            }
            resolved.append((event, update.newStart, update.newEnd))
        }

        do {
            for item in resolved {
                item.event.startDate = item.newStart
                item.event.endDate = item.newEnd
                try eventStore.save(item.event, span: .thisEvent, commit: false)
            }
            try eventStore.commit()
            return true
        } catch {
            eventStore.reset()
            errorMessage = "Failed to update event times: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Count Existing Sessions
    
    func countExistingSessions(
        for date: Date,
        workCalendar: CalendarDescriptor,
        sideCalendar: CalendarDescriptor,
        deepConfig: DeepSessionConfig?
    ) -> (work: Int, side: Int, deep: Int, titles: Set<String>) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = effectiveEndOfDay(for: date)

        var calendarsToFetch: [CalendarDescriptor] = [workCalendar, sideCalendar]
        if let deep = deepConfig, deep.enabled {
            calendarsToFetch.append(CalendarDescriptor(name: deep.calendarName, identifier: deep.calendarIdentifier))
        }
        let calendars = calendars(from: calendarsToFetch)
            .filter { isCalendarIncluded($0) }
        
        if calendars.isEmpty { return (0, 0, 0, []) }
        
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: calendars)
        let events = eventStore.events(matching: predicate)
        let validEvents = events.filter { !$0.isAllDay }
        
        var workCount = 0
        var sideCount = 0
        var deepCount = 0
        var titles = Set<String>()
        
        for event in validEvents {
            let eventTitle = event.title ?? ""
            if !eventTitle.isEmpty {
                titles.insert(eventTitle)
            }
            
            // Only count events that have explicit hashtags in their notes.
            // Events without tags are not counted as aware sessions.
            if let type = SessionFlowEventSemantics.sessionType(fromNotes: event.notes) {
                switch type {
                case .work:
                    workCount += 1
                case .side:
                    sideCount += 1
                case .deep:
                    deepCount += 1
                case .planning, .bigRest:
                    break
                }
            }
        }
        
        return (workCount, sideCount, deepCount, titles)
    }

    // MARK: - Check for Existing Planning Session
    
    func hasPlanningSession(for date: Date, planningEventName: String = "Planning") -> Bool {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = effectiveEndOfDay(for: date)
        
        let calendars = includedEventCalendars()
        if calendars.isEmpty { return false }
        
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: calendars)
        let events = eventStore.events(matching: predicate)
        
        return events.contains { 
            ($0.title ?? "") == planningEventName || 
            SessionFlowEventSemantics.sessionType(fromNotes: $0.notes) == .planning
        }
    }
    
    // MARK: - Calendar Management
    
    func createCalendar(named name: String, color: Color) {
        // Double check if it already exists
        if getCalendar(named: name) != nil { return }
        
        let newCalendar = EKCalendar(for: .event, eventStore: eventStore)
        newCalendar.title = name
        
        // Find a suitable source (Local or iCloud)
        let sources = eventStore.sources
        // Prefer iCloud or Local
        if let bestSource = sources.first(where: { $0.sourceType == .calDAV && $0.title == "iCloud" }) ??
                            sources.first(where: { $0.sourceType == .local }) {
            newCalendar.source = bestSource
        } else {
            // Fallback to first available source
            newCalendar.source = sources.first
        }
        
        // Set color
        let nsColor = NSColor(color)
        newCalendar.cgColor = nsColor.cgColor
        
        do {
            try eventStore.saveCalendar(newCalendar, commit: true)
            // Reload to include the new calendar
            loadCalendars()
        } catch {
            errorMessage = "Failed to create calendar '\(name)': \(error.localizedDescription)"
        }
    }
    
    // MARK: - Delete Events
    
    /// Deletes all events from specified calendars for a given date
    func deleteEvents(for date: Date, fromCalendars calendarsToDelete: [CalendarDescriptor]) -> (deleted: Int, failed: Int) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = effectiveEndOfDay(for: date)

        let calendars = calendars(from: calendarsToDelete)
        
        guard !calendars.isEmpty else {
            errorMessage = "No matching calendars found for deletion"
            return (0, 0)
        }
        
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: calendars)
        let events = eventStore.events(matching: predicate)
        
        var deletedCount = 0
        var failedCount = 0
        
        for event in events {
            do {
                try eventStore.remove(event, span: .thisEvent)
                deletedCount += 1
            } catch {
                failedCount += 1
            }
        }
        
        return (deletedCount, failedCount)
    }
    
    /// Deletes specific events or all events from specified calendars
    func deleteSessionEvents(
        for date: Date,
        sessionNames: [String]? = nil,
        fromCalendars calendarsToDelete: [CalendarDescriptor],
        requireSessionTag: Bool = false
    ) -> (deleted: Int, failed: Int) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = effectiveEndOfDay(for: date)

        let calendars = calendars(from: calendarsToDelete)

        guard !calendars.isEmpty else {
            return (0, 0)
        }

        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: calendars)
        let events = eventStore.events(matching: predicate)
        
        let sessionsToDelete = events.filter { event in
            if requireSessionTag && !eventContainsSessionTag(event) {
                return false
            }
            guard let names = sessionNames, !names.isEmpty else {
                return true
            }
            guard let title = event.title else { return false }
            return names.contains(title)
        }
        
        var deletedCount = 0
        var failedCount = 0
        
        for event in sessionsToDelete {
            do {
                try eventStore.remove(event, span: .thisEvent)
                deletedCount += 1
            } catch {
                failedCount += 1
            }
        }
        
        return (deletedCount, failedCount)
    }
    
    /// Deletes specific future events or all future events from specified calendars
    func deleteFutureSessionEvents(
        for date: Date,
        after cutoffTime: Date,
        sessionNames: [String]? = nil,
        fromCalendars calendarsToDelete: [CalendarDescriptor],
        requireSessionTag: Bool = false
    ) -> (deleted: Int, failed: Int) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = effectiveEndOfDay(for: date)

        let calendars = calendars(from: calendarsToDelete)

        guard !calendars.isEmpty else {
            return (0, 0)
        }

        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: calendars)
        let events = eventStore.events(matching: predicate)
        
        let sessionsToDelete = events.filter { event in
            guard event.startDate >= cutoffTime else { return false }
            if requireSessionTag && !eventContainsSessionTag(event) {
                return false
            }
            guard let names = sessionNames, !names.isEmpty else {
                return true
            }
            guard let title = event.title else { return false }
            return names.contains(title)
        }
        
        var deletedCount = 0
        var failedCount = 0
        
        for event in sessionsToDelete {
            do {
                try eventStore.remove(event, span: .thisEvent)
                deletedCount += 1
            } catch {
                failedCount += 1
            }
        }
        
        return (deletedCount, failedCount)
    }
}

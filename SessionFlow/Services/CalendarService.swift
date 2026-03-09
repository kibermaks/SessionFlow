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
    private let recognizedSessionTags = ["#work", "#side", "#deep", "#plan", "#break"]

    /// Resolves a session tag in notes to its corresponding SessionType.
    static func sessionType(fromNotes notes: String?) -> SessionType? {
        guard let notes = notes?.lowercased() else { return nil }
        if notes.contains("#work") { return .work }
        if notes.contains("#side") { return .side }
        if notes.contains("#deep") { return .deep }
        if notes.contains("#plan") { return .planning }
        if notes.contains("#break") { return .bigRest }
        return nil
    }
    
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var availableCalendars: [EKCalendar] = []
    @Published var busySlots: [BusyTimeSlot] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastRefresh: Date = Date()
    @Published var excludedCalendarIDs: Set<String> = []
    
    // Store the current date for auto-refresh
    private var currentFetchDate: Date?

    /// Set from ContentView to match SchedulingEngine.scheduleEndHour.
    /// When > 24, fetches/counts/deletes extend into the next calendar day.
    var scheduleEndHour: Int = 24

    /// Calculates effective end-of-day for a given date, respecting scheduleEndHour.
    private func effectiveEndOfDay(for date: Date) -> Date {
        let calendar = Calendar.current
        let nextMidnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: date)!)
        if scheduleEndHour <= 24 {
            return nextMidnight
        }
        return calendar.date(byAdding: .hour, value: scheduleEndHour - 24, to: nextMidnight)!
    }
    
    init() {
        excludedCalendarIDs = Set(
            UserDefaults.standard.stringArray(forKey: Self.excludedCalendarsDefaultsKey) ?? []
        )
        checkAuthorizationStatus()
        setupNotificationObserver()
    }
    
    deinit {
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
            guard let self = self, let date = self.currentFetchDate else { return }
            Task {
                // Clear cached EventKit objects so deletions are reflected immediately.
                self.eventStore.reset()
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
        guard let notes = event.notes?.lowercased() else { return false }
        return recognizedSessionTags.contains(where: { notes.contains($0) })
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
    
    private func refreshCurrentEvents() {
        guard let date = currentFetchDate else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.fetchEvents(for: date)
        }
    }
    
    // MARK: - Event Fetching
    
    func fetchEvents(for date: Date) async {
        await MainActor.run {
            self.isLoading = true
            self.currentFetchDate = date
        }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = effectiveEndOfDay(for: date)

        let calendars = includedEventCalendars()
        if calendars.isEmpty {
            await MainActor.run {
                self.busySlots = []
                self.isLoading = false
                self.lastRefresh = Date()
            }
            return
        }
        
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: calendars)
        let events = eventStore.events(matching: predicate)
        
        // Filter out all-day events (duration >= 23 hours)
        let nearAlldayThreshold: TimeInterval = 23 * 60 * 60
        let timedEvents = events.filter { event in
            let duration = event.endDate.timeIntervalSince(event.startDate)
            return duration < nearAlldayThreshold && !event.isAllDay
        }
        
        let slots = timedEvents.map { BusyTimeSlot(from: $0) }
        
        await MainActor.run {
            self.busySlots = slots
            self.isLoading = false
            self.lastRefresh = Date()
        }
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
        let sourceStart = source.startDate!
        let sourceEnd = source.endDate!
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

        let copy = EKEvent(eventStore: eventStore)
        copy.title = source.title
        copy.startDate = newStart
        copy.endDate = newEnd
        copy.calendar = source.calendar
        copy.notes = source.notes
        copy.url = source.url

        do {
            try eventStore.save(copy, span: .thisEvent)
            return (true, copy.eventIdentifier, newStart)
        } catch {
            errorMessage = "Failed to copy event: \(error.localizedDescription)"
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

    func createSessions(_ sessions: [ScheduledSession]) -> (success: Int, failed: Int) {
        var successCount = 0
        var failCount = 0
        var savedNames: Set<String> = [] // Track unique names saved per type
        
        for session in sessions {
            if createEvent(
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
        
        return (successCount, failCount)
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
            
            let notes = (event.notes ?? "").lowercased()
            
            // Only count events that have explicit hashtags in their notes
            // Events without tags are not counted as aware sessions
            if notes.contains("#work") {
                workCount += 1
            } else if notes.contains("#side") {
                sideCount += 1
            } else if notes.contains("#deep") {
                deepCount += 1
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
            ($0.notes ?? "").lowercased().contains("#plan")
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

import SwiftUI

// MARK: - Date Selection
enum DateSelection: String, CaseIterable {
    case today = "Today"
    case tomorrow = "Tomorrow"
    case custom = "Custom"
}

// MARK: - App State
/// Shared observable state that replaces the binding cascade from ContentView.
/// All child views access this via @EnvironmentObject instead of @Binding chains.
@MainActor
class AppState: ObservableObject {
    // MARK: - Service References (wired at app startup)
    weak var schedulingEngine: SchedulingEngine?
    weak var calendarService: CalendarService?

    // MARK: - Scheduling Context
    @Published var selectedDate = Date()
    @Published var startTime = Date()
    @Published var dateSelection: DateSelection = .today
    @Published var autoPreview = true
    @Published var useNowTime = true

    // MARK: - Preset State
    @Published var presets: [Preset] = []
    @Published var selectedPreset: Preset?
    @Published var showingNewPresetSheet = false

    // MARK: - Confirmation Dialogs
    @Published var showingConfirmation = false
    @Published var showingDeleteConfirmation = false
    @Published var deletePastSessions = false

    // MARK: - Sheet Presentation
    @Published var showingWelcome = false
    @Published var showingPatternsGuide = false
    @Published var showingTasksGuide = false
    @Published var showingCalendarSetup = false

    // MARK: - Transient
    @Published var updateAlert: UpdateService.UpdateAlert?
    var nowTimer: Timer?

    // MARK: - Computed

    var effectiveStartTime: Date {
        if useNowTime && dateSelection == .today {
            return roundedNowTime()
        }
        return startTime
    }

    // MARK: - Methods

    func roundedNowTime() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let minute = components.minute ?? 0
        let roundedMinute = ((minute / 5) + 1) * 5
        let extraHour = roundedMinute >= 60 ? 1 : 0

        var newComponents = components
        newComponents.minute = roundedMinute % 60
        newComponents.hour = (components.hour ?? 0) + extraHour
        newComponents.second = 0

        return calendar.date(from: newComponents) ?? now
    }

    func updateSelectedDate(for selection: DateSelection) {
        let calendar = Calendar.current
        switch selection {
        case .today:
            selectedDate = Date()
            useNowTime = true
            startTime = roundedNowTime()
        case .tomorrow:
            selectedDate = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            useNowTime = false
            startTime = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        case .custom:
            useNowTime = false
            let hour = calendar.component(.hour, from: startTime)
            let minute = calendar.component(.minute, from: startTime)
            if let updatedStartTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: selectedDate) {
                startTime = updatedStartTime
            }
        }
    }

    func onAppearActions() {
        presets = PresetStorage.shared.loadPresets()

        if let lastId = PresetStorage.shared.loadLastActivePresetId(),
           let lastPreset = presets.first(where: { $0.id == lastId }) {
            applyPreset(lastPreset)
        } else if let first = presets.first {
            applyPreset(first)
        }

        nowTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.useNowTime && self.dateSelection == .today && self.autoPreview {
                DispatchQueue.main.async { self.updateProjectedSchedule() }
            }
        }
    }

    func applyPreset(_ preset: Preset) {
        guard let schedulingEngine, let calendarService else { return }
        selectedPreset = preset
        ensureCalendarsExist(for: preset)
        schedulingEngine.applyPreset(preset)
        PresetStorage.shared.saveLastActivePresetId(preset.id)
        if autoPreview { updateProjectedSchedule() }
    }

    func ensureCalendarsExist(for preset: Preset) {
        guard let calendarService else { return }

        let workName = preset.calendarMapping.workCalendarName
        if calendarService.getCalendar(identifier: preset.calendarMapping.workCalendarIdentifier) == nil &&
            calendarService.getCalendar(named: workName) == nil {
            calendarService.createCalendar(named: workName, color: .blue)
        }

        let sideName = preset.calendarMapping.sideCalendarName
        if calendarService.getCalendar(identifier: preset.calendarMapping.sideCalendarIdentifier) == nil &&
            calendarService.getCalendar(named: sideName) == nil {
            calendarService.createCalendar(named: sideName, color: .orange)
        }

        if preset.deepSessionConfig.enabled {
            let deepName = preset.deepSessionConfig.calendarName
            if calendarService.getCalendar(identifier: preset.deepSessionConfig.calendarIdentifier) == nil &&
                calendarService.getCalendar(named: deepName) == nil {
                calendarService.createCalendar(named: deepName, color: .purple)
            }
        }
    }

    func updateProjectedSchedule() {
        guard let schedulingEngine, let calendarService else { return }

        let planningExists = calendarService.hasPlanningSession(for: selectedDate)

        let existing = calendarService.countExistingSessions(
            for: selectedDate,
            workCalendar: CalendarDescriptor(
                name: schedulingEngine.workCalendarName,
                identifier: schedulingEngine.workCalendarIdentifier
            ),
            sideCalendar: CalendarDescriptor(
                name: schedulingEngine.sideCalendarName,
                identifier: schedulingEngine.sideCalendarIdentifier
            ),
            deepConfig: schedulingEngine.deepSessionConfig
        )

        _ = schedulingEngine.generateSchedule(
            startTime: effectiveStartTime,
            baseDate: selectedDate,
            busySlots: calendarService.busySlots,
            includePlanning: !planningExists,
            existingSessions: (work: existing.work, side: existing.side, deep: existing.deep),
            existingTitles: existing.titles
        )
    }

    func requestCalendarAccess() async {
        guard let calendarService, let schedulingEngine else { return }
        if calendarService.authorizationStatus != .fullAccess {
            let _ = await calendarService.requestAccess()
        }
        await calendarService.fetchEvents(for: selectedDate)
        schedulingEngine.reconcileCalendars(with: calendarService)
        PresetStorage.shared.populateCalendarIdentifiers(using: calendarService.availableCalendars)
        if autoPreview { updateProjectedSchedule() }
    }

    func scheduleAllSessions() {
        guard let calendarService, let schedulingEngine else { return }
        let result = calendarService.createSessions(schedulingEngine.projectedSessions)
        if result.failed == 0 {
            schedulingEngine.schedulingMessage = "Successfully scheduled \(result.success) sessions!"
        } else {
            schedulingEngine.schedulingMessage = "Scheduled \(result.success), failed \(result.failed)"
        }
        Task {
            await calendarService.fetchEvents(for: selectedDate)
            await MainActor.run { schedulingEngine.projectedSessions = [] }
        }
    }

    func deleteScheduledSessions() {
        guard let calendarService, let schedulingEngine else { return }

        var calendars: [CalendarDescriptor] = [
            CalendarDescriptor(
                name: schedulingEngine.workCalendarName,
                identifier: schedulingEngine.workCalendarIdentifier
            ),
            CalendarDescriptor(
                name: schedulingEngine.sideCalendarName,
                identifier: schedulingEngine.sideCalendarIdentifier
            )
        ]
        if schedulingEngine.deepSessionConfig.enabled {
            calendars.append(
                CalendarDescriptor(
                    name: schedulingEngine.deepSessionConfig.calendarName,
                    identifier: schedulingEngine.deepSessionConfig.calendarIdentifier
                )
            )
        }

        var uniqueCalendars: [CalendarDescriptor] = []
        for descriptor in calendars {
            if !uniqueCalendars.contains(where: { $0.identifier != nil && $0.identifier == descriptor.identifier }) &&
                !uniqueCalendars.contains(where: { $0.identifier == nil && $0.name == descriptor.name }) {
                uniqueCalendars.append(descriptor)
            }
        }

        let result: (deleted: Int, failed: Int)
        if deletePastSessions {
            result = calendarService.deleteSessionEvents(
                for: selectedDate,
                sessionNames: nil,
                fromCalendars: uniqueCalendars,
                requireSessionTag: true
            )
        } else {
            result = calendarService.deleteFutureSessionEvents(
                for: selectedDate,
                after: Date(),
                sessionNames: nil,
                fromCalendars: uniqueCalendars,
                requireSessionTag: true
            )
        }

        schedulingEngine.schedulingMessage = result.deleted > 0 ? "Deleted \(result.deleted) events" : "No events found to delete"

        Task {
            await calendarService.fetchEvents(for: selectedDate)
            await MainActor.run {
                if autoPreview { updateProjectedSchedule() }
            }
        }
    }
}

import SwiftUI
import AppKit

/// Info for the Copy-toast shown after copying an event to another day.
struct CopyToastInfo: Identifiable {
    let id = UUID()
    let title: String
    let targetLabel: String
    let targetDate: Date
    let targetStartTime: Date
    let newEventId: String
}

// MARK: - Copy Toast View

private struct CopyToastView: View {
    let toast: CopyToastInfo
    let onUndo: () -> Void
    let onJumpTo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color(hex: "10B981"))
            Text("Copied \"\(toast.title)\" to \(toast.targetLabel)")
                .font(.system(size: 13))
                .foregroundColor(.white)
            Spacer(minLength: 8)
            Button("Undo") {
                onUndo()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button("Jump to") {
                onJumpTo()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.85))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        .frame(maxWidth: 420)
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var schedulingEngine: SchedulingEngine
    @EnvironmentObject var updateService: UpdateService
    
    @State private var selectedDate = Date()
    @State private var startTime = Date()
    @State private var showingDeleteConfirmation = false
    @State private var dateSelection: DateSelection = .today
    @State private var autoPreview = true
    @State private var useNowTime = true
    @State private var deletePastSessions = false
    @State private var presets: [Preset] = []
    @State private var selectedPreset: Preset?
    @State private var showingNewPresetSheet = false
    @State private var nowTimer: Timer?
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @AppStorage("hasSeenPatternsGuide") private var hasSeenPatternsGuide = false
    @AppStorage("hasSeenTasksGuide") private var hasSeenTasksGuide = false
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false
    @State private var showingWelcome = false
    @State private var showingPatternsGuide = false
    @State private var showingTasksGuide = false
    @State private var showingCalendarSetup = false
    @State private var updateAlert: UpdateService.UpdateAlert?
    @State private var showingWhatsNew = false
    @AppStorage("SessionFlow.LastSeenVersion") private var lastSeenVersion = ""
    @State private var copyToast: CopyToastInfo? = nil

    enum DateSelection: String, CaseIterable {
        case today = "Today"
        case tomorrow = "Tomorrow"
        case custom = "Custom"
    }
    
    var body: some View {
        Group {
            if !hasSeenWelcome {
                // First: Show welcome guide
                WelcomeScreen()
                    .onDisappear {
                        // After welcome is dismissed, check permissions
                        calendarService.checkAuthorizationStatus()
                    }
            } else if calendarService.authorizationStatus != .fullAccess {
                // Second: Show permission screen if not authorized
                CalendarPermissionView()
            } else if !hasCompletedSetup {
                // Third: Show setup screen after permission is granted
                CalendarSetupView()
            } else {
                // Finally: Show main app once everything is ready
                ContentViewBody(
                    selectedDate: $selectedDate,
                    startTime: $startTime,
                    showingDeleteConfirmation: $showingDeleteConfirmation,
                    dateSelection: $dateSelection,
                    autoPreview: $autoPreview,
                    useNowTime: $useNowTime,
                    deletePastSessions: $deletePastSessions,
                    presets: $presets,
                    selectedPreset: $selectedPreset,
                    showingNewPresetSheet: $showingNewPresetSheet,
                    nowTimer: $nowTimer,
                    hasSeenWelcome: $hasSeenWelcome,
                    showingWelcome: $showingWelcome,
                    hasSeenPatternsGuide: $hasSeenPatternsGuide,
                    showingPatternsGuide: $showingPatternsGuide,
                    hasSeenTasksGuide: $hasSeenTasksGuide,
                    showingTasksGuide: $showingTasksGuide,
                    copyToast: $copyToast
                )
            }
        }
        .onAppear {
            calendarService.checkAuthorizationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Check permission status when app becomes active
            calendarService.checkAuthorizationStatus()
            
            // Check if setup was completed
            hasCompletedSetup = UserDefaults.standard.bool(forKey: "SessionFlow.HasCompletedSetup")
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SetupCompleted"))) { _ in
            // Update setup completion status
            hasCompletedSetup = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ResetCalendarSetup"))) { _ in
            // Reset setup for testing
            hasCompletedSetup = false
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PresetsUpdated"))) { _ in
            presets = PresetStorage.shared.loadPresets()
            if let current = selectedPreset,
               let refreshed = presets.first(where: { $0.id == current.id }) {
                selectedPreset = refreshed
            }
        }
        .onReceive(updateService.$pendingAlert) { alert in
            updateAlert = alert
        }
        .sheet(item: $updateAlert) { alert in
            UpdateAlertSheet(alert: alert)
                .environmentObject(updateService)
        }
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewView(changelog: ChangelogService.shared)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowWhatsNew"))) { _ in
            showingWhatsNew = true
        }
        .onAppear {
            checkForWhatsNew()
        }
    }

    private func checkForWhatsNew() {
        let currentVersion = ChangelogService.currentVersion
        guard lastSeenVersion != currentVersion else { return }
        lastSeenVersion = currentVersion
        ChangelogService.shared.fetchIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if hasCompletedSetup && hasSeenWelcome {
                showingWhatsNew = true
            }
        }
    }
}

// MARK: - Content View Body (Extracted)
struct ContentViewBody: View {
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var schedulingEngine: SchedulingEngine
    @EnvironmentObject var sessionAwarenessService: SessionAwarenessService
    @EnvironmentObject var sessionAudioService: SessionAudioService
    
    @Binding var selectedDate: Date
    @Binding var startTime: Date
    @Binding var showingDeleteConfirmation: Bool
    @Binding var dateSelection: ContentView.DateSelection
    @Binding var autoPreview: Bool
    @Binding var useNowTime: Bool
    @Binding var deletePastSessions: Bool
    @Binding var presets: [Preset]
    @Binding var selectedPreset: Preset?
    @Binding var showingNewPresetSheet: Bool
    @Binding var nowTimer: Timer?
    @Binding var hasSeenWelcome: Bool
    @Binding var showingWelcome: Bool
    @Binding var hasSeenPatternsGuide: Bool
    @Binding var showingPatternsGuide: Bool
    @Binding var hasSeenTasksGuide: Bool
    @Binding var showingTasksGuide: Bool
    @Binding var copyToast: CopyToastInfo?

    /// Last date selected while in Custom mode. Restored when switching back to Custom.
    @State private var lastCustomDate: Date?

    var body: some View {
        ZStack {
            backgroundGradient
            VStack(spacing: 0) {
                HeaderView(
                    dateSelection: $dateSelection,
                    selectedDate: $selectedDate,
                    useNowTime: $useNowTime,
                    startTime: $startTime,
                    autoPreview: $autoPreview
                )
                mainHStack
                if sessionAwarenessService.config.enabled && !sessionAwarenessService.isCollapsed {
                    SessionAwarenessPanel()
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = copyToast {
                CopyToastView(
                    toast: toast,
                    onUndo: {
                        _ = calendarService.deleteEvent(identifier: toast.newEventId)
                        Task { await calendarService.fetchEvents(for: toast.targetDate) }
                        copyToast = nil
                    },
                    onJumpTo: {
                        selectedDate = toast.targetDate
                        startTime = toast.targetStartTime
                        dateSelection = .custom
                        copyToast = nil
                    },
                    onDismiss: { copyToast = nil }
                )
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
                .task(id: toast.id) {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    await MainActor.run { copyToast = nil }
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: copyToast?.id)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingNewPresetSheet) {
            NewPresetSheet { preset in
                PresetStorage.shared.addPreset(preset)
                presets = PresetStorage.shared.loadPresets()
                applyPreset(preset)
            }
            .environmentObject(schedulingEngine)
        }
        .sheet(isPresented: $showingDeleteConfirmation) {
            DeleteConfirmationSheet(
                deletePastSessions: $deletePastSessions,
                showingSheet: $showingDeleteConfirmation,
                onDelete: deleteScheduledSessions
            )
            .environmentObject(schedulingEngine)
        }
        .sheet(isPresented: $showingWelcome) {
            WelcomeScreen()
        }
        .sheet(isPresented: $showingPatternsGuide) {
            PatternsGuide()
        }
        .sheet(isPresented: $showingTasksGuide) {
            TasksGuide()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowWelcomeScreen"))) { _ in
            showingWelcome = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowPatternsGuide"))) { _ in
            showingPatternsGuide = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowTasksGuide"))) { _ in
            showingTasksGuide = true
        }
        .task { await requestCalendarAccess() }
        .onAppear { onAppearActions() }
        .onDisappear { nowTimer?.invalidate() }
        .onChange(of: dateSelection) { _, newSelection in
            updateSelectedDate(for: newSelection)
        }
        .onChange(of: selectedDate) { _, newDate in
            schedulingEngine.sessionsFrozen = false

            // If we're on Custom and the new date is Today or Tomorrow, switch to the dedicated button
            if dateSelection == .custom {
                let calendar = Calendar.current
                if calendar.isDateInToday(newDate) {
                    dateSelection = .today
                    return
                }
                if let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()),
                   calendar.isDate(newDate, inSameDayAs: tomorrow) {
                    dateSelection = .tomorrow
                    return
                }
                // Remember this custom date for when user switches back to Custom
                lastCustomDate = newDate
            }

            Task {
                // If we are in custom mode, we might want to update startTime's day to match selectedDate
                // so that the scheduler doesn't look at a different day's 08:00
                if dateSelection == .custom {
                    let calendar = Calendar.current
                    let hour = calendar.component(.hour, from: startTime)
                    let minute = calendar.component(.minute, from: startTime)
                    if let updatedStartTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: newDate) {
                        startTime = updatedStartTime
                    }
                }

                await calendarService.fetchEvents(for: newDate)
                if autoPreview { updateProjectedSchedule() }
            }
        }
        .onChange(of: startTime) { _, _ in
            if autoPreview && !useNowTime { updateProjectedSchedule() }
        }
        .onChange(of: useNowTime) { _, isNow in
            if isNow { startTime = roundedNowTime() }
            if autoPreview { updateProjectedSchedule() }
        }
        .onChange(of: calendarService.lastRefresh) { _, _ in
            // Calendar events changed externally (from Calendar.app)
            if autoPreview { updateProjectedSchedule() }
        }
        .onChange(of: calendarService.availableCalendars) { _, _ in
            schedulingEngine.reconcileCalendars(with: calendarService)
            PresetStorage.shared.populateCalendarIdentifiers(using: calendarService.availableCalendars)
        }
        .modifier(SettingsChangeModifier(selectedDate: $selectedDate, autoPreview: autoPreview, updatePreview: updateProjectedSchedule))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            let calendar = Calendar.current
            var dateChanged = false
            
            // Check if we need to refresh the date because the day has changed
            if dateSelection == .today {
                if !calendar.isDate(selectedDate, inSameDayAs: Date()) {
                    updateSelectedDate(for: .today)
                    dateChanged = true
                }
            } else if dateSelection == .tomorrow {
                if let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()),
                   !calendar.isDate(selectedDate, inSameDayAs: tomorrow) {
                    updateSelectedDate(for: .tomorrow)
                    dateChanged = true
                }
            }
            
            // If date didn't change (or wasn't stale), perform standard active refresh
            if !dateChanged {
                if useNowTime && dateSelection == .today {
                    startTime = roundedNowTime()
                }
                
                Task {
                    await calendarService.fetchEvents(for: selectedDate)
                    if autoPreview { updateProjectedSchedule() }
                }
            }
        }
    }
    
    private func updateSelectedDate(for selection: ContentView.DateSelection) {
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
            // Restore last custom date if we have one; else preset to day after tomorrow when coming from Today/Tomorrow
            if let remembered = lastCustomDate {
                selectedDate = remembered
            } else if calendar.isDateInToday(selectedDate) || (calendar.date(byAdding: .day, value: 1, to: Date()).map { calendar.isDate(selectedDate, inSameDayAs: $0) } ?? false) {
                selectedDate = calendar.date(byAdding: .day, value: 2, to: Date()) ?? selectedDate
            }
            // Sync startTime day with selectedDate
            let hour = calendar.component(.hour, from: startTime)
            let minute = calendar.component(.minute, from: startTime)
            if let updatedStartTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: selectedDate) {
                startTime = updatedStartTime
            }
        }
    }
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(hex: "0F172A"), Color(hex: "1E293B")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    private var mainHStack: some View {
        HStack(spacing: 0) {
            LeftPanel(
                presets: $presets,
                selectedPreset: $selectedPreset,
                showingNewPresetSheet: $showingNewPresetSheet,
                autoPreview: autoPreview,
                updatePreview: updateProjectedSchedule,
                applyPreset: applyPreset,
                hasSeenPatternsGuide: $hasSeenPatternsGuide,
                showingPatternsGuide: $showingPatternsGuide,
                hasSeenTasksGuide: $hasSeenTasksGuide,
                showingTasksGuide: $showingTasksGuide
            )
            
            Divider().background(Color.white.opacity(0.1))
            
            TimelineView(
                selectedDate: selectedDate,
                startTime: effectiveStartTime,
                onCopySuccess: { info in copyToast = info }
            )
            .padding()
            
            Divider().background(Color.white.opacity(0.1))
            
            RightPanel(
                selectedDate: selectedDate,
                effectiveStartTime: effectiveStartTime,
                autoPreview: autoPreview,
                scheduleAll: scheduleAllSessions,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                deletePastSessions: $deletePastSessions,
                updatePreview: updateProjectedSchedule
            )
        }
    }
    
    var effectiveStartTime: Date {
        if useNowTime && dateSelection == .today {
            return roundedNowTime()
        }
        return startTime
    }
    
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
    
    private func onAppearActions() {
        presets = PresetStorage.shared.loadPresets()
        
        // Restore last active preset
        if let lastId = PresetStorage.shared.loadLastActivePresetId(),
           let lastPreset = presets.first(where: { $0.id == lastId }) {
            applyPreset(lastPreset)
        } else if let first = presets.first {
            applyPreset(first)
        }
        
        calendarService.scheduleEndHour = schedulingEngine.scheduleEndHour

        nowTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            if useNowTime && dateSelection == .today && autoPreview {
                DispatchQueue.main.async { updateProjectedSchedule() }
            }
        }
    }
    
    private func applyPreset(_ preset: Preset) {
        selectedPreset = preset
        
        // Ensure calendars exist
        ensureCalendarsExist(for: preset)
        
        schedulingEngine.applyPreset(preset)
        PresetStorage.shared.saveLastActivePresetId(preset.id)
        if autoPreview { updateProjectedSchedule() }
    }
    
    private func ensureCalendarsExist(for preset: Preset) {
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
    
    private func requestCalendarAccess() async {
        if calendarService.authorizationStatus != .fullAccess {
            let _ = await calendarService.requestAccess()
        }
        await calendarService.fetchEvents(for: selectedDate)
        schedulingEngine.reconcileCalendars(with: calendarService)
        PresetStorage.shared.populateCalendarIdentifiers(using: calendarService.availableCalendars)
        if autoPreview { updateProjectedSchedule() }
    }
    
    private func scheduleAllSessions() {
        let sessionsToSchedule = schedulingEngine.projectedSessions.filter { $0.type != .bigRest }
        let result = calendarService.createSessions(sessionsToSchedule)
        if result.failed == 0 {
            schedulingEngine.schedulingMessage = "Successfully scheduled \(result.success) sessions!"
        } else {
            schedulingEngine.schedulingMessage = "Scheduled \(result.success), failed \(result.failed)"
        }
        schedulingEngine.sessionsFrozen = false
        Task {
            await calendarService.fetchEvents(for: selectedDate)
            schedulingEngine.projectedSessions = []
        }
    }
    
    private func deleteScheduledSessions() {
        // Collect all calendars to clear
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
        
        // Remove duplicates if any calendars share the same identity
        var uniqueCalendars: [CalendarDescriptor] = []
        for descriptor in calendars {
            if !uniqueCalendars.contains(where: { $0.identifier != nil && $0.identifier == descriptor.identifier }) &&
                !uniqueCalendars.contains(where: { $0.identifier == nil && $0.name == descriptor.name }) {
                uniqueCalendars.append(descriptor)
            }
        }
        
        // Passing nil for sessionNames means "delete all events on these calendars"
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
            if autoPreview { updateProjectedSchedule() }
        }
    }
}


// MARK: - Settings Change Modifier
struct SettingsChangeModifier: ViewModifier {
    @EnvironmentObject var engine: SchedulingEngine
    @EnvironmentObject var calendarService: CalendarService
    @Binding var selectedDate: Date
    let autoPreview: Bool
    let updatePreview: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onChange(of: engine.workSessions) { _, _ in trigger() }
            .onChange(of: engine.sideSessions) { _, _ in trigger() }
            .onChange(of: engine.workSessionDuration) { _, _ in trigger() }
            .onChange(of: engine.sideSessionDuration) { _, _ in trigger() }
            .onChange(of: engine.restDuration) { _, _ in trigger() }
            .onChange(of: engine.pattern) { _, _ in trigger() }
            .onChange(of: engine.schedulePlanning) { _, _ in trigger() }
            .onChange(of: engine.planningDuration) { _, _ in trigger() }
            .onChange(of: engine.workSessionName) { _, _ in trigger() }
            .onChange(of: engine.sideSessionName) { _, _ in trigger() }
            .onChange(of: engine.workCalendarName) { _, _ in trigger() }
            .onChange(of: engine.sideCalendarName) { _, _ in trigger() }
            .background(extraObservers1)
            .background(extraObservers2)
    }
    
    private var extraObservers1: some View {
        Color.clear
            .onChange(of: engine.workSessionsPerCycle) { _, _ in trigger() }
            .onChange(of: engine.sideSessionsPerCycle) { _, _ in trigger() }
            .onChange(of: engine.sideFirst) { _, _ in trigger() }
            .onChange(of: engine.flexibleSideScheduling) { _, _ in trigger() }
            .onChange(of: engine.awareExistingTasks) { _, _ in trigger() }
            .onChange(of: engine.sideRestDuration) { _, _ in trigger() }
            .onChange(of: engine.deepRestDuration) { _, _ in trigger() }
            .onChange(of: engine.deepSessionConfig.enabled) { _, _ in trigger() }
            .onChange(of: engine.deepSessionConfig.sessionCount) { _, _ in trigger() }
            .onChange(of: engine.deepSessionConfig.injectAfterEvery) { _, _ in trigger() }
            .onChange(of: engine.deepSessionConfig.name) { _, _ in trigger() }
    }
    
    private var extraObservers2: some View {
        Color.clear
            .onChange(of: engine.deepSessionConfig.duration) { _, _ in trigger() }
            .onChange(of: engine.deepSessionConfig.calendarName) { _, _ in trigger() }
            .onChange(of: engine.deepSessionConfig.andThenGap) { _, _ in trigger() }
            .onChange(of: engine.workTasks) { _, _ in trigger() }
            .onChange(of: engine.sideTasks) { _, _ in trigger() }
            .onChange(of: engine.deepTasks) { _, _ in trigger() }
            .onChange(of: engine.useWorkTasks) { _, _ in trigger() }
            .onChange(of: engine.useSideTasks) { _, _ in trigger() }
            .onChange(of: engine.useDeepTasks) { _, _ in trigger() }
            .onChange(of: engine.bigRestConfig.enabled) { _, _ in trigger() }
            .onChange(of: engine.bigRestConfig.count) { _, _ in trigger() }
            .onChange(of: engine.bigRestConfig.duration) { _, _ in trigger() }
            .onChange(of: engine.bigRestConfig.afterMinutes) { _, _ in trigger() }
            .onChange(of: engine.scheduleEndHour) { _, newValue in
                calendarService.scheduleEndHour = newValue
                trigger()
                Task { await calendarService.fetchEvents(for: selectedDate) }
            }
    }

    private func trigger() {
        if autoPreview { updatePreview() }
    }
}

// MARK: - Header View
struct HeaderView: View {
    @EnvironmentObject var updateService: UpdateService
    @Binding var dateSelection: ContentView.DateSelection
    @Binding var selectedDate: Date
    @Binding var useNowTime: Bool
    @Binding var startTime: Date
    @Binding var autoPreview: Bool
    
    var body: some View {
        HStack {
            appTitle
            Spacer()
            dateButtons
            Spacer()
            startTimeControls
            Spacer()
            // Settings Link
            SettingsLink {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .help("App Settings")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(WindowDragView())
        .background(Color.black.opacity(0.2))
    }
    
    private var appTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("SessionFlow")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
            }
            Text("Plan your productive day")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
            if let status = updateService.installationStatus {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7, anchor: .center)
                        .progressViewStyle(.circular)
                    Text(status.message)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
    }
    
    private var dateButtons: some View {
        HStack(spacing: 12) {
            Button {
                showPastDaysMenu()
            } label: {
                Text("⋮")
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()

            ForEach(ContentView.DateSelection.allCases, id: \.self) { sel in
                Button { dateSelection = sel } label: {
                    Text(sel.rawValue)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(dateSelection == sel ? Color(hex: "8B5CF6") : Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }
            if dateSelection == .custom {
                DateInputField(date: $selectedDate)
            }
        }
    }

    private func pastDayLabel(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        let dateStr = formatter.string(from: date)
        switch daysAgo {
        case 1: return "Yesterday (\(dateStr))"
        default: return "\(daysAgo) days ago (\(dateStr))"
        }
    }
    
    private func showPastDaysMenu() {
        let menu = NSMenu()
        for daysAgo in 1..<8 {
            let item = NSMenuItem(title: pastDayLabel(daysAgo: daysAgo), action: #selector(NSApplication.sendAction(_:to:from:)), keyEquivalent: "")
            item.target = nil
            item.representedObject = daysAgo
            menu.addItem(item)
        }

        // Use a responder-based approach: create action items via a helper
        menu.removeAllItems()
        for daysAgo in 1..<8 {
            let item = PastDayMenuItem(title: pastDayLabel(daysAgo: daysAgo), daysAgo: daysAgo) { [self] days in
                let date = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
                selectedDate = date
                dateSelection = .custom
                useNowTime = false
                startTime = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: date) ?? date
            }
            menu.addItem(item)
        }

        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: event.window?.contentView ?? NSView())
        }
    }

    private var startTimeControls: some View {
        HStack(spacing: 8) {
            Text("Start:").foregroundColor(.white.opacity(0.7))
            Picker("", selection: $useNowTime) {
                Text("Now").tag(true)
                Text("Set").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
            
            ZStack {
                if !useNowTime {
                    TimeInputField(date: $startTime)
                } else {
                    Button(action: {
                        useNowTime = false
                    }) {
                        Text(formatNowTime())
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(hex: "3B82F6"))
                            .padding(.horizontal, 8)
                            .frame(width: 80, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .help("Click to set a custom start time")
                }
            }
            .frame(width: 100)
        }
    }
    
    private func formatNowTime() -> String {
        let calendar = Calendar.current
        let now = Date()
        let comp = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let minute = comp.minute ?? 0
        let rounded = ((minute / 5) + 1) * 5
        var newComp = comp
        newComp.minute = rounded % 60
        newComp.hour = (comp.hour ?? 0) + (rounded >= 60 ? 1 : 0)
        let date = calendar.date(from: newComp) ?? now
        
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
}

// MARK: - Left Panel
struct LeftPanel: View {
    @EnvironmentObject var schedulingEngine: SchedulingEngine
    @Binding var presets: [Preset]
    @Binding var selectedPreset: Preset?
    @Binding var showingNewPresetSheet: Bool
    let autoPreview: Bool
    let updatePreview: () -> Void
    let applyPreset: (Preset) -> Void

    @Binding var hasSeenPatternsGuide: Bool
    @Binding var showingPatternsGuide: Bool
    @Binding var hasSeenTasksGuide: Bool
    @Binding var showingTasksGuide: Bool

    @State private var selectedTab: TabArea = .settings
    @State private var isConfirmingReset: Bool = false

    enum TabArea: String, CaseIterable {
        case settings = "Time Settings"
        case tasks = "Tasks"
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                tabPicker

                if selectedTab == .settings {
                    VStack(spacing: 0) {
                        presetDropdown
                        Divider().background(Color.white.opacity(0.1))
                        SettingsPanel(
                            hasSeenPatternsGuide: $hasSeenPatternsGuide,
                            showingPatternsGuide: $showingPatternsGuide,
                            isLocked: schedulingEngine.sessionsFrozen
                        )
                    }
                } else {
                    TasksPanel(isLocked: schedulingEngine.sessionsFrozen)
                }
            }

            if schedulingEngine.sessionsFrozen {
                // Overlay with same effect as card – allows scroll through
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.75))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)

                // Centered card content
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.8))
                    Text("Manual alignment active")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Text("Settings are locked while you adjust projected sessions")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button {
                        handleResetTap()
                    } label: {
                        Text(isConfirmingReset ? "Click again to confirm" : "Reset")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(isConfirmingReset ? Color(hex: "EF4444") : Color(hex: "8B5CF6"))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .help(isConfirmingReset ? "Click again to confirm" : "Reset manual alignment")
                    .animation(.easeInOut(duration: 0.15), value: isConfirmingReset)
                }
                .padding(20)
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .tasks && !hasSeenTasksGuide {
                showingTasksGuide = true
                hasSeenTasksGuide = true
            }
        }
        .frame(width: 320)
        .padding()
        .onChange(of: schedulingEngine.sessionsFrozen) { _, frozen in
            if !frozen { isConfirmingReset = false }
        }
    }

    private func handleResetTap() {
        if isConfirmingReset {
            schedulingEngine.sessionsFrozen = false
            updatePreview()
            withAnimation(.easeInOut(duration: 0.15)) {
                isConfirmingReset = false
            }
        } else {
            withAnimation(.easeInOut(duration: 0.15)) {
                isConfirmingReset = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if isConfirmingReset {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isConfirmingReset = false
                    }
                }
            }
        }
    }
    
    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(TabArea.allCases, id: \.self) { tab in
                Button { selectedTab = tab } label: {
                    VStack(spacing: 8) {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: selectedTab == tab ? .bold : .medium))
                            .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.5))
                        
                        Rectangle()
                            .fill(selectedTab == tab ? Color(hex: "8B5CF6") : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 16)
    }
    
    private var presetDropdown: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bookmark.fill").foregroundColor(Color(hex: "8B5CF6"))
                Text("Preset").font(.headline).foregroundColor(.white)
            }
            Spacer()
            presetMenu
                .frame(width: 170)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
    }
    
    private var presetMenu: some View {
        Menu {
            ForEach(presets) { preset in
                Button { applyPreset(preset) } label: { Label(preset.name, systemImage: preset.icon) }
            }
            Divider()
            Button { showingNewPresetSheet = true } label: { Label("Save Current as New Preset...", systemImage: "plus") }
            if let p = selectedPreset {
                Button { updateCurrentPreset(p) } label: { Label("Update Current Preset", systemImage: "arrow.triangle.2.circlepath") }
                Button(role: .destructive) { deletePreset(p) } label: { Label("Delete Preset", systemImage: "trash") }
            }
        } label: {
            HStack(spacing: 6) {
                if let p = selectedPreset {
                    Image(systemName: p.icon).foregroundColor(Color(hex: "8B5CF6"))
                    let modified = schedulingEngine.isPresetModified(p)
                    Text(p.name + (modified ? " ＊" : "")).foregroundColor(.white)
                } else {
                    Image(systemName: "doc").foregroundColor(.white.opacity(0.5))
                    Text("No Preset Selected").foregroundColor(.white.opacity(0.5))
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .trailing)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(height: 24)
    }
    
    private func updateCurrentPreset(_ preset: Preset) {
        let updated = Preset(id: preset.id, name: preset.name, icon: preset.icon,
            workSessionCount: schedulingEngine.workSessions, sideSessionCount: schedulingEngine.sideSessions,
            workSessionName: schedulingEngine.workSessionName, sideSessionName: schedulingEngine.sideSessionName,
            workSessionDuration: schedulingEngine.workSessionDuration, sideSessionDuration: schedulingEngine.sideSessionDuration,
            planningDuration: schedulingEngine.planningDuration, restDuration: schedulingEngine.restDuration,
            sideRestDuration: schedulingEngine.sideRestDuration,
            deepRestDuration: schedulingEngine.deepRestDuration,
            schedulePlanning: schedulingEngine.schedulePlanning, pattern: schedulingEngine.pattern,
            workSessionsPerCycle: schedulingEngine.workSessionsPerCycle,
            sideSessionsPerCycle: schedulingEngine.sideSessionsPerCycle,
            sideFirst: schedulingEngine.sideFirst,
            deepSessionConfig: schedulingEngine.deepSessionConfig,
            calendarMapping: CalendarMapping(
                workCalendarName: schedulingEngine.workCalendarName,
                sideCalendarName: schedulingEngine.sideCalendarName,
                workCalendarIdentifier: schedulingEngine.workCalendarIdentifier,
                sideCalendarIdentifier: schedulingEngine.sideCalendarIdentifier
            ))
        PresetStorage.shared.updatePreset(updated)
        presets = PresetStorage.shared.loadPresets()
        selectedPreset = updated
    }
    
    private func deletePreset(_ preset: Preset) {
        PresetStorage.shared.deletePreset(preset)
        presets = PresetStorage.shared.loadPresets()
        selectedPreset = presets.first
        if let first = selectedPreset {
            applyPreset(first)
        }
    }
}

// MARK: - Right Panel
struct RightPanel: View {
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var schedulingEngine: SchedulingEngine
    let selectedDate: Date
    let effectiveStartTime: Date
    let autoPreview: Bool
    let scheduleAll: () -> Void
    @Binding var showingDeleteConfirmation: Bool
    @Binding var deletePastSessions: Bool
    let updatePreview: () -> Void
    
    @State private var showingAvailabilityHelp = false
    @State private var showingProjectionHelp = false
    @State private var didYouKnowIndex = 0
    
    private let availabilityHelpBase = "Shows calculated free time gaps in your calendar. 'Possible' counts indicate how many sessions of each type could fit into these gaps based on your duration settings."
    private let projectionHelp = "A live preview of how many sessions will be placed in your calendar and when you might be done for the day."
    private let didYouKnowFacts: [DidYouKnowFact] = [
        DidYouKnowFact(
            title: "Edit existing events",
            message: "Click Title, Notes, or URL in the preview to edit the calendar event instantly."
        ),
        DidYouKnowFact(
            title: "Toggle night time",
            message: "Use the moon button or Settings to hide or show night hours on the timeline."
        ),
        DidYouKnowFact(
            title: "Local only changes",
            message: "Scheduling runs on your Mac and calendar updates happen only after you confirm Schedule or Delete."
        ),
        DidYouKnowFact(
            title: "Live preview",
            message: "Adjust durations or presets and watch projected sessions reshuffle immediately before committing."
        ),
        DidYouKnowFact(
            title: "Preset shortcuts",
            message: "Save Workday, Focus, Weekend, or any custom preset once and keep it one click away."
        ),
        DidYouKnowFact(
            title: "Session Awareness",
            message: "Get a live panel with timer, progress bar, and ambient audio to keep you in the zone."
        ),
        DidYouKnowFact(
            title: "Ambient sounds",
            message: "Each session type can have its own ambient sound, speed, and accelerando — configure them in Settings → Awareness."
        ),
        DidYouKnowFact(
            title: "Mini player mode",
            message: "Click the collapse button on the awareness panel to switch to a compact mini player that floats on your desktop."
        ),
        DidYouKnowFact(
            title: "Presence reminder",
            message: "Enable a periodic sound reminder in Settings → Awareness to stay focused during long sessions."
        ),
        DidYouKnowFact(
            title: "Manual layout mode",
            message: "Freeze projected sessions to freely drag and resize them by hand — overlapping sessions push out of the way automatically."
        ),
        DidYouKnowFact(
            title: "Drag to reschedule",
            message: "Drag any calendar event on the timeline to move it — projected sessions shift in real time to fill the gaps."
        ),
        DidYouKnowFact(
            title: "Undo & redo",
            message: "Moved an event to the wrong spot? Use ⌘Z to undo and ⇧⌘Z to redo any drag or resize on the timeline."
        ),
        DidYouKnowFact(
            title: "Resize events",
            message: "Drag the bottom edge of a calendar event to resize it. Hold ⌥ Option to snap to 5-minute increments."
        )
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            ScrollView(showsIndicators: false) {
            availabilityCard
            sessionsSummaryCard
            if schedulingEngine.showDidYouKnowCard, let fact = currentDidYouKnowFact {
                DidYouKnowCard(
                    fact: fact,
                    factIndex: didYouKnowIndex,
                    totalFacts: didYouKnowFacts.count,
                    onNext: nextDidYouKnowFact,
                    onPrevious: previousDidYouKnowFact,
                    onClose: { schedulingEngine.showDidYouKnowCard = false }
                )
                .frame(maxWidth: .infinity)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            }
            Spacer()
            actionButtons
        }
        .frame(width: 280)
        .padding()
    }
    
    private var availabilityCard: some View {
        let avail = schedulingEngine.calculateAvailability(startTime: effectiveStartTime, baseDate: selectedDate, busySlots: calendarService.busySlots)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.fill").foregroundColor(Color(hex: "3B82F6"))
                Text("Availability").font(.headline).foregroundColor(.white)
                
                Spacer()
                
                Button {
                    showingAvailabilityHelp.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingAvailabilityHelp) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(availabilityHelpBase)
                        if schedulingEngine.scheduleEndHour > 24 {
                            Text("Includes +1d hours until \(formattedHourForCard(schedulingEngine.scheduleEndHour))")
                                .font(.system(size: 12))
                                .foregroundColor(.orange.opacity(0.9))
                                .italic()
                        }
                    }
                    .font(.system(size: 13))
                    .padding()
                    .frame(width: 250)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                row("Available Time:", "\(avail.availableMinutes / 60)h \(avail.availableMinutes % 60)m")
                row("Possible Work:", "\(avail.possibleWorkSessions) sessions", Color(hex: "8B5CF6"))
                row("Possible Side:", "\(avail.possibleSideSessions) sessions", Color(hex: "3B82F6"))
                if schedulingEngine.deepSessionConfig.enabled {
                    row("Possible Deep:", "\(avail.possibleDeepSessions) sessions", Color(hex: "10B981"))
                }
            }
            .font(.system(size: 13)).foregroundColor(.white.opacity(0.8))
        }
        .padding().background(Color.white.opacity(0.05)).cornerRadius(12)
    }
    
    private func row(_ label: String, _ val: String, _ color: Color? = nil) -> some View {
        HStack { Text(label); Spacer(); Text(val).fontWeight(.semibold).foregroundColor(color ?? .white.opacity(0.8)) }
    }

    private func formattedHourForCard(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        var comps = DateComponents()
        comps.hour = hour % 24
        if let date = Calendar.current.date(from: comps) { return formatter.string(from: date) }
        return "\(hour % 24):00"
    }

    private var currentDidYouKnowFact: DidYouKnowFact? {
        guard !didYouKnowFacts.isEmpty else { return nil }
        let safeIndex = max(0, min(didYouKnowIndex, didYouKnowFacts.count - 1))
        return didYouKnowFacts[safeIndex]
    }
    
    private func nextDidYouKnowFact() {
        guard !didYouKnowFacts.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            didYouKnowIndex = (didYouKnowIndex + 1) % didYouKnowFacts.count
        }
    }
    
    private func previousDidYouKnowFact() {
        guard !didYouKnowFacts.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            didYouKnowIndex = (didYouKnowIndex - 1 + didYouKnowFacts.count) % didYouKnowFacts.count
        }
    }
    
    private var sessionsSummaryCard: some View {
        let sessions = schedulingEngine.projectedSessions
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet.clipboard.fill").foregroundColor(Color(hex: "8B5CF6"))
                Text("Projected Sessions").font(.headline).foregroundColor(.white)
                
                Spacer()
                
                Button {
                    showingProjectionHelp.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingProjectionHelp) {
                    Text(projectionHelp)
                        .font(.system(size: 13))
                        .padding()
                        .frame(width: 250)
                }
            }
            if sessions.isEmpty {
                if schedulingEngine.hasNoSessionTargets {
                    Text("No sessions configured")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.vertical, 8)
                } else if schedulingEngine.quotasSatisfied {
                    Text("Daily quotas satisfied")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "10B981"))
                        .padding(.vertical, 8)
                } else if !schedulingEngine.schedulingMessage.isEmpty {
                    Text("No additional sessions projected")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.vertical, 8)
                } else {
                    Text("Scheduling preview will appear here")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.vertical, 8)
                }
            } else {
                sessionStats(sessions)
            }
            if !schedulingEngine.schedulingMessage.isEmpty {
                Text(schedulingEngine.schedulingMessage).font(.system(size: 11)).foregroundColor(.yellow.opacity(0.8))
            }
            
            if schedulingEngine.awareExistingTasks {
                HStack(spacing: 4) {
                    Image(systemName: "brain.head.profile").font(.system(size: 10))
                    Text("Accounting for existing sessions from calendar").font(.system(size: 10)).italic()
                }
                .foregroundColor(.white.opacity(0.4))
                .padding(.top, -4)
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundColor(Color.white.opacity(0.15))
        )
    }
    
    private func sessionStats(_ sessions: [ScheduledSession]) -> some View {
        let wc = sessions.filter { $0.type == .work }.count
        let sc = sessions.filter { $0.type == .side }.count
        let pc = sessions.filter { $0.type == .planning }.count
        let dc = sessions.filter { $0.type == .deep }.count
        let lrc = sessions.filter { $0.type == .bigRest }.count
        let sessionCount = sessions.filter { $0.type != .bigRest }.count
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return VStack(alignment: .leading, spacing: 6) {
            if pc > 0 { countRow(.planning, pc) }
            countRow(.work, wc)
            countRow(.side, sc)
            if dc > 0 { countRow(.deep, dc) }
            Divider().background(Color.white.opacity(0.2))
            HStack { Text("Total:").fontWeight(.medium); Spacer(); Text("\(sessionCount) sessions").fontWeight(.semibold) }
            if lrc > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "pause.circle.fill").font(.system(size: 9)).foregroundColor(SessionType.bigRest.color.opacity(0.6))
                    Text("\(lrc) long \(lrc == 1 ? "rest" : "rests") between sessions")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            if let last = sessions.last {
                let isNextDay = !Calendar.current.isDate(last.endTime, inSameDayAs: selectedDate)
                HStack {
                    Text("Done by:").foregroundColor(Color(hex: "10B981"))
                    Spacer()
                    HStack(spacing: 4) {
                        if isNextDay {
                            Text("+1d")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                        }
                        Text(formatter.string(from: last.endTime)).fontWeight(.semibold).foregroundColor(Color(hex: "10B981"))
                    }
                }
            }
        }
        .font(.system(size: 13)).foregroundColor(.white.opacity(0.8))
    }
    
    private func isCalendarHidden(for type: SessionType) -> Bool {
        let identifier: String?
        let name: String
        switch type {
        case .work, .planning:
            identifier = schedulingEngine.workCalendarIdentifier
            name = schedulingEngine.workCalendarName
        case .side:
            identifier = schedulingEngine.sideCalendarIdentifier
            name = schedulingEngine.sideCalendarName
        case .deep:
            identifier = schedulingEngine.deepSessionConfig.calendarIdentifier
            name = schedulingEngine.deepSessionConfig.calendarName
        default:
            return false
        }
        if let id = identifier {
            return calendarService.isCalendarExcluded(identifier: id)
        }
        if let cal = calendarService.availableCalendars.first(where: { $0.title == name }) {
            return calendarService.isCalendarExcluded(identifier: cal.calendarIdentifier)
        }
        return false
    }

    private func countRow(_ type: SessionType, _ count: Int) -> some View {
        let hidden = isCalendarHidden(for: type)
        return HStack {
            if hidden {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .help("Calendar for \(type.rawValue) sessions is hidden from the timeline")
            }
            Circle().fill(type.color).frame(width: 8, height: 8)
            Text("\(type.rawValue):")
            Spacer()
            Text("\(count)").fontWeight(.medium)
        }
    }
    
    private var actionButtons: some View {
        let purple = Color(hex: "8B5CF6")
        let disabled = schedulingEngine.projectedSessions.isEmpty

        return VStack(spacing: 12) {
            // Split button: Schedule Sessions (main) + dropdown arrow (planning)
            HStack(spacing: 0) {
                Button(action: { scheduleAll() }) {
                    HStack { Image(systemName: "calendar.badge.plus"); Text("Schedule Sessions") }
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .help("Add all projected sessions to your Calendar")

                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 1)
                    .padding(.vertical, 6)

                Menu {
                    Button {
                        createPlanningSession()
                    } label: {
                        Label("Create Just Planning", systemImage: "calendar.badge.clock")
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .frame(maxWidth: 36, maxHeight: .infinity)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize(horizontal: true, vertical: false)
                .help("More scheduling options")
            }
            .frame(height: 44)
            .background(disabled ? Color.gray.opacity(0.3) : purple)
            .foregroundColor(.white)
            .cornerRadius(10)

            Button(action: { deletePastSessions = false; showingDeleteConfirmation = true }) {
                HStack { Image(systemName: "trash"); Text("Delete Day's Sessions") }
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.red.opacity(0.2)).foregroundColor(.red).cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.red.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Remove scheduled sessions for the selected day")
        }
    }
    
    private func createPlanningSession() {
        // Project a single planning session
        if let session = schedulingEngine.projectSingleSession(
            type: .planning,
            startTime: effectiveStartTime,
            baseDate: selectedDate,
            busySlots: calendarService.busySlots
        ) {
            let result = calendarService.createSessions([session])
            if result.failed == 0 {
                schedulingEngine.schedulingMessage = "Scheduled Planning session!"
                // Refresh calendar
                Task {
                    await calendarService.fetchEvents(for: selectedDate)
                    if autoPreview { updatePreview() }
                }
            } else {
                schedulingEngine.schedulingMessage = "Failed to create planning session."
            }
        } else {
            schedulingEngine.schedulingMessage = "Could not find a slot for Planning session."
        }
    }
}

private struct DidYouKnowFact: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

private struct DidYouKnowCard: View {
    let fact: DidYouKnowFact
    let factIndex: Int
    let totalFacts: Int
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void
    
    @State private var rotationTimer: Timer?
    private let rotationInterval: TimeInterval = 12
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 10, height: 10)
                            .foregroundColor(.yellow.opacity(0.7))
                        Text("Did you know?")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    Text(fact.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
                Spacer()
                controlButtons
            }
            Text(fact.message)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 8)
            
            if totalFacts > 1 {
                HStack(spacing: 4) {
                    ForEach(0..<totalFacts, id: \.self) { idx in
                        Capsule()
                            .fill(idx == factIndex ? Color.white.opacity(0.9) : Color.white.opacity(0.25))
                            .frame(width: idx == factIndex ? 16 : 8, height: 3)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onAppear(perform: restartTimer)
        .onDisappear(perform: stopTimer)
        .onChange(of: fact.id) { _, _ in restartTimer() }
        .onChange(of: totalFacts) { _, _ in restartTimer() }
    }
    
    private var controlButtons: some View {
        HStack(spacing: 6) {
            controlButton(icon: "chevron.right", disabled: totalFacts < 2, action: onNext)
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1, height: 14)
                .padding(.horizontal, 2)
            controlButton(icon: "xmark", action: onClose)
        }
    }
    
    private func controlButton(icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(disabled ? 0.25 : 0.8))
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(disabled ? 0.05 : 0.12))
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
    
    private func restartTimer() {
        stopTimer()
        startTimer()
    }
    
    private func startTimer() {
        guard rotationTimer == nil && totalFacts > 1 else { return }
        rotationTimer = Timer.scheduledTimer(withTimeInterval: rotationInterval, repeats: true) { _ in
            onNext()
        }
    }
    
    private func stopTimer() {
        rotationTimer?.invalidate()
        rotationTimer = nil
    }
}

// MARK: - Delete Confirmation Sheet
struct DeleteConfirmationSheet: View {
    @EnvironmentObject var schedulingEngine: SchedulingEngine
    @Binding var deletePastSessions: Bool
    @Binding var showingSheet: Bool
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)
            
            Text("Delete Schedule?")
                .font(.title2)
                .bold()
            
            VStack(spacing: 8) {
                Text("This will delete added events from the following calendars for the selected day:")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                
                // List calendars
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle().fill(Color(hex: "8B5CF6")).frame(width: 6, height: 6)
                        Text(schedulingEngine.workCalendarName)
                    }
                    HStack {
                        Circle().fill(Color(hex: "3B82F6")).frame(width: 6, height: 6)
                        Text(schedulingEngine.sideCalendarName)
                    }
                    if schedulingEngine.deepSessionConfig.enabled {
                        HStack {
                            Circle().fill(Color(hex: "10B981")).frame(width: 6, height: 6)
                            Text(schedulingEngine.deepSessionConfig.calendarName)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
                
                Text("This action cannot be undone.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Toggle(isOn: $deletePastSessions) {
                Text("Delete lapsed (past) events too")
                    .font(.system(size: 13))
            }
            .toggleStyle(.checkbox)
            
            HStack(spacing: 16) {
                Button("Cancel") { showingSheet = false }
                    .keyboardShortcut(.cancelAction)
                
                Button("Delete Events") { onDelete(); showingSheet = false }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

#Preview {
    ContentView()
        .environmentObject(CalendarService())
        .environmentObject(SchedulingEngine())
        .frame(width: 1200, height: 800)
}

// MARK: - Past Day Menu Item Helper

private class PastDayMenuItem: NSMenuItem {
    private let handler: (Int) -> Void
    private let daysAgo: Int

    init(title: String, daysAgo: Int, handler: @escaping (Int) -> Void) {
        self.handler = handler
        self.daysAgo = daysAgo
        super.init(title: title, action: #selector(didSelect), keyEquivalent: "")
        self.target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func didSelect() {
        handler(daysAgo)
    }
}

// MARK: - Window Drag & Zoom Helpers

struct WindowDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TitleBarDraggableView()
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class TitleBarDraggableView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            if let window = window, let screen = window.screen {
                let currentFrame = window.frame
                let maxFrame = screen.visibleFrame
                
                // Check if we are currently maximized (with a small tolerance)
                let isMaximized = abs(currentFrame.width - maxFrame.width) < 5 &&
                                  abs(currentFrame.height - maxFrame.height) < 5
                
                if isMaximized {
                    // Restore is handled by zoom if we were zoomed, but since we are manually setting frame,
                    // zoom behavior might vary. Surprisingly, user usually wants standard zoom behavior 
                    // which toggles user/standard states. 
                    // Let's try calling zoom which often knows how to go back to "User" size.
                    window.zoom(nil)
                } else {
                    // Force maximize
                    window.setFrame(maxFrame, display: true, animate: true)
                }
            }
        } else {
            super.mouseDown(with: event)
        }
    }
}

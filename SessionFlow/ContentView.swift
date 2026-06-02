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
    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

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
    @State private var showingSessionAwarenessGuide = false
    @State private var showingShortcutsGuide = false
    @State private var showingCalendarSetup = false
    @State private var updateAlert: UpdateService.UpdateAlert?
    @State private var showingWhatsNew = false
    @AppStorage("SessionFlow.LastSeenVersion") private var legacyLastSeenVersion = ""
    @AppStorage("SessionFlow.LastSeenChangelogVersion") private var lastSeenChangelogVersion = ""
    @State private var pendingWhatsNewVersion: String?
    @State private var copyToast: CopyToastInfo? = nil
    @State private var modeToast: String? = nil

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
                    copyToast: $copyToast,
                    modeToast: $modeToast
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
        .onReceive(updateService.$latestReleaseStatus) { status in
            handleLatestReleaseStatus(status)
        }
        .sheet(item: $updateAlert) { alert in
            UpdateAlertSheet(alert: alert)
                .environmentObject(updateService)
        }
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewView(changelog: ChangelogService.shared)
        }
        .sheet(isPresented: $showingSessionAwarenessGuide) {
            SessionAwarenessGuide()
        }
        .sheet(isPresented: $showingShortcutsGuide) {
            ShortcutsGuide()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowWhatsNew"))) { _ in
            showingWhatsNew = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowSessionAwarenessGuide"))) { _ in
            showingSessionAwarenessGuide = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowShortcutsGuide"))) { _ in
            showingShortcutsGuide = true
        }
        .onAppear {
            checkForWhatsNew()
        }
        .focusEffectDisabled()
    }

    private func checkForWhatsNew() {
        let currentVersion = ChangelogService.currentVersion
        migrateLastSeenChangelogVersionIfNeeded(currentVersion: currentVersion)

        guard let unseenVersion = ChangelogService.shared.newestUnseenVersion(
            currentVersion: currentVersion,
            lastSeenVersion: lastSeenChangelogVersion
        ) else {
            pendingWhatsNewVersion = nil
            return
        }

        pendingWhatsNewVersion = unseenVersion
        if updateService.latestReleaseStatus == .current {
            showWhatsNewIfEligible(for: unseenVersion)
        }
    }

    private func handleLatestReleaseStatus(_ status: UpdateService.LatestReleaseStatus) {
        guard let pendingVersion = pendingWhatsNewVersion else { return }
        guard ChangelogService.compareVersion(lhs: pendingVersion, rhs: ChangelogService.currentVersion) != .orderedDescending else {
            pendingWhatsNewVersion = nil
            return
        }

        switch status {
        case .current:
            showWhatsNewIfEligible(for: pendingVersion)
        case .newerThanLatestRelease, .updateAvailable, .unavailable:
            pendingWhatsNewVersion = nil
        case .unknown:
            break
        }
    }

    private func showWhatsNewIfEligible(for version: String) {
        guard hasCompletedSetup, hasSeenWelcome, updateService.installationStatus == nil else { return }
        guard ChangelogService.compareVersion(lhs: version, rhs: lastSeenChangelogVersion) == .orderedDescending else {
            pendingWhatsNewVersion = nil
            return
        }

        pendingWhatsNewVersion = nil
        lastSeenChangelogVersion = version
        ChangelogService.shared.fetchIfNeeded()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showingWhatsNew = true
        }
    }

    private func migrateLastSeenChangelogVersionIfNeeded(currentVersion: String) {
        guard lastSeenChangelogVersion.isEmpty, !legacyLastSeenVersion.isEmpty else { return }

        if let latestChangelogVersion = ChangelogService.shared.latestEntryVersion(upTo: currentVersion),
           ChangelogService.compareVersion(lhs: legacyLastSeenVersion, rhs: latestChangelogVersion) == .orderedDescending {
            lastSeenChangelogVersion = latestChangelogVersion
        } else {
            lastSeenChangelogVersion = legacyLastSeenVersion
        }
    }
}

// MARK: - Content View Body (Extracted)
struct ContentViewBody: View {
    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var schedulingEngine: SchedulingEngine
    @EnvironmentObject var sessionAwarenessService: SessionAwarenessService
    @EnvironmentObject var sessionAudioService: SessionAudioService
    @EnvironmentObject var eventCreationCoordinator: EventCreationCoordinator

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
    @Binding var modeToast: String?

    @AppStorage("devNowLineOverrideEnabled") private var devNowLineOverrideEnabled = false
    @AppStorage("devNowLineOverrideHour") private var devNowLineOverrideHour = 10
    @AppStorage("devNowLineOverrideMinute") private var devNowLineOverrideMinute = 30

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

            if let creationTime = eventCreationCoordinator.startTime {
                eventCreationModalLayer(startTime: creationTime)
                    .transition(.opacity)
                    .zIndex(200)
            }
        }
        .animation(.easeOut(duration: 0.15), value: eventCreationCoordinator.startTime)
        .overlay(alignment: .bottom) {
            if let msg = modeToast {
                Text(msg)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(99)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            modeToast = nil
                        }
                    }
            }
            if let toast = copyToast {
                CopyToastView(
                    toast: toast,
                    onUndo: {
                        _ = calendarService.deleteEvent(identifier: toast.newEventId)
                        Task { await calendarService.fetchEvents(for: selectedDate) }
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
        .animation(.easeOut(duration: 0.25), value: modeToast)
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

            alignStartTimeWithSelectedDate()

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
            alignStartTimeWithSelectedDate()
            if autoPreview { updateProjectedSchedule() }
        }
        .onChange(of: calendarService.lastRefresh) { _, _ in
            // Calendar events changed externally (from Calendar.app)
            if let fetchedDate = calendarService.fetchedDate,
               !Calendar.current.isDate(fetchedDate, inSameDayAs: selectedDate) {
                Task { await calendarService.fetchEvents(for: selectedDate) }
                return
            }
            alignStartTimeWithSelectedDate()
            if autoPreview { updateProjectedSchedule() }
        }
        .onChange(of: eventCreationCoordinator.startTime) { _, _ in
            if autoPreview { updateProjectedSchedule() }
        }
        .onChange(of: eventCreationCoordinator.durationMinutes) { _, _ in
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
                alignStartTimeWithSelectedDate()
                
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
            startTime = calendar.date(bySettingHour: schedulingEngine.defaultStartHour, minute: 0, second: 0, of: selectedDate) ?? selectedDate
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

    private func alignStartTimeWithSelectedDate() {
        let calendar = Calendar.current
        let selectedIsToday = calendar.isDateInToday(selectedDate)
        let wasUsingNow = useNowTime

        if !selectedIsToday && useNowTime {
            useNowTime = false
        }

        guard !calendar.isDate(startTime, inSameDayAs: selectedDate) || (wasUsingNow && !selectedIsToday) else {
            return
        }

        let hour = (wasUsingNow && !selectedIsToday) ? schedulingEngine.defaultStartHour : calendar.component(.hour, from: startTime)
        let minute = (wasUsingNow && !selectedIsToday) ? 0 : calendar.component(.minute, from: startTime)
        if let aligned = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: selectedDate) {
            startTime = aligned
        }
    }
    
    @ViewBuilder
    private func eventCreationModalLayer(startTime: Date) -> some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.15)) {
                        eventCreationCoordinator.dismiss()
                    }
                }

            EventCreationPopover(
                startTime: Binding(
                    get: { eventCreationCoordinator.startTime ?? startTime },
                    set: { eventCreationCoordinator.startTime = $0 }
                ),
                durationMinutes: $eventCreationCoordinator.durationMinutes,
                onCommit: { title, start, end, calendar in
                    eventCreationCoordinator.onCommit?(title, start, end, calendar)
                },
                onCancel: {
                    withAnimation(.easeOut(duration: 0.15)) {
                        eventCreationCoordinator.dismiss()
                    }
                }
            )
        }
    }

    private var backgroundGradient: some View {
        colors.backgroundGradient
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
            
            Divider().background(colors.divider)

            TimelineView(
                selectedDate: selectedDate,
                startTime: effectiveStartTime,
                useNowTime: useNowTime && dateSelection == .today && Calendar.current.isDateInToday(selectedDate),
                onCopySuccess: { info in copyToast = info },
                onModeToast: { modeToast = $0 }
            )
            .padding()

            Divider().background(colors.divider)
            
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
        let calendar = Calendar.current
        let selectedIsToday = calendar.isDateInToday(selectedDate)

        if useNowTime && !selectedIsToday {
            return calendar.date(
                bySettingHour: schedulingEngine.defaultStartHour,
                minute: 0,
                second: 0,
                of: selectedDate
            ) ?? selectedDate
        }

        if useNowTime && dateSelection == .today && selectedIsToday {
            // Dev override: use fixed time for demos/screenshots (also drives planning start)
            if devNowLineOverrideEnabled {
                let dayStart = calendar.startOfDay(for: selectedDate)
                return calendar.date(byAdding: .hour, value: devNowLineOverrideHour, to: dayStart)
                    .flatMap { calendar.date(byAdding: .minute, value: devNowLineOverrideMinute, to: $0) } ?? roundedNowTime()
            }
            return roundedNowTime()
        }

        if !calendar.isDate(startTime, inSameDayAs: selectedDate),
           let aligned = calendar.date(
                bySettingHour: calendar.component(.hour, from: startTime),
                minute: calendar.component(.minute, from: startTime),
                second: 0,
                of: selectedDate
           ) {
            return aligned
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
        syncRestDurationsToAwareness()

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
    
    private func syncRestDurationsToAwareness() {
        sessionAwarenessService.restDurations = [
            .work: schedulingEngine.restDuration,
            .side: schedulingEngine.sideRestDuration,
            .deep: schedulingEngine.deepRestDuration,
            .planning: schedulingEngine.restDuration,
        ]
    }

    func updateProjectedSchedule() {
        if let fetchedDate = calendarService.fetchedDate,
           !Calendar.current.isDate(fetchedDate, inSameDayAs: selectedDate) {
            Task { await calendarService.fetchEvents(for: selectedDate) }
            return
        }

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
            busySlots: busySlotsIncludingEventCreationDraft(),
            includePlanning: !planningExists,
            existingSessions: (work: existing.work, side: existing.side, deep: existing.deep),
            existingTitles: existing.titles
        )
    }

    private func busySlotsIncludingEventCreationDraft() -> [BusyTimeSlot] {
        guard let draftStart = eventCreationCoordinator.startTime,
              Calendar.current.isDate(draftStart, inSameDayAs: selectedDate)
        else {
            return calendarService.busySlotsForFetchedDate(selectedDate)
        }

        let durationMinutes = max(5, eventCreationCoordinator.durationMinutes)
        let draftEnd = draftStart.addingTimeInterval(Double(durationMinutes) * 60)
        let title = eventCreationCoordinator.draftTitle.isEmpty ? "New Event" : eventCreationCoordinator.draftTitle

        var slots = calendarService.busySlotsForFetchedDate(selectedDate)
        slots.append(BusyTimeSlot(
            id: "sessionflow-event-creation-draft",
            title: title,
            startTime: draftStart,
            endTime: draftEnd,
            calendarName: "Draft Event",
            calendarColor: eventCreationCoordinator.calendarColor
        ))
        return slots
    }
    
    private func requestCalendarAccess() async {
        guard !ProcessInfo.processInfo.isRunningTests else { return }
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
            let cutoff = Calendar.current.isDateInToday(selectedDate)
                ? Date()
                : Calendar.current.startOfDay(for: selectedDate)
            result = calendarService.deleteFutureSessionEvents(
                for: selectedDate,
                after: cutoff,
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
    @EnvironmentObject var awarenessService: SessionAwarenessService
    @Binding var selectedDate: Date
    let autoPreview: Bool
    let updatePreview: () -> Void
    @State private var debounceWork: DispatchWorkItem?

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
            .background(extraObservers3)
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

    private var extraObservers3: some View {
        Color.clear
            .onChange(of: engine.workCalendarIdentifier) { _, _ in trigger() }
            .onChange(of: engine.sideCalendarIdentifier) { _, _ in trigger() }
            .onChange(of: engine.deepSessionConfig.calendarIdentifier) { _, _ in trigger() }
    }

    private func trigger() {
        syncRestDurations()
        debounceWork?.cancel()
        let work = DispatchWorkItem { if autoPreview { updatePreview() } }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func syncRestDurations() {
        awarenessService.restDurations = [
            .work: engine.restDuration,
            .side: engine.sideRestDuration,
            .deep: engine.deepRestDuration,
            .planning: engine.restDuration,
        ]
    }
}

// MARK: - Header View
struct HeaderView: View {
    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    @EnvironmentObject var updateService: UpdateService
    @EnvironmentObject var schedulingEngine: SchedulingEngine
    @Binding var dateSelection: ContentView.DateSelection
    @Binding var selectedDate: Date
    @Binding var useNowTime: Bool
    @Binding var startTime: Date
    @Binding var autoPreview: Bool

    @AppStorage("devNowLineOverrideEnabled") private var devNowLineOverrideEnabled = false
    @AppStorage("devNowLineOverrideHour") private var devNowLineOverrideHour = 10
    @AppStorage("devNowLineOverrideMinute") private var devNowLineOverrideMinute = 30

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
                    .foregroundColor(colors.textMuted)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(colors.subtleBackground))
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: 0.2)
            .help("App Settings")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(WindowDragView())
        .background(colors.overlayBackground)
        #if DEBUG
        .task {
            let branch = Self.resolveGitBranch()
            await MainActor.run { gitBranch = branch }
        }
        #endif
    }

    #if DEBUG
    @State private var gitBranch: String?

    private static func resolveGitBranch() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
        process.currentDirectoryURL = Bundle.main.bundleURL.deletingLastPathComponent()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let branch = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !branch.isEmpty, branch != "main"
        else { return nil }
        return branch
    }
    #endif

    private var appTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("SessionFlow")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(colors.textPrimary)
                Text(displayedHeaderVersion)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(colors.textMuted)
            }
            HStack(spacing: 6) {
                Text("Plan your productive day")
                    .font(.subheadline)
                    .foregroundColor(colors.textSecondary)
                #if DEBUG
                if let branch = gitBranch {
                    Text(branch)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.15)))
                }
                #endif
            }
            if let status = updateService.installationStatus {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7, anchor: .center)
                        .progressViewStyle(.circular)
                    Text(status.message)
                        .font(.caption)
                        .foregroundColor(colors.textSecondary)
                }
            }
        }
    }

    private var displayedHeaderVersion: String {
        let marketingVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        #if DEBUG
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "v\(marketingVersion).\(buildNumber)"
        #else
        return "v\(marketingVersion)"
        #endif
    }
    
    private var dateButtons: some View {
        HStack(spacing: 12) {
            Button {
                showPastDaysMenu()
            } label: {
                Text("⋮")
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(colors.hoveredBackground)
                    .foregroundColor(colors.textPrimary)
                    .cornerRadius(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: 0.15)
            .focusEffectDisabled()

            ForEach(ContentView.DateSelection.allCases, id: \.self) { sel in
                Button { dateSelection = sel } label: {
                    Text(sel.rawValue)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(dateSelection == sel ? Color(hex: "8B5CF6") : colors.hoveredBackground)
                        .foregroundColor(dateSelection == sel ? .white : colors.textPrimary)
                        .cornerRadius(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect(brightness: dateSelection == sel ? 0 : 0.15)
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
                startTime = Calendar.current.date(bySettingHour: schedulingEngine.defaultStartHour, minute: 0, second: 0, of: date) ?? date
            }
            menu.addItem(item)
        }

        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: event.window?.contentView ?? NSView())
        }
    }

    private var startTimeControls: some View {
        let nowDisabled = dateSelection != .today || !Calendar.current.isDateInToday(selectedDate)
        return HStack(spacing: 8) {
            Text("Start:").foregroundColor(colors.textSecondary)
            Picker("", selection: $useNowTime) {
                Text("Now").tag(true)
                Text("Set").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
            .disabled(nowDisabled)
            .help(nowDisabled ? "\"Now\" is only available for Today" : "")
            
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
                    .hoverEffect(brightness: 0.2)
                    .help("Click to set a custom start time")
                }
            }
            .frame(width: 100)
        }
    }
    
    private func formatNowTime() -> String {
        let calendar = Calendar.current
        let date: Date
        if devNowLineOverrideEnabled, useNowTime, dateSelection == .today {
            let dayStart = calendar.startOfDay(for: selectedDate)
            date = calendar.date(byAdding: .hour, value: devNowLineOverrideHour, to: dayStart)
                .flatMap { calendar.date(byAdding: .minute, value: devNowLineOverrideMinute, to: $0) } ?? Date()
        } else {
            let now = Date()
            let comp = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
            let minute = comp.minute ?? 0
            let rounded = ((minute / 5) + 1) * 5
            var newComp = comp
            newComp.minute = rounded % 60
            newComp.hour = (comp.hour ?? 0) + (rounded >= 60 ? 1 : 0)
            date = calendar.date(from: newComp) ?? now
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
}

// MARK: - Left Panel
struct LeftPanel: View {
    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

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
                        Divider().background(colors.divider)
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
                // Dim overlay – scheme-aware so the card stays readable in both themes
                RoundedRectangle(cornerRadius: 12)
                    .fill((colorScheme == .dark ? Color.black : Color.white).opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)

                // Centered card content
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 28))
                        .foregroundColor(colors.textSecondary)
                    Text("Manual alignment active")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                    Text("Settings are locked while you adjust projected sessions")
                        .font(.system(size: 12))
                        .foregroundColor(colors.textSecondary)
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
                    .hoverEffect(brightness: 0.12)
                    .help(isConfirmingReset ? "Click again to confirm" : "Reset manual alignment")
                    .animation(.easeInOut(duration: 0.15), value: isConfirmingReset)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colors.panelBackground)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border, lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.2), radius: 12, y: 4)
                )
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
                            .foregroundColor(selectedTab == tab ? colors.textPrimary : colors.textMuted)

                        Rectangle()
                            .fill(selectedTab == tab ? Color(hex: "8B5CF6") : Color.clear)
                            .frame(height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect(brightness: selectedTab == tab ? 0 : 0.15)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 16)
    }
    
    private var presetDropdown: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bookmark.fill").foregroundColor(Color(hex: "8B5CF6"))
                Text("Preset").font(.headline).foregroundColor(colors.textPrimary)
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
                    Text(p.name + (modified ? " ＊" : "")).foregroundColor(colors.textPrimary)
                } else {
                    Image(systemName: "doc").foregroundColor(colors.textSecondary)
                    Text("No Preset Selected").foregroundColor(colors.textSecondary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(colors.textSecondary)
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
        // Reuse saveAsPreset so the field list stays in one place (preserve id/name/icon).
        let updated = schedulingEngine.saveAsPreset(id: preset.id, name: preset.name, icon: preset.icon)
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
    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var schedulingEngine: SchedulingEngine
    @EnvironmentObject var sessionAwarenessService: SessionAwarenessService
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
                VStack(spacing: 20) {
                    availabilityCard
                    sessionsSummaryCard
                    if sessionAwarenessService.config.enabled && sessionAwarenessService.config.productivityEnabled && calendarService.busySlotsForFetchedDate(selectedDate).contains(where: { SessionRating.fromNotes($0.notes) != nil }) {
                        ProductivityCard()
                    }
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
            }
            Spacer()
            actionButtons
        }
        .frame(width: 280)
        .padding()
    }
    
    private var availabilityCard: some View {
        let avail = schedulingEngine.calculateAvailability(startTime: effectiveStartTime, baseDate: selectedDate, busySlots: calendarService.busySlotsForFetchedDate(selectedDate))
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.fill").foregroundColor(Color(hex: "3B82F6"))
                Text("Availability").font(.headline).foregroundColor(colors.textPrimary)

                Spacer()

                Button {
                    showingAvailabilityHelp.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundColor(colors.textMuted)
                }
                .buttonStyle(.plain)
                .hoverEffect(brightness: 0.3)
                .popover(isPresented: $showingAvailabilityHelp) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(availabilityHelpBase)
                        if schedulingEngine.scheduleEndHour > 24 {
                            Text("Includes +1d hours until \(formattedHourForCard(schedulingEngine.scheduleEndHour))")
                                .font(.system(size: 12))
                                .foregroundColor(colors.isDark ? .orange.opacity(0.9) : Color(hex: "C2410C"))
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
            .font(.system(size: 13)).foregroundColor(colors.textSecondary)
        }
        .padding().background(colors.subtleBackground).cornerRadius(12)
    }
    
    private func row(_ label: String, _ val: String, _ color: Color? = nil) -> some View {
        HStack { Text(label); Spacer(); Text(val).fontWeight(.semibold).foregroundColor(color ?? colors.textSecondary) }
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
                Text("Projected Sessions").font(.headline).foregroundColor(colors.textPrimary)

                Spacer()

                Button {
                    showingProjectionHelp.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundColor(colors.textMuted)
                }
                .buttonStyle(.plain)
                .hoverEffect(brightness: 0.3)
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
                        .foregroundColor(colors.textSecondary)
                        .padding(.vertical, 8)
                } else if schedulingEngine.quotasSatisfied {
                    quotaSatisfiedStats
                        .padding(.vertical, 8)
                } else if !schedulingEngine.schedulingMessage.isEmpty {
                    Text("No additional sessions projected")
                        .font(.system(size: 12))
                        .foregroundColor(colors.textSecondary)
                        .padding(.vertical, 8)
                } else {
                    Text("Scheduling preview will appear here")
                        .font(.system(size: 12))
                        .foregroundColor(colors.textSecondary)
                        .padding(.vertical, 8)
                }
            } else {
                sessionStats(sessions)
            }
            if !schedulingEngine.schedulingMessage.isEmpty {
                Text(schedulingEngine.schedulingMessage).font(.system(size: 11)).foregroundColor(colors.isDark ? .yellow.opacity(0.8) : Color(hex: "92400E"))
            }
            
            if schedulingEngine.awareExistingTasks {
                HStack(spacing: 4) {
                    Image(systemName: "brain.head.profile").font(.system(size: 10))
                    Text("Accounting for existing sessions from calendar").font(.system(size: 10)).italic()
                }
                .foregroundColor(colors.textMuted)
                .padding(.top, -4)
            }
        }
        .padding()
        .background(colors.subtleBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundColor(colors.border)
        )
    }
    
    private func sessionStats(_ sessions: [ScheduledSession]) -> some View {
        let wc = sessions.filter { $0.type == .work }.count
        let sc = sessions.filter { $0.type == .side }.count
        let pc = sessions.filter { $0.type == .planning }.count
        let dc = sessions.filter { $0.type == .deep }.count
        let lrc = sessions.filter { $0.type == .bigRest }.count
        let sessionCount = sessions.filter { $0.type != .bigRest }.count
        let minutes: (SessionType) -> Int = { type in
            sessions.filter { $0.type == type }.reduce(0) { $0 + $1.durationMinutes }
        }
        let totalMinutes = sessions.filter { $0.type != .bigRest }.reduce(0) { $0 + $1.durationMinutes }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return VStack(alignment: .leading, spacing: 6) {
            if pc > 0 { countRow(.planning, pc, minutes: minutes(.planning)) }
            countRow(.work, wc, minutes: minutes(.work))
            countRow(.side, sc, minutes: minutes(.side))
            if dc > 0 { countRow(.deep, dc, minutes: minutes(.deep)) }
            Divider().background(colors.borderStrong)
            HStack { Text("Total:").fontWeight(.medium); Spacer(); Text("\(formatDuration(totalMinutes)) · \(sessionCount) sessions").fontWeight(.semibold) }
            if lrc > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "pause.circle.fill").font(.system(size: 9)).foregroundColor(SessionType.bigRest.color.opacity(0.6))
                    Text("\(lrc) long \(lrc == 1 ? "rest" : "rests") between sessions")
                        .font(.system(size: 11))
                        .foregroundColor(colors.textMuted)
                }
            }
            if let last = sessions.last {
                let cal = Calendar.current
                let comps = cal.dateComponents([.hour, .minute], from: last.endTime)
                let isMidnight = comps.hour == 0 && comps.minute == 0
                let isNextDay = !isMidnight && !cal.isDate(last.endTime, inSameDayAs: selectedDate)
                HStack {
                    Text("Done by:").foregroundColor(Color(hex: "10B981"))
                    Spacer()
                    HStack(spacing: 4) {
                        if isNextDay {
                            Text("+1d")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(colors.isDark ? .orange : Color(hex: "C2410C"))
                        }
                        Text(formatter.string(from: last.endTime)).fontWeight(.semibold).foregroundColor(Color(hex: "10B981"))
                    }
                }
            }
        }
        .font(.system(size: 13)).foregroundColor(colors.textSecondary)
    }

    private var quotaSatisfiedStats: some View {
        let counts = schedulingEngine.quotaCounts
        return VStack(alignment: .leading, spacing: 6) {
            Text("Daily quotas satisfied")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "10B981"))
            if schedulingEngine.schedulePlanning { countRow(.planning, 1) }
            if schedulingEngine.workSessions > 0 { countRow(.work, counts.work) }
            if schedulingEngine.sideSessions > 0 { countRow(.side, counts.side) }
            if schedulingEngine.deepSessionConfig.enabled { countRow(.deep, counts.deep) }
        }
        .font(.system(size: 13)).foregroundColor(colors.textSecondary)
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

    private func countRow(_ type: SessionType, _ count: Int, minutes: Int? = nil) -> some View {
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
            HStack(spacing: 6) {
                if let minutes, minutes > 0 {
                    Text(formatDuration(minutes))
                        .font(.system(size: 11))
                        .foregroundColor(colors.textMuted)
                }
                Text("\(count)").fontWeight(.medium)
            }
        }
    }

    private func formatDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        }
        return "\(mins)m"
    }
    
    private var actionButtons: some View {
        let accent = Color(hex: "6366F1")
        let disabled = schedulingEngine.projectedSessions.isEmpty

        return VStack(spacing: 12) {
            // Split button: Schedule Sessions (main) + dropdown arrow (planning)
            HStack(spacing: 0) {
                Button(action: { scheduleAll() }) {
                    HStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "calendar.badge.plus")
                        Text("Schedule Sessions")
                        Spacer()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.leading, 24) // slight visual offset to compensate right chevron area
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .help("Add all projected sessions to your Calendar")

                Rectangle()
                    .fill(colors.borderStrong)
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
                        .foregroundColor(.white)
                        .frame(maxWidth: 36, maxHeight: .infinity)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize(horizontal: true, vertical: false)
                .help("More scheduling options")
            }
            .frame(height: 44)
            .background(disabled ? Color.gray.opacity(0.3) : accent)
            .foregroundColor(.white)
            .environment(\.colorScheme, .dark)
            .cornerRadius(10)
            .hoverEffect(brightness: disabled ? 0 : 0.12)

            Button(action: { deletePastSessions = false; showingDeleteConfirmation = true }) {
                HStack { Image(systemName: "trash"); Text("Delete Day's Sessions") }
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.red.opacity(0.2)).foregroundColor(.red).cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.red.opacity(0.3), lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: 0.15)
            .help("Remove scheduled sessions for the selected day")
        }
    }
    
    private func createPlanningSession() {
        // Project a single planning session
        if let session = schedulingEngine.projectSingleSession(
            type: .planning,
            startTime: effectiveStartTime,
            baseDate: selectedDate,
            busySlots: calendarService.busySlotsForFetchedDate(selectedDate)
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
    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

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
                            .foregroundColor(colors.isDark ? .yellow.opacity(0.7) : Color(hex: "92400E"))
                        Text("Did you know?")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                    }
                    Text(fact.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                }
                Spacer()
                controlButtons
            }
            Text(fact.message)
                .font(.system(size: 12))
                .foregroundColor(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 8)

            if totalFacts > 1 {
                HStack(spacing: 4) {
                    ForEach(0..<totalFacts, id: \.self) { idx in
                        Capsule()
                            .fill(idx == factIndex ? colors.textPrimary : colors.textDisabled)
                            .frame(width: idx == factIndex ? 16 : 8, height: 3)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(colors.subtleBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colors.divider, lineWidth: 1)
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
                .fill(colors.divider)
                .frame(width: 1, height: 14)
                .padding(.horizontal, 2)
            controlButton(icon: "xmark", action: onClose)
        }
    }
    
    private func controlButton(icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(disabled ? colors.textDisabled : colors.textSecondary)
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(disabled ? colors.subtleBackground : colors.hoveredBackground)
                )
        }
        .buttonStyle(.plain)
        .hoverEffect(brightness: disabled ? 0 : 0.2)
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
                .background(Color.primary.opacity(0.07))
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
    private var localMouseMonitor: Any?

    override var mouseDownCanMoveWindow: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLocalMouseMonitor()
    }

    deinit {
        removeLocalMouseMonitor()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            if let window {
                WindowTitleBarDoubleClick.perform(on: window)
            }
        } else {
            window?.performDrag(with: event)
        }
    }

    private func updateLocalMouseMonitor() {
        removeLocalMouseMonitor()

        guard window != nil else { return }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self,
                  let window = self.window,
                  event.window === window,
                  event.clickCount == 2
            else {
                return event
            }

            let pointInHeader = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(pointInHeader),
                  !self.isInteractiveClick(in: window, at: event.locationInWindow)
            else {
                return event
            }

            WindowTitleBarDoubleClick.perform(on: window)
            return nil
        }
    }

    private func removeLocalMouseMonitor() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }

    private func isInteractiveClick(in window: NSWindow, at location: NSPoint) -> Bool {
        guard let contentView = window.contentView else { return false }
        let pointInContent = contentView.convert(location, from: nil)
        guard let hitView = contentView.hitTest(pointInContent) else { return false }
        var current: NSView? = hitView

        while let view = current {
            if view is NSControl || view is NSTextView || view is NSScrollView {
                return true
            }
            current = view.superview
        }

        return false
    }
}

enum WindowTitleBarDoubleClick {
    private static weak var lastWindow: NSWindow?
    private static var lastActionTime: TimeInterval = 0

    static func perform(on window: NSWindow) {
        let now = ProcessInfo.processInfo.systemUptime
        if lastWindow === window, now - lastActionTime < 0.25 {
            return
        }

        lastWindow = window
        lastActionTime = now

        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize":
            window.miniaturize(nil)
        case "None":
            return
        default:
            window.performZoom(nil)
        }
    }
}

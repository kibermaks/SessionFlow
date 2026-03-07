import SwiftUI
import EventKit
import AppKit

struct AppSettingsView: View {
    @EnvironmentObject var schedulingEngine: SchedulingEngine
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var sessionAwarenessService: SessionAwarenessService
    @EnvironmentObject var sessionAudioService: SessionAudioService

    @AppStorage("hasSeenWelcome") var hasSeenWelcome = false
    @AppStorage("hasSeenPatternsGuide") var hasSeenPatternsGuide = false
    @AppStorage("hasSeenTasksGuide") var hasSeenTasksGuide = false
    @AppStorage("timelineIntroBarDismissed") var timelineIntroBarDismissed = false
    @AppStorage("showDevSettings") private var showDevSettings = false

    @State private var showingResetPresetsConfirmation = false
    @State private var showingResetAwarenessConfirmation = false
    @State private var pendingReplacementContext: CalendarReplacementContext?
    @State private var selectedReplacementCalendarId: String = ""
    @State private var replacementErrorMessage: String?
    @State private var selectedSettingsTab: SettingsTab = .general
    @State private var activePreviewID: String? = nil
    @State private var previewResetWorkItem: DispatchWorkItem? = nil
    private let ambientVolumeSliderWidth: CGFloat = 132
    private let soundControlHeight: CGFloat = 22
    private let showVolumeSliderDebugBorder = false
    private let previewDuration: TimeInterval = 4.0
    private let transitionPreviewDuration: TimeInterval = 1.5

    private enum SettingsTab: String, CaseIterable {
        case general, calendars, awareness
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .calendars: return "calendar"
            case .awareness: return "eye.circle"
            }
        }
        var label: String {
            switch self {
            case .general: return "General"
            case .calendars: return "Calendars"
            case .awareness: return "Awareness"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases, id: \.rawValue) { tab in
                    settingsTabButton(tab)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(height: 72)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()
                .background(Color.white.opacity(0.1))

            Group {
                switch selectedSettingsTab {
                case .general: generalTab
                case .calendars: calendarsTab
                case .awareness: sessionAwarenessTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 520, height: 680)
        .preferredColorScheme(.dark)
        .alert("Reset Presets?", isPresented: $showingResetPresetsConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetPresets()
            }
        } message: {
            Text("This will permanently delete all saved presets and launch Calendar Setup to recreate them.")
        }
        .sheet(item: $pendingReplacementContext, onDismiss: {
            selectedReplacementCalendarId = ""
        }) { context in
            CalendarReplacementSheet(
                context: context,
                replacementOptions: replacementOptions(excluding: context.calendar),
                selectedCalendarId: $selectedReplacementCalendarId,
                onCancel: {
                    pendingReplacementContext = nil
                },
                onConfirm: {
                    confirmCalendarReplacement(for: context)
                }
            )
        }
        .alert("Cannot Hide Calendar", isPresented: replacementErrorBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(replacementErrorMessage ?? "Unknown issue occurred.")
        }
        .onDisappear {
            stopPreview()
        }
    }

    private func settingsTabButton(_ tab: SettingsTab) -> some View {
        let isSelected = selectedSettingsTab == tab
        return Button {
            selectedSettingsTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: .medium))
                Text(tab.label)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Rectangle())
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    // MARK: - Tab 1: General

    private var generalTab: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.accentColor)

                    Text("General")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .onTapGesture(count: 4) {
                            withAnimation { showDevSettings.toggle() }
                        }

                    Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }

            Section("Scheduling Logic") {
                Toggle("Aware existing tasks", isOn: $schedulingEngine.awareExistingTasks)

                Text("When enabled, the app only projects remaining tasks needed to meet your quotas by counting existing events on your calendar.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Tagging System")
                        .font(.caption)
                        .fontWeight(.bold)
                    Text("The app uses hashtags in event notes to identify session types: #work, #side, #deep, #plan. This allows accurate counting even if calendars overlap.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)

                LabeledContent("Schedule until:") {
                    HStack {
                        if schedulingEngine.scheduleEndHour > 24 {
                            Text("+1d \(formattedHourForSettings(schedulingEngine.scheduleEndHour))")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                        }
                        NumericInputField(value: $schedulingEngine.scheduleEndHour, range: 13...30, step: 1, unit: "h")
                    }
                }
                Text("When to stop placing sessions. Values above 24 extend into the next day.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Timeline Visibility") {
                Toggle("Hide night hours", isOn: $schedulingEngine.hideNightHours)

                LabeledContent("Morning Edge:") {
                    HStack {
                        NumericInputField(value: $schedulingEngine.dayStartHour, range: 0...12, step: 1, unit: "h")
                    }
                }
                .padding(.leading, 10)
                .disabled(!schedulingEngine.hideNightHours)

                Text("Night edge is controlled by \"Schedule until\" above.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Tips") {
                Toggle("Show \"Did you know?\" card", isOn: $schedulingEngine.showDidYouKnowCard)
                Text("Displays rotating tips next of how to use the app.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Preset Management") {
                Button(role: .destructive, action: { showingResetPresetsConfirmation = true }) {
                    Label("Reset Presets", systemImage: "arrow.counterclockwise")
                }

                Text("This will erase all saved presets and launch Calendar Setup.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if showDevSettings {
                Section("Developer Settings") {
                    Button(action: {
                        hasSeenWelcome = false
                        hasSeenPatternsGuide = false
                        hasSeenTasksGuide = false
                        timelineIntroBarDismissed = false
                        UserDefaults.standard.set(false, forKey: "hasSeenSessionAwarenessGuide")
                    }) {
                        Label("Reset All Dirty Triggers", systemImage: "arrow.counterclockwise")
                    }

                    Button(action: resetCalendarSetup) {
                        Label("Reset Calendar Setup", systemImage: "calendar.badge.clock")
                    }

                    Text("This will show the calendar setup screen again for testing.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    Menu {
                        Button {
                            sessionAwarenessService.simulatePresenceReminder()
                        } label: {
                            Label("Presence Reminder", systemImage: "bell.badge.fill")
                        }
                        Button {
                            sessionAwarenessService.simulateEndingSoon()
                        } label: {
                            Label("Ending Soon", systemImage: "clock.badge.exclamationmark")
                        }
                    } label: {
                        Label("Simulate Awareness Event", systemImage: "play.circle")
                    }

                    Text("Triggers awareness sounds and flash effects for testing.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    Button(role: .destructive, action: resetCalendarPermissions) {
                        Label("Reset Calendar Permissions", systemImage: "lock.slash.fill")
                    }

                    Text("Note: Resetting permissions will immediately terminate the application to clear the system cache.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Tab 2: Calendars

    private var calendarsTab: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 20))
                        .foregroundColor(.accentColor)

                    Text("Calendar Filters")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }

            Section {
                if calendarService.authorizationStatus != .fullAccess {
                    Text("Grant calendar access to manage which calendars contribute busy events.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    let calendars = calendarService.availableCalendars.sorted { $0.title < $1.title }
                    if calendars.isEmpty {
                        Text("No editable calendars available. Create or add calendars in the macOS Calendar app.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Unchecked calendars are ignored when fetching busy slots and counting existing sessions.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        ForEach(calendars, id: \.calendarIdentifier) { calendar in
                            Toggle(isOn: Binding(
                                get: { !calendarService.isCalendarExcluded(identifier: calendar.calendarIdentifier) },
                                set: { included in
                                    handleCalendarToggle(for: calendar, included: included)
                                }
                            )) {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(color(for: calendar))
                                        .frame(width: 12, height: 12)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(calendar.title)
                                            .font(.body)
                                        Text(calendar.source.title)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Tab 3: Session Awareness

    @State private var showingCustomSoundImport = false
    @State private var customSoundImportIsAmbient = true
    @State private var pendingImportURL: URL? = nil
    @State private var customSoundName: String = ""
    @State private var showingNamePrompt = false

    private var sessionAwarenessTab: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "eye.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.accentColor)

                    Text("Session Awareness")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }

            Section {
                Toggle("Enable Tracking", isOn: Binding(
                    get: { sessionAwarenessService.config.enabled },
                    set: { newValue in
                        sessionAwarenessService.config.enabled = newValue
                        sessionAwarenessService.isEnabled = newValue
                    }
                ))

                Text("Bottom panel tracks your current session with timer, progress, and ambient sound.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if sessionAwarenessService.config.enabled {
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 16)

                        Text("Master Volume")
                            .font(.system(size: 14, weight: .medium))

                        Slider(value: Binding(
                            get: { sessionAwarenessService.config.masterVolume },
                            set: { newValue in
                                sessionAwarenessService.config.masterVolume = newValue
                                sessionAudioService.setMasterVolume(newValue)
                            }
                        ), in: 0...1)

                        Text("\(Int(sessionAwarenessService.config.masterVolume * 100))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 38, alignment: .trailing)
                    }

                    Toggle("Awareness of your other calendar events", isOn: Binding(
                        get: { sessionAwarenessService.config.trackOtherEvents },
                        set: { sessionAwarenessService.config.trackOtherEvents = $0 }
                    ))

                    Text("Tracking with timer, progress, and ambient sound.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if sessionAwarenessService.config.enabled {
                Section("Ambient Sounds For") {
                    ambientSoundRow(icon: "briefcase.fill", iconColor: SessionType.work.color, label: "Work",
                                    soundKeyPath: \.workSound, accelKeyPath: \.workSoundAccelerando)
                    ambientSoundRow(icon: "star.fill", iconColor: SessionType.side.color, label: "Side",
                                    soundKeyPath: \.sideSound, accelKeyPath: \.sideSoundAccelerando)
                    ambientSoundRow(icon: "bolt.circle.fill", iconColor: SessionType.deep.color, label: "Deep",
                                    soundKeyPath: \.deepSound, accelKeyPath: \.deepSoundAccelerando)
                    ambientSoundRow(icon: "calendar.badge.clock", iconColor: SessionType.planning.color, label: "Planning",
                                    soundKeyPath: \.planningSound, accelKeyPath: \.planningSoundAccelerando)

                    if sessionAwarenessService.config.trackOtherEvents {
                        ambientSoundRow(icon: "calendar", iconColor: .gray, label: "Your events",
                                        soundKeyPath: \.otherEventsSound, accelKeyPath: \.otherEventsSoundAccelerando)
                    }
                }

                Section("Session Transitions") {
                    soundRow(icon: "play.fill", iconColor: .green, label: "Start",
                             config: bindingSoundConfig(forTransition: \.startSound), isAmbient: false)
                    soundRow(icon: "clock.badge.exclamationmark", iconColor: .yellow, label: "Ending",
                             config: bindingSoundConfig(forTransition: \.endingSoonSound), isAmbient: false)

                    Text("\"Ending\" plays 2 minutes before session ends.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    soundRow(icon: "stop.fill", iconColor: .orange, label: "End",
                             config: bindingSoundConfig(forTransition: \.endSound), isAmbient: false)
                }

                Section("Presence Reminder") {
                    Toggle("Periodic nudge during sessions", isOn: Binding(
                        get: { sessionAwarenessService.config.presenceReminderEnabled },
                        set: { sessionAwarenessService.config.presenceReminderEnabled = $0 }
                    ))

                    if sessionAwarenessService.config.presenceReminderEnabled {
                        Picker("Interval", selection: Binding(
                            get: { sessionAwarenessService.config.presenceReminderIntervalMinutes },
                            set: { sessionAwarenessService.config.presenceReminderIntervalMinutes = $0 }
                        )) {
                            Text("5 min").tag(5)
                            Text("10 min").tag(10)
                            Text("15 min").tag(15)
                            Text("20 min").tag(20)
                            Text("30 min").tag(30)
                        }

                        soundRow(icon: "bell.badge.fill", iconColor: .yellow, label: "Sound",
                                 config: bindingSoundConfig(forTransition: \.presenceReminderSound), isAmbient: false)
                    }

                    Text("Plays a short sound at regular intervals to help you stay focused.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Menu Bar & Dock") {
                    Toggle("Show in menu bar", isOn: Binding(
                        get: { sessionAwarenessService.config.showMenuBarItem },
                        set: { sessionAwarenessService.config.showMenuBarItem = $0 }
                    ))

                    Toggle("Show progress on Dock icon", isOn: Binding(
                        get: { sessionAwarenessService.config.showDockProgress },
                        set: { sessionAwarenessService.config.showDockProgress = $0 }
                    ))

                    Text("Menu bar shows session icon and timer. Dock icon shows a progress donut during active sessions.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Audio Output") {
                    Picker("Output Device", selection: Binding(
                        get: { sessionAwarenessService.config.outputDeviceUID ?? "" },
                        set: { newValue in
                            let uid = newValue.isEmpty ? nil : newValue
                            sessionAwarenessService.config.outputDeviceUID = uid
                            sessionAudioService.setOutputDevice(uid: uid)
                        }
                    )) {
                        Text("System Default").tag("")
                        ForEach(sessionAudioService.availableOutputDevices) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                    .onAppear { sessionAudioService.refreshOutputDevices() }
                }

                Section {
                    Button {
                        sessionAudioService.resetAudioEngine()
                    } label: {
                        Label("Fix Sound Issues", systemImage: "wrench.and.screwdriver")
                    }

                    Text("Stops all audio, resets the sound engine, and clears stale playback state.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    Button("Reset Awareness Settings", role: .destructive) {
                        showingResetAwarenessConfirmation = true
                    }

                    Text("Resets all awareness settings to defaults: sounds, transitions, presence reminder, menu bar, and audio output.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .alert("Reset Awareness Settings?", isPresented: $showingResetAwarenessConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetAwarenessSettings()
            }
        } message: {
            Text("This will reset all session awareness settings to their defaults. This cannot be undone.")
        }
        .alert("Name Your Sound", isPresented: $showingNamePrompt) {
            TextField("Sound name", text: $customSoundName)
            Button("Add") { finishCustomSoundImport() }
            Button("Cancel", role: .cancel) { pendingImportURL = nil }
        } message: {
            Text("Enter a display name for this custom sound.")
        }
    }

    // MARK: - Ambient sound row with accelerando

    private func ambientSoundRow(icon: String, iconColor: Color, label: String,
                                  soundKeyPath: WritableKeyPath<SessionAwarenessConfig, SessionSoundConfig>,
                                  accelKeyPath: WritableKeyPath<SessionAwarenessConfig, AccelerandoConfig>) -> some View {
        let isEnabled = sessionAwarenessService.config[keyPath: soundKeyPath].enabled
        let accelEnabled = sessionAwarenessService.config[keyPath: accelKeyPath].enabled
        let defaultSound = SessionAwarenessConfig.default[keyPath: soundKeyPath].sound
        let fallbackSound = defaultSound == "Off"
            ? (SessionSoundConfig.availableSounds.first ?? "Off")
            : defaultSound

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(iconColor)
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 14, weight: .medium))

                Spacer(minLength: 8)

                Toggle("", isOn: Binding(
                    get: { sessionAwarenessService.config[keyPath: soundKeyPath].enabled },
                    set: { isEnabled in
                        sessionAwarenessService.config[keyPath: soundKeyPath].enabled = isEnabled
                        if isEnabled {
                            if sessionAwarenessService.config[keyPath: soundKeyPath].sound == "Off" {
                                sessionAwarenessService.config[keyPath: soundKeyPath].sound = fallbackSound
                            }
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            if isEnabled {
                HStack(spacing: 8) {
                    soundPicker(for: soundKeyPath, isAmbient: true, width: nil)
                        .layoutPriority(1)

                    let previewID = "ambient-\(label)"
                    iconButton(systemName: activePreviewID == previewID ? "stop.fill" : "play.fill", isEnabled: true) {
                        toggleAmbientPreview(
                            id: previewID,
                            sound: sessionAwarenessService.config[keyPath: soundKeyPath].sound,
                            volume: sessionAwarenessService.config[keyPath: soundKeyPath].volume,
                            accelConfig: accelEnabled ? sessionAwarenessService.config[keyPath: accelKeyPath] : nil
                        )
                    }
                    .help(activePreviewID == previewID ? "Stop preview" : "Preview")

                    volumeSlider(
                        value: Binding(
                            get: { sessionAwarenessService.config[keyPath: soundKeyPath].volume },
                            set: { sessionAwarenessService.config[keyPath: soundKeyPath].volume = $0 }
                        ),
                        width: ambientVolumeSliderWidth
                    )

                    speedPicker(value: Binding(
                        get: { sessionAwarenessService.config[keyPath: accelKeyPath].maxMultiplier },
                        set: { sessionAwarenessService.config[keyPath: accelKeyPath].maxMultiplier = $0 }
                    ))

                    accelerandoButton(
                        isEnabled: accelEnabled,
                        isDisabled: sessionAwarenessService.config[keyPath: accelKeyPath].maxMultiplier == 1.0
                    ) {
                        sessionAwarenessService.config[keyPath: accelKeyPath].enabled.toggle()
                    }
                    .help(
                        sessionAwarenessService.config[keyPath: accelKeyPath].maxMultiplier == 1.0
                        ? "Choose a speed other than 1.0x to enable accelerando"
                        : (accelEnabled
                           ? (sessionAwarenessService.config[keyPath: accelKeyPath].maxMultiplier < 1.0
                              ? "Accelerando ON — playback speeds up from \(String(format: "%.1fx", sessionAwarenessService.config[keyPath: accelKeyPath].maxMultiplier)) to 1.0x during session"
                              : "Accelerando ON — playback speeds up from 1.0x to \(String(format: "%.1fx", sessionAwarenessService.config[keyPath: accelKeyPath].maxMultiplier)) during session")
                           : "Enable accelerando — gradually changes playback speed over the session")
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Sound Picker with Standard/Custom sections

    private func soundPicker(for keyPath: WritableKeyPath<SessionAwarenessConfig, SessionSoundConfig>, isAmbient: Bool, width: CGFloat? = nil) -> some View {
        soundSelectionPicker(
            selection: Binding(
                get: { sessionAwarenessService.config[keyPath: keyPath].sound },
                set: { sessionAwarenessService.config[keyPath: keyPath].sound = $0 }
            ),
            availableSounds: SessionSoundConfig.availableSounds,
            width: width
        ) {
            customSoundImportIsAmbient = isAmbient
            openCustomSoundImport(for: keyPath)
        }
    }

    private func transitionSoundPicker(for keyPath: WritableKeyPath<SessionAwarenessConfig, TransitionSoundConfig>, width: CGFloat? = nil) -> some View {
        soundSelectionPicker(
            selection: Binding(
                get: { sessionAwarenessService.config[keyPath: keyPath].sound },
                set: { sessionAwarenessService.config[keyPath: keyPath].sound = $0 }
            ),
            availableSounds: TransitionSoundConfig.availableSounds,
            width: width
        ) {
            customSoundImportIsAmbient = false
            openTransitionSoundImport(for: keyPath)
        }
    }

    private func soundSelectionPicker(selection: Binding<String>, availableSounds: [String], width: CGFloat? = nil, onImport: @escaping () -> Void) -> some View {
        SoundSelectionButton(
            selection: selection,
            availableSounds: availableSounds,
            onImport: onImport
        )
        .frame(minWidth: width ?? 150,
               idealWidth: width,
               maxWidth: width ?? .infinity,
               minHeight: soundControlHeight,
               maxHeight: soundControlHeight,
               alignment: .leading)
    }

    private func volumeSlider(value: Binding<Float>, width: CGFloat = 170) -> some View {
        let iconWidth: CGFloat = 10
        let spacing: CGFloat = 6
        let sliderWidth = max(0, width - iconWidth - spacing)

        return HStack(spacing: spacing) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: iconWidth)

            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(showVolumeSliderDebugBorder ? Color.red.opacity(0.9) : Color.clear, lineWidth: 1)

                Slider(value: value, in: 0...1)
                    .labelsHidden()
                    .frame(width: sliderWidth)
            }
            .frame(width: sliderWidth, height: soundControlHeight)
        }
        .frame(width: width, height: soundControlHeight, alignment: .leading)
    }

    private func speedPicker(value: Binding<Double>) -> some View {
        Menu {
            ForEach(AccelerandoConfig.multiplierOptions, id: \.self) { multiplier in
                Button {
                    value.wrappedValue = multiplier
                } label: {
                    if multiplier == value.wrappedValue {
                        Label(String(format: "%.1fx", multiplier), systemImage: "checkmark")
                    } else {
                        Text(String(format: "%.1fx", multiplier))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "hare.fill")
                    .font(.system(size: 5))
                    .foregroundColor(.white.opacity(0.24))
                    .frame(width: 7)

                Text(String(format: "%.1fx", value.wrappedValue))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 8)
            .frame(width: 92, height: soundControlHeight, alignment: .leading)
            .background(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .cornerRadius(4)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Target speed at session end")
    }

    // MARK: - Unified Sound Row (for transition sounds)

    private struct SoundRowConfig {
        var enabled: Binding<Bool>
        var sound: Binding<String>
        var volume: Binding<Float>
        var availableSounds: [String]
        var fallbackSound: String
    }

    private func bindingSoundConfig(forTransition keyPath: WritableKeyPath<SessionAwarenessConfig, TransitionSoundConfig>) -> SoundRowConfig {
        SoundRowConfig(
            enabled: Binding(
                get: { sessionAwarenessService.config[keyPath: keyPath].enabled },
                set: { sessionAwarenessService.config[keyPath: keyPath].enabled = $0 }
            ),
            sound: Binding(
                get: { sessionAwarenessService.config[keyPath: keyPath].sound },
                set: { sessionAwarenessService.config[keyPath: keyPath].sound = $0 }
            ),
            volume: Binding(
                get: { sessionAwarenessService.config[keyPath: keyPath].volume },
                set: { sessionAwarenessService.config[keyPath: keyPath].volume = $0 }
            ),
            availableSounds: TransitionSoundConfig.availableSounds,
            fallbackSound: SessionAwarenessConfig.default[keyPath: keyPath].sound == "Off"
                ? (TransitionSoundConfig.availableSounds.first ?? "Off")
                : SessionAwarenessConfig.default[keyPath: keyPath].sound
        )
    }

    private func soundRow(icon: String, iconColor: Color, label: String, config: SoundRowConfig, isAmbient: Bool) -> some View {
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(iconColor)
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 14, weight: .medium))

                Spacer(minLength: 8)

                Toggle("", isOn: Binding(
                    get: { config.enabled.wrappedValue },
                    set: { isEnabled in
                        config.enabled.wrappedValue = isEnabled
                        if isEnabled && config.sound.wrappedValue == "Off" {
                            config.sound.wrappedValue = config.fallbackSound
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            if config.enabled.wrappedValue {
                HStack(spacing: 8) {
                    soundSelectionPicker(selection: config.sound, availableSounds: config.availableSounds, width: nil) {
                        customSoundImportIsAmbient = isAmbient
                        showCustomSoundFilePanel()
                    }
                    .layoutPriority(1)

                    let previewID = "transition-\(label)"
                    iconButton(systemName: activePreviewID == previewID ? "stop.fill" : "play.fill", isEnabled: true) {
                        if activePreviewID == previewID {
                            stopPreview()
                        } else if isAmbient {
                            toggleAmbientPreview(
                                id: previewID,
                                sound: config.sound.wrappedValue,
                                volume: config.volume.wrappedValue
                            )
                        } else {
                            toggleTransitionPreview(
                                id: previewID,
                                sound: config.sound.wrappedValue,
                                volume: config.volume.wrappedValue
                            )
                        }
                    }
                    .help(activePreviewID == previewID ? "Stop preview" : "Preview")

                    volumeSlider(value: config.volume)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func iconButton(systemName: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9))
                .foregroundColor(isEnabled ? .white.opacity(0.6) : .white.opacity(0.22))
                .frame(width: soundControlHeight, height: soundControlHeight)
                .background(Color.white.opacity(isEnabled ? 0.1 : 0.03))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    private func accelerandoButton(isEnabled: Bool, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "waveform.path")
                .font(.system(size: 9))
                .foregroundColor(
                    isDisabled
                    ? .white.opacity(0.22)
                    : (isEnabled ? .orange : .white.opacity(0.6))
                )
                .frame(width: soundControlHeight, height: soundControlHeight)
                .background(Color.white.opacity(isDisabled ? 0.03 : 0.1))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    // MARK: - Custom Sound Import

    private func openCustomSoundImport(for _: WritableKeyPath<SessionAwarenessConfig, SessionSoundConfig>) {
        showCustomSoundFilePanel()
    }

    private func openTransitionSoundImport(for _: WritableKeyPath<SessionAwarenessConfig, TransitionSoundConfig>) {
        showCustomSoundFilePanel()
    }

    private func showCustomSoundFilePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.wav, .mp3, .aiff, .mpeg4Audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an audio file to import as a custom sound"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        pendingImportURL = url
        customSoundName = url.deletingPathExtension().lastPathComponent
        showingNamePrompt = true
    }

    private func finishCustomSoundImport() {
        guard let url = pendingImportURL, !customSoundName.isEmpty else { return }

        if let filePath = SessionAudioService.importCustomSound(from: url) {
            let entry = CustomSoundEntry(name: customSoundName, filePath: filePath)
            CustomSoundStore.shared.addEntry(entry)
        }

        pendingImportURL = nil
        customSoundName = ""
    }

    // MARK: - Sound Preview

    private func stopPreview() {
        previewResetWorkItem?.cancel()
        previewResetWorkItem = nil
        activePreviewID = nil
        sessionAudioService.resumeAfterPreview()
    }

    private func schedulePreviewReset(after delay: TimeInterval, id: String) {
        previewResetWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            if self.activePreviewID == id {
                self.activePreviewID = nil
                self.sessionAudioService.resumeAfterPreview()
            }
        }
        previewResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func toggleAmbientPreview(id: String, sound: String, volume: Float, accelConfig: AccelerandoConfig? = nil) {
        guard sound != "Off" else { return }
        if activePreviewID == id {
            stopPreview()
            return
        }
        stopPreview()
        activePreviewID = id
        previewAmbientSound(sound, volume: volume, accelConfig: accelConfig)
        schedulePreviewReset(after: previewDuration, id: id)
    }

    private func toggleTransitionPreview(id: String, sound: String, volume: Float) {
        guard sound != "Off" else { return }
        if activePreviewID == id {
            stopPreview()
            return
        }
        stopPreview()
        activePreviewID = id
        previewTransitionSound(sound, volume: volume)
        schedulePreviewReset(after: transitionPreviewDuration, id: id)
    }

    private func previewAmbientSound(_ sound: String, volume: Float, accelConfig: AccelerandoConfig? = nil) {
        guard sound != "Off" else { return }
        sessionAudioService.pauseForPreview()
        let config = SessionSoundConfig(sound: sound, volume: volume, enabled: true)
        sessionAudioService.playAmbient(config: config, ignoreMute: true)

        // Set fixed playback speed from multiplier
        let multiplier = accelConfig?.maxMultiplier ?? 1.0
        if multiplier != 1.0 {
            sessionAudioService.setFixedPlaybackRate(Float(multiplier))
        }

        // If accelerando enabled, demo the ramp effect over previewDuration seconds
        if let accel = accelConfig, accel.enabled, accel.maxMultiplier != 1.0 {
            let steps = 40
            let stepDuration = previewDuration / Double(steps)
            for i in 0...steps {
                let progress = Double(i) / Double(steps)
                DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(i)) {
                    self.sessionAudioService.updatePlaybackRate(progress: progress, accelerando: accel)
                }
            }
        }
    }

    private func previewTransitionSound(_ sound: String, volume: Float) {
        guard sound != "Off" else { return }
        sessionAudioService.pauseForPreview()
        let config = TransitionSoundConfig(sound: sound, volume: volume, enabled: true)
        sessionAudioService.playTransition(config: config, ignoreMute: true)
    }

    // MARK: - Utility

    private func formattedHourForSettings(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        var components = DateComponents()
        components.hour = hour % 24
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(hour % 24):00"
    }

    private func resetCalendarSetup() {
        UserDefaults.standard.set(false, forKey: "TaskScheduler.HasCompletedSetup")
        NotificationCenter.default.post(name: Notification.Name("ResetCalendarSetup"), object: nil)
    }

    private func resetPresets() {
        UserDefaults.standard.removeObject(forKey: "TaskScheduler.Presets")
        UserDefaults.standard.removeObject(forKey: "TaskScheduler.LastActivePresetID")
        timelineIntroBarDismissed = false
        UserDefaults.standard.set(false, forKey: "TaskScheduler.HasCompletedSetup")
        NotificationCenter.default.post(name: Notification.Name("PresetsReset"), object: nil)
        NotificationCenter.default.post(name: Notification.Name("ResetCalendarSetup"), object: nil)
        if let window = NSApp.windows.first(where: { $0.title == "Settings" }) {
            window.close()
        }
    }

    private func resetAwarenessSettings() {
        sessionAudioService.stopAmbient()
        let wasEnabled = sessionAwarenessService.config.enabled
        var freshConfig = SessionAwarenessConfig()
        freshConfig.enabled = wasEnabled
        sessionAwarenessService.config = freshConfig
        sessionAudioService.setOutputDevice(uid: nil)
    }

    private func resetCalendarPermissions() {
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Calendar", bundleId]
        do {
            try process.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
        } catch {
            print("Failed to reset permissions: \(error)")
        }
    }
}

#Preview {
    AppSettingsView()
        .environmentObject(SchedulingEngine())
        .environmentObject(CalendarService())
        .environmentObject(SessionAwarenessService())
        .environmentObject(SessionAudioService())
}

extension AppSettingsView {
    private func color(for calendar: EKCalendar) -> Color {
        if let cgColor = calendar.cgColor,
           let nsColor = NSColor(cgColor: cgColor) {
            return Color(nsColor: nsColor)
        }
        return .gray
    }

    private func handleCalendarToggle(for calendar: EKCalendar, included: Bool) {
        if included {
            calendarService.setCalendar(calendar, included: true)
            return
        }

        let affectedPresets = presetsUsingCalendar(calendar: calendar)
        guard !affectedPresets.isEmpty else {
            calendarService.setCalendar(calendar, included: false)
            return
        }

        let options = replacementOptions(excluding: calendar)
        guard !options.isEmpty else {
            replacementErrorMessage = "No other visible calendars are available to replace \"\(calendar.title)\". Create or enable another calendar first."
            return
        }

        selectedReplacementCalendarId = ""
        pendingReplacementContext = CalendarReplacementContext(calendar: calendar, affectedPresets: affectedPresets)
    }

    private func presetsUsingCalendar(calendar: EKCalendar) -> [Preset] {
        let presets = PresetStorage.shared.loadPresets()
        return presets.filter { preset in
            preset.calendarMapping.workCalendarIdentifier == calendar.calendarIdentifier ||
            (preset.calendarMapping.workCalendarIdentifier == nil && preset.calendarMapping.workCalendarName == calendar.title) ||
            preset.calendarMapping.sideCalendarIdentifier == calendar.calendarIdentifier ||
            (preset.calendarMapping.sideCalendarIdentifier == nil && preset.calendarMapping.sideCalendarName == calendar.title) ||
            preset.deepSessionConfig.calendarIdentifier == calendar.calendarIdentifier ||
            (preset.deepSessionConfig.calendarIdentifier == nil && preset.deepSessionConfig.calendarName == calendar.title)
        }
    }

    private func replacementOptions(excluding calendar: EKCalendar) -> [EKCalendar] {
        calendarService.availableCalendars.filter {
            $0.calendarIdentifier != calendar.calendarIdentifier &&
            !calendarService.isCalendarExcluded(identifier: $0.calendarIdentifier)
        }
    }

    private func confirmCalendarReplacement(for context: CalendarReplacementContext) {
        guard
            let replacement = calendarService.availableCalendars.first(where: { $0.calendarIdentifier == selectedReplacementCalendarId })
        else {
            replacementErrorMessage = "Select a replacement calendar before continuing."
            return
        }

        applyCalendarReplacement(
            oldCalendar: context.calendar,
            newCalendar: replacement,
            affectedPresetIDs: Set(context.affectedPresets.map { $0.id })
        )

        calendarService.setCalendar(context.calendar, included: false)
        pendingReplacementContext = nil
    }

    private func applyCalendarReplacement(oldCalendar: EKCalendar, newCalendar: EKCalendar, affectedPresetIDs: Set<UUID>) {
        var presets = PresetStorage.shared.loadPresets()
        var changed = false
        let newIdentifier = newCalendar.calendarIdentifier

        for index in presets.indices {
            guard affectedPresetIDs.contains(presets[index].id) else { continue }

            if presets[index].calendarMapping.workCalendarIdentifier == oldCalendar.calendarIdentifier ||
                (presets[index].calendarMapping.workCalendarIdentifier == nil && presets[index].calendarMapping.workCalendarName == oldCalendar.title) {
                presets[index].calendarMapping.workCalendarName = newCalendar.title
                presets[index].calendarMapping.workCalendarIdentifier = newIdentifier
                changed = true
            }
            if presets[index].calendarMapping.sideCalendarIdentifier == oldCalendar.calendarIdentifier ||
                (presets[index].calendarMapping.sideCalendarIdentifier == nil && presets[index].calendarMapping.sideCalendarName == oldCalendar.title) {
                presets[index].calendarMapping.sideCalendarName = newCalendar.title
                presets[index].calendarMapping.sideCalendarIdentifier = newIdentifier
                changed = true
            }
            if presets[index].deepSessionConfig.calendarIdentifier == oldCalendar.calendarIdentifier ||
                (presets[index].deepSessionConfig.calendarIdentifier == nil && presets[index].deepSessionConfig.calendarName == oldCalendar.title) {
                presets[index].deepSessionConfig.calendarName = newCalendar.title
                presets[index].deepSessionConfig.calendarIdentifier = newIdentifier
                changed = true
            }
        }

        if changed {
            PresetStorage.shared.savePresets(presets)
            NotificationCenter.default.post(name: Notification.Name("PresetsUpdated"), object: nil)
        }

        if schedulingEngine.workCalendarIdentifier == oldCalendar.calendarIdentifier ||
            (schedulingEngine.workCalendarIdentifier == nil && schedulingEngine.workCalendarName == oldCalendar.title) {
            schedulingEngine.workCalendarName = newCalendar.title
            schedulingEngine.workCalendarIdentifier = newIdentifier
        }
        if schedulingEngine.sideCalendarIdentifier == oldCalendar.calendarIdentifier ||
            (schedulingEngine.sideCalendarIdentifier == nil && schedulingEngine.sideCalendarName == oldCalendar.title) {
            schedulingEngine.sideCalendarName = newCalendar.title
            schedulingEngine.sideCalendarIdentifier = newIdentifier
        }
        if schedulingEngine.deepSessionConfig.calendarIdentifier == oldCalendar.calendarIdentifier ||
            (schedulingEngine.deepSessionConfig.calendarIdentifier == nil && schedulingEngine.deepSessionConfig.calendarName == oldCalendar.title) {
            var config = schedulingEngine.deepSessionConfig
            config.calendarName = newCalendar.title
            config.calendarIdentifier = newIdentifier
            schedulingEngine.deepSessionConfig = config
        }
    }

    private var replacementErrorBinding: Binding<Bool> {
        Binding(
            get: { replacementErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    replacementErrorMessage = nil
                }
            }
        )
    }
}

fileprivate struct SoundSelectionButton: NSViewRepresentable {
    @Binding var selection: String
    let availableSounds: [String]
    let onImport: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> SoundSelectionControl {
        let control = SoundSelectionControl()
        control.target = context.coordinator
        control.action = #selector(Coordinator.showMenu(_:))
        updateNSView(control, context: context)
        return control
    }

    func updateNSView(_ control: SoundSelectionControl, context: Context) {
        context.coordinator.parent = self
        let displayTitle = selection == "Off"
            ? (availableSounds.first ?? selection)
            : selection
        control.setTitle(displayTitle)
        control.toolTip = displayTitle
    }

    final class Coordinator: NSObject {
        var parent: SoundSelectionButton

        init(_ parent: SoundSelectionButton) {
            self.parent = parent
        }

        @objc func showMenu(_ sender: SoundSelectionControl) {
            let menu = NSMenu()
            menu.autoenablesItems = false

            addSection(title: "Standard", sounds: parent.availableSounds, to: menu)

            let customSounds = CustomSoundStore.shared.loadEntries()
            if !customSounds.isEmpty {
                menu.addItem(.separator())
                addSection(title: "Custom", sounds: customSounds.map(\.name), to: menu)
            }

            menu.addItem(.separator())

            let importItem = NSMenuItem(title: "Import Sound...", action: #selector(handleImport), keyEquivalent: "")
            importItem.target = self
            menu.addItem(importItem)

            let selectedItem = menu.items.first(where: { ($0.representedObject as? String) == parent.selection })
            menu.popUp(positioning: selectedItem, at: NSPoint(x: 0, y: sender.bounds.height - 2), in: sender)
        }

        private func addSection(title: String, sounds: [String], to menu: NSMenu) {
            let headerItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            menu.addItem(headerItem)

            for sound in sounds {
                let item = NSMenuItem(title: sound, action: #selector(handleSelection(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = sound
                item.state = sound == parent.selection ? .on : .off
                menu.addItem(item)
            }
        }

        @objc private func handleSelection(_ sender: NSMenuItem) {
            guard let sound = sender.representedObject as? String else { return }
            parent.selection = sound
        }

        @objc private func handleImport() {
            DispatchQueue.main.async {
                self.parent.onImport()
            }
        }
    }
}

fileprivate final class SoundSelectionControl: NSControl {
    private let titleField = NSTextField(labelWithString: "")
    private let chevronView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 60, height: 22)
    }

    private func setup() {
        focusRingType = .none
        wantsLayer = true
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        layer?.cornerRadius = 4
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = .systemFont(ofSize: 13)
        titleField.textColor = NSColor.white.withAlphaComponent(0.92)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Show sounds")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium))
        chevronView.contentTintColor = NSColor.white.withAlphaComponent(0.5)

        addSubview(titleField)
        addSubview(chevronView)

        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -8),
            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func setTitle(_ title: String) {
        titleField.stringValue = title
    }

    override func mouseDown(with event: NSEvent) {
        if let action {
            NSApp.sendAction(action, to: target, from: self)
        }
    }
}

private struct CalendarReplacementContext: Identifiable {
    let calendar: EKCalendar
    let affectedPresets: [Preset]

    var id: String { calendar.calendarIdentifier }
}

private struct CalendarReplacementSheet: View {
    let context: CalendarReplacementContext
    let replacementOptions: [EKCalendar]
    @Binding var selectedCalendarId: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reassign Calendar")
                .font(.title2)
                .fontWeight(.bold)

            Text("\"\(context.calendar.title)\" is used in the presets below. Choose a replacement calendar before hiding it.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            if !context.affectedPresets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Affected Presets (\(context.affectedPresets.count))")
                        .font(.headline)
                    ForEach(context.affectedPresets) { preset in
                        HStack(spacing: 6) {
                            Image(systemName: preset.icon)
                                .foregroundColor(.accentColor)
                                .frame(width: 18)
                            Text(preset.name)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(8)
                    }
                }
            }

            Picker("Replacement Calendar", selection: $selectedCalendarId) {
                Text("Select a calendar...").tag("")
                ForEach(replacementOptions, id: \.calendarIdentifier) { option in
                    Text(option.title).tag(option.calendarIdentifier)
                }
            }
            .pickerStyle(.menu)

            Spacer(minLength: 0)

            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                Spacer()
                Button("Replace & Hide") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCalendarId.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 380)
    }
}


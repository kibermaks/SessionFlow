import SwiftUI

struct CalendarSetupView: View {
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var schedulingEngine: SchedulingEngine
    
    @State private var selectedWorkCalendar: String = ""
    @State private var selectedSideCalendar: String = ""
    @State private var selectedDeepCalendar: String = ""
    @State private var selectedWorkCalendarId: String = ""
    @State private var selectedSideCalendarId: String = ""
    @State private var selectedDeepCalendarId: String = ""
    @State private var workDuration: Int = 40
    @State private var restDuration: Int = 10
    @State private var basicSessions: Int = 5
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isCompleting = false
    @State private var isReloading = false
    
    var canComplete: Bool {
        !selectedWorkCalendar.isEmpty &&
        !selectedSideCalendar.isEmpty &&
        !selectedDeepCalendar.isEmpty &&
        !selectedWorkCalendarId.isEmpty &&
        !selectedSideCalendarId.isEmpty &&
        !selectedDeepCalendarId.isEmpty
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(hex: "0F172A"), Color(hex: "1E293B")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Main content container with frosted glass effect
            VStack(spacing: 0) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quick Setup")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Configure your sessions and calendars")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    // Info badge
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 12))
                        Text("All settings can be changed later")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Color(hex: "60A5FA"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(hex: "3B82F6").opacity(0.15))
                    .cornerRadius(8)
                }
                .padding(.horizontal, 32)
                .padding(.top, 32)
                .padding(.bottom, 20)
                
                // Content
                ScrollView {
                    VStack(spacing: 28) {
                        // SECTION 1: Session Defaults
                        sessionConfigurationCard()
                        
                        // SECTION 2: Calendar Selection
                        VStack(alignment: .leading, spacing: 16) {
                            // Section header with reload button
                            HStack {
                                Text("Calendars")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white.opacity(0.9))
                                
                                Text("Where sessions will be created")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.5))
                                
                                Spacer()
                                
                                // Reload button
                                Button {
                                    reloadCalendars()
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 11, weight: .semibold))
                                            .rotationEffect(.degrees(isReloading ? 360 : 0))
                                            .animation(isReloading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isReloading)
                                        Text("Reload")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                                .disabled(isReloading)
                                .help("Reload after adding new calendars in Calendar.app")
                            }
                            .padding(.horizontal, 32)
                            
                            // Calendar cards
                            VStack(spacing: 16) {
                                calendarSelectionCard(
                                    title: "Work Sessions",
                                    icon: "briefcase.fill",
                                    color: Color(hex: "8B5CF6"),
                                    description: "Primary focus blocks for important tasks",
                                    tag: "#work",
                                    selectedCalendar: $selectedWorkCalendar,
                                    selectedCalendarId: $selectedWorkCalendarId
                                )
                                
                                calendarSelectionCard(
                                    title: "Side Sessions",
                                    icon: "star.fill",
                                    color: Color(hex: "3B82F6"),
                                    description: "Life admin, emails, and quick errands",
                                    tag: "#side",
                                    selectedCalendar: $selectedSideCalendar,
                                    selectedCalendarId: $selectedSideCalendarId
                                )
                                
                                calendarSelectionCard(
                                    title: "Deep Work Sessions",
                                    icon: "bolt.circle.fill",
                                    color: Color(hex: "10B981"),
                                    description: "Rare, high-intensity focus blocks",
                                    tag: "#deep",
                                    selectedCalendar: $selectedDeepCalendar,
                                    selectedCalendarId: $selectedDeepCalendarId
                                )
                            }
                        }
                    }
                    .padding(.bottom, 32)
                }
                
                // Footer
                VStack(spacing: 16) {
                    if showError {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Color(hex: "EF4444"))
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 32)
                    }
                    
                    Button {
                        completeSetup()
                    } label: {
                        HStack(spacing: 12) {
                            if isCompleting {
                                ProgressView()
                                    .scaleEffect(0.9)
                                    .tint(.white)
                            }
                            Text(isCompleting ? "Completing..." : "Complete Setup")
                                .font(.system(size: 17, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    canComplete ?
                                    LinearGradient(
                                        colors: [Color(hex: "10B981"), Color(hex: "059669")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ) :
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: canComplete ? Color(hex: "10B981").opacity(0.5) : .clear, radius: 15, y: 8)
                        )
                        .opacity(canComplete ? 1.0 : 0.5)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canComplete || isCompleting)
                    .padding(.horizontal, 32)
                }
                .padding(.bottom, 32)
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(hex: "1E293B").opacity(0.95))
                    .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .padding(40)
            .frame(width: 800)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            calendarService.loadCalendars()
            loadAvailableCalendars()
        }
    }
    
    private func sessionConfigurationCard() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Text("Session Defaults")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                
                Text("How your day is structured")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                
                Spacer()
            }
            .padding(.horizontal, 32)
            
            // Inputs card
            HStack(alignment: .top, spacing: 32) {
                // Work Sessions
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sessions")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                    
                    NumericInputField(
                        value: $basicSessions,
                        range: 2...12,
                        step: 1,
                        unit: "/day"
                    )
                }
                
                // Work Duration
                VStack(alignment: .leading, spacing: 6) {
                    Text("Duration")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                    
                    NumericInputField(
                        value: $workDuration,
                        range: 15...120,
                        step: 5,
                        unit: "min"
                    )
                }
                
                // Rest Duration
                VStack(alignment: .leading, spacing: 6) {
                    Text("Rest")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                    
                    NumericInputField(
                        value: $restDuration,
                        range: 5...30,
                        step: 5,
                        unit: "min"
                    )
                }
                
                Spacer()
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 32)
        }
    }
    
    private func calendarSelectionCard(
        title: String,
        icon: String,
        color: Color,
        description: String,
        tag: String,
        selectedCalendar: Binding<String>,
        selectedCalendarId: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        LinearGradient(
                            colors: [color.opacity(0.8), color.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
                    .shadow(color: color.opacity(0.3), radius: 8, y: 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Text(description)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                Text(tag)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(color.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            
            // Calendar picker
            HStack(spacing: 10) {
                Text("Calendar")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                CalendarPickerPopover(
                    selectedCalendar: selectedCalendar,
                    calendars: calendarService.calendarInfoList(),
                    accentColor: color,
                    onSelection: { info in
                        selectedCalendar.wrappedValue = info.name
                        selectedCalendarId.wrappedValue = info.id
                    }
                )
            }
        }
        .padding(26)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            LinearGradient(
                                colors: [color.opacity(0.6), color.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: color.opacity(0.15), radius: 12, y: 6)
        )
        .padding(.horizontal, 32)
    }
    
    private func loadAvailableCalendars() {
        let calendars = calendarService.calendarNames()
        guard !calendars.isEmpty else { return }
        
        func assign(_ name: String, to idStorage: inout String) {
            if let calendar = calendarService.availableCalendars.first(where: { $0.title == name }) {
                idStorage = calendar.calendarIdentifier
            } else {
                idStorage = ""
            }
        }
        
        func prioritizedMatch(from candidates: [String], keywords: [String]) -> String? {
            // 1. Look for exact matches, in priority order
            for keyword in keywords {
                if let exact = candidates.first(where: { $0.lowercased() == keyword.lowercased() }) {
                    return exact
                }
            }
            // 2. Otherwise, look for first by keyword in order (not exact, substring, but respect keyword priority)
            for keyword in keywords {
                if let contains = candidates.first(where: { $0.lowercased().contains(keyword.lowercased()) }) {
                    return contains
                }
            }
            // 3. Fallback
            return nil
        }
        
        // Work: prioritize "work" then "tasks"
        if selectedWorkCalendar.isEmpty {
            let workKeywords = ["work", "tasks"]
            if let match = prioritizedMatch(from: calendars, keywords: workKeywords) {
                selectedWorkCalendar = match
                assign(match, to: &selectedWorkCalendarId)
            } else if let first = calendars.first {
                selectedWorkCalendar = first
                assign(first, to: &selectedWorkCalendarId)
            }
        } else if selectedWorkCalendarId.isEmpty {
            assign(selectedWorkCalendar, to: &selectedWorkCalendarId)
        }

        // Side: prioritize "side" then "admin" then "personal"
        if selectedSideCalendar.isEmpty {
            let sideKeywords = ["side", "admin", "personal"]
            if let match = prioritizedMatch(from: calendars, keywords: sideKeywords) {
                selectedSideCalendar = match
                assign(match, to: &selectedSideCalendarId)
            } else if calendars.count > 1 {
                selectedSideCalendar = calendars[1]
                assign(calendars[1], to: &selectedSideCalendarId)
            } else if let first = calendars.first {
                selectedSideCalendar = first
                assign(first, to: &selectedSideCalendarId)
            }
        } else if selectedSideCalendarId.isEmpty {
            assign(selectedSideCalendar, to: &selectedSideCalendarId)
        }
        
        // Deep: prioritize "deep" then "focus" then "work"
        if selectedDeepCalendar.isEmpty {
            let deepKeywords = ["deep", "focus", "work"]
            if let match = prioritizedMatch(from: calendars, keywords: deepKeywords) {
                selectedDeepCalendar = match
                assign(match, to: &selectedDeepCalendarId)
            } else if calendars.count > 2 {
                selectedDeepCalendar = calendars[2]
                assign(calendars[2], to: &selectedDeepCalendarId)
            } else if let first = calendars.first {
                selectedDeepCalendar = first
                assign(first, to: &selectedDeepCalendarId)
            }
        } else if selectedDeepCalendarId.isEmpty {
            assign(selectedDeepCalendar, to: &selectedDeepCalendarId)
        }
    }
    
    private func reloadCalendars() {
        isReloading = true
        calendarService.loadCalendars()
        
        // Give a brief moment for the animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isReloading = false
            loadAvailableCalendars()
        }
    }
    
    private func completeSetup() {
        // Validate selections
        guard !selectedWorkCalendar.isEmpty,
              !selectedSideCalendar.isEmpty,
              !selectedDeepCalendar.isEmpty else {
            errorMessage = "Please select a calendar for each session type"
            showError = true
            return
        }
        
        isCompleting = true
        
        // Initialize presets with the selected calendars and configuration (this is the key step!)
        PresetStorage.shared.initializePresets(
            workCalendar: selectedWorkCalendar,
            sideCalendar: selectedSideCalendar,
            deepCalendar: selectedDeepCalendar,
            workCalendarId: selectedWorkCalendarId,
            sideCalendarId: selectedSideCalendarId,
            deepCalendarId: selectedDeepCalendarId,
            workDuration: workDuration,
            restDuration: restDuration,
            basicSessions: basicSessions
        )
        
        // Save to scheduling engine for backward compatibility
        schedulingEngine.workCalendarName = selectedWorkCalendar
        schedulingEngine.sideCalendarName = selectedSideCalendar
        schedulingEngine.workCalendarIdentifier = selectedWorkCalendarId
        schedulingEngine.sideCalendarIdentifier = selectedSideCalendarId
        
        // Update deep session config
        var deepConfig = schedulingEngine.deepSessionConfig
        deepConfig.calendarName = selectedDeepCalendar
        deepConfig.calendarIdentifier = selectedDeepCalendarId
        schedulingEngine.deepSessionConfig = deepConfig
        
        // Give a moment for all saves to complete, then mark setup as complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Mark setup as complete
            UserDefaults.standard.set(true, forKey: "SessionFlow.HasCompletedSetup")
            
            // Trigger refresh notification
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: Notification.Name("SetupCompleted"), object: nil)
                isCompleting = false
            }
        }
    }
}

#Preview {
    CalendarSetupView()
        .environmentObject(CalendarService())
        .environmentObject(SchedulingEngine())
}

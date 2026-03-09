import SwiftUI
import AppKit
import Combine

struct SettingsPanel: View {
    @EnvironmentObject var schedulingEngine: SchedulingEngine
    @EnvironmentObject var calendarService: CalendarService
    
    @Binding var hasSeenPatternsGuide: Bool
    @Binding var showingPatternsGuide: Bool
    var isLocked: Bool = false

    @State private var showingWorkHelp = false
    @State private var showingSideHelp = false
    @State private var showingDeepHelp = false
    @State private var showingFlexibleSideHelp = false
    @State private var showingPlanningHelp = false
    @State private var showingPatternHelp = false
    @State private var showingRestHelp = false
    @State private var showingBigRestHelp = false
    
    @StateObject private var nameHistory = SessionNameHistory.shared

    @AppStorage("settings.workExpanded") private var workExpanded = true
    @AppStorage("settings.sideExpanded") private var sideExpanded = true
    @AppStorage("settings.patternExpanded") private var patternExpanded = true
    @AppStorage("settings.deepExpanded") private var deepExpanded = true
    @AppStorage("settings.restExpanded") private var restExpanded = true
    @AppStorage("settings.longRestExpanded") private var longRestExpanded = true

    private let workHelpText = "Work sessions are your primary focus blocks. Use these for your main professional tasks or projects that require sustained concentration."
    private let sideHelpText = "Side sessions are for secondary tasks or 'life admin'. Perfect for paying bills, checking something new, responding to emails, or handling quick errands."
    private let deepHelpText = "Deep sessions (often called Deep Work) are rare, high-intensity focus blocks. You want to inject these periodically for your most demanding creative or analytical work that requires additional focus."
    private let flexibleSideHelpText = "Try to fit side sessions into smaller time gaps when work sessions don't fit. By default it's enabled to help you fit more sessions and finish your day earlier."
    private let planningHelpText = "The Planning session is a short block at the start of your day to review your actual tasks and organize them into your sequence. It ensures you start with clarity."
    private let patternHelpText = "Scheduling patterns define how Work and Side sessions are interleaved. Various patterns work best for different situations(e.g. weekends, workdays, meeting days, etc.)."
    private let restHelpText = "Rest intervals are crucial for maintaining peak performance. Choose different durations for after-work, after-side, or after-deep sessions to recharge effectively."
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Planning Section
                planningSection
                
                Divider().background(Color.white.opacity(0.1))
                
                sessionSection(
                    title: "Work Sessions",
                    icon: "briefcase.fill",
                    iconColor: Color(hex: "8B5CF6"),
                    count: $schedulingEngine.workSessions,
                    name: $schedulingEngine.workSessionName,
                    duration: $schedulingEngine.workSessionDuration,
                    calendar: $schedulingEngine.workCalendarName,
                    helpText: workHelpText,
                    isShowingHelp: $showingWorkHelp,
                    isExpanded: $workExpanded,
                    sessionType: .work,
                    onCalendarSelected: { info in
                        schedulingEngine.workCalendarIdentifier = info.identifier
                        schedulingEngine.workCalendarName = info.name
                    }
                )
                
                Divider().background(Color.white.opacity(0.1))
                
                // Side Sessions Section
                sessionSection(
                    title: "Side Sessions",
                    icon: "star.fill",
                    iconColor: Color(hex: "3B82F6"),
                    count: $schedulingEngine.sideSessions,
                    name: $schedulingEngine.sideSessionName,
                    duration: $schedulingEngine.sideSessionDuration,
                    calendar: $schedulingEngine.sideCalendarName,
                    helpText: sideHelpText,
                    isShowingHelp: $showingSideHelp,
                    isExpanded: $sideExpanded,
                    sessionType: .side,
                    onCalendarSelected: { info in
                        schedulingEngine.sideCalendarIdentifier = info.identifier
                        schedulingEngine.sideCalendarName = info.name
                    }
                )
                
                Divider().background(Color.white.opacity(0.1))
                
                // Pattern Section
                patternSection
                
                Divider().background(Color.white.opacity(0.1))
                
                // Deep Sessions Section
                deepSessionSection
                Divider().background(Color.white.opacity(0.1))
                
                // Rest Section
                restSection
                Divider().background(Color.white.opacity(0.1))

                // Long Rest Section
                longRestSection
            }
            .padding()
            .disabled(isLocked)
        }
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
    }
    
    // MARK: - Timeline Visibility Section
    
    private var timelineVisibilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "eye.fill")
                    .foregroundColor(Color(hex: "3B82F6"))
                Text("Timeline View")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            Toggle(isOn: $schedulingEngine.hideNightHours) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hide night hours")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                    Text(schedulingEngine.hideNightHours ? "Showing \(formattedHour(schedulingEngine.dayStartHour)) - \(schedulingEngine.scheduleEndHour > 24 ? "+1d " : "")\(formattedHour(schedulingEngine.scheduleEndHour))" : "Showing full 24h")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .toggleStyle(.switch)
            .tint(Color(hex: "3B82F6"))

            if schedulingEngine.hideNightHours {
                VStack(spacing: 8) {
                    HStack {
                        Text("Morning Edge:")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                        NumericInputField(value: $schedulingEngine.dayStartHour, range: 0...12, unit: "h")
                    }

                    Text("Night edge controlled by Schedule Until in Settings")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .italic()
                }
                .padding(.leading, 8)
            }

        }
    }

    // MARK: - Schedule Until Section

    private var scheduleUntilSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "moon.fill")
                    .foregroundColor(.orange)
                Text("Schedule Until")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            HStack {
                Text("End hour:")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                if schedulingEngine.scheduleEndHour > 24 {
                    Text("+1d \(formattedHour(schedulingEngine.scheduleEndHour))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                }
                NumericInputField(value: $schedulingEngine.scheduleEndHour, range: 13...30, unit: "h")
            }
            .help("When to stop placing sessions. Values above 24 extend into the next day.")
        }
    }

    private func formattedHour(_ hour: Int) -> String {
        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = hour % 24
        
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        
        if let date = calendar.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(hour):00"
    }
    
    
    
    // MARK: - Planning Section
    
    private var planningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(Color(hex: "EF4444"))
                Text("Planning Session")
                    .font(.headline)
                    .foregroundColor(.white)

                Button {
                    showingPlanningHelp.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingPlanningHelp) {
                    Text(planningHelpText)
                        .font(.system(size: 13))
                        .padding()
                        .frame(width: 250)
                }

                Spacer()
                Toggle("", isOn: $schedulingEngine.schedulePlanning)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Color(hex: "EF4444"))
            }

            if schedulingEngine.schedulePlanning {
                HStack {
                    Text("Duration:")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))

                    Spacer()

                    NumericInputField(
                        value: $schedulingEngine.planningDuration,
                        range: 5...60,
                        step: 5,
                        unit: "min"
                    )
                }
            }
        }
    }
    
    // MARK: - Session Section (Generic)
    
    private func sessionSection(
        title: String,
        icon: String,
        iconColor: Color,
        count: Binding<Int>,
        name: Binding<String>,
        duration: Binding<Int>,
        calendar: Binding<String>,
        helpText: String,
        isShowingHelp: Binding<Bool>,
        isExpanded: Binding<Bool>,
        sessionType: SessionType,
        onCalendarSelected: @escaping (CalendarService.CalendarInfo) -> Void
    ) -> some View {
        let secondaryTooltip = "Duration: \(duration.wrappedValue) min\nCalendar: \(calendar.wrappedValue)"

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)

                Button {
                    isShowingHelp.wrappedValue.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .popover(isPresented: isShowingHelp) {
                    Text(helpText)
                        .font(.system(size: 13))
                        .padding()
                        .frame(width: 250)
                }

                SectionExpandButton(isExpanded: isExpanded, tooltip: secondaryTooltip)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            }

            // Count — essential
            HStack {
                Text("Count:")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))

                Spacer()

                NumericInputField(value: count, range: 0...15)
            }

            // Name — essential
            NameFieldWithHistory(
                label: "Name:",
                text: name,
                sessionType: sessionType,
                placeholder: "Session name"
            )

            // Secondary fields
            if isExpanded.wrappedValue {
                HStack {
                    Text("Duration:")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))

                    Spacer()

                    NumericInputField(
                        value: duration,
                        range: 10...120,
                        step: 5,
                        unit: "min"
                    )
                }

                HStack {
                    Text("Calendar:")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))

                    Spacer()

                    CalendarPickerCompact(
                        selectedCalendar: calendar,
                        calendars: calendarService.calendarInfoList(includeExcluded: true),
                        accentColor: iconColor,
                        onSelection: onCalendarSelected
                    )
                    .frame(width: 150)
                }
            }
        }
    }
    
    // MARK: - Pattern Section
    
    private var patternSecondaryTooltip: String {
        var lines: [String] = []
        if [.alternating, .alternatingReverse, .customRatio].contains(schedulingEngine.pattern) {
            lines.append("Work per cycle: \(schedulingEngine.workSessionsPerCycle)")
        }
        if [.customRatio, .sidesFirstAndLast].contains(schedulingEngine.pattern) {
            lines.append("Side per cycle: \(schedulingEngine.sideSessionsPerCycle)")
        }
        if schedulingEngine.pattern == .customRatio {
            lines.append("Side First: \(schedulingEngine.sideFirst ? "On" : "Off")")
        }
        lines.append("Flexible Side: \(schedulingEngine.flexibleSideScheduling ? "On" : "Off")")
        return lines.joined(separator: "\n")
    }

    private var patternSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundColor(Color(hex: "10B981"))
                Text("Scheduling Pattern")
                    .font(.headline)
                    .foregroundColor(.white)

                Button {
                    showingPatternHelp.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingPatternHelp) {
                    Text(patternHelpText)
                        .font(.system(size: 13))
                        .padding()
                        .frame(width: 250)
                }

                if hasSeenPatternsGuide {
                    SectionExpandButton(isExpanded: $patternExpanded, tooltip: patternSecondaryTooltip)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if hasSeenPatternsGuide {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        patternExpanded.toggle()
                    }
                }
            }

            if !hasSeenPatternsGuide {
                Button {
                    showingPatternsGuide = true
                    hasSeenPatternsGuide = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Reveal options")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "10B981"))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.05))
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.ultraThinMaterial)
                                    .opacity(0.5)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(hex: "10B981").opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    // Pattern picker — essential
                    HStack {
                        Text("Pattern:")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Picker("", selection: $schedulingEngine.pattern) {
                            ForEach(SchedulePattern.allCases) { pattern in
                                HStack {
                                    Image(systemName: pattern.icon)
                                    Text(pattern.rawValue)
                                }
                                .tag(pattern)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200, height: 24)
                    }

                    // Secondary fields
                    if patternExpanded {
                        Text(schedulingEngine.pattern.description)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                        if [.alternating, .alternatingReverse, .customRatio].contains(schedulingEngine.pattern) {
                            HStack {
                                Text("Work per cycle:")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.7))

                                Spacer()

                                NumericInputField(value: $schedulingEngine.workSessionsPerCycle, range: 1...5)
                            }
                        }

                        if [.customRatio, .sidesFirstAndLast].contains(schedulingEngine.pattern) {
                            HStack {
                                Text("Side per cycle:")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.7))

                                Spacer()

                                NumericInputField(value: $schedulingEngine.sideSessionsPerCycle, range: 1...5)
                            }
                        }

                        if schedulingEngine.pattern == .customRatio {
                            Toggle("Side First", isOn: $schedulingEngine.sideFirst)
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.7))
                                .toggleStyle(.switch)
                                .tint(Color(hex: "3B82F6"))
                        }

                        Divider().background(Color.white.opacity(0.05))

                        HStack(spacing: 8) {
                            Text("Flexible Side Scheduling")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.7))
                            Button {
                                showingFlexibleSideHelp.toggle()
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showingFlexibleSideHelp) {
                                Text(flexibleSideHelpText)
                                    .font(.system(size: 13))
                                    .padding()
                                    .frame(width: 250)
                            }
                            Spacer()

                            Toggle("", isOn: $schedulingEngine.flexibleSideScheduling)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .tint(Color(hex: "3B82F6"))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Deep Sessions Section
    
    private var deepSecondaryTooltip: String {
        var lines = ["Duration: \(schedulingEngine.deepSessionConfig.duration) min"]
        lines.append("Inject after: \(schedulingEngine.deepSessionConfig.injectAfterEvery) slots")
        if schedulingEngine.deepSessionConfig.sessionCount > 1 {
            lines.append("And then after: \(schedulingEngine.deepSessionConfig.andThenGap) slots")
        }
        lines.append("Calendar: \(schedulingEngine.deepSessionConfig.calendarName)")
        return lines.joined(separator: "\n")
    }

    private var deepSessionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.circle.fill")
                        .foregroundColor(Color(hex: "10B981"))
                    Text("Deep Sessions")
                        .font(.headline)
                        .foregroundColor(.white)

                    Button {
                        showingDeepHelp.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingDeepHelp) {
                        Text(deepHelpText)
                            .font(.system(size: 13))
                            .padding()
                            .frame(width: 250)
                    }

                    SectionExpandButton(isExpanded: $deepExpanded, tooltip: deepSecondaryTooltip)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        deepExpanded.toggle()
                    }
                }

                Spacer()
                Toggle("", isOn: $schedulingEngine.deepSessionConfig.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Color(hex: "10B981"))
            }

            if schedulingEngine.deepSessionConfig.enabled {
                // Essential fields
                HStack {
                    Text("Count:")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    NumericInputField(value: $schedulingEngine.deepSessionConfig.sessionCount, range: 1...10)
                }

                NameFieldWithHistory(
                    label: "Name:",
                    text: $schedulingEngine.deepSessionConfig.name,
                    sessionType: .deep,
                    placeholder: "Name"
                )

                // Secondary fields
                if deepExpanded {
                    HStack {
                        Text("Duration:")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        NumericInputField(value: $schedulingEngine.deepSessionConfig.duration, range: 5...180, step: 5, unit: "min")
                    }

                    HStack {
                        Text("Inject after:")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        NumericInputField(value: $schedulingEngine.deepSessionConfig.injectAfterEvery, range: 0...10, unit: "slots")
                    }

                    if schedulingEngine.deepSessionConfig.sessionCount > 1 {
                        HStack {
                            Text("And then after:")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            NumericInputField(value: $schedulingEngine.deepSessionConfig.andThenGap, range: 0...10, unit: "slots")
                        }
                        .help("Regular sessions between consecutive deep sessions (0 = back to back)")
                    }

                    HStack {
                        Text("Calendar:")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        CalendarPickerCompact(
                            selectedCalendar: $schedulingEngine.deepSessionConfig.calendarName,
                            calendars: calendarService.calendarInfoList(includeExcluded: true),
                            accentColor: Color(hex: "10B981"),
                            onSelection: { info in
                                var config = schedulingEngine.deepSessionConfig
                                config.calendarName = info.name
                                config.calendarIdentifier = info.identifier
                                schedulingEngine.deepSessionConfig = config
                            }
                        )
                        .frame(width: 150)
                    }
                }
            }
        }
    }
    
    // MARK: - Rest Section
    
    private var restSecondaryTooltip: String {
        "After Work: \(schedulingEngine.restDuration) min\nAfter Side: \(schedulingEngine.sideRestDuration) min\nAfter Deep: \(schedulingEngine.deepRestDuration) min"
    }

    private var restSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "cup.and.saucer.fill")
                    .foregroundColor(Color(hex: "F59E0B"))
                Text("Rest Between Sessions")
                    .font(.headline)
                    .foregroundColor(.white)

                Button {
                    showingRestHelp.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingRestHelp) {
                    Text(restHelpText)
                        .font(.system(size: 13))
                        .padding()
                        .frame(width: 250)
                }

                SectionExpandButton(isExpanded: $restExpanded, tooltip: restSecondaryTooltip)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    restExpanded.toggle()
                }
            }

            if restExpanded {
                HStack {
                    Text("After Work:")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    NumericInputField(value: $schedulingEngine.restDuration, range: 0...60, step: 5, unit: "min")
                }

                HStack {
                    Text("After Side:")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    NumericInputField(value: $schedulingEngine.sideRestDuration, range: 0...60, step: 5, unit: "min")
                }

                HStack {
                    Text("After Deep:")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    NumericInputField(value: $schedulingEngine.deepRestDuration, range: 0...60, step: 5, unit: "min")
                }
            }
        }
    }

    private var longRestSecondaryTooltip: String {
        "Duration: \(schedulingEngine.bigRestConfig.duration) min\nAfter: \(schedulingEngine.bigRestConfig.afterMinutes) min"
    }

    private var longRestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "pause.circle.fill")
                        .foregroundColor(Color(hex: "F59E0B"))
                    Text("Long Rest")
                        .font(.headline)
                        .foregroundColor(.white)

                    Button {
                        showingBigRestHelp.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingBigRestHelp) {
                        Text("A longer rest period injected after sustained focus time. Helps prevent burnout during long work days. The break appears as a gap between calendar events — it won't create an event itself.")
                            .font(.system(size: 13))
                            .padding()
                            .frame(width: 260)
                    }

                    SectionExpandButton(isExpanded: $longRestExpanded, tooltip: longRestSecondaryTooltip)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        longRestExpanded.toggle()
                    }
                }

                Spacer()
                Toggle("", isOn: $schedulingEngine.bigRestConfig.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Color(hex: "F59E0B"))
            }

            if schedulingEngine.bigRestConfig.enabled {
                // Essential
                HStack {
                    Text("Count:")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    NumericInputField(value: $schedulingEngine.bigRestConfig.count, range: 1...5, step: 1, unit: "")
                }

                // Secondary
                if longRestExpanded {
                    HStack {
                        Text("Duration:")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        NumericInputField(value: $schedulingEngine.bigRestConfig.duration, range: 15...120, step: 5, unit: "min")
                    }

                    HStack {
                        Text("After:")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        NumericInputField(value: $schedulingEngine.bigRestConfig.afterMinutes, range: 30...480, step: 15, unit: "min")
                    }
                }
            }
        }
    }
}

// MARK: - Section Expand Button

struct SectionExpandButton: View {
    @Binding var isExpanded: Bool
    var tooltip: String = ""

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.2), value: isExpanded)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(false)
        .help(isExpanded ? "" : tooltip)
    }
}

// MARK: - Name Field with Suggestions
struct NameFieldWithHistory: View {
    let label: String
    @Binding var text: String
    let sessionType: SessionType
    let placeholder: String
    
    @StateObject private var nameHistory = SessionNameHistory.shared
    @StateObject private var suggestionModel = SuggestionsModel<String>()
    
    private var accentColor: Color {
        switch sessionType {
        case .work: return Color(hex: "8B5CF6")
        case .side: return Color(hex: "3B82F6")
        case .deep: return Color(hex: "10B981")
        default: return .blue
        }
    }
    
    private var suggestionGroups: [SuggestionGroup<String>] {
        let names = nameHistory.getNames(for: sessionType)
        if names.isEmpty { return [] }
        // Create suggestions from history
        // Add current text if not empty and not in history? No, strict history.
        let suggestions = names.map { Suggestion(text: $0, value: $0) }
        return [SuggestionGroup(title: "History", suggestions: suggestions)]
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
            
            Spacer()
            
            // Match NumericInputField styling and calendar dropdown width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(suggestionModel.isFocused ? 0.2 : 0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(suggestionModel.isFocused ? 0.4 : 0), lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                SuggestionInputWithModel(
                    text: $text,
                    model: suggestionModel,
                    suggestionGroups: suggestionGroups,
                    placeholder: placeholder,
                    accentColor: accentColor,
                    onDelete: { name in
                        nameHistory.removeName(name, from: sessionType)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 8)
            }
            .frame(width: 150, height: 24)
        }
    }
}

// MARK: - Session Name History Manager
class SessionNameHistory: ObservableObject {
    static let shared = SessionNameHistory()
    
    private let workKey = "SessionFlow.WorkSessionNames"
    private let sideKey = "SessionFlow.SideSessionNames"
    private let deepKey = "SessionFlow.DeepSessionNames"
    
    @Published var workNames: [String] = []
    @Published var sideNames: [String] = []
    @Published var deepNames: [String] = []
    
    private init() {
        loadNames()
    }
    
    private func loadNames() {
        workNames = UserDefaults.standard.stringArray(forKey: workKey) ?? []
        sideNames = UserDefaults.standard.stringArray(forKey: sideKey) ?? []
        deepNames = UserDefaults.standard.stringArray(forKey: deepKey) ?? []
    }
    
    func addName(_ name: String, for type: SessionType) {
        guard !name.isEmpty else { return }
        
        var names: [String]
        let key: String
        
        switch type {
        case .work:
            names = workNames
            key = workKey
        case .side:
            names = sideNames
            key = sideKey
        case .deep:
            names = deepNames
            key = deepKey
        default:
            return
        }
        
        // Remove if exists and add to front (most recent first)
        names.removeAll { $0 == name }
        names.insert(name, at: 0)
        
        // Limit to 20 most recent
        if names.count > 20 {
            names = Array(names.prefix(20))
        }
        
        UserDefaults.standard.set(names, forKey: key)
        
        switch type {
        case .work:
            workNames = names
        case .side:
            sideNames = names
        case .deep:
            deepNames = names
        default:
            break
        }
    }
    
    func removeName(_ name: String, from type: SessionType) {
        var names: [String]
        let key: String
        
        switch type {
        case .work:
            names = workNames
            key = workKey
        case .side:
            names = sideNames
            key = sideKey
        case .deep:
            names = deepNames
            key = deepKey
        default:
            return
        }
        
        names.removeAll { $0 == name }
        UserDefaults.standard.set(names, forKey: key)
        
        switch type {
        case .work:
            workNames = names
        case .side:
            sideNames = names
        case .deep:
            deepNames = names
        default:
            break
        }
    }
    
    func getNames(for type: SessionType) -> [String] {
        switch type {
        case .work:
            return workNames
        case .side:
            return sideNames
        case .deep:
            return deepNames
        default:
            return []
        }
    }
}

// MARK: - Suggestions Implementation

struct Suggestion<V: Equatable>: Equatable, Identifiable {
    var id: String { text }
    var text: String = ""
    var value: V
    
    static func ==(_ lhs: Suggestion<V>, _ rhs: Suggestion<V>) -> Bool {
        return lhs.value == rhs.value
    }
}

struct SuggestionGroup<V: Equatable>: Equatable {
    var title: String?
    var suggestions: [Suggestion<V>]
    
    static func ==(_ lhs: SuggestionGroup<V>, _ rhs: SuggestionGroup<V>) -> Bool {
        return lhs.suggestions == rhs.suggestions
    }
}

class SuggestionsModel<V: Equatable>: ObservableObject {
    @Published var suggestionGroups: [SuggestionGroup<V>] = []
    @Published var selectedSuggestion: Suggestion<V>?
    
    @Published var suggestionsVisible: Bool = false
    @Published var suggestionConfirmed: Bool = false
    @Published var isFocused: Bool = false
    
    @Published var width: CGFloat = 100
    
    var textBinding: Binding<String>?
    
    func modifiedText(_ text: String) {
        self.textBinding?.wrappedValue = text
        
        // Show if there are suggestions
        self.suggestionsVisible = !self.suggestionGroups.isEmpty
        self.suggestionConfirmed = false
        
        if !text.isEmpty {
            let allSuggestions = self.suggestions
            // Select first matching (case insensitive)
            if let firstMatch = allSuggestions.first(where: { $0.text.localizedCaseInsensitiveContains(text) }) {
                 self.selectedSuggestion = firstMatch
            } else {
                 self.selectedSuggestion = nil
            }
        } else {
             self.selectedSuggestion = nil
        }
    }
    
    func startEditing() {
        self.suggestionsVisible = !self.suggestionGroups.isEmpty
    }
    
    func cancel() {
        self.suggestionConfirmed = false
        self.suggestionsVisible = false
        self.selectedSuggestion = nil
    }
    
    private var suggestions: [Suggestion<V>] {
        self.suggestionGroups.flatMap(\.suggestions)
    }
    
    func moveUp() {
        self.suggestionConfirmed = false
        
        guard let selectedSuggestion = self.selectedSuggestion else {
             if let last = self.suggestions.last {
                 self.selectedSuggestion = last
             }
            return
        }

        guard let suggestion = self.previousSuggestion(for: selectedSuggestion) else {
            self.selectedSuggestion = nil
            return
        }
        self.selectedSuggestion = suggestion
    }

    func moveDown() {
        self.suggestionConfirmed = false
        
        guard let selectedSuggestion = self.selectedSuggestion else {
            guard let suggestion = self.firstSuggestion else {
                return
            }
            self.selectedSuggestion = suggestion
            return
        }
        
        guard let suggestion = self.nextSuggestion(for: selectedSuggestion) else {
            return
        }
        self.selectedSuggestion = suggestion
    }
    
    var firstSuggestion: Suggestion<V>? {
        let suggestions = self.suggestions
        return suggestions.first
    }

    func nextSuggestion(for suggestion: Suggestion<V>) -> Suggestion<V>? {
        let suggestions = self.suggestions
        guard let index = suggestions.firstIndex(of: suggestion),
              index + 1 < suggestions.count else {
            return nil
        }
        return suggestions[index + 1]
    }

    func previousSuggestion(for suggestion: Suggestion<V>) -> Suggestion<V>? {
        let suggestions = self.suggestions
        guard let index = suggestions.firstIndex(of: suggestion),
              index - 1 >= 0 else {
            return nil
        }
        return suggestions[index - 1]
    }
    
    func chooseSuggestion(_ suggestion: Suggestion<V>?) {
        self.selectedSuggestion = suggestion
        self.suggestionConfirmed = false
    }
    
    func confirmSuggestion(_ suggestion: Suggestion<V>) {
        self.selectedSuggestion = suggestion
        self.suggestionsVisible = false
        self.textBinding?.wrappedValue = suggestion.text
        self.suggestionConfirmed = true
    }
}

fileprivate struct SuggestionView<V: Equatable>: View {
    var suggestion: Suggestion<V>
    var accentColor: Color
    @ObservedObject var model: SuggestionsModel<V>
    var onDelete: ((String) -> Void)?
    
    @State private var isHovering = false
    
    var body: some View {
        let suggestion = self.suggestion
        let model = self.model
        let isSelected = model.selectedSuggestion == suggestion
        
        return HStack {
            Text(suggestion.text)
                .font(.system(size: 13))
                // Always use light text for dark popup background
                .foregroundColor(isSelected ? .white : .white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if isHovering || isSelected {
                Button {
                    onDelete?(suggestion.text)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isSelected ? .white.opacity(0.9) : .white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
        }
        .id(suggestion.text)
        .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
        .background(
            RoundedRectangle(cornerRadius: 6)
                .foregroundColor(isSelected ? accentColor : (isHovering ? Color.white.opacity(0.1) : Color.clear))
        )
        .contentShape(Rectangle()) // Make entire area tappable/hoverable
        .onHover(perform: { hovering in
            isHovering = hovering
            if hovering {
                model.chooseSuggestion(suggestion)
            }
        })
        .onTapGesture {
            model.confirmSuggestion(suggestion)
        }
    }
}

fileprivate struct SuggestionGroupView<V: Equatable>: View {
    var suggestionGroup: SuggestionGroup<V>
    var showDivider: Bool
    var accentColor: Color
    @ObservedObject var model: SuggestionsModel<V>
    var onDelete: ((String) -> Void)?
    
    var body: some View {
        let suggestionGroup = self.suggestionGroup
        let model = self.model
        
        return VStack(alignment: .leading, spacing: 0) {
            if self.showDivider {
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.vertical, 4)
            }
            if let title = suggestionGroup.title {
                Text(title)
                    .foregroundColor(.white.opacity(0.6)) // Light label for dark theme
                    .font(.system(size: 11, weight: .bold))
                    .padding(.leading, 8)
                    .padding(.bottom, 2)
                    .padding(.top, 4)
            }
            VStack(spacing: 0) {
                ForEach(suggestionGroup.suggestions) { suggestion in
                    SuggestionView(
                        suggestion: suggestion,
                        accentColor: accentColor,
                        model: model,
                        onDelete: onDelete
                    )
                }
            }
        }
    }
}

fileprivate struct SuggestionPopup<V: Equatable>: View {
    @ObservedObject var model: SuggestionsModel<V>
    var accentColor: Color
    var onDelete: ((String) -> Void)?
    
    var body: some View {
        let model = self.model
        let suggestionGroups = model.suggestionGroups
        
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(suggestionGroups.enumerated()), id: \.0)  { (suggestionGroupIndex, suggestionGroup) in
                        SuggestionGroupView(
                            suggestionGroup: suggestionGroup,
                            showDivider: suggestionGroupIndex > 0,
                            accentColor: accentColor,
                            model: model,
                            onDelete: onDelete
                        )
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 250)
            .onChange(of: model.selectedSuggestion) { _, newSelection in
                if let selection = newSelection {
                    withAnimation {
                        proxy.scrollTo(selection.text, anchor: .center)
                    }
                }
            }
        }
    }
}

fileprivate struct SuggestionTextField<V: Equatable>: NSViewRepresentable {
    @Binding var text: String
    @ObservedObject var model: SuggestionsModel<V>
    var placeholder: String
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(frame: .zero)
        textField.focusRingType = .none
        textField.isBordered = false
        textField.drawsBackground = false
        textField.font = NSFont.systemFont(ofSize: 13)
        // Set placeholder color to be lighter/consistent
        let placeholderStr = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: NSColor.white.withAlphaComponent(0.4)
        ])
        textField.placeholderAttributedString = placeholderStr
        textField.textColor = .white
        
        textField.delegate = context.coordinator
        
        // Add click gesture to show suggestions immediately on click
        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick))
        textField.addGestureRecognizer(clickGesture)
        
        context.coordinator.textField = textField
        
        return textField
    }
    
    func updateNSView(_ textField: NSTextField, context: Context) {
        let model = self.model
        let text = self.text
        
        let coordinator = context.coordinator
        coordinator.model = model
        
        // Update width tracking
        if coordinator.textField == nil {
            coordinator.textField = textField
        }
        
        coordinator.updatingSelectedRange = true
        defer {
            coordinator.updatingSelectedRange = false
        }
        
        // Keep the field strictly in sync with the bound text only.
        // Do NOT overwrite with the currently selected suggestion while navigating
        // or hovering – only confirmation (click/Enter) changes the binding itself.
        if textField.stringValue != text {
            textField.stringValue = text
        }
        
        // We intentionally do NOT auto-complete / select ranges based on suggestions here.
        // That avoids the field changing when moving with arrows or hovering.
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(text: self.$text, model: self.model)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var model: SuggestionsModel<V>
        var updatingSelectedRange: Bool = false
        var textField: NSTextField? {
            didSet {
                if let textField = self.textField {
                    textField.postsFrameChangedNotifications = true
                    self.frameDidChangeSubscription = NotificationCenter.default.publisher(for: NSView.frameDidChangeNotification, object: textField)
                        .sink(receiveValue: { [weak self] (_) in
                            guard let self = self else { return }
                            self.model.width = textField.frame.width
                        })
                    // Initial width
                    self.model.width = textField.frame.width
                }
            }
        }
        var frameDidChangeSubscription: AnyCancellable?
        
        init(text: Binding<String>, model: SuggestionsModel<V>) {
            self._text = text
            self.model = model
            super.init()
        }
        
        @objc func handleClick() {
            // Force show suggestions on click
            self.model.startEditing()
        }
        
        func controlTextDidBeginEditing(_ obj: Notification) {
            self.model.isFocused = true
            self.model.startEditing()
        }
        
        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            let text = textField.stringValue
            self.text = text
            self.model.modifiedText(text)
        }
        
        func controlTextDidEndEditing(_ obj: Notification) {
            self.model.isFocused = false
            self.model.cancel()
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                guard self.model.suggestionsVisible else { return false }
                self.model.moveUp()
                return true
            }
            
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                guard self.model.suggestionsVisible else { return false }
                self.model.moveDown()
                return true
            }
            
            if commandSelector == #selector(NSResponder.complete(_:)) ||
                commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                guard self.model.suggestionsVisible else { return false }
                self.model.cancel()
                return true
            }
            
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if let suggestion = self.model.selectedSuggestion {
                    self.model.confirmSuggestion(suggestion)
                     return true
                }
            }
            
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                if let suggestion = self.model.selectedSuggestion {
                    self.model.confirmSuggestion(suggestion)
                    return true
                }
            }
            
            return false
        }
    }
}

fileprivate struct SuggestionInput<V: Equatable>: View {
    @Binding var text: String
    var suggestionGroups: [SuggestionGroup<V>]
    var placeholder: String
    var accentColor: Color = .blue
    var onDelete: ((String) -> Void)?
    
    @StateObject var model = SuggestionsModel<V>()
    
    var body: some View {
        let model = self.model
        if model.suggestionGroups != self.suggestionGroups {
            model.suggestionGroups = self.suggestionGroups
        }
        model.textBinding = self.$text
        
        return SuggestionTextField(text: self.$text, model: model, placeholder: placeholder)
            .borderlessWindow(isVisible: Binding<Bool>(get: { model.suggestionsVisible && !model.suggestionGroups.isEmpty },
                                                     set: { model.suggestionsVisible = $0 }),
                              behavior: .transient,
                              anchor: .bottomLeading,
                              windowAnchor: .topLeading,
                              windowOffset: CGPoint(x: -8, y: -4)) {
                SuggestionPopup(model: model, accentColor: accentColor, onDelete: onDelete)
                    .frame(width: max(model.width, 200))
                    .background(Color(hex: "1E293B").opacity(0.98)) // Dark background
                    .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(lineWidth: 1)
                                .foregroundColor(Color.white.opacity(0.1))
                    )
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 4)
                    .padding(10)
            }
            .onAppear {
                model.suggestionGroups = self.suggestionGroups
            }
    }
}

fileprivate struct SuggestionInputWithModel<V: Equatable>: View {
    @Binding var text: String
    @ObservedObject var model: SuggestionsModel<V>
    var suggestionGroups: [SuggestionGroup<V>]
    var placeholder: String
    var accentColor: Color = .blue
    var onDelete: ((String) -> Void)?
    
    var body: some View {
        if model.suggestionGroups != self.suggestionGroups {
            model.suggestionGroups = self.suggestionGroups
        }
        model.textBinding = self.$text
        
        return SuggestionTextField(text: self.$text, model: model, placeholder: placeholder)
            .borderlessWindow(isVisible: Binding<Bool>(get: { model.suggestionsVisible && !model.suggestionGroups.isEmpty },
                                                     set: { model.suggestionsVisible = $0 }),
                              behavior: .transient,
                              anchor: .bottomLeading,
                              windowAnchor: .topLeading,
                              windowOffset: CGPoint(x: -8, y: -4)) {
                SuggestionPopup(model: model, accentColor: accentColor, onDelete: onDelete)
                    .frame(width: max(model.width, 200))
                    .background(Color(hex: "1E293B").opacity(0.98)) // Dark background
                    .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(lineWidth: 1)
                                .foregroundColor(Color.white.opacity(0.1))
                    )
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 4)
                    .padding(10)
            }
            .onAppear {
                model.suggestionGroups = self.suggestionGroups
            }
    }
}

// MARK: - Window & Effects

extension CGRect {
    fileprivate func point(anchor: UnitPoint) -> CGPoint {
        var point = self.origin
        point.x += self.size.width * anchor.x
        point.y += self.size.height * (1 - anchor.y)
        return point
    }
}

fileprivate enum BorderlessWindowBehavior {
    case applicationDefined
    case transient
    case semitransient
}

fileprivate struct BorderlessWindow<Content>: NSViewRepresentable where Content: View {
    @Binding private var isVisible: Bool
    private var behavior: BorderlessWindowBehavior
    private let anchor: UnitPoint
    private let windowAnchor: UnitPoint
    private let windowOffset: CGPoint
    private let content: () -> Content
    
    init(isVisible: Binding<Bool>,
         behavior: BorderlessWindowBehavior = .applicationDefined,
         anchor: UnitPoint = .center,
         windowAnchor: UnitPoint = .center,
         windowOffset: CGPoint = .zero,
         @ViewBuilder content: @escaping () -> Content) {
        self._isVisible = isVisible
        self.behavior = behavior
        self.anchor = anchor
        self.windowAnchor = windowAnchor
        self.windowOffset = windowOffset
        self.content = content
    }
    
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }
    
    func updateNSView(_ view: NSView, context: Context) {
        // Set content first to prevent white flash
        context.coordinator.hostingViewController.rootView = AnyView(self.content())
        let window = context.coordinator.window
        
        // Ensure hosting view has clear background
        context.coordinator.hostingViewController.view.wantsLayer = true
        context.coordinator.hostingViewController.view.layer?.backgroundColor = NSColor.clear.cgColor
        
        let isVisible = self.isVisible
        let wasVisible = window.isVisible && window.alphaValue > 0
        
        if isVisible != wasVisible {
            if isVisible {
                // Force layout before showing to prevent white flash
                context.coordinator.hostingViewController.view.needsLayout = true
                context.coordinator.hostingViewController.view.layoutSubtreeIfNeeded()
                
                if let parentWindow = view.window {
                    parentWindow.addChildWindow(window, ordered: .above)
                }
                window.alphaValue = 1.0
                window.makeKeyAndOrderFront(nil)
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.1
                    context.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeIn)
                    window.animator().alphaValue = 0.0
                } completionHandler: {
                    if let parentWindow = view.window {
                        parentWindow.removeChildWindow(window)
                    }
                    window.orderOut(nil)
                }
            }
        }
        
        var viewFrame = view.convert(view.bounds, to: nil)
        viewFrame = view.window?.convertToScreen(viewFrame) ?? viewFrame
        let viewPoint = viewFrame.point(anchor: self.anchor)
        var windowFrame = window.frame
        
        // Calculate content size and update window frame
        let contentSize = context.coordinator.hostingViewController.view.fittingSize
        if contentSize.width > 0 && contentSize.height > 0 {
            windowFrame.size = contentSize
        }
        
        let windowPoint = windowFrame.point(anchor: self.windowAnchor)
        
        var shift: CGPoint = viewPoint
        let windowOffset = self.windowOffset
        shift.x += windowOffset.x
        shift.y -= windowOffset.y
        shift.x -= windowPoint.x
        shift.y -= windowPoint.y
        
        windowFrame.origin.x += shift.x
        windowFrame.origin.y += shift.y
        
        window.setFrame(windowFrame, display: false)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSWindowDelegate {
        private var parent: BorderlessWindow
        fileprivate let window: NSWindow
        fileprivate let hostingViewController: NSHostingController<AnyView>
        private var localMouseDownEventMonitor: Any?
        
        fileprivate init(_ parent: BorderlessWindow) {
            self.parent = parent
            let window = NSWindow(contentRect: .zero,
                                  styleMask: [.borderless],
                                  backing: .buffered,
                                  defer: true)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hidesOnDeactivate = true
            window.isExcludedFromWindowsMenu = true
            window.isReleasedWhenClosed = false
            // Hide window initially to prevent white flash
            window.alphaValue = 0.0
            window.orderOut(nil)
            self.window = window
            let hostingViewController = NSHostingController(rootView: AnyView(EmptyView()))
            // Set dark background for hosting view to prevent white flash
            hostingViewController.view.wantsLayer = true
            hostingViewController.view.layer?.backgroundColor = NSColor.clear.cgColor
            window.contentViewController = hostingViewController
            self.hostingViewController = hostingViewController
            super.init()
            window.delegate = self
            
            let behaviour = self.parent.behavior
            if behaviour != .applicationDefined {
                self.localMouseDownEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] (event) -> NSEvent? in
                    guard let self = self else { return event }
                    if !self.window.isVisible { return event }
                    if event.window != self.window {
                        if behaviour == .semitransient {
                            if event.window != self.window.parent {
                                self.parent.isVisible = false
                                return nil
                            }
                        } else {
                            self.parent.isVisible = false
                            return nil
                        }
                    }
                    return event
                }
            }
        }
    }
}

fileprivate extension View {
    func borderlessWindow<Content: View>(isVisible: Binding<Bool>,
                                                behavior: BorderlessWindowBehavior = .applicationDefined,
                                                anchor: UnitPoint = .center,
                                                windowAnchor: UnitPoint = .center,
                                                windowOffset: CGPoint = .zero,
                                                @ViewBuilder content: @escaping () -> Content) -> some View {
        self.background(BorderlessWindow(isVisible: isVisible,
                                         behavior: behavior,
                                         anchor: anchor,
                                         windowAnchor: windowAnchor,
                                         windowOffset: windowOffset,
                                         content: content))
    }
}

fileprivate struct VisualEffectBlur: View {
    private let material: NSVisualEffectView.Material
    private let blendingMode: NSVisualEffectView.BlendingMode
    private let cornerRadius: CGFloat
    
    init(material: NSVisualEffectView.Material = .headerView,
                blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
                cornerRadius: CGFloat = 0) {
        self.material = material
        self.blendingMode = blendingMode
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        Representable(material: self.material,
                      blendingMode: self.blendingMode,
                      cornerRadius: self.cornerRadius)
            .accessibility(hidden: true)
    }
    
    struct Representable: NSViewRepresentable {
        var material: NSVisualEffectView.Material
        var blendingMode: NSVisualEffectView.BlendingMode
        var cornerRadius: CGFloat
        
        func makeNSView(context: Context) -> NSVisualEffectView {
            return NSVisualEffectView()
        }
        
        func updateNSView(_ view: NSVisualEffectView, context: Context) {
            view.material = self.material
            view.blendingMode = self.blendingMode
            view.wantsLayer = true
            view.layer?.cornerRadius = self.cornerRadius
            view.layer?.masksToBounds = true
        }
    }
}

#Preview {
    SettingsPanel(
        hasSeenPatternsGuide: .constant(false),
        showingPatternsGuide: .constant(false)
    )
        .environmentObject(SchedulingEngine())
        .environmentObject(CalendarService())
        .frame(width: 320, height: 800)
        .background(Color(hex: "0F172A"))
}

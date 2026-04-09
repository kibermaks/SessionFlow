import SwiftUI
import EventKit

/// Inline popover for creating calendar events directly from the timeline.
/// Features Spotlight-like autocomplete from recently created events.
struct EventCreationPopover: View {
    let startTime: Date
    let defaultDurationMinutes: Int
    let onCommit: (String, Date, Date, CalendarDescriptor) -> Void
    let onCancel: () -> Void

    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var schedulingEngine: SchedulingEngine
    @EnvironmentObject var recentEventsStore: RecentEventsStore

    @State private var eventTitle: String = ""
    @State private var durationMinutes: Int
    @AppStorage("SessionFlow.EventCreationLastCalendar") private var selectedCalendarName: String = ""
    @State private var selectedSuggestionIndex: Int = -1
    @FocusState private var titleFieldFocused: Bool

    init(startTime: Date, defaultDurationMinutes: Int = 30,
         onCommit: @escaping (String, Date, Date, CalendarDescriptor) -> Void,
         onCancel: @escaping () -> Void) {
        self.startTime = startTime
        self.defaultDurationMinutes = defaultDurationMinutes
        self.onCommit = onCommit
        self.onCancel = onCancel
        _durationMinutes = State(initialValue: defaultDurationMinutes)
    }

    /// Calendar info list sorted: non-session calendars first (alphabetically), then work/side/deep.
    /// Only writable calendars are included.
    private var sortedCalendars: [CalendarService.CalendarInfo] {
        let all = calendarService.calendarInfoList(includeExcluded: true)
            .filter { info in
                calendarService.availableCalendars
                    .first { $0.calendarIdentifier == info.identifier }?
                    .allowsContentModifications == true
            }
        let sessionIds: Set<String> = {
            var ids = Set<String>()
            if let id = schedulingEngine.workCalendarIdentifier { ids.insert(id) }
            if let id = schedulingEngine.sideCalendarIdentifier { ids.insert(id) }
            if let id = schedulingEngine.deepSessionConfig.calendarIdentifier { ids.insert(id) }
            return ids
        }()
        let regular = all.filter { !sessionIds.contains($0.identifier) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let session = all.filter { sessionIds.contains($0.identifier) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return regular + session
    }

    private var selectedCalendarInfo: CalendarService.CalendarInfo? {
        sortedCalendars.first { $0.name == selectedCalendarName }
    }

    /// Unified suggestion: either a recent event template or a calendar name match.
    private enum Suggestion: Identifiable {
        case recentEvent(RecentEventsStore.EventTemplate)
        case calendar(CalendarService.CalendarInfo)

        var id: String {
            switch self {
            case .recentEvent(let t): return "event-\(t.id)"
            case .calendar(let c): return "cal-\(c.id)"
            }
        }
    }

    private var suggestions: [Suggestion] {
        let trimmed = eventTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let eventMatches = recentEventsStore.search(trimmed).prefix(5).map { Suggestion.recentEvent($0) }

        let lowered = trimmed.lowercased()
        let calMatches = sortedCalendars
            .filter { !$0.isExcluded && $0.name.lowercased().contains(lowered) }
            .prefix(3)
            .map { Suggestion.calendar($0) }

        return Array(eventMatches) + Array(calMatches)
    }

    private var showSuggestions: Bool {
        !eventTitle.isEmpty && !suggestions.isEmpty
    }

    private var endTime: Date {
        startTime.addingTimeInterval(Double(durationMinutes) * 60)
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
                Text("New Event")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text(timeFormatter.string(from: startTime))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }

            Divider().background(Color.white.opacity(0.1))

            // Title field with autocomplete
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                    TextField("Event name", text: $eventTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .focused($titleFieldFocused)
                        .onSubmit { commitEvent() }
                        .onChange(of: eventTitle) { _, newValue in
                            selectedSuggestionIndex = -1
                            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }

                            // Auto-propose from best recent event match
                            let bestMatch = recentEventsStore.templates.first(where: {
                                $0.title.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
                            }) ?? recentEventsStore.search(trimmed).first

                            if let match = bestMatch {
                                durationMinutes = recentEventsStore.resolveDuration(for: match, using: calendarService)
                                if let calId = match.calendarIdentifier,
                                   let info = sortedCalendars.first(where: { $0.identifier == calId }) {
                                    selectedCalendarName = info.name
                                }
                            }
                        }
                }
                .padding(8)
                .background(Color.white.opacity(0.08))
                .cornerRadius(6)

                // Suggestions dropdown
                if showSuggestions {
                    VStack(spacing: 0) {
                        let visible = Array(suggestions.prefix(8))
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, suggestion in
                            suggestionRow(suggestion, isSelected: index == selectedSuggestionIndex)
                                .onTapGesture { applySuggestion(suggestion) }
                        }
                    }
                    .background(Color(hex: "1A2332"))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.top, 2)
                }
            }

            // Calendar picker — reuses CalendarPickerCompact from SettingsPanel
            CalendarPickerCompact(
                selectedCalendar: $selectedCalendarName,
                calendars: sortedCalendars,
                accentColor: .blue,
                onSelection: { info in
                    selectedCalendarName = info.name
                }
            )

            // Duration control
            VStack(spacing: 6) {
                HStack {
                    Text("Duration")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                    NumericInputField(value: $durationMinutes, range: 5...480, step: 5, unit: "min")
                }
                HStack(spacing: 6) {
                    Spacer()
                    durationChip(30)
                    durationChip(45)
                    durationChip(60)
                    durationChip(90)
                }
            }

            // Time summary
            HStack {
                Text("\(timeFormatter.string(from: startTime)) – \(timeFormatter.string(from: endTime))")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }

            Divider().background(Color.white.opacity(0.1))

            // Action buttons
            HStack {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.5))
                    .font(.system(size: 12))
                    .hoverEffect(brightness: 0.3)

                Spacer()

                Button {
                    commitEvent()
                } label: {
                    Text("Create")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(eventTitle.trimmingCharacters(in: .whitespaces).isEmpty ? Color.blue.opacity(0.3) : Color.blue)
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(eventTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                .hoverEffect(brightness: 0.2)
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: "1E293B"))
                .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            // Use persisted calendar if still valid, otherwise fall back to first
            let cals = sortedCalendars
            if selectedCalendarName.isEmpty || !cals.contains(where: { $0.name == selectedCalendarName }) {
                selectedCalendarName = cals.first?.name ?? ""
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                titleFieldFocused = true
            }
        }
        .onKeyPress(.upArrow, phases: .down) { press in
            if press.modifiers.contains(.command) {
                cycleCalendar(delta: -1)
                return .handled
            }
            navigateSuggestion(delta: -1)
            return .handled
        }
        .onKeyPress(.downArrow, phases: .down) { press in
            if press.modifiers.contains(.command) {
                cycleCalendar(delta: 1)
                return .handled
            }
            navigateSuggestion(delta: 1)
            return .handled
        }
        .onKeyPress(.escape) {
            if showSuggestions && selectedSuggestionIndex >= 0 {
                selectedSuggestionIndex = -1
                return .handled
            }
            onCancel()
            return .handled
        }
        .onKeyPress(.tab) {
            // Tab applies the current suggestion
            if showSuggestions, selectedSuggestionIndex >= 0,
               selectedSuggestionIndex < suggestions.count {
                applySuggestion(suggestions[selectedSuggestionIndex])
                return .handled
            }
            if showSuggestions, let first = suggestions.first {
                applySuggestion(first)
                return .handled
            }
            return .ignored
        }
    }

    private func durationChip(_ minutes: Int) -> some View {
        let isSelected = durationMinutes == minutes
        return Button {
            durationMinutes = minutes
        } label: {
            Text("\(minutes)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isSelected ? Color.blue.opacity(0.5) : Color.white.opacity(0.06))
                .cornerRadius(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(brightness: 0.2)
    }

    @ViewBuilder
    private func suggestionRow(_ suggestion: Suggestion, isSelected: Bool) -> some View {
        switch suggestion {
        case .recentEvent(let template):
            let liveDuration = recentEventsStore.resolveDuration(for: template, using: calendarService)
            HStack(spacing: 8) {
                if let calId = template.calendarIdentifier,
                   let info = sortedCalendars.first(where: { $0.identifier == calId }) {
                    Circle()
                        .fill(info.color)
                        .frame(width: 6, height: 6)
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: 6, height: 6)
                }
                highlightedTitle(template.title, query: eventTitle)
                    .lineLimit(1)
                Spacer()
                Text("\(liveDuration)m")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? Color.blue.opacity(0.25) : Color.clear)
            .contentShape(Rectangle())

        case .calendar(let info):
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                    .foregroundColor(info.color)
                    .frame(width: 6)
                Circle()
                    .fill(info.color)
                    .frame(width: 6, height: 6)
                highlightedTitle(info.name, query: eventTitle)
                    .lineLimit(1)
                Spacer()
                Text("calendar")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? Color.blue.opacity(0.25) : Color.clear)
            .contentShape(Rectangle())
        }
    }

    /// Renders the title with matching characters bolded, Spotlight-style.
    private func highlightedTitle(_ title: String, query: String) -> some View {
        let lowTitle = title.lowercased()
        let lowQuery = query.lowercased()

        // Find range of the query in the title
        if let range = lowTitle.range(of: lowQuery) {
            let before = String(title[title.startIndex..<range.lowerBound])
            let match = String(title[range.lowerBound..<range.upperBound])
            let after = String(title[range.upperBound...])

            return (Text(before).foregroundColor(.white.opacity(0.6)) +
                    Text(match).foregroundColor(.white).bold() +
                    Text(after).foregroundColor(.white.opacity(0.6)))
                .font(.system(size: 12))
        }

        return Text(title)
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.6))
    }

    private func navigateSuggestion(delta: Int) {
        guard showSuggestions else { return }
        let count = min(suggestions.count, 8)
        let newIndex = selectedSuggestionIndex + delta
        if newIndex < 0 {
            selectedSuggestionIndex = -1
        } else if newIndex >= count {
            selectedSuggestionIndex = count - 1
        } else {
            selectedSuggestionIndex = newIndex
        }
        // Preview the highlighted suggestion's calendar and duration
        if selectedSuggestionIndex >= 0, selectedSuggestionIndex < count {
            previewSuggestion(suggestions[selectedSuggestionIndex])
        }
    }

    /// Updates calendar/duration to preview a suggestion without applying the title.
    private func previewSuggestion(_ suggestion: Suggestion) {
        switch suggestion {
        case .recentEvent(let template):
            durationMinutes = recentEventsStore.resolveDuration(for: template, using: calendarService)
            if let calId = template.calendarIdentifier,
               let info = sortedCalendars.first(where: { $0.identifier == calId }) {
                selectedCalendarName = info.name
            }
        case .calendar(let info):
            selectedCalendarName = info.name
        }
    }

    /// Cycle through calendars with Cmd+Up/Down
    private func cycleCalendar(delta: Int) {
        let cals = sortedCalendars
        guard !cals.isEmpty else { return }
        let currentIndex = cals.firstIndex(where: { $0.name == selectedCalendarName }) ?? -1
        var newIndex = currentIndex + delta
        if newIndex < 0 { newIndex = cals.count - 1 }
        if newIndex >= cals.count { newIndex = 0 }
        // Skip excluded calendars
        let startIndex = newIndex
        while cals[newIndex].isExcluded {
            newIndex += delta > 0 ? 1 : -1
            if newIndex < 0 { newIndex = cals.count - 1 }
            if newIndex >= cals.count { newIndex = 0 }
            if newIndex == startIndex { break }
        }
        selectedCalendarName = cals[newIndex].name
    }

    private func applySuggestion(_ suggestion: Suggestion) {
        switch suggestion {
        case .recentEvent(let template):
            eventTitle = template.title
            durationMinutes = recentEventsStore.resolveDuration(for: template, using: calendarService)
            if let calId = template.calendarIdentifier,
               let info = sortedCalendars.first(where: { $0.identifier == calId }) {
                selectedCalendarName = info.name
            }
        case .calendar(let info):
            selectedCalendarName = info.name
            eventTitle = ""
        }
        selectedSuggestionIndex = -1
    }

    private func commitEvent() {
        // If a suggestion is selected via keyboard, apply it first
        if showSuggestions, selectedSuggestionIndex >= 0,
           selectedSuggestionIndex < suggestions.count {
            applySuggestion(suggestions[selectedSuggestionIndex])
            return
        }

        let title = eventTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, let info = selectedCalendarInfo else { return }
        let end = startTime.addingTimeInterval(Double(durationMinutes) * 60)
        let descriptor = CalendarDescriptor(name: info.name, identifier: info.identifier)
        onCommit(title, startTime, end, descriptor)
    }
}

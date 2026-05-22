import SwiftUI

struct ProductivityCard: View {
    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var sessionAwarenessService: SessionAwarenessService
    @Environment(\.openSettings) private var openSettings
    @State private var showingMonthly = false
    @State private var showingHelp = false
    @State private var selectedSessionType: SessionType? = nil

    private var isFiltering: Bool {
        selectedSessionType != nil
    }

    /// Busy slots filtered by selected session type (passthrough when nil)
    private var filteredSlots: [BusyTimeSlot] {
        guard let selectedType = selectedSessionType else { return calendarService.busySlots }
        return calendarService.busySlots.filter { slot in
            CalendarService.sessionType(fromNotes: slot.notes) == selectedType
        }
    }

    /// Reactive: derived from filteredSlots
    private var todayCounts: [SessionRating: Int] {
        var counts: [SessionRating: Int] = [:]
        for slot in filteredSlots {
            if let rating = SessionRating.fromNotes(slot.notes) {
                counts[rating, default: 0] += 1
            }
        }
        return counts
    }

    /// Count of past events without feedback (filtered)
    private var unratedCount: Int {
        filteredSlots.filter {
            $0.endTime < Date() && SessionRating.fromNotes($0.notes) == nil
        }.count
    }

    /// Focus time: weighted sum of rated session durations (filtered)
    private var focusTimeMinutes: Int {
        let weights = sessionAwarenessService.config.focusWeights
        var total: Double = 0
        for slot in filteredSlots {
            guard let rating = SessionRating.fromNotes(slot.notes) else { continue }
            let minutes = slot.endTime.timeIntervalSince(slot.startTime) / 60
            total += minutes * weights.multiplier(for: rating)
        }
        return Int(total)
    }

    /// Card is visible only when at least one feedback has been set
    var hasFeedback: Bool {
        calendarService.busySlots.contains { SessionRating.fromNotes($0.notes) != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.orange)
                Text("Productivity")
                    .font(.headline)
                    .foregroundColor(colors.textPrimary)

                Spacer()

                Button {
                    showingHelp.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundColor(colors.textMuted)
                }
                .buttonStyle(.plain)
                .hoverEffect(brightness: 0.3)
                .popover(isPresented: $showingHelp) {
                    let w = sessionAwarenessService.config.focusWeights
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your daily focus summary")
                            .font(.system(size: 13, weight: .semibold))

                        Text("Rate your calendar events after they end to track how your day went. Each event gets a rating that reflects your focus quality.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()

                        Text("How Focus Time works")
                            .font(.system(size: 12, weight: .semibold))

                        VStack(alignment: .leading, spacing: 4) {
                            Label("Fire — counts \(w.rocketPercent)% of event duration", systemImage: "flame.fill")
                                .foregroundColor(colors.isDark ? .orange : Color(hex: "C2410C"))
                            Label("Done — counts \(w.completedPercent)%", systemImage: "checkmark.circle.fill")
                                .foregroundColor(colors.isDark ? .green : Color(hex: "15803D"))
                            Label("Partly — counts \(w.partialPercent)%", systemImage: "circle.lefthalf.filled")
                                .foregroundColor(colors.isDark ? .yellow : Color(hex: "D97706"))
                            Label("Skipped — counts \(w.skippedPercent)%", systemImage: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                        .font(.system(size: 12))

                        Text("For example, a 1-hour event rated Done adds \(w.completedPercent * 60 / 100) min of focus time.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .italic()
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()

                        Label("Use the calendar button to see your monthly overview with per-day breakdowns.", systemImage: "calendar")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()

                        HStack {
                            Spacer()
                            Button {
                                showingHelp = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    openSettings()
                                    NotificationCenter.default.post(name: AppSettingsView.switchToAwarenessTab, object: nil)
                                }
                            } label: {
                                Label("Adjust in Settings", systemImage: "gearshape")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .hoverEffect(brightness: 0.3)
                            .focusable(false)
                            Spacer()
                        }
                    }
                    .padding(14)
                    .frame(width: 340)
                }

                // Session type filter
                Menu {
                    Button("All Types") { selectedSessionType = nil }
                    Divider()
                    ForEach(SessionType.filterableTypes, id: \.self) { type in
                        Button(action: { selectedSessionType = type }) {
                            Label(type.rawValue, systemImage: type.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 13))
                        if let type = selectedSessionType {
                            Image(systemName: type.icon)
                                .font(.system(size: 10))
                                .foregroundColor(type.color)
                        }
                    }
                    .foregroundColor(isFiltering ? .accentColor : colors.textMuted)
                    .frame(height: 24)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Filter by session type")

                Button {
                    showingMonthly = true
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 13))
                        .foregroundColor(colors.textMuted)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect(brightness: 0.2)
                .help("Monthly overview")
            }

            // Active filter indicator
            if let type = selectedSessionType {
                HStack(spacing: 6) {
                    Image(systemName: type.icon)
                        .font(.system(size: 10))
                        .foregroundColor(type.color)
                    Text(type.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(type.color)
                    Button {
                        selectedSessionType = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(colors.textMuted)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(type.color.opacity(0.15))
                )
            }

            // Today's stats
            todayStats

            // Focus time
            if focusTimeMinutes > 0 || isFiltering {
                HStack(spacing: 6) {
                    Image(systemName: "target")
                        .font(.system(size: 12))
                        .foregroundColor(colors.isDark ? .green.opacity(0.8) : Color(hex: "15803D"))
                    Text("Focus Time")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                    Spacer()
                    Text(focusTimeFormatted)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(colors.isDark ? .green : Color(hex: "15803D"))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colors.subtleBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(colors.divider, lineWidth: 1)
                )
        )
        .sheet(isPresented: $showingMonthly) {
            MonthlyStatsView(selectedSessionType: $selectedSessionType)
                .environmentObject(calendarService)
                .environmentObject(sessionAwarenessService)
        }
    }

    // MARK: - Today stats

    private var todayStats: some View {
        HStack(spacing: 0) {
            ForEach(SessionRating.allCases, id: \.rawValue) { rating in
                let count = todayCounts[rating] ?? 0
                VStack(spacing: 4) {
                    Image(systemName: rating.icon)
                        .font(.system(size: 14))
                        .foregroundColor(ratingColor(rating))
                    Text("\(count)")
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(count > 0 ? colors.textPrimary : colors.textMuted)
                }
                .frame(maxWidth: .infinity)
                .help(rating.label)
            }

            // Unrated count
            VStack(spacing: 4) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 14))
                    .foregroundColor(colors.textMuted)
                Text("\(unratedCount)")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(unratedCount > 0 ? colors.textSecondary : colors.textMuted)
            }
            .frame(maxWidth: .infinity)
            .help("Unrated")
        }
    }

    private var focusTimeFormatted: String {
        let hours = focusTimeMinutes / 60
        let mins = focusTimeMinutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    private func ratingColor(_ rating: SessionRating) -> Color {
        switch rating {
        case .rocket: return .orange
        case .completed: return .green
        case .partial: return colors.isDark ? .yellow : Color(hex: "92400E")
        case .skipped: return .red
        }
    }
}

// MARK: - Monthly Stats Modal

struct MonthlyStatsView: View {
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var sessionAwarenessService: SessionAwarenessService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    @Binding var selectedSessionType: SessionType?

    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var month: Int = Calendar.current.component(.month, from: Date())
    @State private var dayStats: [Int: CalendarService.DayFeedbackStats] = [:]
    @State private var typeCounts: [SessionType: Int] = [:]
    @State private var viewMode: ViewMode = .month
    @State private var yearMonthStats: [Int: MonthStat] = [:]

    private enum ViewMode { case month, year }

    private struct MonthStat {
        var totalEvents: Int
        var focusMinutes: Int
        var counts: [SessionRating: Int]
        var rated: Int { counts.values.reduce(0, +) }
        var unrated: Int { max(0, totalEvents - rated) }
    }

    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let date = Calendar.current.date(from: DateComponents(year: year, month: month))!
        return formatter.string(from: date)
    }

    private var daysInMonth: Int {
        let cal = Calendar.current
        let date = cal.date(from: DateComponents(year: year, month: month))!
        return cal.range(of: .day, in: .month, for: date)!.count
    }

    private var firstWeekday: Int {
        let cal = Calendar.current
        let date = cal.date(from: DateComponents(year: year, month: month, day: 1))!
        let wd = cal.component(.weekday, from: date)
        return (wd + 5) % 7
    }

    private var monthTotals: (counts: [SessionRating: Int], totalEvents: Int, focusMinutes: Int) {
        var counts: [SessionRating: Int] = [:]
        var total = 0
        var focus: Double = 0
        for (_, stats) in dayStats {
            total += stats.totalEvents
            focus += stats.focusMinutes
            for (rating, count) in stats.counts {
                counts[rating, default: 0] += count
            }
        }
        return (counts, total, Int(focus))
    }

    private var isCurrentMonth: Bool {
        let cal = Calendar.current
        let now = Date()
        return year == cal.component(.year, from: now) && month == cal.component(.month, from: now)
    }

    private var currentCalYear: Int { Calendar.current.component(.year, from: Date()) }

    private var maxDayFocusMinutes: Double {
        dayStats.values.map(\.focusMinutes).max() ?? 0
    }

    private var yearTotals: (totalEvents: Int, focusMinutes: Int, counts: [SessionRating: Int]) {
        var totalEvents = 0
        var focusMinutes = 0
        var counts: [SessionRating: Int] = [:]
        for (_, stat) in yearMonthStats {
            totalEvents += stat.totalEvents
            focusMinutes += stat.focusMinutes
            for (rating, count) in stat.counts {
                counts[rating, default: 0] += count
            }
        }
        return (totalEvents, focusMinutes, counts)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            Divider()

            if viewMode == .month {
                monthNavigationRow

                HStack(spacing: 0) {
                    ForEach(["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"], id: \.self) { day in
                        Text(day)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

                calendarGrid
                    .padding(.horizontal, 12)

                Divider()
                    .padding(.top, 8)

                monthTotalsRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                yearNavigationRow

                Divider()

                yearOverviewContent

                Divider()

                aggregateTotalsRow(totals: (
                    counts: yearTotals.counts,
                    totalEvents: yearTotals.totalEvents,
                    focusMinutes: yearTotals.focusMinutes
                ))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 400)
        .onAppear { loadData() }
        .onChange(of: selectedSessionType) { _, _ in
            loadData()
            if viewMode == .year { loadYearData() }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text("Productivity Calendar")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            Menu {
                Button("All Types") { selectedSessionType = nil }
                Divider()
                ForEach(SessionType.filterableTypes, id: \.self) { type in
                    let count = typeCounts[type] ?? 0
                    Button(action: { selectedSessionType = type }) {
                        Label("\(type.rawValue) (\(count))", systemImage: type.icon)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 11))
                    if let type = selectedSessionType {
                        HStack(spacing: 3) {
                            Image(systemName: type.icon)
                                .font(.system(size: 10))
                                .foregroundColor(type.color)
                            Text(type.rawValue)
                                .font(.system(size: 12, weight: .medium))
                        }
                    } else {
                        Text("All Types")
                            .font(.system(size: 12, weight: .medium))
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundColor(.primary.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.06))
                )
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .focusable(false)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewMode = viewMode == .month ? .year : .month
                }
                if viewMode == .year { loadYearData() }
            } label: {
                Image(systemName: viewMode == .month ? "list.bullet" : "calendar")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: 0.2)
            .focusable(false)
            .help(viewMode == .month ? "Year overview" : "Month view")

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: 0.2)
            .focusable(false)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Navigation rows

    private var monthNavigationRow: some View {
        HStack {
            Button { navigateMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: 0.2)
            .focusable(false)

            Spacer()

            Menu {
                ForEach(1...12, id: \.self) { m in
                    Button(action: { jumpToMonth(m) }) {
                        Text(fullMonthName(for: m))
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(monthName)
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .focusable(false)

            Spacer()

            Button { navigateMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isCurrentMonth ? .secondary.opacity(0.3) : .primary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: isCurrentMonth ? 0 : 0.2)
            .focusable(false)
            .disabled(isCurrentMonth)

            Button { jumpToToday() } label: {
                Text("Today")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.1)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: 0.2)
            .focusable(false)
            .opacity(isCurrentMonth ? 0 : 1)
            .disabled(isCurrentMonth)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var yearNavigationRow: some View {
        HStack {
            Button { navigateYear(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: 0.2)
            .focusable(false)

            Spacer()

            Text(String(year))
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            Button { navigateYear(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(year >= currentCalYear ? .secondary.opacity(0.3) : .primary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: year >= currentCalYear ? 0 : 0.2)
            .focusable(false)
            .disabled(year >= currentCalYear)

            Button { jumpToToday() } label: {
                Text("Today")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.1)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: 0.2)
            .focusable(false)
            .opacity(year >= currentCalYear ? 0 : 1)
            .disabled(year >= currentCalYear)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Calendar grid

    private var calendarGrid: some View {
        let totalCells = firstWeekday + daysInMonth
        let rows = (totalCells + 6) / 7

        return VStack(spacing: 2) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<7, id: \.self) { col in
                        let cellIndex = row * 7 + col
                        let day = cellIndex - firstWeekday + 1

                        if day >= 1 && day <= daysInMonth {
                            dayCellView(day: day)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, minHeight: 62, maxHeight: 62)
                        }
                    }
                }
            }
        }
    }

    private func dayCellView(day: Int) -> some View {
        let cal = Calendar.current
        let cellDate = cal.date(from: DateComponents(year: year, month: month, day: day))!
        let isToday = cal.isDateInToday(cellDate)
        let isFuture = cellDate > Date()
        let stats = dayStats[day]
        let ratedTotal = stats?.counts.values.reduce(0, +) ?? 0
        let focus = stats?.focusMinutes ?? 0

        return VStack(spacing: 2) {
            Text("\(day)")
                .font(.system(size: 12, weight: isToday ? .bold : .regular))
                .foregroundColor(isFuture ? .secondary.opacity(0.3) : (isToday ? .primary : .primary.opacity(0.7)))

            if ratedTotal > 0 {
                feedbackDots(stats: stats!)

                Text(dayFocusLabel(focus))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(focusColor(focus))
            } else {
                Color.clear.frame(height: 24)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 62, maxHeight: 62)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isToday ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(isToday ? 0.0 : 0.07), lineWidth: 0.5)
        )
    }

    /// Shows one dot per event, colored by rating
    private func feedbackDots(stats: CalendarService.DayFeedbackStats) -> some View {
        var dots: [Color] = []
        for rating in SessionRating.allCases {
            let count = stats.counts[rating] ?? 0
            for _ in 0..<count {
                dots.append(ratingColor(rating))
            }
        }
        let maxDots = 8
        let displayDots = Array(dots.prefix(maxDots))

        return HStack(spacing: 1) {
            ForEach(Array(displayDots.enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
            }
            if dots.count > maxDots {
                Text("+")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 8)
    }

    private func dayFocusLabel(_ minutes: Double) -> String {
        let m = Int(minutes)
        if m >= 60 {
            return "\(m / 60)h\(m % 60 > 0 ? "\(m % 60)" : "")"
        }
        return "\(m)m"
    }

    private func focusColor(_ minutes: Double) -> Color {
        guard maxDayFocusMinutes > 0 else { return .secondary }
        let ratio = minutes / maxDayFocusMinutes
        if colors.isDark {
            // Dark mode: vibrant bright colors on dark bg
            if ratio < 0.5 {
                let t = ratio / 0.5
                return Color(red: 1.0, green: t * 0.85, blue: 0)
            } else {
                let t = (ratio - 0.5) / 0.5
                return Color(red: 1.0 - t * 0.7, green: 0.85 + t * 0.15, blue: t * 0.2)
            }
        } else {
            // Light mode: deep saturated colors for contrast on white bg
            // low → deep red, mid → dark amber, high → deep green
            if ratio < 0.5 {
                let t = ratio / 0.5
                return Color(red: 0.82, green: 0.10 + t * 0.28, blue: 0.04)
            } else {
                let t = (ratio - 0.5) / 0.5
                return Color(red: 0.82 - t * 0.74, green: 0.38 + t * 0.17, blue: 0.04 + t * 0.11)
            }
        }
    }

    // MARK: - Year overview

    private var yearOverviewContent: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(1...12, id: \.self) { m in
                    yearMonthRow(month: m)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    private func yearMonthRow(month m: Int) -> some View {
        let stat = yearMonthStats[m]
        let cal = Calendar.current
        let now = Date()
        let curMonth = cal.component(.month, from: now)
        let isThisMonth = year == currentCalYear && m == curMonth
        let isFuture = year > currentCalYear || (year == currentCalYear && m > curMonth)
        let hasData = (stat?.totalEvents ?? 0) > 0

        return Button(action: {
            month = m
            viewMode = .month
            loadData()
        }) {
            HStack(spacing: 8) {
                Text(shortMonthName(for: m))
                    .font(.system(size: 13, weight: isThisMonth ? .bold : .medium))
                    .foregroundColor(isFuture ? .secondary.opacity(0.3) : .primary.opacity(isThisMonth ? 1.0 : 0.8))
                    .frame(width: 32, alignment: .leading)

                if hasData {
                    HStack(spacing: 5) {
                        ForEach(SessionRating.allCases, id: \.rawValue) { rating in
                            let count = stat?.counts[rating] ?? 0
                            HStack(spacing: 2) {
                                Image(systemName: rating.icon)
                                    .font(.system(size: 10))
                                    .foregroundColor(count > 0 ? ratingColor(rating) : .secondary.opacity(0.2))
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(count > 0 ? .primary.opacity(0.7) : .secondary.opacity(0.2))
                            }
                        }
                        let unrated = stat?.unrated ?? 0
                        if unrated > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary.opacity(0.4))
                                Text("\(unrated)")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                        }
                    }

                    Spacer()

                    if let focusMin = stat?.focusMinutes, focusMin > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "target")
                                .font(.system(size: 10))
                                .foregroundColor(colors.isDark ? .green.opacity(0.8) : Color(hex: "15803D"))
                            Text(formatFocusTime(focusMin))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(colors.isDark ? .green : Color(hex: "15803D"))
                        }
                    } else {
                        Text("\(stat?.totalEvents ?? 0)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                } else {
                    Spacer()
                    if !isFuture {
                        Text("—")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.3))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isThisMonth ? Color.accentColor.opacity(0.08) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Totals rows

    private var monthTotalsRow: some View {
        let totals = monthTotals
        return aggregateTotalsRow(totals: (totals.counts, totals.totalEvents, totals.focusMinutes))
    }

    private func aggregateTotalsRow(totals: (counts: [SessionRating: Int], totalEvents: Int, focusMinutes: Int)) -> some View {
        let rated = totals.counts.values.reduce(0, +)
        let unrated = totals.totalEvents - rated

        return HStack(spacing: 10) {
            ForEach(SessionRating.allCases, id: \.rawValue) { rating in
                let count = totals.counts[rating] ?? 0
                HStack(spacing: 3) {
                    Image(systemName: rating.icon)
                        .font(.system(size: 12))
                        .foregroundColor(ratingColor(rating))
                    Text("\(count)")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(count > 0 ? .primary : .secondary.opacity(0.4))
                }
                .help(rating.label)
            }

            Spacer()

            HStack(spacing: 3) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("\(unrated)")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(unrated > 0 ? .primary.opacity(0.6) : .secondary.opacity(0.4))
            }
            .help("Unrated")

            Divider().frame(height: 18)

            Text("\(totals.totalEvents)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary.opacity(0.5))

            if totals.focusMinutes > 0 {
                Divider().frame(height: 18)

                HStack(spacing: 3) {
                    Image(systemName: "target")
                        .font(.system(size: 12))
                        .foregroundColor(colors.isDark ? .green : Color(hex: "15803D"))
                    Text(formatFocusTime(totals.focusMinutes))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(colors.isDark ? .green : Color(hex: "15803D"))
                }
            }
        }
    }

    // MARK: - Helpers

    private func navigateMonth(_ offset: Int) {
        var comps = DateComponents(year: year, month: month)
        comps.month! += offset
        let cal = Calendar.current
        if let date = cal.date(from: comps) {
            year = cal.component(.year, from: date)
            month = cal.component(.month, from: date)
            loadData()
        }
    }

    private func navigateYear(_ offset: Int) {
        year += offset
        loadYearData()
    }

    private func jumpToMonth(_ m: Int) {
        month = m
        loadData()
    }

    private func jumpToToday() {
        let now = Date()
        year = Calendar.current.component(.year, from: now)
        month = Calendar.current.component(.month, from: now)
        if viewMode == .year { loadYearData() } else { loadData() }
    }

    private func fullMonthName(for m: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        let date = Calendar.current.date(from: DateComponents(year: year, month: m))!
        return formatter.string(from: date)
    }

    private func shortMonthName(for m: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        let date = Calendar.current.date(from: DateComponents(year: year, month: m))!
        return formatter.string(from: date)
    }

    private func loadData() {
        dayStats = calendarService.monthlyFeedbackStats(
            year: year, month: month,
            weights: sessionAwarenessService.config.focusWeights,
            sessionType: selectedSessionType
        )
        typeCounts = calendarService.monthlySessionTypeCounts(year: year, month: month)
    }

    private func loadYearData() {
        var stats: [Int: MonthStat] = [:]
        for m in 1...12 {
            let dayData = calendarService.monthlyFeedbackStats(
                year: year, month: m,
                weights: sessionAwarenessService.config.focusWeights,
                sessionType: selectedSessionType
            )
            var totalEvents = 0
            var focusMinutes: Double = 0
            var counts: [SessionRating: Int] = [:]
            for (_, dayStat) in dayData {
                totalEvents += dayStat.totalEvents
                focusMinutes += dayStat.focusMinutes
                for (rating, count) in dayStat.counts {
                    counts[rating, default: 0] += count
                }
            }
            stats[m] = MonthStat(totalEvents: totalEvents, focusMinutes: Int(focusMinutes), counts: counts)
        }
        yearMonthStats = stats
    }

    private func formatFocusTime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    private func ratingColor(_ rating: SessionRating) -> Color {
        switch rating {
        case .rocket: return .orange
        case .completed: return .green
        case .partial: return colors.isDark ? .yellow : Color(hex: "92400E")
        case .skipped: return .red
        }
    }

}


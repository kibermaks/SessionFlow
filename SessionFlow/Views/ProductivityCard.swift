import SwiftUI

struct ProductivityCard: View {
    @EnvironmentObject var calendarService: CalendarService
    @State private var showingMonthly = false

    /// Reactive: derived from calendarService.busySlots (which is @Published)
    private var todayCounts: [SessionRating: Int] {
        var counts: [SessionRating: Int] = [:]
        for slot in calendarService.busySlots {
            if let rating = SessionRating.fromNotes(slot.notes) {
                counts[rating, default: 0] += 1
            }
        }
        return counts
    }

    /// Count of past events without feedback
    private var unratedCount: Int {
        calendarService.busySlots.filter {
            $0.endTime < Date() && SessionRating.fromNotes($0.notes) == nil
        }.count
    }

    /// Focus time: weighted sum of rated session durations
    private var focusTimeMinutes: Int {
        var total: Double = 0
        for slot in calendarService.busySlots {
            guard let rating = SessionRating.fromNotes(slot.notes) else { continue }
            let minutes = slot.endTime.timeIntervalSince(slot.startTime) / 60
            total += minutes * rating.focusMultiplier
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
                    .foregroundColor(.white)

                Spacer()

                Button {
                    showingMonthly = true
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Monthly overview")
            }

            // Today's stats
            todayStats

            // Focus time
            if focusTimeMinutes > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "target")
                        .font(.system(size: 12))
                        .foregroundColor(.green.opacity(0.8))
                    Text("Focus Time")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                    Text(focusTimeFormatted)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.green)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .sheet(isPresented: $showingMonthly) {
            MonthlyStatsView()
                .environmentObject(calendarService)
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
                        .foregroundColor(.white.opacity(count > 0 ? 0.9 : 0.3))
                }
                .frame(maxWidth: .infinity)
            }

            // Unrated count
            VStack(spacing: 4) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.3))
                Text("\(unratedCount)")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(unratedCount > 0 ? 0.6 : 0.3))
            }
            .frame(maxWidth: .infinity)
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
        case .partial: return .yellow
        case .skipped: return .red
        }
    }
}

// MARK: - Monthly Stats Modal

struct MonthlyStatsView: View {
    @EnvironmentObject var calendarService: CalendarService
    @Environment(\.dismiss) private var dismiss

    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var month: Int = Calendar.current.component(.month, from: Date())
    @State private var dayStats: [Int: CalendarService.DayFeedbackStats] = [:]

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

    /// Weekday of 1st day (0=Mon, 6=Sun)
    private var firstWeekday: Int {
        let cal = Calendar.current
        let date = cal.date(from: DateComponents(year: year, month: month, day: 1))!
        let wd = cal.component(.weekday, from: date) // 1=Sun, 2=Mon...
        return (wd + 5) % 7 // 0=Mon
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

    private var maxDayFocusMinutes: Double {
        dayStats.values.map(\.focusMinutes).max() ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Productivity")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            // Month navigation
            HStack {
                Button { navigateMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)

                Spacer()

                Text(monthName)
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button { navigateMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isCurrentMonth ? .secondary.opacity(0.3) : .primary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(isCurrentMonth)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            // Day headers
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

            // Calendar grid
            calendarGrid
                .padding(.horizontal, 12)

            Divider()
                .padding(.top, 8)

            // Month totals
            monthTotalsRow
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(width: 400, height: 470)
        .onAppear { loadData() }
    }

    // MARK: - Calendar grid

    private var calendarGrid: some View {
        let totalCells = firstWeekday + daysInMonth
        let rows = (totalCells + 6) / 7

        return VStack(spacing: 2) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        let cellIndex = row * 7 + col
                        let day = cellIndex - firstWeekday + 1

                        if day >= 1 && day <= daysInMonth {
                            dayCellView(day: day)
                                .frame(maxWidth: .infinity)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, minHeight: 44)
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

        return VStack(spacing: 1) {
            Text("\(day)")
                .font(.system(size: 12, weight: isToday ? .bold : .regular))
                .foregroundColor(isFuture ? .secondary.opacity(0.3) : (isToday ? .primary : .primary.opacity(0.7)))

            if ratedTotal > 0 {
                feedbackDots(stats: stats!)

                Text(dayFocusLabel(focus))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(focusColor(focus))
            } else {
                Color.clear.frame(height: 18)
            }
        }
        .frame(minHeight: 48)
        .background(isToday ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
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

    /// Interpolate red → yellow → green based on focus time relative to best day
    private func focusColor(_ minutes: Double) -> Color {
        guard maxDayFocusMinutes > 0 else { return .secondary }
        let ratio = minutes / maxDayFocusMinutes // 0...1
        if ratio < 0.5 {
            let t = ratio / 0.5
            return Color(red: 1.0, green: t * 0.85, blue: 0)
        } else {
            let t = (ratio - 0.5) / 0.5
            return Color(red: 1.0 - t * 0.7, green: 0.85 + t * 0.15, blue: t * 0.2)
        }
    }

    // MARK: - Month totals

    private var monthTotalsRow: some View {
        let totals = monthTotals
        let rated = totals.counts.values.reduce(0, +)
        let unrated = totals.totalEvents - rated

        return HStack(spacing: 8) {
            ForEach(SessionRating.allCases, id: \.rawValue) { rating in
                let count = totals.counts[rating] ?? 0
                HStack(spacing: 2) {
                    Image(systemName: rating.icon)
                        .font(.system(size: 10))
                        .foregroundColor(ratingColor(rating))
                    Text("\(count)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(count > 0 ? .primary : .secondary.opacity(0.4))
                }
            }

            Spacer()

            // Unrated
            HStack(spacing: 2) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("\(unrated)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(unrated > 0 ? .primary.opacity(0.6) : .secondary.opacity(0.4))
            }

            Divider().frame(height: 14)

            Text("\(totals.totalEvents)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary.opacity(0.5))

            if totals.focusMinutes > 0 {
                Divider().frame(height: 14)

                HStack(spacing: 2) {
                    Image(systemName: "target")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    Text(formatFocusTime(totals.focusMinutes))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.green)
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

    private func loadData() {
        dayStats = calendarService.monthlyFeedbackStats(year: year, month: month)
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
        case .partial: return .yellow
        case .skipped: return .red
        }
    }
}

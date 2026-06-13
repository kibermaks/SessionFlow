import SwiftUI

struct ProductivityCard: View {
    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var sessionAwarenessService: SessionAwarenessService
    @Environment(\.openSettings) private var openSettings
    let selectedDate: Date
    @State private var showingMonthly = false
    @State private var showingHelp = false
    @State private var selectedSessionType: SessionType? = nil
    @AppStorage("rightPanel.productivityExpanded") private var productivityExpanded = true

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

    private var reviewMetrics: ReviewMetrics {
        ReviewMetrics(
            slots: filteredSlots,
            focusWeights: sessionAwarenessService.config.focusWeights,
            alignmentWeights: sessionAwarenessService.config.alignmentWeights
        )
    }

    /// Card is visible only when at least one feedback has been set
    var hasFeedback: Bool {
        calendarService.busySlots.contains {
            SessionRating.fromNotes($0.notes) != nil || SessionAlignment.fromNotes($0.notes) != nil
        }
    }

    private struct ReviewMetrics {
        var ratingCounts: [SessionRating: Int] = [:]
        var alignmentCounts: [SessionAlignment: Int] = [:]
        var pastEvents = 0
        var spentMinutes = 0
        var focusMinutes = 0
        var alignedFocusMinutes = 0
        var alignmentEligibleFocusMinutes = 0
        var directFocusMinutes = 0
        var lowAlignmentFocusMinutes = 0
        var alignmentMissing = 0

        var rated: Int {
            ratingCounts.values.reduce(0, +)
        }

        var unrated: Int {
            max(0, pastEvents - rated)
        }

        var alignmentRated: Int {
            alignmentCounts.values.reduce(0, +)
        }

        var alignmentPercent: Int? {
            guard alignmentEligibleFocusMinutes > 0 else { return nil }
            return Int((Double(alignedFocusMinutes) / Double(alignmentEligibleFocusMinutes) * 100).rounded())
        }

        init(slots: [BusyTimeSlot], focusWeights: FocusWeights, alignmentWeights: AlignmentWeights) {
            var focusTotal: Double = 0
            var alignedTotal: Double = 0
            var alignmentEligibleTotal: Double = 0
            var spentTotal: Double = 0
            var directTotal: Double = 0
            var lowAlignmentTotal: Double = 0
            let now = Date()

            for slot in slots {
                if slot.endTime < now {
                    pastEvents += 1
                }

                guard let rating = SessionRating.fromNotes(slot.notes) else { continue }
                ratingCounts[rating, default: 0] += 1

                let minutes = slot.endTime.timeIntervalSince(slot.startTime) / 60
                let focus = minutes * focusWeights.multiplier(for: rating)
                let spent = rating == .skipped ? 0 : minutes
                spentTotal += spent
                focusTotal += focus
                let alignmentEligible = rating == .procrastinated ? minutes : max(0, focus)

                let alignment = SessionAlignment.fromNotes(slot.notes)
                let countsTowardAlignment = FlowFlexibilityNotes.countsTowardAlignmentScore(
                    slot.notes,
                    alignment: alignment
                )
                if countsTowardAlignment {
                    alignmentEligibleTotal += alignmentEligible
                }

                guard let alignment else {
                    if countsTowardAlignment {
                        alignmentMissing += 1
                    }
                    continue
                }

                alignmentCounts[alignment, default: 0] += 1
                let aligned = focus * alignmentWeights.multiplier(for: alignment)
                alignedTotal += aligned

                if alignment == .direct && focus > 0 {
                    directTotal += focus
                }
                if focus > 0 && alignmentWeights.multiplier(for: alignment) <= alignmentWeights.multiplier(for: .maintenance) {
                    lowAlignmentTotal += focus
                }
            }

            spentMinutes = Int(spentTotal)
            focusMinutes = Int(focusTotal)
            alignedFocusMinutes = Int(alignedTotal)
            alignmentEligibleFocusMinutes = Int(alignmentEligibleTotal)
            directFocusMinutes = Int(directTotal)
            lowAlignmentFocusMinutes = Int(lowAlignmentTotal)
        }
    }

    private struct DailyReviewPhrase {
        let text: String
        let icon: String
        let tone: Tone

        enum FocusBand {
            case none, light, solid, heavy
        }

        enum AlignmentBand {
            case unrated, poor, mixed, strong, excellent
        }

        enum Tone {
            case neutral, warning, mixed, good, great
        }

        func color(isDark: Bool) -> Color {
            switch tone {
            case .neutral: return isDark ? Color(hex: "A3A3A3") : Color(hex: "525252")
            case .warning: return .red
            case .mixed: return isDark ? Color(hex: "FACC15") : Color(hex: "A16207")
            case .good: return isDark ? Color(hex: "A78BFA") : Color(hex: "7C3AED")
            case .great: return isDark ? Color(hex: "34D399") : Color(hex: "047857")
            }
        }

        static func phrase(for metrics: ReviewMetrics, date: Date) -> DailyReviewPhrase {
            let focusBand = focusBand(for: metrics.focusMinutes)
            let alignmentBand = alignmentBand(for: metrics)
            let variants = phraseVariants(focusBand: focusBand, alignmentBand: alignmentBand)
            let seed = stableSeed(date: date, metrics: metrics)
            let text = variants[abs(seed) % variants.count]

            return DailyReviewPhrase(
                text: text,
                icon: icon(for: alignmentBand),
                tone: tone(for: alignmentBand)
            )
        }

        private static func focusBand(for minutes: Int) -> FocusBand {
            switch minutes {
            case ..<15: return .none
            case ..<90: return .light
            case ..<240: return .solid
            default: return .heavy
            }
        }

        private static func alignmentBand(for metrics: ReviewMetrics) -> AlignmentBand {
            guard metrics.alignmentRated > 0 else { return .unrated }
            guard let percent = metrics.alignmentPercent else { return .unrated }
            switch percent {
            case ..<25: return .poor
            case ..<50: return .mixed
            case ..<75: return .strong
            default: return .excellent
            }
        }

        private static func stableSeed(date: Date, metrics: ReviewMetrics) -> Int {
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
            return (parts.year ?? 0) * 10_000
                + (parts.month ?? 0) * 100
                + (parts.day ?? 0)
                + metrics.focusMinutes
                + metrics.alignedFocusMinutes
                + metrics.alignmentRated * 17
        }

        private static func phraseVariants(focusBand: FocusBand, alignmentBand: AlignmentBand) -> [String] {
            let indexableFocus = focusVariants(for: focusBand)
            let indexableAlignment = alignmentVariants(for: alignmentBand)
            return zip(indexableFocus, indexableAlignment).map { "\($0) \($1)" }
        }

        private static func focusVariants(for band: FocusBand) -> [String] {
            switch band {
            case .none:
                return [
                    "No reviewed focus yet.",
                    "Nothing meaningful is logged yet.",
                    "The day does not have a focus signal yet.",
                    "No scored work is on the board yet.",
                    "This day is still waiting for a review signal."
                ]
            case .light:
                return [
                    "A light focus day so far.",
                    "Some work landed, but the signal is still small.",
                    "You have a modest amount of reviewed focus.",
                    "The day has a little traction.",
                    "There is some focus here, just not a lot yet."
                ]
            case .solid:
                return [
                    "A productive day is forming.",
                    "You put real focus minutes on the board.",
                    "There is solid execution here.",
                    "The day has meaningful work behind it.",
                    "You built a real block of reviewed focus."
                ]
            case .heavy:
                return [
                    "A heavy focus day.",
                    "You spent a serious amount of energy.",
                    "There is a lot of execution in this day.",
                    "You carried a large focus load.",
                    "This was a substantial work day."
                ]
            }
        }

        private static func alignmentVariants(for band: AlignmentBand) -> [String] {
            switch band {
            case .unrated:
                return [
                    "Alignment is still unknown.",
                    "Add Alignment ratings to see if it served the goal.",
                    "The direction of that effort has not been judged yet.",
                    "Rate Alignment to separate motion from progress.",
                    "Goal fit is missing, so the day cannot be diagnosed yet."
                ]
            case .poor:
                return [
                    "Most of that effort missed the current goal.",
                    "The work was active, but it drifted away from the current goal.",
                    "Execution was not the issue; direction was.",
                    "A lot of energy leaked into low-value paths.",
                    "This is the pattern to catch early: busy, but off-target."
                ]
            case .mixed:
                return [
                    "Goal fit was mixed; useful motion, but with drift.",
                    "Some work helped, some pulled sideways.",
                    "The day had progress, but not enough direct pressure.",
                    "There is value here, but the opportunity cost is visible.",
                    "This is a split day: partly goal-serving, partly maintenance."
                ]
            case .strong:
                return [
                    "Most of the effort stayed close to the goal.",
                    "The work generally pointed in the right direction.",
                    "Good alignment: not perfect, but strategically useful.",
                    "The day converted focus into meaningful progress.",
                    "This was mostly goal-serving work."
                ]
            case .excellent:
                return [
                    "The work was tightly aimed at the goal.",
                    "High-quality effort landed where it mattered.",
                    "This is the ideal pattern: productive and aligned.",
                    "The day converted energy into direct goal movement.",
                    "Strong signal: your focus went to the right target."
                ]
            }
        }

        private static func icon(for band: AlignmentBand) -> String {
            switch band {
            case .unrated: return "questionmark.circle"
            case .poor: return "exclamationmark.triangle.fill"
            case .mixed: return "arrow.left.and.right"
            case .strong: return "scope"
            case .excellent: return "target"
            }
        }

        private static func tone(for band: AlignmentBand) -> Tone {
            switch band {
            case .unrated: return .neutral
            case .poor: return .warning
            case .mixed: return .mixed
            case .strong: return .good
            case .excellent: return .great
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.orange)
                Text("Focus & Alignment")
                    .font(.headline)
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .layoutPriority(1)

                Spacer()

                HStack(spacing: 3) {
                    Button {
                        showingHelp.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundColor(colors.textMuted)
                            .frame(width: 18, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(brightness: 0.3)
                    .popover(isPresented: $showingHelp) {
                        let w = sessionAwarenessService.config.focusWeights
                        let aw = sessionAwarenessService.config.alignmentWeights
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Your daily focus and alignment summary")
                                .font(.system(size: 13, weight: .semibold))

                            Text("Rate ended sessions on two axes: Focus measures execution quality; Alignment measures whether the work moved your current goal.")
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
                                Label("Procrastinated — counts \(w.procrastinatedPercent)% Focus, but still counts as spent time", systemImage: "iphone")
                                    .foregroundColor(.red)
                                Label("Skipped — counts \(w.skippedPercent)%", systemImage: "xmark.circle.fill")
                                    .foregroundColor(colors.isDark ? Color(hex: "94A3B8") : Color(hex: "64748B"))
                            }
                            .font(.system(size: 12))

                            Text("For example, a 1-hour event rated Done adds \(w.completedPercent * 60 / 100) min of focus time.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .italic()
                                .fixedSize(horizontal: false, vertical: true)

                            Divider()

                            Text("How Alignment works")
                                .font(.system(size: 12, weight: .semibold))

                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(SessionAlignment.allCases, id: \.rawValue) { alignment in
                                    Label("\(alignment.label) — counts \(aw.percent(for: alignment))% of Focus Time", systemImage: alignment.icon)
                                        .foregroundColor(alignmentColor(alignment))
                                }
                            }
                            .font(.system(size: 12))

                            Text("Alignment uses Focus Time as its denominator, except Procrastinated uses the full spent duration. External calendar events without Alignment are ignored for Alignment %.")
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
                    .help("Focus & Alignment help")

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
                        HStack(spacing: 3) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 12))
                            if let type = selectedSessionType {
                                Image(systemName: type.icon)
                                    .font(.system(size: 9))
                                    .foregroundColor(type.color)
                            }
                        }
                        .foregroundColor(isFiltering ? .accentColor : colors.textMuted)
                        .frame(width: isFiltering ? 24 : 18, height: 20)
                        .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .hoverEffect(brightness: 0.3)
                    .help("Filter by session type")

                    Button {
                        showingMonthly = true
                    } label: {
                        Image(systemName: "calendar")
                            .font(.system(size: 12))
                            .foregroundColor(colors.textMuted)
                            .frame(width: 18, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(brightness: 0.3)
                    .help("Monthly overview")

                    RightPanelCollapseButton(
                        isExpanded: $productivityExpanded,
                        expandedHelp: "Collapse Focus & Alignment",
                        collapsedHelp: "Expand Focus & Alignment"
                    )
                }
            }

            if productivityExpanded {
                VStack(alignment: .leading, spacing: 12) {
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

                    if sessionAwarenessService.config.dailyPhraseEnabled {
                        dailyPhraseCard
                    }

                    // Today's stats
                    todayStats
                    alignmentStats

                    if reviewMetrics.spentMinutes > 0 || reviewMetrics.focusMinutes != 0 || reviewMetrics.alignmentEligibleFocusMinutes > 0 || isFiltering {
                        focusSummary
                    }
                }
                .transition(.opacity)
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
        .animation(.easeOut(duration: 0.14), value: productivityExpanded)
        .sheet(isPresented: $showingMonthly) {
            MonthlyStatsView(selectedSessionType: $selectedSessionType)
                .environmentObject(calendarService)
                .environmentObject(sessionAwarenessService)
        }
    }

    // MARK: - Today stats

    private var todayStats: some View {
        let metrics = reviewMetrics
        return HStack(spacing: 0) {
            ForEach(SessionRating.allCases, id: \.rawValue) { rating in
                let count = metrics.ratingCounts[rating] ?? 0
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

            VStack(spacing: 4) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 14))
                    .foregroundColor(colors.textMuted)
                Text("\(metrics.unrated)")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(metrics.unrated > 0 ? colors.textSecondary : colors.textMuted)
            }
            .frame(maxWidth: .infinity)
            .help("Unrated")
        }
    }

    private var alignmentStats: some View {
        let metrics = reviewMetrics
        return HStack(spacing: 0) {
            ForEach(SessionAlignment.allCases, id: \.rawValue) { alignment in
                let count = metrics.alignmentCounts[alignment] ?? 0
                VStack(spacing: 4) {
                    Image(systemName: alignment.icon)
                        .font(.system(size: 13))
                        .foregroundColor(alignmentColor(alignment))
                    Text("\(count)")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundColor(count > 0 ? colors.textPrimary : colors.textMuted)
                }
                .frame(maxWidth: .infinity)
                .help("\(alignment.label): \(alignment.description)")
            }
        }
    }

    private var focusSummary: some View {
        let metrics = reviewMetrics
        let alignmentPercent = metrics.alignmentPercent ?? 0
        let hasAlignmentEligibleFocus = metrics.alignmentEligibleFocusMinutes > 0
        let alignmentColor = hasAlignmentEligibleFocus
            ? alignmentPercentColor(alignmentPercent)
            : colors.textMuted
        let focusColor = metrics.focusMinutes < 0
            ? .red
            : (colors.isDark ? .green : Color(hex: "15803D"))
        return VStack(spacing: 8) {
            metricRow(
                icon: "clock",
                label: "Spent Time",
                value: formatMinutes(metrics.spentMinutes),
                color: colors.textSecondary
            )
            metricRow(
                icon: "timer",
                label: "Focus Time",
                value: formatMinutes(metrics.focusMinutes),
                color: focusColor
            )
            metricRow(
                icon: "target",
                label: "Aligned Focus",
                value: hasAlignmentEligibleFocus ? formatMinutes(metrics.alignedFocusMinutes) : "—",
                color: alignmentColor
            )
            HStack(spacing: 8) {
                Text("Alignment")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colors.textSecondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(colors.divider)
                        Capsule()
                            .fill(alignmentPercentColor(alignmentPercent))
                            .frame(width: hasAlignmentEligibleFocus
                                ? geo.size.width * CGFloat(max(0, min(100, alignmentPercent))) / 100
                                : 0)
                    }
                }
                .frame(height: 6)
                Text(metrics.alignmentPercent.map { "\($0)%" } ?? "—")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(alignmentColor)
                    .frame(width: 42, alignment: .trailing)
            }
            if metrics.alignmentMissing > 0 {
                Label("\(metrics.alignmentMissing) rated session\(metrics.alignmentMissing == 1 ? "" : "s") missing Alignment", systemImage: "target")
                    .font(.system(size: 10))
                    .foregroundColor(colors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var dailyPhraseCard: some View {
        let phrase = DailyReviewPhrase.phrase(for: reviewMetrics, date: selectedDate)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: phrase.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(phrase.color(isDark: colors.isDark))
                .frame(width: 18, alignment: .center)
            Text(phrase.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(phrase.color(isDark: colors.isDark).opacity(colors.isDark ? 0.12 : 0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(phrase.color(isDark: colors.isDark).opacity(0.18), lineWidth: 1)
        )
    }

    private func metricRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let sign = minutes < 0 ? "-" : ""
        let absoluteMinutes = abs(minutes)
        let hours = absoluteMinutes / 60
        let mins = absoluteMinutes % 60
        if hours > 0 {
            return "\(sign)\(hours)h \(mins)m"
        }
        return "\(sign)\(mins)m"
    }

    private func ratingColor(_ rating: SessionRating) -> Color {
        awarenessRatingColor(rating, isDark: colors.isDark)
    }

    private func alignmentColor(_ alignment: SessionAlignment) -> Color {
        awarenessAlignmentColor(alignment, isDark: colors.isDark)
    }

    private func alignmentPercentColor(_ percent: Int) -> Color {
        switch percent {
        case 75...100: return colors.isDark ? Color(hex: "34D399") : Color(hex: "047857")
        case 50..<75: return colors.isDark ? Color(hex: "A78BFA") : Color(hex: "7C3AED")
        case 25..<50: return colors.isDark ? Color(hex: "FACC15") : Color(hex: "A16207")
        default: return .red
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
    @State private var selectedDay: Int?
    @State private var dayCellMetricMode: DayCellMetricMode = .focus

    private enum ViewMode { case month, year }

    private enum DayCellMetricMode: String, CaseIterable {
        case focus
        case alignment

        var icon: String {
            switch self {
            case .focus: return "timer"
            case .alignment: return "target"
            }
        }

        var help: String {
            switch self {
            case .focus: return "Show Focus Time in day cells"
            case .alignment: return "Show Alignment in day cells"
            }
        }
    }

    private struct MonthStat {
        var totalEvents: Int
        var spentMinutes: Int
        var focusMinutes: Int
        var alignedFocusMinutes: Int
        var alignmentEligibleFocusMinutes: Int
        var counts: [SessionRating: Int]
        var alignmentCounts: [SessionAlignment: Int]
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

    private var monthTotals: (
        counts: [SessionRating: Int],
        alignmentCounts: [SessionAlignment: Int],
        totalEvents: Int,
        spentMinutes: Int,
        focusMinutes: Int,
        alignedFocusMinutes: Int,
        alignmentEligibleFocusMinutes: Int
    ) {
        var counts: [SessionRating: Int] = [:]
        var alignmentCounts: [SessionAlignment: Int] = [:]
        var total = 0
        var spent: Double = 0
        var focus: Double = 0
        var alignedFocus: Double = 0
        var alignmentEligibleFocus: Double = 0
        for (_, stats) in dayStats {
            total += stats.totalEvents
            spent += stats.spentMinutes
            focus += stats.focusMinutes
            alignedFocus += stats.alignedFocusMinutes
            alignmentEligibleFocus += stats.alignmentEligibleFocusMinutes
            for (rating, count) in stats.counts {
                counts[rating, default: 0] += count
            }
            for (alignment, count) in stats.alignmentCounts {
                alignmentCounts[alignment, default: 0] += count
            }
        }
        return (
            counts: counts,
            alignmentCounts: alignmentCounts,
            totalEvents: total,
            spentMinutes: Int(spent),
            focusMinutes: Int(focus),
            alignedFocusMinutes: Int(alignedFocus),
            alignmentEligibleFocusMinutes: Int(alignmentEligibleFocus)
        )
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

    private var yearTotals: (
        totalEvents: Int,
        spentMinutes: Int,
        focusMinutes: Int,
        alignedFocusMinutes: Int,
        alignmentEligibleFocusMinutes: Int,
        counts: [SessionRating: Int],
        alignmentCounts: [SessionAlignment: Int]
    ) {
        var totalEvents = 0
        var spentMinutes = 0
        var focusMinutes = 0
        var alignedFocusMinutes = 0
        var alignmentEligibleFocusMinutes = 0
        var counts: [SessionRating: Int] = [:]
        var alignmentCounts: [SessionAlignment: Int] = [:]
        for (_, stat) in yearMonthStats {
            totalEvents += stat.totalEvents
            spentMinutes += stat.spentMinutes
            focusMinutes += stat.focusMinutes
            alignedFocusMinutes += stat.alignedFocusMinutes
            alignmentEligibleFocusMinutes += stat.alignmentEligibleFocusMinutes
            for (rating, count) in stat.counts {
                counts[rating, default: 0] += count
            }
            for (alignment, count) in stat.alignmentCounts {
                alignmentCounts[alignment, default: 0] += count
            }
        }
        return (
            totalEvents: totalEvents,
            spentMinutes: spentMinutes,
            focusMinutes: focusMinutes,
            alignedFocusMinutes: alignedFocusMinutes,
            alignmentEligibleFocusMinutes: alignmentEligibleFocusMinutes,
            counts: counts,
            alignmentCounts: alignmentCounts
        )
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
                    alignmentCounts: yearTotals.alignmentCounts,
                    totalEvents: yearTotals.totalEvents,
                    spentMinutes: yearTotals.spentMinutes,
                    focusMinutes: yearTotals.focusMinutes,
                    alignedFocusMinutes: yearTotals.alignedFocusMinutes,
                    alignmentEligibleFocusMinutes: yearTotals.alignmentEligibleFocusMinutes
                ))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 520)
        .onAppear { loadData() }
        .onChange(of: selectedSessionType) { _, _ in
            selectedDay = nil
            loadData()
            if viewMode == .year { loadYearData() }
        }
        .onChange(of: sessionAwarenessService.config.focusWeights) { _, _ in
            loadData()
            if viewMode == .year { loadYearData() }
        }
        .onChange(of: sessionAwarenessService.config.alignmentWeights) { _, _ in
            loadData()
            if viewMode == .year { loadYearData() }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 10) {
            Text("Focus & Alignment")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .layoutPriority(1)

            Spacer()

            HStack(spacing: 4) {
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
                .menuIndicator(.hidden)
                .fixedSize()
                .focusable(false)
                .hoverEffect(brightness: 0.2)
                .help("Filter by session type")

                if viewMode == .month {
                    dayCellMetricToggle
                }

                monthYearModeSelector

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect(brightness: 0.2)
                .focusable(false)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var dayCellMetricToggle: some View {
        HStack(spacing: 1) {
            ForEach(DayCellMetricMode.allCases, id: \.rawValue) { mode in
                Button {
                    dayCellMetricMode = mode
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(dayCellMetricMode == mode ? .accentColor : .secondary)
                        .frame(width: 23, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(dayCellMetricMode == mode ? Color.accentColor.opacity(0.14) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect(brightness: 0.2)
                .focusable(false)
                .help(mode.help)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
    }

    private var monthYearModeSelector: some View {
        HStack(spacing: 1) {
            modeButton(mode: .month, icon: "calendar", help: "Month view")
            modeButton(mode: .year, icon: "list.bullet", help: "Year overview")
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
    }

    private func modeButton(mode: ViewMode, icon: String, help: String) -> some View {
        Button {
            setViewMode(mode)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(viewMode == mode ? .accentColor : .secondary)
                .frame(width: 23, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(viewMode == mode ? Color.accentColor.opacity(0.14) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(brightness: 0.2)
        .focusable(false)
        .help(help)
    }

    private func setViewMode(_ mode: ViewMode) {
        guard viewMode != mode else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            viewMode = mode
        }
        if mode == .year {
            loadYearData()
        } else {
            loadData()
        }
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

        return VStack(spacing: 4) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { col in
                        let cellIndex = row * 7 + col
                        let day = cellIndex - firstWeekday + 1

                        if day >= 1 && day <= daysInMonth {
                            dayCellView(day: day)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, minHeight: 70, maxHeight: 70)
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
        let ratedTotal = stats?.sessionReviews.count ?? 0
        let metric = dayCellMetric(stats: stats, isFuture: isFuture)

        return Button {
            selectedDay = day
        } label: {
            VStack(spacing: 3) {
                Text("\(day)")
                    .font(.system(size: 12, weight: isToday ? .bold : .regular))
                    .foregroundColor(isFuture ? .secondary.opacity(0.3) : (isToday ? .primary : .primary.opacity(0.7)))

                if ratedTotal > 0 {
                    feedbackDots(stats: stats!)
                } else {
                    Color.clear.frame(height: 9)
                }

                Text(metric.text)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(metric.color)
            }
            .frame(maxWidth: .infinity, minHeight: 70, maxHeight: 70)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isToday ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(isToday ? 0.0 : 0.07), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(brightness: isFuture && stats == nil ? 0 : 0.1)
        .help(dayCellHelp(date: cellDate, stats: stats, isFuture: isFuture))
        .disabled(isFuture && stats == nil)
        .popover(isPresented: Binding(
            get: { selectedDay == day },
            set: { if !$0 { selectedDay = nil } }
        )) {
            dayDetailPopover(day: day, date: cellDate, stats: stats)
        }
    }

    /// Shows one dot per reviewed event: Focus color on top, Alignment color underneath.
    private func feedbackDots(stats: CalendarService.DayFeedbackStats) -> some View {
        let maxDots = 8
        let displayReviews = Array(stats.sessionReviews.prefix(maxDots))

        return HStack(alignment: .top, spacing: 2) {
            ForEach(displayReviews) { review in
                VStack(spacing: 1) {
                    Circle()
                        .fill(ratingColor(review.rating))
                        .frame(width: 4, height: 4)
                    Capsule()
                        .fill(alignmentMarkerColor(review.alignment))
                        .frame(width: 4, height: 2)
                }
                .help("\(review.rating.label) / \(review.alignment?.label ?? "Alignment missing")")
            }
            if stats.sessionReviews.count > maxDots {
                Text("+")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 9)
    }

    private func dayFocusLabel(_ minutes: Double) -> String {
        let m = Int(minutes)
        if m >= 60 {
            return "\(m / 60)h\(m % 60 > 0 ? "\(m % 60)" : "")"
        }
        return "\(m)m"
    }

    private func dayCellMetric(stats: CalendarService.DayFeedbackStats?, isFuture: Bool) -> (text: String, color: Color) {
        switch dayCellMetricMode {
        case .focus:
            guard let stats else {
                return (isFuture ? "—" : "0m", .secondary.opacity(isFuture ? 0.3 : 0.45))
            }
            let minutes = stats.focusMinutes
            return (dayFocusLabel(minutes), minutes > 0 ? focusColor(minutes) : .secondary.opacity(0.45))
        case .alignment:
            guard let stats, stats.sessionReviews.count > 0 else {
                return ("—", .secondary.opacity(isFuture ? 0.3 : 0.45))
            }
            guard let percent = dayAlignmentPercent(stats) else {
                return ("—", .secondary.opacity(0.55))
            }
            return ("\(percent)%", alignmentPercentColor(percent))
        }
    }

    private func dayCellHelp(date: Date, stats: CalendarService.DayFeedbackStats?, isFuture: Bool) -> String {
        let title = dayDateTitle(date)
        guard let stats else {
            return isFuture ? title : "\(title): no sessions found"
        }

        let reviewed = stats.sessionReviews.count
        let alignmentText = dayAlignmentPercent(stats).map { ", \($0)% alignment" } ?? ""
        return "\(title): \(reviewed)/\(stats.totalEvents) reviewed, \(formatFocusTime(Int(stats.focusMinutes.rounded()))) focus\(alignmentText)"
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

    private func dayDetailPopover(day: Int, date: Date, stats optionalStats: CalendarService.DayFeedbackStats?) -> some View {
        let stats = optionalStats ?? CalendarService.DayFeedbackStats()
        let rated = stats.sessionReviews.count
        let alignmentMissing = stats.alignmentMissing
        let phrase = dayDetailPhrase(for: stats, date: date)
        let alignmentPercent = dayAlignmentPercent(stats)
        let hasReviews = rated > 0

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayDateTitle(date))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("\(stats.totalEvents) session\(stats.totalEvents == 1 ? "" : "s") planned or found")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("#\(day)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: phrase.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(phrase.color)
                    .frame(width: 18)
                Text(phrase.text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(phrase.color.opacity(colors.isDark ? 0.14 : 0.09))
            )

            VStack(spacing: 7) {
                dayMetricRow(
                    icon: "clock",
                    label: "Spent Time",
                    value: hasReviews ? formatFocusTime(Int(stats.spentMinutes.rounded())) : "—",
                    color: .secondary
                )
                dayMetricRow(
                    icon: "timer",
                    label: "Focus Time",
                    value: hasReviews ? formatFocusTime(Int(stats.focusMinutes.rounded())) : "—",
                    color: stats.focusMinutes < 0 ? .red : (colors.isDark ? .green : Color(hex: "15803D"))
                )
                dayMetricRow(
                    icon: "target",
                    label: "Aligned Focus",
                    value: stats.alignmentRated > 0 ? formatFocusTime(Int(stats.alignedFocusMinutes.rounded())) : "—",
                    color: alignmentPercent.map(alignmentPercentColor) ?? .secondary
                )
                dayMetricRow(
                    icon: "scope",
                    label: "Alignment",
                    value: alignmentPercent.map { "\($0)%" } ?? "—",
                    color: alignmentPercent.map(alignmentPercentColor) ?? .secondary
                )
                dayMetricRow(
                    icon: "checkmark.circle",
                    label: "Reviewed",
                    value: "\(rated)/\(stats.totalEvents)",
                    color: rated > 0 ? .accentColor : .secondary
                )
                if stats.unrated > 0 {
                    dayMetricRow(
                        icon: "questionmark.circle",
                        label: "Unrated",
                        value: "\(stats.unrated)",
                        color: .secondary
                    )
                }
                if alignmentMissing > 0 {
                    dayMetricRow(
                        icon: "target",
                        label: "Missing Alignment",
                        value: "\(alignmentMissing)",
                        color: .secondary
                    )
                }
            }

            if stats.totalEvents > 0 {
                Divider()
                dayDistribution(stats: stats)
            }

            if !stats.sessionReviews.isEmpty {
                Divider()
                daySessionList(stats.sessionReviews)
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    private func dayDistribution(stats: CalendarService.DayFeedbackStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Breakdown")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 0) {
                ForEach(SessionRating.allCases, id: \.rawValue) { rating in
                    dayCountPill(
                        icon: rating.icon,
                        count: stats.counts[rating] ?? 0,
                        color: ratingColor(rating),
                        help: rating.label
                    )
                }
                dayCountPill(
                    icon: "questionmark.circle",
                    count: stats.unrated,
                    color: .secondary.opacity(0.6),
                    help: "Unrated"
                )
            }

            HStack(spacing: 0) {
                ForEach(SessionAlignment.allCases, id: \.rawValue) { alignment in
                    dayCountPill(
                        icon: alignment.icon,
                        count: stats.alignmentCounts[alignment] ?? 0,
                        color: alignmentColor(alignment),
                        help: alignment.label
                    )
                }
            }
        }
    }

    private func daySessionList(_ reviews: [CalendarService.DaySessionReview]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sessions")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            ForEach(Array(reviews.prefix(6))) { review in
                let alignmentText = review.alignment?.shortLabel
                    ?? (review.alignmentCountsTowardScore ? "No alignment" : "Optional")
                HStack(spacing: 8) {
                    VStack(spacing: 2) {
                        Circle()
                            .fill(ratingColor(review.rating))
                            .frame(width: 7, height: 7)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(alignmentMarkerColor(review.alignment))
                            .frame(width: 7, height: 3)
                    }
                    .frame(width: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(review.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary.opacity(0.82))
                            .lineLimit(1)
                        Text("\(timeRange(review.startDate, review.endDate)) · \(formatFocusTime(review.durationMinutes)) spent · \(formatFocusTime(review.focusMinutes)) focus · \(alignmentText)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
            }

            if reviews.count > 6 {
                Text("+\(reviews.count - 6) more reviewed session\(reviews.count - 6 == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func dayMetricRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
                .frame(width: 14)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
    }

    private func dayCountPill(icon: String, count: Int, color: Color, help: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(count > 0 ? color : .secondary.opacity(0.25))
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(count > 0 ? .primary.opacity(0.78) : .secondary.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .help(help)
    }

    private func dayDetailPhrase(for stats: CalendarService.DayFeedbackStats, date: Date) -> (icon: String, text: String, color: Color) {
        let rated = stats.sessionReviews.count
        if stats.totalEvents == 0 {
            return ("calendar.badge.exclamationmark", "No sessions found for this day yet.", .secondary)
        }
        if rated == 0 {
            return ("questionmark.circle", "There are sessions here, but no Focus review yet.", .secondary)
        }
        guard stats.alignmentRated > 0, let percent = dayAlignmentPercent(stats) else {
            return ("target", "Focus is logged, but Alignment is still missing for this day.", .secondary)
        }

        let focusText = formatFocusTime(Int(stats.focusMinutes.rounded()))
        let variants: [String]
        let icon: String
        let color: Color
        switch percent {
        case 75...100:
            icon = "target"
            color = alignmentPercentColor(percent)
            variants = [
                "\(focusText) of Focus mostly landed on the goal.",
                "Strong day: \(percent)% Alignment turned focus into goal movement.",
                "This day stayed aimed: \(focusText) focused, \(percent)% aligned.",
                "Good signal: the work was productive and goal-serving.",
                "Most of the reviewed effort pointed where it mattered."
            ]
        case 50..<75:
            icon = "scope"
            color = alignmentPercentColor(percent)
            variants = [
                "\(focusText) of Focus with useful, but imperfect, Alignment.",
                "The day helped the goal, though some drift is visible.",
                "\(percent)% Alignment: solid motion, not fully direct.",
                "Mostly useful work, with room to tighten the target.",
                "Focus was real; the goal fit was mixed-positive."
            ]
        case 25..<50:
            icon = "arrow.left.and.right"
            color = alignmentPercentColor(percent)
            variants = [
                "\(focusText) of Focus, but the goal fit was split.",
                "\(percent)% Alignment: useful work competed with sideways motion.",
                "There is progress here, but opportunity cost is visible.",
                "The day had effort; it needs a sharper target next time.",
                "Some sessions helped, but the overall direction drifted."
            ]
        default:
            icon = "exclamationmark.triangle.fill"
            color = alignmentPercentColor(percent)
            variants = [
                "\(focusText) of Focus mostly missed the current goal.",
                "\(percent)% Alignment: productive time went sideways.",
                "The execution may be there, but this day did not serve the goal.",
                "This is the pattern to catch: focus without payoff.",
                "The day needs a stricter filter against non-goal work."
            ]
        }

        let seed = Calendar.current.component(.day, from: date) + Int(stats.focusMinutes.rounded()) + stats.alignmentRated * 17
        return (icon, variants[abs(seed) % variants.count], color)
    }

    private func dayDateTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: date)
    }

    private func timeRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start))-\(formatter.string(from: end))"
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
        let alignmentPercent = stat.flatMap { monthAlignmentPercent($0) }

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

                    if let stat, stat.spentMinutes > 0 || stat.focusMinutes != 0 || stat.alignmentEligibleFocusMinutes > 0 {
                        VStack(alignment: .trailing, spacing: 1) {
                            HStack(spacing: 3) {
                                Image(systemName: "clock")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary.opacity(0.8))
                                Text(formatFocusTime(stat.spentMinutes))
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Image(systemName: "timer")
                                    .font(.system(size: 10))
                                    .foregroundColor(stat.focusMinutes > 0 ? (colors.isDark ? .green.opacity(0.8) : Color(hex: "15803D")) : .secondary.opacity(0.5))
                                Text(formatFocusTime(stat.focusMinutes))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(stat.focusMinutes > 0 ? (colors.isDark ? .green : Color(hex: "15803D")) : .secondary)
                            }
                            if let alignmentPercent {
                                HStack(spacing: 3) {
                                    Image(systemName: "target")
                                        .font(.system(size: 9, weight: .semibold))
                                    Text("\(alignmentPercent)%")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                }
                                .foregroundColor(alignmentPercentColor(alignmentPercent))
                            }
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
        .hoverEffect(brightness: isFuture ? 0 : 0.08)
        .help(yearMonthHelp(month: m, stat: stat, isFuture: isFuture))
    }

    private func yearMonthHelp(month m: Int, stat: MonthStat?, isFuture: Bool) -> String {
        let monthTitle = fullMonthName(for: m)
        guard let stat else {
            return isFuture ? monthTitle : "\(monthTitle): no sessions found"
        }

        let alignmentText = monthAlignmentPercent(stat).map { ", \($0)% alignment" } ?? ""
        return "\(monthTitle): \(stat.rated)/\(stat.totalEvents) reviewed, \(formatFocusTime(stat.focusMinutes)) focus\(alignmentText)"
    }

    // MARK: - Totals rows

    private var monthTotalsRow: some View {
        let totals = monthTotals
        return aggregateTotalsRow(totals: (
            counts: totals.counts,
            alignmentCounts: totals.alignmentCounts,
            totalEvents: totals.totalEvents,
            spentMinutes: totals.spentMinutes,
            focusMinutes: totals.focusMinutes,
            alignedFocusMinutes: totals.alignedFocusMinutes,
            alignmentEligibleFocusMinutes: totals.alignmentEligibleFocusMinutes
        ))
    }

    private func aggregateTotalsRow(totals: (
        counts: [SessionRating: Int],
        alignmentCounts: [SessionAlignment: Int],
        totalEvents: Int,
        spentMinutes: Int,
        focusMinutes: Int,
        alignedFocusMinutes: Int,
        alignmentEligibleFocusMinutes: Int
    )) -> some View {
        let rated = totals.counts.values.reduce(0, +)
        let unrated = totals.totalEvents - rated
        let alignmentPercent = totals.alignmentEligibleFocusMinutes > 0
            ? Int((Double(totals.alignedFocusMinutes) / Double(totals.alignmentEligibleFocusMinutes) * 100).rounded())
            : nil
        let hasAlignmentEligibleFocus = totals.alignmentEligibleFocusMinutes > 0
        let alignmentSummaryColor = alignmentPercent.map(alignmentPercentColor) ?? .secondary

        return VStack(spacing: 8) {
            HStack(spacing: 10) {
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
            }

            HStack(spacing: 8) {
                ForEach(SessionAlignment.allCases, id: \.rawValue) { alignment in
                    let count = totals.alignmentCounts[alignment] ?? 0
                    HStack(spacing: 3) {
                        Image(systemName: alignment.icon)
                            .font(.system(size: 11))
                            .foregroundColor(alignmentColor(alignment))
                        Text("\(count)")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(count > 0 ? .primary : .secondary.opacity(0.4))
                    }
                    .help("\(alignment.label): \(alignment.description)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if totals.spentMinutes > 0 || totals.focusMinutes != 0 || totals.alignmentEligibleFocusMinutes > 0 {
                HStack(spacing: 12) {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("Spent")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(formatFocusTime(totals.spentMinutes))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 3) {
                        Image(systemName: "timer")
                            .font(.system(size: 12))
                            .foregroundColor(colors.isDark ? .green : Color(hex: "15803D"))
                        Text("Focus")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(formatFocusTime(totals.focusMinutes))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(colors.isDark ? .green : Color(hex: "15803D"))
                    }

                    HStack(spacing: 3) {
                        Image(systemName: "target")
                            .font(.system(size: 12))
                            .foregroundColor(alignmentSummaryColor)
                        Text("Aligned")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(hasAlignmentEligibleFocus ? formatFocusTime(totals.alignedFocusMinutes) : "—")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(alignmentSummaryColor)
                    }

                    Spacer()

                    Text(alignmentPercent.map { "\($0)%" } ?? "—")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(alignmentSummaryColor)
                        .help("Alignment percentage")
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
            alignmentWeights: sessionAwarenessService.config.alignmentWeights,
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
                alignmentWeights: sessionAwarenessService.config.alignmentWeights,
                sessionType: selectedSessionType
            )
            var totalEvents = 0
            var spentMinutes: Double = 0
            var focusMinutes: Double = 0
            var alignedFocusMinutes: Double = 0
            var alignmentEligibleFocusMinutes: Double = 0
            var counts: [SessionRating: Int] = [:]
            var alignmentCounts: [SessionAlignment: Int] = [:]
            for (_, dayStat) in dayData {
                totalEvents += dayStat.totalEvents
                spentMinutes += dayStat.spentMinutes
                focusMinutes += dayStat.focusMinutes
                alignedFocusMinutes += dayStat.alignedFocusMinutes
                alignmentEligibleFocusMinutes += dayStat.alignmentEligibleFocusMinutes
                for (rating, count) in dayStat.counts {
                    counts[rating, default: 0] += count
                }
                for (alignment, count) in dayStat.alignmentCounts {
                    alignmentCounts[alignment, default: 0] += count
                }
            }
            stats[m] = MonthStat(
                totalEvents: totalEvents,
                spentMinutes: Int(spentMinutes),
                focusMinutes: Int(focusMinutes),
                alignedFocusMinutes: Int(alignedFocusMinutes),
                alignmentEligibleFocusMinutes: Int(alignmentEligibleFocusMinutes),
                counts: counts,
                alignmentCounts: alignmentCounts
            )
        }
        yearMonthStats = stats
    }

    private func formatFocusTime(_ minutes: Int) -> String {
        let sign = minutes < 0 ? "-" : ""
        let absoluteMinutes = abs(minutes)
        let hours = absoluteMinutes / 60
        let mins = absoluteMinutes % 60
        if hours > 0 {
            return "\(sign)\(hours)h \(mins)m"
        }
        return "\(sign)\(mins)m"
    }

    private func ratingColor(_ rating: SessionRating) -> Color {
        awarenessRatingColor(rating, isDark: colors.isDark)
    }

    private func alignmentColor(_ alignment: SessionAlignment) -> Color {
        awarenessAlignmentColor(alignment, isDark: colors.isDark)
    }

    private func alignmentMarkerColor(_ alignment: SessionAlignment?) -> Color {
        guard let alignment else { return .secondary.opacity(0.35) }
        return alignmentColor(alignment)
    }

    private func dayAlignmentPercent(_ stats: CalendarService.DayFeedbackStats) -> Int? {
        guard stats.alignmentEligibleFocusMinutes > 0 else { return nil }
        return Int((stats.alignedFocusMinutes / stats.alignmentEligibleFocusMinutes * 100).rounded())
    }

    private func monthAlignmentPercent(_ stat: MonthStat) -> Int? {
        guard stat.alignmentEligibleFocusMinutes > 0 else { return nil }
        return Int((Double(stat.alignedFocusMinutes) / Double(stat.alignmentEligibleFocusMinutes) * 100).rounded())
    }

    private func alignmentPercentColor(_ percent: Int) -> Color {
        switch percent {
        case 75...100: return colors.isDark ? Color(hex: "34D399") : Color(hex: "047857")
        case 50..<75: return colors.isDark ? Color(hex: "A78BFA") : Color(hex: "7C3AED")
        case 25..<50: return colors.isDark ? Color(hex: "FACC15") : Color(hex: "A16207")
        default: return .red
        }
    }

}

import SwiftUI

// MARK: - Formatting Utilities

func formatSessionTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

func formatSessionTimeRange(start: Date, end: Date) -> String {
    return "\(formatSessionTime(start)) – \(formatSessionTime(end))"
}

var awarenessSessionMetaColumnWidth: CGFloat {
    uses12HourClock ? 160 : 110
}

var uses12HourClock: Bool {
    let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.autoupdatingCurrent) ?? ""
    return format.contains("a")
}

func formatSessionDuration(_ interval: TimeInterval) -> String {
    let totalSeconds = max(0, Int(interval))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
}

func nextSessionTimeDescription(start: Date, end: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    let durationMinutes = Int(end.timeIntervalSince(start) / 60)
    return "\(formatter.string(from: start)) - \(formatter.string(from: end)) \u{2022} \(durationMinutes) min"
}

func awarenessRatingColor(_ rating: SessionRating, isDark: Bool = true) -> Color {
    switch rating {
    case .rocket: return .orange
    case .completed: return .green
    case .partial: return isDark ? .yellow : Color(hex: "92400E")
    case .skipped: return .red
    }
}

func awarenessIconName(service: SessionAwarenessService) -> String {
    service.isBusySlotMode ? "calendar" : (service.currentSessionType?.icon ?? "circle")
}

func awarenessIconColor(service: SessionAwarenessService) -> Color {
    service.isBusySlotMode ? (service.busySlotCalendarColor ?? .gray) : (service.currentSessionType?.color ?? .gray)
}

func awarenessBarColor(service: SessionAwarenessService) -> Color {
    service.isBusySlotMode
        ? (service.busySlotCalendarColor ?? .gray)
        : (service.currentSessionType?.color ?? .blue)
}

// MARK: - Divider

struct AwarenessDivider: View {
    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    var body: some View {
        Rectangle()
            .fill(colors.divider)
            .frame(width: 1, height: 32)
            .padding(.horizontal, 8)
    }
}

// MARK: - Skip Session Button

struct AwarenessSkipSessionButton: View {
    @ObservedObject var awarenessService: SessionAwarenessService

    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    var body: some View {
        if awarenessService.isActive || awarenessService.isResting {
            Button {
                awarenessService.toggleSessionMute()
            } label: {
                Image(systemName: awarenessService.isSessionMuted ? "forward.end.fill" : "forward.end")
                    .font(.system(size: 13))
                    .foregroundColor(awarenessService.isSessionMuted ? (colors.isDark ? .yellow.opacity(0.9) : Color(hex: "D97706")) : colors.textMuted)
                    .frame(width: 32, height: 32)
                    .background(awarenessService.isSessionMuted ? (colors.isDark ? Color.yellow.opacity(0.12) : Color(hex: "FEF3C7")) : colors.subtleBackground)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(awarenessService.isSessionMuted ? (colors.isDark ? Color.yellow.opacity(0.25) : Color(hex: "D97706").opacity(0.4)) : Color.clear, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: 0.2)
            .help(awarenessService.isSessionMuted ? "Resume sounds" : "Mute until next session")
        }
    }
}

// MARK: - Mute Button

struct AwarenessMuteButton: View {
    @ObservedObject var audioService: SessionAudioService
    @ObservedObject var awarenessService: SessionAwarenessService

    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    var body: some View {
        Button {
            let newValue = !audioService.muteEnabled
            audioService.muteEnabled = newValue
            awarenessService.config.muteEnabled = newValue
        } label: {
            iconView
                .frame(width: 32, height: 32)
                .background(colors.subtleBackground)
                .cornerRadius(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(brightness: 0.2)
        .help(helpText)
    }

    @ViewBuilder
    private var iconView: some View {
        if audioService.muteEnabled {
            // Manually muted
            Image(systemName: "speaker.slash.fill")
                .font(.system(size: 14))
                .foregroundColor(.red.opacity(0.6))
        } else if audioService.micAwareEnabled {
            // Mic-aware mode
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: audioService.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 14))
                    .foregroundColor(audioService.isMuted ? .orange.opacity(0.7) : colors.textSecondary)
                Text("A")
                    .font(.system(size: 7, weight: .heavy, design: .rounded))
                    .foregroundColor(audioService.isMuted ? .orange.opacity(0.7) : (colors.isDark ? .green.opacity(0.7) : Color(hex: "15803D")))
                    .offset(x: 3, y: 3)
            }
        } else {
            // Normal
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 14))
                .foregroundColor(colors.textSecondary)
        }
    }

    private var helpText: String {
        if audioService.muteEnabled {
            return "Unmute sounds"
        } else if audioService.micAwareEnabled && audioService.isMuted {
            return "Auto-muted (mic in use)"
        } else {
            return "Mute all sounds"
        }
    }
}

// MARK: - Feedback Rating Button

struct AwarenessFeedbackButton: View {
    let rating: SessionRating
    let onSubmit: (SessionRating) -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let color = awarenessRatingColor(rating, isDark: colorScheme == .dark)

        Button {
            onSubmit(rating)
        } label: {
            Image(systemName: rating.icon)
                .font(.system(size: 16))
                .foregroundColor(color.opacity(0.9))
                .frame(width: 40, height: 32)
                .background(color.opacity(0.12))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(brightness: 0.2)
        .help(rating.label)
    }
}

// MARK: - Session Info (icon + title + notes with popover)

struct AwarenessSessionInfo: View {
    @ObservedObject var awarenessService: SessionAwarenessService
    @Binding var showingEventInfo: Bool

    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: awarenessIconName(service: awarenessService))
                .font(.system(size: 18))
                .foregroundColor(awarenessIconColor(service: awarenessService))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(awarenessService.currentSessionTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.tail)

                if awarenessService.config.harshModeEnabled && awarenessService.config.harshModeShowGoalsInAwareness {
                    let goals = HarshModeSessionNotes.goals(from: awarenessService.currentEventNotes)
                    if !goals.isEmpty {
                        HStack(alignment: .top, spacing: 5) {
                            Image(systemName: "scope")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(colors.isDark ? .orange.opacity(0.95) : Color(hex: "C2410C"))
                                .padding(.top, 1)
                            Text(goalReminderText(goals))
                                .font(.system(size: awarenessService.config.harshModeReminderStyle == .prominent ? 12 : 11, weight: .semibold))
                                .foregroundColor(colors.isDark ? .orange.opacity(0.95) : Color(hex: "C2410C"))
                                .lineLimit(awarenessService.config.harshModeReminderStyle == .prominent ? 2 : 1)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, awarenessService.config.harshModeReminderStyle == .prominent ? 7 : 0)
                        .padding(.vertical, awarenessService.config.harshModeReminderStyle == .prominent ? 3 : 0)
                        .background(goalReminderBackground)
                        .overlay(goalReminderBorder)
                        .cornerRadius(5)
                    }
                }

                if let notes = SessionAwarenessService.strippedNotes(awarenessService.currentEventNotes) {
                    HStack(alignment: .top, spacing: 4) {
                        Text(notes)
                            .font(.system(size: 11))
                            .foregroundColor(colors.textMuted)
                            .lineLimit(2)
                            .truncationMode(.tail)

                        Button {
                            showingEventInfo.toggle()
                        } label: {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(brightness: 0.3)
                        .popover(isPresented: $showingEventInfo) {
                            AwarenessEventInfoPopover(awarenessService: awarenessService)
                        }
                    }
                }
            }
        }
    }

    private func goalReminderText(_ goals: [String]) -> String {
        switch awarenessService.config.harshModeReminderStyle {
        case .compact:
            return goals.first ?? ""
        case .prominent:
            return goals.prefix(2).joined(separator: " / ")
        }
    }

    @ViewBuilder
    private var goalReminderBackground: some View {
        if awarenessService.config.harshModeReminderStyle == .prominent {
            colors.isDark ? Color.orange.opacity(0.12) : Color(hex: "FFEDD5")
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var goalReminderBorder: some View {
        if awarenessService.config.harshModeReminderStyle == .prominent {
            RoundedRectangle(cornerRadius: 5)
                .stroke(colors.isDark ? Color.orange.opacity(0.22) : Color(hex: "FDBA74"), lineWidth: 1)
        }
    }
}

// MARK: - Session Meta Column

struct AwarenessSessionMeta: View {
    @ObservedObject var awarenessService: SessionAwarenessService

    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let start = awarenessService.sessionStartTime, let end = awarenessService.sessionEndTime {
                Text(formatSessionTimeRange(start: start, end: end))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(1)
            }
            if awarenessService.isBusySlotMode {
                Text(awarenessService.busySlotCalendarName ?? "Calendar")
                    .font(.system(size: 12))
                    .foregroundColor((awarenessService.busySlotCalendarColor ?? .gray).opacity(0.8))
            } else if let type = awarenessService.currentSessionType {
                Text(type.rawValue)
                    .font(.system(size: 12))
                    .foregroundColor(type.color.opacity(0.8))
            }
        }
    }
}

// MARK: - Event Info Popover

struct AwarenessEventInfoPopover: View {
    @ObservedObject var awarenessService: SessionAwarenessService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(awarenessService.currentSessionTitle)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.primary)

            if let start = awarenessService.sessionStartTime, let end = awarenessService.sessionEndTime {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(formatSessionTimeRange(start: start, end: end))
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                }
            }

            if let type = awarenessService.currentSessionType {
                HStack(spacing: 6) {
                    Image(systemName: type.icon)
                        .font(.system(size: 11))
                        .foregroundColor(type.color)
                    Text(type.rawValue)
                        .font(.system(size: 12))
                }
            }

            if awarenessService.isBusySlotMode {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                        .foregroundColor(awarenessService.busySlotCalendarColor ?? .gray)
                    Text(awarenessService.busySlotCalendarName ?? "Calendar")
                        .font(.system(size: 12))
                }
            }

            if let notes = SessionAwarenessService.strippedNotes(awarenessService.currentEventNotes) {
                Divider()
                Text(notes)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(minWidth: 200, maxWidth: 300)
    }
}

// MARK: - Progress Bar

struct AwarenessProgressBar: View {
    @ObservedObject var awarenessService: SessionAwarenessService
    @ObservedObject private var timeState: SessionTimeState

    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    init(awarenessService: SessionAwarenessService) {
        _awarenessService = ObservedObject(wrappedValue: awarenessService)
        _timeState = ObservedObject(wrappedValue: awarenessService.timeState)
    }

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                let barColor = awarenessBarColor(service: awarenessService)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(colors.divider)

                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(barColor)
                        .frame(width: max(0, geo.size.width * CGFloat(awarenessService.progress)))
                }
            }
            .frame(height: 6)

            HStack {
                Text(formatSessionDuration(awarenessService.elapsed))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer()

                Text(formatSessionDuration(awarenessService.remaining))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

// MARK: - Clickable Time Display

struct AwarenessClickableTime: View {
    @ObservedObject var awarenessService: SessionAwarenessService
    @ObservedObject private var timeState: SessionTimeState

    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    init(awarenessService: SessionAwarenessService) {
        _awarenessService = ObservedObject(wrappedValue: awarenessService)
        _timeState = ObservedObject(wrappedValue: awarenessService.timeState)
    }

    private var timeText: String {
        let time: TimeInterval = awarenessService.timeDisplayMode == .remaining
            ? awarenessService.remaining : awarenessService.elapsed
        return formatSessionDuration(time)
    }

    private var timeLabel: String {
        awarenessService.timeDisplayMode == .remaining ? "remaining" : "elapsed"
    }

    var body: some View {
        VStack(spacing: 1) {
            Text(timeText)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundColor(colors.textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(timeLabel)
                .font(.system(size: 10))
                .foregroundColor(colors.textMuted)
                .lineLimit(1)
        }
        .frame(width: 76)
        .contentShape(Rectangle())
        .onTapGesture {
            awarenessService.cycleTimeDisplay()
        }
        .help("Click to toggle remaining/elapsed")
    }
}

// MARK: - Countdown Text

struct AwarenessCountdown: View {
    @ObservedObject var awarenessService: SessionAwarenessService
    @ObservedObject private var timeState: SessionTimeState

    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    init(awarenessService: SessionAwarenessService) {
        _awarenessService = ObservedObject(wrappedValue: awarenessService)
        _timeState = ObservedObject(wrappedValue: awarenessService.timeState)
    }

    var body: some View {
        if let startTime = awarenessService.nextSessionStartTime {
            let minutesUntil = Int(startTime.timeIntervalSince(awarenessService.currentTime) / 60)
            if minutesUntil >= 60 {
                let h = minutesUntil / 60
                let m = minutesUntil % 60
                Text(m > 0 ? "in \(h)h \(m)m" : "in \(h)h")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(colors.textMuted)
            } else if minutesUntil > 0 {
                Text("in \(minutesUntil) min")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(colors.textMuted)
            } else {
                Text("starting now")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colors.textSecondary)
            }
        }
    }
}

// MARK: - Next Up Content

struct AwarenessNextUpContent<ToggleButton: View>: View {
    @ObservedObject var awarenessService: SessionAwarenessService
    @ObservedObject var audioService: SessionAudioService
    let toggleButton: ToggleButton

    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    var body: some View {
        HStack(spacing: 10) {
            toggleButton

            if awarenessService.nextSessionIsBusySlot {
                Image(systemName: "calendar")
                    .font(.system(size: 13))
                    .foregroundColor((awarenessService.nextSessionCalendarColor ?? .white).opacity(0.6))
            } else if let type = awarenessService.nextSessionType {
                Image(systemName: type.icon)
                    .font(.system(size: 13))
                    .foregroundColor(type.color.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Next: \(awarenessService.nextSessionTitle ?? "")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(1)

                if let start = awarenessService.nextSessionStartTime,
                   let end = awarenessService.nextSessionEndTime {
                    Text(nextSessionTimeDescription(start: start, end: end))
                        .font(.system(size: 10))
                        .foregroundColor(colors.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            AwarenessCountdown(awarenessService: awarenessService)

            AwarenessMuteButton(audioService: audioService, awarenessService: awarenessService)
        }
    }
}

// MARK: - Idle Content

struct AwarenessIdleContent<ToggleButton: View>: View {
    @ObservedObject var awarenessService: SessionAwarenessService
    @ObservedObject var audioService: SessionAudioService
    let toggleButton: ToggleButton

    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    var body: some View {
        HStack(spacing: 8) {
            toggleButton

            Image(systemName: "eye.circle")
                .font(.system(size: 13))
                .foregroundColor(colors.textDisabled)

            Text("SessionFlow Awareness")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colors.textMuted)

            Spacer()

            Text("No sessions today")
                .font(.system(size: 11))
                .foregroundColor(colors.textDisabled)

            AwarenessMuteButton(audioService: audioService, awarenessService: awarenessService)
        }
    }
}

// MARK: - Feedback Content

struct AwarenessFeedbackContent<ToggleButton: View>: View {
    @ObservedObject var awarenessService: SessionAwarenessService
    @ObservedObject var audioService: SessionAudioService
    @Binding var feedbackConfirmation: SessionRating?
    let toggleButton: ToggleButton

    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    var body: some View {
        HStack(spacing: 12) {
            toggleButton

            if let feedback = awarenessService.sessionFeedbackPending {
                if feedbackConfirmation != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(colors.isDark ? .green : Color(hex: "15803D"))
                        Text("Logged!")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                    }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Text("How was \"\(feedback.sessionTitle)\"?")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: 6) {
                        AwarenessFeedbackButton(rating: .rocket) { submitFeedback($0) }
                        AwarenessFeedbackButton(rating: .completed) { submitFeedback($0) }
                        AwarenessFeedbackButton(rating: .partial) { submitFeedback($0) }
                        AwarenessFeedbackButton(rating: .skipped) { submitFeedback($0) }
                    }

                    Button {
                        awarenessService.dismissFeedback()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12))
                            .foregroundColor(colors.textMuted)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(brightness: 0.3)
                    .help("Dismiss")

                    AwarenessMuteButton(audioService: audioService, awarenessService: awarenessService)
                }
            }
        }
    }

    private func submitFeedback(_ rating: SessionRating) {
        withAnimation(.easeInOut(duration: 0.2)) {
            feedbackConfirmation = rating
        }
        awarenessService.submitFeedback(rating: rating)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { feedbackConfirmation = nil }
        }
    }
}

// MARK: - Rest Content

struct AwarenessRestContent<ToggleButton: View>: View {
    @ObservedObject var awarenessService: SessionAwarenessService
    @ObservedObject var audioService: SessionAudioService
    @ObservedObject private var timeState: SessionTimeState
    let toggleButton: ToggleButton
    let showProgress: Bool

    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    init(awarenessService: SessionAwarenessService, audioService: SessionAudioService, toggleButton: ToggleButton, showProgress: Bool = true) {
        _awarenessService = ObservedObject(wrappedValue: awarenessService)
        _audioService = ObservedObject(wrappedValue: audioService)
        _timeState = ObservedObject(wrappedValue: awarenessService.timeState)
        self.toggleButton = toggleButton
        self.showProgress = showProgress
    }

    var body: some View {
        HStack(spacing: 10) {
            toggleButton

            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 16))
                .foregroundColor(colors.isDark ? .teal.opacity(0.7) : Color(hex: "0F766E"))

            VStack(alignment: .leading, spacing: 2) {
                Text("Rest")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(1)

                if let type = awarenessService.restAfterSessionType {
                    Text("after \(type.rawValue)")
                        .font(.system(size: 11))
                        .foregroundColor(colors.textMuted)
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            if showProgress {
                AwarenessDivider()

                restProgressBar
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
            } else {
                Spacer()
            }

            VStack(spacing: 1) {
                Text(formatSessionDuration(awarenessService.restRemaining))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(1)
                Text("rest")
                    .font(.system(size: 10))
                    .foregroundColor(colors.textDisabled)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)

            AwarenessSkipSessionButton(awarenessService: awarenessService)
            AwarenessMuteButton(audioService: audioService, awarenessService: awarenessService)
        }
    }

    private var restProgressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(colors.divider)

                RoundedRectangle(cornerRadius: 2.5)
                    .fill(colors.isDark ? Color.teal.opacity(0.6) : Color(hex: "0D9488"))
                    .frame(width: max(0, geo.size.width * CGFloat(awarenessService.restProgress)))
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Flash Animation Modifier

struct AwarenessFlashModifier: ViewModifier {
    @ObservedObject var awarenessService: SessionAwarenessService
    @Binding var flashOpacity: Double
    @Binding var flashColor: Color

    func body(content: Content) -> some View {
        content.onChange(of: awarenessService.flashTrigger != nil) { _, isFlashing in
            if isFlashing, let trigger = awarenessService.flashTrigger {
                switch trigger {
                case .endingSoon: flashColor = .red
                case .presenceReminder: flashColor = .orange
                case .sessionStarted: flashColor = .green
                }
                withAnimation(.easeIn(duration: 0.15)) { flashOpacity = 0.25 }
                withAnimation(.easeOut(duration: 0.35).delay(0.2)) { flashOpacity = 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    withAnimation(.easeIn(duration: 0.15)) { flashOpacity = 0.25 }
                    withAnimation(.easeOut(duration: 0.35).delay(0.2)) { flashOpacity = 0 }
                }
            }
        }
    }
}

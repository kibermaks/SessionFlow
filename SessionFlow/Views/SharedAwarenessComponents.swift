import SwiftUI

// MARK: - Formatting Utilities

func formatSessionTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
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

func awarenessRatingColor(_ rating: SessionRating) -> Color {
    switch rating {
    case .rocket: return .orange
    case .completed: return .green
    case .partial: return .yellow
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
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 32)
            .padding(.horizontal, 8)
    }
}

// MARK: - Skip Session Button

struct AwarenessSkipSessionButton: View {
    @ObservedObject var awarenessService: SessionAwarenessService

    var body: some View {
        if awarenessService.isActive {
            Button {
                awarenessService.toggleSessionMute()
            } label: {
                Image(systemName: awarenessService.isSessionMuted ? "forward.end.fill" : "forward.end")
                    .font(.system(size: 13))
                    .foregroundColor(awarenessService.isSessionMuted ? .yellow.opacity(0.8) : .white.opacity(0.4))
                    .frame(width: 32, height: 32)
                    .background(awarenessService.isSessionMuted ? Color.yellow.opacity(0.12) : Color.white.opacity(0.06))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(awarenessService.isSessionMuted ? Color.yellow.opacity(0.25) : Color.clear, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: 0.2)
            .help(awarenessService.isSessionMuted ? "Resume sounds for this session" : "Mute until next session")
        }
    }
}

// MARK: - Mute Button

struct AwarenessMuteButton: View {
    @ObservedObject var audioService: SessionAudioService

    var body: some View {
        Button {
            audioService.toggleMute()
        } label: {
            iconView
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.06))
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
                    .foregroundColor(audioService.isMuted ? .orange.opacity(0.7) : .white.opacity(0.5))
                Text("A")
                    .font(.system(size: 7, weight: .heavy, design: .rounded))
                    .foregroundColor(audioService.isMuted ? .orange.opacity(0.7) : .green.opacity(0.7))
                    .offset(x: 3, y: 3)
            }
        } else {
            // Normal
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
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

    var body: some View {
        let color = awarenessRatingColor(rating)

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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: awarenessIconName(service: awarenessService))
                .font(.system(size: 18))
                .foregroundColor(awarenessIconColor(service: awarenessService))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(awarenessService.currentSessionTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .truncationMode(.tail)

                if let notes = SessionAwarenessService.strippedNotes(awarenessService.currentEventNotes) {
                    HStack(alignment: .top, spacing: 4) {
                        Text(notes)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(2)
                            .truncationMode(.tail)

                        Button {
                            showingEventInfo.toggle()
                        } label: {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.5))
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
}

// MARK: - Session Meta Column

struct AwarenessSessionMeta: View {
    @ObservedObject var awarenessService: SessionAwarenessService

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let start = awarenessService.sessionStartTime, let end = awarenessService.sessionEndTime {
                Text("\(formatSessionTime(start)) – \(formatSessionTime(end))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
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
                    Text("\(formatSessionTime(start)) – \(formatSessionTime(end))")
                        .font(.system(size: 12, design: .monospaced))
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

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                let barColor = awarenessBarColor(service: awarenessService)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.white.opacity(0.08))

                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(barColor)
                        .frame(width: max(0, geo.size.width * CGFloat(awarenessService.progress)))
                }
            }
            .frame(height: 6)

            HStack {
                Text(formatSessionDuration(awarenessService.elapsed))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()

                Text(formatSessionDuration(awarenessService.remaining))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}

// MARK: - Clickable Time Display

struct AwarenessClickableTime: View {
    @ObservedObject var awarenessService: SessionAwarenessService

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
                .foregroundColor(.white.opacity(0.7))
            Text(timeLabel)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
        }
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

    var body: some View {
        if let startTime = awarenessService.nextSessionStartTime {
            let minutesUntil = Int(startTime.timeIntervalSince(awarenessService.currentTime) / 60)
            if minutesUntil >= 60 {
                let h = minutesUntil / 60
                let m = minutesUntil % 60
                Text(m > 0 ? "in \(h)h \(m)m" : "in \(h)h")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            } else if minutesUntil > 0 {
                Text("in \(minutesUntil) min")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                Text("starting now")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - Next Up Content

struct AwarenessNextUpContent<ToggleButton: View>: View {
    @ObservedObject var awarenessService: SessionAwarenessService
    @ObservedObject var audioService: SessionAudioService
    let toggleButton: ToggleButton

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
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)

                if let start = awarenessService.nextSessionStartTime,
                   let end = awarenessService.nextSessionEndTime {
                    Text(nextSessionTimeDescription(start: start, end: end))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                        .lineLimit(1)
                }
            }

            Spacer()

            AwarenessCountdown(awarenessService: awarenessService)

            AwarenessMuteButton(audioService: audioService)
        }
    }
}

// MARK: - Idle Content

struct AwarenessIdleContent<ToggleButton: View>: View {
    @ObservedObject var audioService: SessionAudioService
    let toggleButton: ToggleButton

    var body: some View {
        HStack(spacing: 8) {
            toggleButton

            Image(systemName: "eye.circle")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.25))

            Text("SessionFlow Awareness")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.3))

            Spacer()

            Text("No sessions today")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.2))

            AwarenessMuteButton(audioService: audioService)
        }
    }
}

// MARK: - Feedback Content

struct AwarenessFeedbackContent<ToggleButton: View>: View {
    @ObservedObject var awarenessService: SessionAwarenessService
    @ObservedObject var audioService: SessionAudioService
    @Binding var feedbackConfirmation: SessionRating?
    let toggleButton: ToggleButton

    var body: some View {
        HStack(spacing: 12) {
            toggleButton

            if let feedback = awarenessService.sessionFeedbackPending {
                if feedbackConfirmation != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Logged!")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Text("How was \"\(feedback.sessionTitle)\"?")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
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
                            .foregroundColor(.white.opacity(0.3))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(brightness: 0.3)
                    .help("Dismiss")

                    AwarenessMuteButton(audioService: audioService)
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

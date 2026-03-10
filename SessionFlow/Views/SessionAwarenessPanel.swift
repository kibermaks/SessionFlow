import SwiftUI

struct SessionAwarenessPanel: View {
    @EnvironmentObject var awarenessService: SessionAwarenessService
    @EnvironmentObject var audioService: SessionAudioService

    @AppStorage("hasSeenSessionAwarenessGuide") private var hasSeenGuide = false
    @State private var showingGuide = false
    @State private var showingEventInfo = false
    @State private var feedbackConfirmation: SessionRating? = nil
    @State private var flashOpacity: Double = 0
    @State private var flashColor: Color = .clear

    var body: some View {
        VStack(spacing: 0) {
            if awarenessService.sessionFeedbackPending != nil {
                feedbackPromptBar
            } else if awarenessService.isActive {
                activeSessionBar
            } else if awarenessService.nextSessionTitle != nil {
                nextUpBar
            } else {
                idleBar
            }
        }
        .animation(.easeInOut(duration: 0.3), value: awarenessService.isActive)
        .animation(.easeInOut(duration: 0.3), value: awarenessService.sessionFeedbackPending?.id)
        .animation(.easeInOut(duration: 0.3), value: awarenessService.nextSessionTitle)
        .contentShape(Rectangle())
        .onTapGesture {
            if !hasSeenGuide {
                hasSeenGuide = true
                showingGuide = true
            }
        }
        .sheet(isPresented: $showingGuide) {
            SessionAwarenessGuide()
        }
    }

    // MARK: - State A: Active Session

    private var activeSessionBar: some View {
        HStack(spacing: 0) {
            // Left: Collapse + Session info (title + notes)
            HStack(spacing: 8) {
                collapseButton
                sessionInfoSection
            }
            .frame(minWidth: 200, maxWidth: 280, alignment: .leading)

            divider

            // Time slot + Calendar/Type
            sessionMetaColumn
                .frame(width: 110, alignment: .leading)

            divider

            // Center: Progress
            progressSection
                .padding(.horizontal, 12)

            divider

            // Right: Time metric + Mute
            HStack(spacing: 12) {
                clickableTimeDisplay
                muteSection
            }
            .frame(width: 150, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            ZStack {
                panelBackground
                flashColor.opacity(flashOpacity)
            }
        )
        .overlay(topBorder, alignment: .top)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onChange(of: awarenessService.flashTrigger != nil) { _, isFlashing in
            if isFlashing, let trigger = awarenessService.flashTrigger {
                flashColor = trigger == .endingSoon ? .red : .orange
                // Flash 1
                withAnimation(.easeIn(duration: 0.15)) { flashOpacity = 0.25 }
                withAnimation(.easeOut(duration: 0.35).delay(0.2)) { flashOpacity = 0 }
                // Flash 2
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    withAnimation(.easeIn(duration: 0.15)) { flashOpacity = 0.25 }
                    withAnimation(.easeOut(duration: 0.35).delay(0.2)) { flashOpacity = 0 }
                }
            }
        }
    }

    // MARK: - Collapse button

    private var collapseButton: some View {
        Button {
            awarenessService.isCollapsed.toggle()
        } label: {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.06))
                .cornerRadius(5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(brightness: 0.2)
        .help("Detach mini-player")
    }

    // MARK: - Session icon + info

    private var sessionIconName: String {
        awarenessService.isBusySlotMode ? "calendar" : (awarenessService.currentSessionType?.icon ?? "circle")
    }

    private var sessionIconColor: Color {
        awarenessService.isBusySlotMode ? (awarenessService.busySlotCalendarColor ?? .gray) : (awarenessService.currentSessionType?.color ?? .gray)
    }

    private var sessionInfoSection: some View {
        HStack(spacing: 10) {
            Image(systemName: sessionIconName)
                .font(.system(size: 18))
                .foregroundColor(sessionIconColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(awarenessService.currentSessionTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .truncationMode(.tail)

                // Event notes (stripped of hashtags), up to 2 lines with (i) popover
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
                            eventInfoPopover
                        }
                    }
                }
            }
        }
    }

    // MARK: - Time slot + Calendar/Type column

    private var sessionMetaColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Time slot
            if let start = awarenessService.sessionStartTime, let end = awarenessService.sessionEndTime {
                Text("\(formatTime(start)) – \(formatTime(end))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }

            // Calendar name or session type
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

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Event info popover

    private var eventInfoPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            Text(awarenessService.currentSessionTitle)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.primary)

            // Time slot
            if let start = awarenessService.sessionStartTime, let end = awarenessService.sessionEndTime {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("\(formatTime(start)) – \(formatTime(end))")
                        .font(.system(size: 12, design: .monospaced))
                }
            }

            // Session type
            if let type = awarenessService.currentSessionType {
                HStack(spacing: 6) {
                    Image(systemName: type.icon)
                        .font(.system(size: 11))
                        .foregroundColor(type.color)
                    Text(type.rawValue)
                        .font(.system(size: 12))
                }
            }

            // Calendar
            if awarenessService.isBusySlotMode {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                        .foregroundColor(awarenessService.busySlotCalendarColor ?? .gray)
                    Text(awarenessService.busySlotCalendarName ?? "Calendar")
                        .font(.system(size: 12))
                }
            }

            // Full notes
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

    // MARK: - Progress bar

    private var progressSection: some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                let barColor: Color = awarenessService.isBusySlotMode
                    ? (awarenessService.busySlotCalendarColor ?? .gray)
                    : (awarenessService.currentSessionType?.color ?? .blue)

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
                Text(formatDuration(awarenessService.elapsed))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()

                Text(formatDuration(awarenessService.remaining))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Clickable time display (cycles remaining/elapsed)

    private var clickableTimeDisplay: some View {
        let text: String = {
            switch awarenessService.timeDisplayMode {
            case .remaining:
                return formatDuration(awarenessService.remaining)
            case .elapsed:
                return formatDuration(awarenessService.elapsed)
            }
        }()

        let label: String = {
            switch awarenessService.timeDisplayMode {
            case .remaining: return "remaining"
            case .elapsed: return "elapsed"
            }
        }()

        return VStack(spacing: 1) {
            Text(text)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            awarenessService.cycleTimeDisplay()
        }
        .help("Click to toggle remaining/elapsed")
    }

    // MARK: - State B: Next Up

    private var nextUpBar: some View {
        HStack(spacing: 10) {
            collapseButton

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
                    Text(nextSessionTimeString(start: start, end: end))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                        .lineLimit(1)
                }
            }

            Spacer()

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
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(panelBackground)
        .overlay(topBorder, alignment: .top)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - State: Idle

    private var idleBar: some View {
        HStack(spacing: 8) {
            collapseButton

            Image(systemName: "eye.circle")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.25))

            Text("Session Awareness")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.3))

            Spacer()

            Text("No sessions today")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.2))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .background(panelBackground)
        .overlay(topBorder, alignment: .top)
    }

    // MARK: - State C: Feedback Prompt

    private var feedbackPromptBar: some View {
        HStack(spacing: 12) {
            collapseButton

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
                        feedbackButton(rating: .rocket)
                        feedbackButton(rating: .completed)
                        feedbackButton(rating: .partial)
                        feedbackButton(rating: .skipped)
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
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(panelBackground)
        .overlay(topBorder, alignment: .top)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func feedbackButton(rating: SessionRating) -> some View {
        let color: Color = {
            switch rating {
            case .rocket: return .orange
            case .completed: return .green
            case .partial: return .yellow
            case .skipped: return .red
            }
        }()

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                feedbackConfirmation = rating
            }
            awarenessService.submitFeedback(rating: rating)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation { feedbackConfirmation = nil }
            }
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

    // MARK: - Mute Section

    private var currentSoundIsOff: Bool {
        if let type = awarenessService.currentSessionType {
            return !awarenessService.config.soundConfig(for: type).isPlayable
        }
        if awarenessService.isBusySlotMode {
            return !awarenessService.config.otherEventsSound.isPlayable
        }
        return true
    }

    private var muteSection: some View {
        Group {
            if awarenessService.isActive && currentSoundIsOff {
                Image(systemName: "speaker.slash")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.15))
                    .frame(width: 32, height: 32)
                    .help("Sound is off for this session type")
            } else {
                muteButton
            }
        }
    }

    private var muteButton: some View {
        Button {
            audioService.isMuted.toggle()
        } label: {
            Image(systemName: audioService.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 14))
                .foregroundColor(audioService.isMuted ? .red.opacity(0.6) : .white.opacity(0.5))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.06))
                .cornerRadius(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(brightness: 0.2)
        .help(audioService.isMuted ? "Unmute" : "Mute")
    }

    // MARK: - Shared styling

    private var panelBackground: some View {
        LinearGradient(
            colors: [Color(hex: "0F172A"), Color(hex: "1E293B")],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var topBorder: some View {
        Rectangle()
            .frame(height: 1)
            .foregroundColor(.white.opacity(0.08))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 32)
            .padding(.horizontal, 8)
    }

    // MARK: - Helpers

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func nextSessionTimeString(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let durationMinutes = Int(end.timeIntervalSince(start) / 60)
        return "\(formatter.string(from: start)) - \(formatter.string(from: end)) \u{2022} \(durationMinutes) min"
    }
}

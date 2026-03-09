import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var awarenessService: SessionAwarenessService
    @ObservedObject var audioService: SessionAudioService

    @State private var flashOpacity: Double = 0
    @State private var flashColor: Color = .clear
    @State private var showingEventInfo = false

    private let progressVisibleWidthThreshold: CGFloat = 620

    var body: some View {
        GeometryReader { geo in
            let showProgress = geo.size.width >= progressVisibleWidthThreshold

            HStack(spacing: 0) {
                // Left: Expand + Session info (icon + title + notes)
                HStack(spacing: 8) {
                    expandButton
                    sessionInfoSection
                }
                .frame(minWidth: 200, maxWidth: 280, alignment: .leading)

                divider

                // Time slot + Calendar/Type
                sessionMetaColumn
                    .frame(width: 110, alignment: .leading)

                if showProgress {
                    divider

                    // Progress bar (spring — fills remaining space)
                    progressSection
                        .padding(.horizontal, 12)

                    divider
                } else {
                    Spacer(minLength: 0)
                }

                // Right: Time metric + Mute
                HStack(spacing: 12) {
                    clickableTimeDisplay
                    muteButton
                }
                .frame(width: 150, alignment: .trailing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "0F172A"), Color(hex: "1E293B")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 2)
                RoundedRectangle(cornerRadius: 10)
                    .fill(flashColor.opacity(flashOpacity))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
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

    // MARK: - Expand button

    private var expandButton: some View {
        Button {
            awarenessService.isCollapsed = false
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.06))
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .help("Return to main window")
    }

    // MARK: - Session info

    private var iconColor: Color {
        awarenessService.isBusySlotMode
            ? (awarenessService.busySlotCalendarColor ?? .gray)
            : (awarenessService.currentSessionType?.color ?? .gray)
    }

    private var iconName: String {
        awarenessService.isBusySlotMode
            ? "calendar"
            : (awarenessService.currentSessionType?.icon ?? "circle")
    }

    private var sessionInfoSection: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
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
                        .popover(isPresented: $showingEventInfo) {
                            eventInfoPopover
                        }
                    }
                }
            }
        }
    }

    // MARK: - Event info popover

    private var eventInfoPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(awarenessService.currentSessionTitle)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.primary)

            if let start = awarenessService.sessionStartTime, let end = awarenessService.sessionEndTime {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("\(formatTime(start)) – \(formatTime(end))")
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

    // MARK: - Meta column (time slot + type)

    private var sessionMetaColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let start = awarenessService.sessionStartTime, let end = awarenessService.sessionEndTime {
                Text("\(formatTime(start)) – \(formatTime(end))")
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

    // MARK: - Progress (spring)

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

    // MARK: - Clickable time

    private var clickableTimeDisplay: some View {
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

    private var timeText: String {
        let time: TimeInterval = awarenessService.timeDisplayMode == .remaining
            ? awarenessService.remaining : awarenessService.elapsed
        let totalSeconds = max(0, Int(time))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    private var timeLabel: String {
        awarenessService.timeDisplayMode == .remaining ? "remaining" : "elapsed"
    }

    // MARK: - Mute

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
        }
        .buttonStyle(.plain)
        .help(audioService.isMuted ? "Unmute" : "Mute")
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 32)
            .padding(.horizontal, 8)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

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
}

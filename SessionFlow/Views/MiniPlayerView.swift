import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var awarenessService: SessionAwarenessService
    @ObservedObject var audioService: SessionAudioService
    var onHeightChange: ((CGFloat) -> Void)? = nil

    @State private var flashOpacity: Double = 0
    @State private var flashColor: Color = .clear
    @State private var showingEventInfo = false
    @State private var feedbackConfirmation: SessionRating? = nil
    @State private var totalWidth: CGFloat = 620
    @State private var progressAreaWidth: CGFloat = 200

    private let metaColumnThreshold: CGFloat = 500
    private let fullProgressThreshold: CGFloat = 150

    var body: some View {
        Group {
            if awarenessService.sessionFeedbackPending != nil {
                miniFeedbackBar
            } else if awarenessService.isActive {
                miniActiveBar
            } else if awarenessService.nextSessionTitle != nil {
                miniNextUpBar
            } else {
                miniIdleBar
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(miniBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: MiniPlayerHeightKey.self, value: geo.size.height)
                    .task(id: geo.size.width) { totalWidth = geo.size.width }
            }
        )
        .onPreferenceChange(MiniPlayerHeightKey.self) { height in
            onHeightChange?(height)
        }
        .animation(.easeInOut(duration: 0.3), value: awarenessService.isActive)
        .animation(.easeInOut(duration: 0.3), value: awarenessService.sessionFeedbackPending?.id)
        .animation(.easeInOut(duration: 0.3), value: awarenessService.nextSessionTitle)
    }

    // MARK: - Active session bar

    private var showMetaColumn: Bool { totalWidth >= metaColumnThreshold }
    private var showFullProgress: Bool { progressAreaWidth >= fullProgressThreshold }

    private var miniActiveBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                expandButton
                AwarenessSessionInfo(awarenessService: awarenessService, showingEventInfo: $showingEventInfo)
            }
            .frame(minWidth: showMetaColumn ? 240 : 220, maxWidth: 280, alignment: .leading)

            AwarenessDivider()

            if showMetaColumn {
                AwarenessSessionMeta(awarenessService: awarenessService)
                    .frame(width: 110, alignment: .leading)

                AwarenessDivider()
            }

            ZStack {
                if showFullProgress {
                    AwarenessProgressBar(awarenessService: awarenessService)
                        .transition(.opacity)
                } else {
                    compactProgressDonut
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(
                GeometryReader { geo in
                    Color.clear.task(id: geo.size.width) { progressAreaWidth = geo.size.width }
                }
            )

            AwarenessDivider()

            HStack(spacing: 12) {
                AwarenessClickableTime(awarenessService: awarenessService)
                AwarenessMuteButton(audioService: audioService)
            }
            .frame(minWidth: 100, maxWidth: 150, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showFullProgress)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .modifier(AwarenessFlashModifier(awarenessService: awarenessService, flashOpacity: $flashOpacity, flashColor: $flashColor))
    }

    // MARK: - Next Up bar

    private var miniNextUpBar: some View {
        AwarenessNextUpContent(awarenessService: awarenessService, audioService: audioService, toggleButton: expandButton)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
    }

    // MARK: - Idle bar

    private var miniIdleBar: some View {
        AwarenessIdleContent(audioService: audioService, toggleButton: expandButton)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
    }

    // MARK: - Feedback bar

    private var miniFeedbackBar: some View {
        AwarenessFeedbackContent(
            awarenessService: awarenessService,
            audioService: audioService,
            feedbackConfirmation: $feedbackConfirmation,
            toggleButton: expandButton
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Background

    private var miniBackground: some View {
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
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(brightness: 0.2)
        .help("Return to main window")
    }

    // MARK: - Compact donut progress

    private var compactProgressDonut: some View {
        let barColor = awarenessBarColor(service: awarenessService)
        let size: CGFloat = 28
        let lineWidth: CGFloat = 3.5

        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(awarenessService.progress))
                .stroke(barColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            (
                Text("\(Int(awarenessService.progress * 100))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                +
                Text("%")
                    .font(.system(size: 6, weight: .medium, design: .monospaced))
            )
            .foregroundColor(.white.opacity(0.5))
        }
        .frame(width: size, height: size)
    }
}

private struct MiniPlayerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

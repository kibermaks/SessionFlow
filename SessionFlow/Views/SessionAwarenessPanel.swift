import SwiftUI

struct SessionAwarenessPanel: View {
    @EnvironmentObject var awarenessService: SessionAwarenessService
    @EnvironmentObject var audioService: SessionAudioService
    @EnvironmentObject var timeState: SessionTimeState

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
            } else if awarenessService.isResting {
                restBar
            } else if awarenessService.nextSessionTitle != nil {
                nextUpBar
            } else {
                idleBar
            }
        }
        .animation(.easeInOut(duration: 0.3), value: awarenessService.isActive)
        .animation(.easeInOut(duration: 0.3), value: awarenessService.isResting)
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

    // MARK: - Active Session

    private var activeSessionBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                collapseButton
                AwarenessSessionInfo(awarenessService: awarenessService, showingEventInfo: $showingEventInfo)
            }
            .frame(minWidth: 200, maxWidth: 280, alignment: .leading)

            AwarenessDivider()

            AwarenessSessionMeta(awarenessService: awarenessService)
                .frame(width: 110, alignment: .leading)

            AwarenessDivider()

            AwarenessProgressBar(awarenessService: awarenessService)
                .padding(.horizontal, 12)

            AwarenessDivider()

            HStack(spacing: 8) {
                AwarenessClickableTime(awarenessService: awarenessService)
                AwarenessSkipSessionButton(awarenessService: awarenessService)
                AwarenessMuteButton(audioService: audioService)
            }
            .frame(width: 180, alignment: .trailing)
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
        .modifier(AwarenessFlashModifier(awarenessService: awarenessService, flashOpacity: $flashOpacity, flashColor: $flashColor))
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

    // MARK: - Next Up

    private var nextUpBar: some View {
        AwarenessNextUpContent(awarenessService: awarenessService, audioService: audioService, toggleButton: collapseButton)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(panelBackground)
            .overlay(topBorder, alignment: .top)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Rest

    private var restBar: some View {
        AwarenessRestContent(awarenessService: awarenessService, audioService: audioService, toggleButton: collapseButton)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(panelBackground)
            .overlay(topBorder, alignment: .top)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Idle

    private var idleBar: some View {
        AwarenessIdleContent(audioService: audioService, toggleButton: collapseButton)
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
            .background(panelBackground)
            .overlay(topBorder, alignment: .top)
    }

    // MARK: - Feedback

    private var feedbackPromptBar: some View {
        AwarenessFeedbackContent(
            awarenessService: awarenessService,
            audioService: audioService,
            feedbackConfirmation: $feedbackConfirmation,
            toggleButton: collapseButton
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(panelBackground)
        .overlay(topBorder, alignment: .top)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Panel styling

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
}

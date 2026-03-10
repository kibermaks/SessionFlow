import SwiftUI

struct SessionAwarenessGuide: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentPage = 0
    @State private var remainingMinutes: Int = Self.demoSessionMinutes
    @State private var countdownActive = false
    @State private var selectedFeedback: String? = nil

    private static let demoSessionMinutes = 40
    private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let pages: [(title: String, subtitle: String, icon: String, color: Color)] = [
        (
            title: "Session Awareness",
            subtitle: "The bottom panel tracks your sessions in real-time. When the current time falls within a scheduled event, you'll see its name, progress, and time remaining.",
            icon: "eye.circle.fill",
            color: Color(hex: "8B5CF6")
        ),
        (
            title: "Stay Focused",
            subtitle: "Ambient sounds play during sessions to help maintain focus. Each session type can have its own sound and volume. Use the mute button for quick silence.",
            icon: "speaker.wave.2.circle.fill",
            color: Color(hex: "3B82F6")
        ),
        (
            title: "Session Feedback",
            subtitle: "After each session ends, rate how it went: Done, Partly, or Skipped. Feedback badges appear on the timeline so you can track your follow-through at a glance.",
            icon: "checkmark.circle.fill",
            color: Color(hex: "10B981")
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "0F172A"), Color(hex: "1E293B")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                // Close button
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(8)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Page content
                ZStack {
                    ForEach(0..<pages.count, id: \.self) { index in
                        if currentPage == index {
                            pageView(for: pages[index])
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                                    removal: .opacity.combined(with: .move(edge: .leading))
                                ))
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                // Interactive element per page
                Group {
                    if currentPage == 0 {
                        sessionProgressView
                            .transition(.scale.combined(with: .opacity))
                    } else if currentPage == 1 {
                        soundWaveView
                            .transition(.scale.combined(with: .opacity))
                    } else if currentPage == 2 {
                        feedbackButtonsView
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(height: 120)
                .padding(.bottom, 24)

                // Footer
                VStack(spacing: 24) {
                    // Page dots
                    HStack(spacing: 8) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Circle()
                                .fill(currentPage == index ? pages[index].color : Color.white.opacity(0.2))
                                .frame(width: 8, height: 8)
                                .animation(.spring(), value: currentPage)
                        }
                    }

                    // Navigation buttons
                    HStack(spacing: 16) {
                        if currentPage > 0 {
                            Button {
                                withAnimation { currentPage -= 1 }
                            } label: {
                                Text("Back")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white.opacity(0.6))
                                    .frame(width: 100)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            if currentPage < pages.count - 1 {
                                withAnimation { currentPage += 1 }
                            } else {
                                dismiss()
                            }
                        } label: {
                            Text(currentPage == pages.count - 1 ? "Got it" : "Next")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: currentPage > 0 ? 180 : 280)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(pages[currentPage].color)
                                        .shadow(color: pages[currentPage].color.opacity(0.4), radius: 10, y: 5)
                                )
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .frame(width: 500, height: 620)
        .focusable()
        .focusEffectDisabled()
        .onReceive(countdownTimer) { _ in
            guard countdownActive else { return }
            if remainingMinutes > 0 {
                remainingMinutes -= 1
            } else {
                remainingMinutes = Self.demoSessionMinutes
            }
        }
        .onChange(of: currentPage) { _, newPage in
            countdownActive = newPage == 0
            if newPage == 0 {
                remainingMinutes = Self.demoSessionMinutes
            }
            if newPage == 2 {
                selectedFeedback = nil
            }
        }
        .onAppear {
            countdownActive = currentPage == 0
        }
    }

    private func pageView(for page: (title: String, subtitle: String, icon: String, color: Color)) -> some View {
        VStack(spacing: 16) {
            Image(systemName: page.icon)
                .font(.system(size: 72))
                .foregroundColor(page.color)

            Text(page.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(page.subtitle)
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 380)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Page 1: Session Progress

    private var sessionProgressView: some View {
        VStack(spacing: 12) {
            // Mini session card
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "8B5CF6"))
                    .frame(width: 4, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Deep Work Session")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text("10:00 - 10:40")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }

                Spacer()

                Text(timeRemainingText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(hex: "8B5CF6"))
            }
            .padding(.horizontal, 16)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.1))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "8B5CF6"))
                        .frame(width: geo.size.width * (1 - CGFloat(remainingMinutes) / CGFloat(Self.demoSessionMinutes)))
                        .animation(.linear(duration: 1), value: remainingMinutes)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .padding(.horizontal, 40)
    }

    private var timeRemainingText: String {
        "\(remainingMinutes)m left"
    }

    // MARK: - Page 2: Sound Waves

    private var soundWaveView: some View {
        HStack(spacing: 20) {
            // Speaker icon
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 28))
                .foregroundColor(Color(hex: "3B82F6"))

            // Sound wave bars
            HStack(spacing: 4) {
                ForEach(0..<12, id: \.self) { i in
                    SoundWaveBar(index: i, color: Color(hex: "3B82F6"))
                }
            }
            .frame(height: 40)

            // Sound label
            VStack(alignment: .leading, spacing: 4) {
                Text("Mountain Atmosphere")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text("Deep Work")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .padding(.horizontal, 40)
    }

    // MARK: - Page 3: Feedback Buttons

    private var feedbackButtonsView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                feedbackButton(label: "Done", icon: "checkmark.circle.fill", color: Color(hex: "10B981"))
                feedbackButton(label: "Partly", icon: "circle.lefthalf.filled", color: Color(hex: "F59E0B"))
                feedbackButton(label: "Skipped", icon: "xmark.circle.fill", color: Color(hex: "EF4444"))
            }

            // Badge preview
            if let feedback = selectedFeedback {
                HStack(spacing: 6) {
                    Image(systemName: badgeIcon(for: feedback))
                        .font(.system(size: 10))
                    Text(feedback)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(badgeColor(for: feedback))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(badgeColor(for: feedback).opacity(0.15))
                .cornerRadius(6)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .padding(.horizontal, 40)
    }

    private func feedbackButton(label: String, icon: String, color: Color) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                selectedFeedback = label
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(selectedFeedback == label ? color : .white.opacity(0.6))
            .frame(width: 80, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selectedFeedback == label ? color.opacity(0.15) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selectedFeedback == label ? color.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func badgeIcon(for feedback: String) -> String {
        switch feedback {
        case "Done": return "checkmark.circle.fill"
        case "Partly": return "circle.lefthalf.filled"
        default: return "xmark.circle.fill"
        }
    }

    private func badgeColor(for feedback: String) -> Color {
        switch feedback {
        case "Done": return Color(hex: "10B981")
        case "Partly": return Color(hex: "F59E0B")
        default: return Color(hex: "EF4444")
        }
    }
}

// MARK: - Sound Wave Bar

struct SoundWaveBar: View {
    let index: Int
    let color: Color
    @State private var animating = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color.opacity(0.7))
            .frame(width: 3, height: animating ? CGFloat.random(in: 8...36) : 8)
            .animation(
                .easeInOut(duration: Double.random(in: 0.3...0.7))
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.05),
                value: animating
            )
            .onAppear {
                animating = true
            }
    }
}

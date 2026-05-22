import SwiftUI

struct ShortcutsGuide: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    @State private var currentPage = 0
    @State private var selectedTrigger: Int? = nil

    private let pages: [(title: String, subtitle: String, icon: String, color: Color)] = [
        (
            title: "Shortcuts Integration",
            subtitle: "SessionFlow can run your macOS Shortcuts automatically when sessions start, end, or are about to begin. Automate your workflow without lifting a finger.",
            icon: "command.square.fill",
            color: Color(hex: "8B5CF6")
        ),
        (
            title: "Automate Everything",
            subtitle: "Each trigger runs a Shortcut of your choice. Toggle Focus modes, change lights, send Watch notifications, update Slack status, control music — anything Shortcuts can do.",
            icon: "sparkles",
            color: Color(hex: "3B82F6")
        ),
        (
            title: "Get Started",
            subtitle: "Download a template shortcut from GitHub, or create your own in the Shortcuts app. Name it to match the trigger field, enable it in Settings, and you're done.",
            icon: "arrow.down.circle.fill",
            color: Color(hex: "10B981")
        )
    ]

    var body: some View {
        ZStack {
            colors.backgroundGradient
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
                            .foregroundColor(colors.textMuted)
                            .padding(8)
                            .background(Circle().fill(colors.divider))
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(brightness: 0.2)
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
                        triggersPreview
                            .transition(.scale.combined(with: .opacity))
                    } else if currentPage == 1 {
                        outcomesPreview
                            .transition(.scale.combined(with: .opacity))
                    } else if currentPage == 2 {
                        getStartedView
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(height: 140)
                .padding(.bottom, 16)

                // Footer
                VStack(spacing: 24) {
                    // Page dots
                    HStack(spacing: 8) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Circle()
                                .fill(currentPage == index ? pages[index].color : colors.border)
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
                                    .foregroundColor(colors.textSecondary)
                                    .frame(width: 100)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(colors.divider)
                                    )
                            }
                            .buttonStyle(.plain)
                            .hoverEffect(brightness: 0.15)
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
                                .foregroundColor(colors.textPrimary)
                                .frame(width: currentPage > 0 ? 180 : 280)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(pages[currentPage].color)
                                        .shadow(color: pages[currentPage].color.opacity(0.4), radius: 10, y: 5)
                                )
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(brightness: 0.12)
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .frame(width: 500, height: 620)
        .focusable()
        .focusEffectDisabled()
    }

    private func pageView(for page: (title: String, subtitle: String, icon: String, color: Color)) -> some View {
        VStack(spacing: 16) {
            Image(systemName: page.icon)
                .font(.system(size: 72))
                .foregroundColor(page.color)

            Text(page.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(colors.textPrimary)

            Text(page.subtitle)
                .font(.system(size: 16))
                .foregroundColor(colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 380)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Page 1: Triggers Preview

    private var triggersPreview: some View {
        VStack(spacing: 6) {
            triggerRow(icon: "bell.fill", label: "Session Approaching", color: Color(hex: "F59E0B"), index: 0)
            triggerRow(icon: "play.fill", label: "Session Started", color: Color(hex: "10B981"), index: 1)
            triggerRow(icon: "stop.fill", label: "Session Ended", color: Color(hex: "EF4444"), index: 2)

            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 9))
                Text("3 rest triggers")
                    .font(.system(size: 11))
            }
            .foregroundColor(colors.textMuted)
            .padding(.top, 2)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(colors.subtleBackground)
        .cornerRadius(16)
        .padding(.horizontal, 40)
    }

    private func triggerRow(icon: String, label: String, color: Color, index: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                selectedTrigger = selectedTrigger == index ? nil : index
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                    .frame(width: 20)

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colors.textPrimary)

                Spacer()

                Image(systemName: selectedTrigger == index ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(selectedTrigger == index ? color : colors.border)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedTrigger == index ? color.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Page 2: Outcomes Preview

    @State private var highlightedOutcome: Int? = nil

    private var outcomesPreview: some View {
        VStack(spacing: 5) {
            outcomeRow(icon: "moon.fill", label: "Turn on Work Focus", detail: "Session Started", color: Color(hex: "8B5CF6"), index: 0)
            outcomeRow(icon: "lightbulb.fill", label: "Change lights to warm", detail: "Rest Started", color: Color(hex: "F59E0B"), index: 1)
            outcomeRow(icon: "applewatch", label: "Notify your Watch", detail: "Session Approaching", color: Color(hex: "3B82F6"), index: 2)
            outcomeRow(icon: "bubble.left.fill", label: "Update Slack status", detail: "Session Started", color: Color(hex: "10B981"), index: 3)
            outcomeRow(icon: "house.fill", label: "Control HomeKit devices", detail: "Session Ended", color: Color(hex: "EF4444"), index: 4)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(colors.subtleBackground)
        .cornerRadius(16)
        .padding(.horizontal, 40)
    }

    private func outcomeRow(icon: String, label: String, detail: String, color: Color, index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(color)
                .frame(width: 22)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(colors.textPrimary)

            Spacer()

            Text(detail)
                .font(.system(size: 11))
                .foregroundColor(colors.textMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(highlightedOutcome == index ? color.opacity(0.1) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                highlightedOutcome = hovering ? index : nil
            }
        }
    }

    // MARK: - Page 3: Get Started

    private var getStartedView: some View {
        VStack(spacing: 10) {
            stepRow(number: "1", text: "Download a template shortcut or create your own", icon: "square.and.arrow.down")
            stepRow(number: "2", text: "The shortcut name must match the trigger name", icon: "character.cursor.ibeam")
            stepRow(number: "3", text: "Enable the trigger in Settings and you're set", icon: "checkmark.circle")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(colors.subtleBackground)
        .cornerRadius(16)
        .padding(.horizontal, 40)
    }

    private func stepRow(number: String, text: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(colors.textPrimary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color(hex: "10B981").opacity(0.3)))

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "10B981").opacity(0.5))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

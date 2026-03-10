import SwiftUI

struct WelcomeScreen: View {
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @Environment(\.dismiss) var dismiss
    @State private var currentPage = 0
    
    let pages = [
        WelcomePage(
            title: "Reclaim Your Day",
            subtitle: "SessionFlow transforms your calendar from a list of 'times I'm busy' into a blueprint for precise productivity.",
            image: "sparkles",
            color: Color(hex: "8B5CF6")
        ),
        WelcomePage(
            title: "Smart Concepts",
            subtitle: "We protect your focus blocks (#work), prioritize your deep work (#deep), and handle your life admin (#side). Name each session in the Tasks tab for specific accountability.",
            image: "brain.head.profile",
            color: Color(hex: "3B82F6")
        ),
        WelcomePage(
            title: "Respects Your Schedule",
            subtitle: "We analyze your existing calendar and perfectly fit new tasks into the available gaps. Your busy slots are always protected.",
            image: "calendar.badge.shield",
            color: Color(hex: "10B981")
        ),
        WelcomePage(
            title: "Built-in Recovery",
            subtitle: "Long Rest is a longer break automatically placed after sustained focus time. It keeps you sharp across long days without you having to plan it.",
            image: "pause.circle.fill",
            color: Color(hex: "F59E0B")
        ),
        WelcomePage(
            title: "Plan with Clarity",
            subtitle: "Each day starts with a Planning session. Visualize your productivity gains, then track them live as sessions unfold.",
            image: "calendar.badge.clock",
            color: Color(hex: "EF4444")
        )
    ]
    
    // Computed property to determine if shown from menu
    private var isShownFromMenu: Bool {
        hasSeenWelcome
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(hex: "0F172A"), Color(hex: "1E293B")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Main content container
            VStack(spacing: 10) {
                // Header
                HStack {
                    Spacer()
                    Button {
                        handleClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(8)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(brightness: 0.2)
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                
                // Content
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
                .clipped()
                
                // Interactivity / Concepts
                Group {
                    if currentPage == 1 {
                        conceptsInteractiveView
                            .transition(.scale.combined(with: .opacity))
                    } else if currentPage == 2 {
                        calendarFittingView
                            .transition(.push(from: .bottom).combined(with: .opacity))
                    } else if currentPage == 3 {
                        bigRestInteractiveView
                            .transition(.scale.combined(with: .opacity))
                    } else if currentPage == 4 {
                        productivityGainView
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        Spacer().frame(height: 120)
                    }
                }
                .frame(height: 120)
                .padding(.bottom, 48)
                
                // Footer
                VStack(spacing: 24) {
                    HStack(spacing: 8) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Circle()
                                .fill(currentPage == index ? pages[index].color : Color.white.opacity(0.2))
                                .frame(width: 8, height: 8)
                                .animation(.spring(), value: currentPage)
                        }
                    }
                    
                    HStack(spacing: 16) {
                        if currentPage > 0 {
                            Button {
                                handleBack()
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
                            .hoverEffect(brightness: 0.15)
                        }

                        Button {
                            handleNext()
                        } label: {
                            Text(currentPage == pages.count - 1 ? (isShownFromMenu ? "Got it" : "Start Planning") : "Next")
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
                        .hoverEffect(brightness: 0.12)
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(.bottom, 40)
            }
            .modifier(ContainerStyleModifier(isShownFromMenu: isShownFromMenu))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) { handleNext(); return .handled }
        .onKeyPress(.return) { handleNext(); return .handled }
        .onKeyPress(.escape) { handleClose(); return .handled }
        .onKeyPress(.leftArrow) { handleBack(); return .handled }
        .onKeyPress(.rightArrow) { handleNext(); return .handled }
        .onAppear {
            // Request focus when view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }
    
    private func handleNext() {
        if currentPage < pages.count - 1 {
            withAnimation { currentPage += 1 }
        } else {
            handleClose()
        }
    }
    
    private func handleBack() {
        if currentPage > 0 {
            withAnimation { currentPage -= 1 }
        }
    }
    
    private func handleClose() {
        // If hasSeenWelcome is already true, we're being shown from menu (as a sheet)
        // In that case, we need to dismiss the sheet
        // If hasSeenWelcome is false, we're in onboarding, so set the flag and let ContentView handle the transition
        if hasSeenWelcome {
            // Shown from menu - dismiss the sheet
            dismiss()
        } else {
            // Onboarding - set flag and let ContentView handle transition
            hasSeenWelcome = true
        }
    }
    
    private func pageView(for page: WelcomePage) -> some View {
        VStack(spacing: 16) {
            Image(systemName: page.image)
                .font(.system(size: 72))
                .foregroundColor(page.color)
                .symbolEffect(.bounce, value: currentPage)
            
            VStack(spacing: 12) {
                Text(page.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(page.subtitle)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private var conceptsInteractiveView: some View {
        HStack(spacing: 20) {
            conceptCard(title: "Focus", icon: "briefcase.fill", color: Color(hex: "8B5CF6"), tag: "#work")
            conceptCard(title: "Deep Work", icon: "bolt.circle.fill", color: Color(hex: "10B981"), tag: "#deep")
            conceptCard(title: "Admin/Side", icon: "star.fill", color: Color(hex: "3B82F6"), tag: "#side")
        }
        .frame(height: 120)
    }
    
    private var calendarFittingView: some View {
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)).frame(height: 30)
                RoundedRectangle(cornerRadius: 6).fill(Color(hex: "8B5CF6")).frame(height: 40)
                    .overlay(Text("Work").font(.system(size: 10, weight: .bold)).foregroundColor(.white))
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)).frame(height: 30)
                RoundedRectangle(cornerRadius: 6).fill(Color(hex: "3B82F6")).frame(height: 30)
                    .overlay(Text("Side").font(.system(size: 10, weight: .bold)).foregroundColor(.white))
            }
            .frame(width: 120)
            .padding(8)
            .background(Color.white.opacity(0.05))
            .cornerRadius(10)
            
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white.opacity(0.3))
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(Color.white.opacity(0.1)).frame(width: 12, height: 12)
                    Text("Existing events").font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                }
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: "8B5CF6")).frame(width: 12, height: 12)
                    Text("Smart placement").font(.system(size: 12)).foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .frame(height: 120)
    }
    
    private func conceptCard(title: String, icon: String, color: Color, tag: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
            Text(tag)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.2))
                .foregroundColor(color)
                .cornerRadius(4)
        }
        .frame(width: 100, height: 110)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var bigRestInteractiveView: some View {
        VStack(spacing: 8) {
            // Mini timeline showing session flow with Big Rest
            HStack(spacing: 4) {
                // Work session
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "8B5CF6"))
                        .frame(width: 60, height: 36)
                        .overlay(Text("Work").font(.system(size: 9, weight: .bold)).foregroundColor(.white))
                    Text("40m").font(.system(size: 8)).foregroundColor(.white.opacity(0.4))
                }

                // Small rest gap
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 14, height: 36)
                    Text("10m").font(.system(size: 8)).foregroundColor(.white.opacity(0.3))
                }

                // Another work session
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "8B5CF6"))
                        .frame(width: 60, height: 36)
                        .overlay(Text("Work").font(.system(size: 9, weight: .bold)).foregroundColor(.white))
                    Text("40m").font(.system(size: 8)).foregroundColor(.white.opacity(0.4))
                }

                // Rest before big rest
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 14, height: 36)
                    Text("10m").font(.system(size: 8)).foregroundColor(.white.opacity(0.3))
                }

                // Big Rest block (hollow with dashed border)
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "F59E0B").opacity(0.08))
                        .frame(width: 70, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .foregroundColor(Color(hex: "F59E0B").opacity(0.6))
                        )
                        .overlay(
                            HStack(spacing: 3) {
                                Image(systemName: "pause.circle.fill")
                                    .font(.system(size: 8))
                                Text("Long Rest")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundColor(Color(hex: "F59E0B"))
                        )
                    Text("50m").font(.system(size: 8)).foregroundColor(Color(hex: "F59E0B").opacity(0.6))
                }

                // Next session
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "3B82F6"))
                        .frame(width: 60, height: 36)
                        .overlay(Text("Side").font(.system(size: 9, weight: .bold)).foregroundColor(.white))
                    Text("30m").font(.system(size: 8)).foregroundColor(.white.opacity(0.4))
                }
            }

            Text("Automatically placed after enough focus time accumulates")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .padding(.horizontal, 20)
    }

    private var productivityGainView: some View {
        VStack(spacing: 16) {
            Text("Potential Productivity Gain")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            
            HStack(alignment: .bottom, spacing: 12) {
                productivityBar(label: "Random", value: 0.4, color: .gray)
                productivityBar(label: "Planned", value: 0.95, color: Color(hex: "10B981"), isHighlight: true)
            }
            .frame(height: 80)
            
            Text("By eliminating decision fatigue, you regain up to 2 hours of pure focus daily.")
                .font(.system(size: 12))
                .italic()
                .foregroundColor(Color(hex: "10B981").opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .padding(.horizontal, 40)
    }
    
    private func productivityBar(label: String, value: CGFloat, color: Color, isHighlight: Bool = false) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 40, height: 60)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: 40, height: 60 * value)
                    .shadow(color: color.opacity(isHighlight ? 0.5 : 0), radius: 5)
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

// MARK: - Container Style Modifier
struct ContainerStyleModifier: ViewModifier {
    let isShownFromMenu: Bool
    
    func body(content: Content) -> some View {
        if isShownFromMenu {
            // Simple style like PatternsGuide when shown from menu
            content
                .frame(width: 500, height: 750)
        } else {
            // Frosted glass style for onboarding
            content
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(hex: "1E293B").opacity(0.95))
                        .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.2),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .padding(40)
                .frame(width: 500, height: 750)
        }
    }
}

struct WelcomePage {
    let title: String
    let subtitle: String
    let image: String
    let color: Color
}

#Preview {
    WelcomeScreen()
}

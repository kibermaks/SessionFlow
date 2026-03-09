import SwiftUI

struct TasksGuide: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentPage = 0
    @AppStorage("hasSeenTasksGuide") private var hasSeenTasksGuide = false
    
    let pages = [
        WelcomePage(
            title: "Beyond Generic Names",
            subtitle: "Stop scheduling 'Work session'. The Tasks tab lets you define exactly what you'll be doing, from coding to content creation.",
            image: "text.badge.plus",
            color: Color(hex: "10B981")
        ),
        WelcomePage(
            title: "Smart Queue",
            subtitle: "The engine pulls titles from your list sequentially. If you schedule more sessions than items in your list, it falls back to generic names to keep the focus on current tasks.",
            image: "text.justify.left",
            color: Color(hex: "8B5CF6")
        ),
        WelcomePage(
            title: "Quick Sorting",
            subtitle: "Use Cmd + Up/Down to reorder your priority list instantly. Your projected schedule updates in real-time.",
            image: "line.3.horizontal.decrease.circle",
            color: Color(hex: "EF4444")
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
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                
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
                        }
                        
                        Button {
                            handleNext()
                        } label: {
                            Text(currentPage == pages.count - 1 ? "Start Organizing" : "Next")
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
        .frame(width: 500, height: 600)
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
        hasSeenTasksGuide = true
        dismiss()
    }
    
    private func pageView(for page: WelcomePage) -> some View {
        VStack(spacing: 16) {
            Image(systemName: page.image)
                .font(.system(size: 72))
                .foregroundColor(page.color)
            
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
}

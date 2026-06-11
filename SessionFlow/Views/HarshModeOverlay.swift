import AppKit
import Combine
import SwiftUI

private final class HarshModePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class HarshModeWindowController: ObservableObject {
    private var panels: [NSPanel] = []
    private var cancellables = Set<AnyCancellable>()
    private weak var awarenessService: SessionAwarenessService?
    private var screenObserver: NSObjectProtocol?
    private var overlayState: HarshModeOverlayState?

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        hidePanels()
    }

    func setup(awarenessService: SessionAwarenessService) {
        if self.awarenessService === awarenessService, !cancellables.isEmpty {
            return
        }

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }

        hidePanels()
        cancellables.removeAll()
        self.awarenessService = awarenessService

        awarenessService.$harshModePrompt
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak awarenessService] prompt in
                guard let self, let awarenessService else { return }
                if let prompt {
                    self.showPanels(prompt: prompt, awarenessService: awarenessService)
                } else {
                    self.hidePanels()
                }
            }
            .store(in: &cancellables)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak awarenessService] _ in
            guard let self, let awarenessService, let prompt = awarenessService.harshModePrompt else { return }
            self.showPanels(prompt: prompt, awarenessService: awarenessService)
        }
    }

    private func showPanels(prompt: HarshModePrompt, awarenessService: SessionAwarenessService) {
        let state: HarshModeOverlayState
        if let overlayState, overlayState.promptID == prompt.id {
            state = overlayState
        } else {
            state = HarshModeOverlayState(prompt: prompt, config: awarenessService.config)
            overlayState = state
        }
        state.activePanelID = nil
        hidePanels(clearState: false)

        let activeScreen = screenContainingMouse() ?? NSScreen.main
        let screens = NSScreen.screens.isEmpty ? [NSScreen.main].compactMap { $0 } : NSScreen.screens
        var firstPanelID: UUID?

        for (index, screen) in screens.enumerated() {
            let panelID = UUID()
            if firstPanelID == nil {
                firstPanelID = panelID
            }
            if screen == activeScreen || (activeScreen == nil && index == 0) {
                state.activePanelID = panelID
            }

            let panel = HarshModePanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isMovable = false
            panel.isReleasedWhenClosed = false
            panel.setFrame(screen.frame, display: false)

            let rootView = HarshModeOverlayView(
                prompt: prompt,
                awarenessService: awarenessService,
                state: state,
                panelID: panelID,
                onActivate: { [weak panel, weak state] in
                    state?.activePanelID = panelID
                    panel?.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                },
                onSubmitGoals: { [weak awarenessService] goals in
                    awarenessService?.submitHarshGoals(goals) ?? false
                },
                onSubmitReview: { [weak awarenessService] rating, reflection in
                    awarenessService?.submitHarshReview(rating: rating, reflection: reflection) ?? false
                },
                onEmergencyBreak: { [weak awarenessService] in
                    awarenessService?.emergencyBreakHarshMode()
                }
            )

            let hostingView = NSHostingView(rootView: rootView)
            hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)
            panel.contentView = hostingView

            if state.activePanelID == panelID {
                panel.makeKeyAndOrderFront(nil)
            } else {
                panel.orderFrontRegardless()
            }
            panels.append(panel)
        }

        if state.activePanelID == nil {
            state.activePanelID = firstPanelID
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hidePanels(clearState: Bool = true) {
        panels.forEach { panel in
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
        if clearState {
            overlayState = nil
        }
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        }
    }
}

private final class HarshModeOverlayState: ObservableObject {
    let promptID: String
    @Published var activePanelID: UUID?
    @Published var goalsText: String
    @Published var reflectionText: String = ""
    @Published var selectedRating: SessionRating?
    @Published var errorMessage: String?

    init(prompt: HarshModePrompt, config: SessionAwarenessConfig) {
        self.promptID = prompt.id
        self.goalsText = Self.initialGoalsText(for: prompt, config: config)
        self.selectedRating = SessionRating.fromNotes(prompt.notes)
    }

    private static func initialGoalsText(for prompt: HarshModePrompt, config: SessionAwarenessConfig) -> String {
        let existingGoals = HarshModeSessionNotes.goals(from: prompt.notes)
        if !existingGoals.isEmpty {
            return existingGoals.joined(separator: "\n")
        }
        return config.harshModePrefillTitleGoal ? prompt.sessionTitle : ""
    }
}

private struct HarshModeTextArea: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let isFocused: Bool
    let canSubmit: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.font = .systemFont(ofSize: fontSize)

        if isFocused, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HarshModeTextArea

        init(parent: HarshModeTextArea) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) ||
                    commandSelector == #selector(NSResponder.insertLineBreak(_:)) else {
                return false
            }

            let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            if flags.contains(.shift) || !parent.canSubmit {
                return false
            }

            parent.onSubmit()
            return true
        }
    }
}

private struct HarshModeOverlayView: View {
    let prompt: HarshModePrompt
    @ObservedObject var awarenessService: SessionAwarenessService
    @ObservedObject var state: HarshModeOverlayState
    @ObservedObject private var timeState: SessionTimeState
    let panelID: UUID
    let onActivate: () -> Void
    let onSubmitGoals: ([String]) -> Bool
    let onSubmitReview: (SessionRating?, String) -> Bool
    let onEmergencyBreak: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    init(
        prompt: HarshModePrompt,
        awarenessService: SessionAwarenessService,
        state: HarshModeOverlayState,
        panelID: UUID,
        onActivate: @escaping () -> Void,
        onSubmitGoals: @escaping ([String]) -> Bool,
        onSubmitReview: @escaping (SessionRating?, String) -> Bool,
        onEmergencyBreak: @escaping () -> Void
    ) {
        self.prompt = prompt
        _awarenessService = ObservedObject(wrappedValue: awarenessService)
        _state = ObservedObject(wrappedValue: state)
        _timeState = ObservedObject(wrappedValue: awarenessService.timeState)
        self.panelID = panelID
        self.onActivate = onActivate
        self.onSubmitGoals = onSubmitGoals
        self.onSubmitReview = onSubmitReview
        self.onEmergencyBreak = onEmergencyBreak
    }

    private var colors: AppColors {
        AppColors(isDark: colorScheme == .dark)
    }

    private var displayNotes: String? {
        awarenessService.currentEventId == prompt.eventId ? awarenessService.currentEventNotes : prompt.notes
    }

    private var goalLines: [String] {
        HarshModeSessionNotes.goalLines(from: state.goalsText)
    }

    private var canSubmitGoals: Bool {
        goalLines.count >= max(1, awarenessService.config.harshModeMinimumGoals)
    }

    private var canSubmitReview: Bool {
        (!awarenessService.config.harshModeRequireEndRating || state.selectedRating != nil) &&
            (!awarenessService.config.harshModeRequireReviewNote || !state.reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var progress: Double {
        if prompt.phase == .end { return 1 }
        if awarenessService.currentEventId == prompt.eventId {
            return awarenessService.progress
        }
        return 0
    }

    private var remainingText: String {
        if prompt.phase == .end {
            return "complete"
        }
        if awarenessService.currentEventId == prompt.eventId {
            return "\(formatSessionDuration(awarenessService.remaining)) left"
        }
        return "starting"
    }

    private var blockerAccent: Color {
        switch awarenessService.config.harshModeBlockerTemplate {
        case .lockdown: return Color(hex: "F87171")
        case .calm: return Color(hex: "2DD4BF")
        case .minimal: return Color.accentColor
        case .space: return Color(hex: "60A5FA")
        }
    }

    private var isActivePanel: Bool {
        state.activePanelID == panelID
    }

    var body: some View {
        ZStack {
            blockerBackground

            GeometryReader { geo in
                ZStack {
                    if isActivePanel {
                        activeDialog
                            .frame(width: min(580, max(360, geo.size.width - 120)))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            }
        }
        .overlay {
            if !isActivePanel {
                inactivePanelOverlay
            }
        }
        .preferredColorScheme(.dark)
        .focusEffectDisabled()
    }

    private var activeDialog: some View {
        VStack(alignment: .leading, spacing: 16) {
            overlayIdentity
            taskFocus

            if prompt.phase == .start {
                startForm
            } else {
                endForm
            }

            if let errorMessage = state.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "FCA5A5"))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            sessionDetailsFooter
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(blockerAccent.opacity(0.36), lineWidth: 1.2)
        )
        .shadow(color: .black.opacity(0.62), radius: 24, x: 0, y: 16)
    }

    private var inactivePanelOverlay: some View {
        ZStack {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture {
                    onActivate()
                }

            VStack(spacing: 10) {
                VStack(spacing: 4) {
                    appIcon(size: 22)
                    Text("SessionFlow · Commit Mode")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.72))

                Label("Click to continue here", systemImage: "cursorarrow.click.2")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.42))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private var overlayIdentity: some View {
        HStack(spacing: 7) {
            appIcon(size: 14)

            Text("SessionFlow")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            Text("Commit Mode")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary.opacity(0.82))

            Spacer()
        }
        .textCase(.none)
    }

    private func appIcon(size: CGFloat) -> some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: max(2, size * 0.18)))
    }

    @ViewBuilder
    private var blockerBackground: some View {
        switch awarenessService.config.harshModeBlockerTemplate {
        case .lockdown:
            ZStack {
                Color.black.opacity(0.88)
                RadialGradient(
                    colors: [
                        Color.red.opacity(0.28),
                        Color.black.opacity(0.0),
                    ],
                    center: .center,
                    startRadius: 10,
                    endRadius: 620
                )
            }
            .ignoresSafeArea()
        case .calm:
            LinearGradient(
                colors: [
                    Color(hex: "0F766E").opacity(0.86),
                    Color(hex: "0F172A").opacity(0.94),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        case .minimal:
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
        case .space:
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: "020617"),
                        Color(hex: "111827"),
                        Color(hex: "1E1B4B"),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                GeometryReader { geo in
                    ForEach(0..<44, id: \.self) { index in
                        let size = CGFloat((index % 3) + 1)
                        Circle()
                            .fill(Color.white.opacity(index % 5 == 0 ? 0.72 : 0.38))
                            .frame(width: size, height: size)
                            .position(
                                x: geo.size.width * CGFloat((index * 37) % 100) / 100,
                                y: geo.size.height * CGFloat((index * 61) % 100) / 100
                            )
                    }
                }
            }
            .ignoresSafeArea()
        }
    }

    private var taskFocus: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(prompt.sessionTitle)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text(prompt.phase == .start ? "Decide what this session is for." : "Close the loop before moving on.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    private var startForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Goals for this session", systemImage: "scope")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
                Text("\(goalLines.count) goal\(goalLines.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(canSubmitGoals ? Color(hex: "86EFAC") : Color(hex: "FCA5A5"))
            }

            HarshModeTextArea(
                text: $state.goalsText,
                fontSize: 16,
                isFocused: isActivePanel,
                canSubmit: canSubmitGoals,
                onSubmit: submitGoals
            )
            .padding(10)
            .frame(height: 104)
            .background(Color.black.opacity(0.26))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(canSubmitGoals ? Color.green.opacity(0.42) : Color.red.opacity(0.45), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("One goal per line. Minimum: \(max(1, awarenessService.config.harshModeMinimumGoals)). Saved into this Calendar event.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                actionRow(
                    primaryTitle: "Start Session",
                    primaryIcon: "play.fill",
                    isPrimaryEnabled: canSubmitGoals,
                    primaryAction: submitGoals
                )
            }
        }
    }

    private var endForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How did it go?")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)

            HStack(spacing: 10) {
                ForEach(SessionRating.allCases, id: \.rawValue) { rating in
                    ratingButton(rating)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Review notes", systemImage: "text.bubble")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)

                HarshModeTextArea(
                    text: $state.reflectionText,
                    fontSize: 14,
                    isFocused: isActivePanel,
                    canSubmit: canSubmitReview,
                    onSubmit: submitReview
                )
                .padding(10)
                .frame(height: 96)
                .background(Color.black.opacity(0.26))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(reviewRequirementText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                actionRow(
                    primaryTitle: "Stop and Save",
                    primaryIcon: "stop.fill",
                    isPrimaryEnabled: canSubmitReview,
                    primaryAction: submitReview
                )
            }
        }
    }

    private func actionRow(
        primaryTitle: String,
        primaryIcon: String,
        isPrimaryEnabled: Bool,
        primaryAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Button(role: .destructive) {
                onEmergencyBreak()
            } label: {
                Label("Emergency", systemImage: "escape")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Button {
                primaryAction()
            } label: {
                Label(primaryTitle, systemImage: primaryIcon)
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isPrimaryEnabled)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var sessionDetailsFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .opacity(0.45)

            HStack(spacing: 8) {
                Image(systemName: prompt.sessionType?.icon ?? "circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(prompt.sessionType?.color ?? .gray)

                if let type = prompt.sessionType {
                    Text(type.rawValue)
                        .foregroundColor(type.color)
                }

                Text(formatSessionTimeRange(start: prompt.startTime, end: prompt.endTime))
                Text(remainingText)

                Spacer()
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(.secondary)

            if awarenessService.config.harshModeShowProgressOnBlocker {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.12))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(blockerAccent.opacity(0.75))
                            .frame(width: geo.size.width * CGFloat(max(0, min(1, progress))))
                    }
                }
                .frame(height: 5)
            }

            if awarenessService.config.harshModeShowEventNotes,
               let notes = SessionAwarenessService.strippedNotes(displayNotes) {
                Text(notes)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var reviewRequirementText: String {
        switch (awarenessService.config.harshModeRequireEndRating, awarenessService.config.harshModeRequireReviewNote) {
        case (true, true):
            return "Rating and review are required, then saved into this Calendar event."
        case (true, false):
            return "Rating is required. Review notes are optional."
        case (false, true):
            return "Review notes are required. Rating is optional."
        case (false, false):
            return "Review is optional and saved into this Calendar event when present."
        }
    }

    private func ratingButton(_ rating: SessionRating) -> some View {
        let isSelected = state.selectedRating == rating
        let color = awarenessRatingColor(rating, isDark: true)

        return Button {
            state.selectedRating = rating
            state.errorMessage = nil
        } label: {
            VStack(spacing: 8) {
                Image(systemName: rating.icon)
                    .font(.system(size: 22, weight: .semibold))
                Text(rating.label)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? color : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(isSelected ? color.opacity(0.18) : Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color.opacity(0.6) : Color.white.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .hoverEffect(brightness: 0.12)
    }

    private func submitGoals() {
        guard canSubmitGoals else {
            state.errorMessage = "Add at least \(max(1, awarenessService.config.harshModeMinimumGoals)) goal\(awarenessService.config.harshModeMinimumGoals == 1 ? "" : "s") before starting."
            return
        }
        state.errorMessage = onSubmitGoals(goalLines) ? nil : "Could not save goals to Calendar."
    }

    private func submitReview() {
        guard canSubmitReview else {
            if awarenessService.config.harshModeRequireEndRating && state.selectedRating == nil {
                state.errorMessage = "Choose a rating before stopping."
            } else {
                state.errorMessage = "Write a review note before stopping."
            }
            return
        }
        state.errorMessage = onSubmitReview(state.selectedRating, state.reflectionText) ? nil : "Could not save review to Calendar."
    }

}

struct HarshModeGuide: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentPage = 0
    @State private var demoGoals = "Ship the hard part\nWrite down the next step"
    @State private var selectedRating: SessionRating? = .completed
    @State private var reflection = "Stayed on task after defining the target."

    private var colors: AppColors {
        AppColors(isDark: colorScheme == .dark)
    }

    private let pages: [(title: String, subtitle: String, icon: String, color: Color)] = [
        (
            title: "Start With Goals",
            subtitle: "When a tagged SessionFlow task starts, Commit Mode covers every display until you set one or more goals.",
            icon: "lock.shield.fill",
            color: Color(hex: "EF4444")
        ),
        (
            title: "Keep The Target Visible",
            subtitle: "Saved goals are written into the Calendar event and shown prominently in the bottom panel and mini player.",
            icon: "scope",
            color: Color(hex: "F97316")
        ),
        (
            title: "Stop With A Review",
            subtitle: "When the session ends, Commit Mode blocks again until you rate the session and optionally add review notes.",
            icon: "checkmark.seal.fill",
            color: Color(hex: "10B981")
        ),
    ]

    var body: some View {
        ZStack {
            colors.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 12) {
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

                pageHeader
                    .frame(maxHeight: .infinity)

                interactiveDemo
                    .frame(height: 190)
                    .padding(.horizontal, 38)

                footer
            }
        }
        .frame(width: 500, height: 680)
        .focusEffectDisabled()
    }

    private var pageHeader: some View {
        let page = pages[currentPage]
        return VStack(spacing: 16) {
            Image(systemName: page.icon)
                .font(.system(size: 72, weight: .semibold))
                .foregroundColor(page.color)

            Text(page.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(colors.textPrimary)

            Text(page.subtitle)
                .font(.system(size: 16))
                .foregroundColor(colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 390)
        }
        .padding(.horizontal, 40)
        .transition(.opacity)
    }

    @ViewBuilder
    private var interactiveDemo: some View {
        if currentPage == 0 {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Goals", systemImage: "scope")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Text("\(HarshModeSessionNotes.goalLines(from: demoGoals).count) saved")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "10B981"))
                }

                TextEditor(text: $demoGoals)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(colors.subtleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    if !HarshModeSessionNotes.goalLines(from: demoGoals).isEmpty {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentPage = 1
                        }
                    }
                } label: {
                    Label("Start Session", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(colors.textPrimary)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(pages[currentPage].color)
                        )
                }
                .buttonStyle(.plain)
                .hoverEffect(brightness: 0.12)
                .disabled(HarshModeSessionNotes.goalLines(from: demoGoals).isEmpty)
            }
        } else if currentPage == 1 {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "briefcase.fill")
                        .foregroundColor(SessionType.work.color)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Writing Session")
                            .font(.system(size: 15, weight: .bold))
                        HStack(spacing: 5) {
                            Image(systemName: "scope")
                                .font(.system(size: 10, weight: .semibold))
                            Text(HarshModeSessionNotes.goalLines(from: demoGoals).prefix(2).joined(separator: " / "))
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(2)
                        }
                        .foregroundColor(Color(hex: "F97316"))
                    }
                    Spacer()
                    Text("18:42")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .background(colors.subtleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(colors.divider)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(SessionType.work.color)
                            .frame(width: geo.size.width * 0.56)
                    }
                }
                .frame(height: 6)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(SessionRating.allCases, id: \.rawValue) { rating in
                        guideRatingButton(rating)
                    }
                }

                TextEditor(text: $reflection)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(colors.subtleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    if selectedRating != nil {
                        dismiss()
                    }
                } label: {
                    Label("Stop and Save", systemImage: "stop.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(colors.textPrimary)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(pages[currentPage].color)
                        )
                }
                .buttonStyle(.plain)
                .hoverEffect(brightness: 0.12)
                .disabled(selectedRating == nil)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 22) {
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(currentPage == index ? pages[index].color : colors.textDisabled)
                        .frame(width: 8, height: 8)
                }
            }

            HStack(spacing: 16) {
                if currentPage > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { currentPage -= 1 }
                    } label: {
                        Text("Back")
                            .font(.system(size: 15, weight: .bold))
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
                        withAnimation(.easeInOut(duration: 0.2)) { currentPage += 1 }
                    } else {
                        dismiss()
                    }
                } label: {
                    Text(currentPage == pages.count - 1 ? "Got it" : "Next")
                        .font(.system(size: 15, weight: .bold))
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
        .padding(.bottom, 38)
    }

    private func guideRatingButton(_ rating: SessionRating) -> some View {
        let color = awarenessRatingColor(rating, isDark: colorScheme == .dark)
        let isSelected = selectedRating == rating
        return Button {
            selectedRating = rating
        } label: {
            VStack(spacing: 6) {
                Image(systemName: rating.icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(rating.label)
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(isSelected ? color : colors.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(isSelected ? color.opacity(0.16) : colors.subtleBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? color.opacity(0.45) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .hoverEffect(brightness: 0.12)
    }
}

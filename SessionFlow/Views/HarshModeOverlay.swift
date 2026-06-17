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
            state = HarshModeOverlayState(prompt: prompt)
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
                onSubmitGoals: { [weak awarenessService] title, goals in
                    awarenessService?.submitHarshGoals(title: title, goals: goals) ?? false
                },
                onSubmitReview: { [weak awarenessService] title, rating, alignment, reflection, goals in
                    awarenessService?.submitHarshReview(title: title, rating: rating, alignment: alignment, reflection: reflection, goals: goals) ?? false
                },
                onDelayPrompt: { [weak awarenessService] minutes in
                    awarenessService?.submitHarshDelay(minutes: minutes) ?? false
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
    @Published var titleText: String
    @Published var goalsText: String
    @Published var reflectionText: String = ""
    @Published var selectedRating: SessionRating?
    @Published var selectedAlignment: SessionAlignment?
    @Published var currentGoalLine: String = ""
    @Published var currentGoalLineRange = NSRange(location: 0, length: 0)
    @Published var errorMessage: String?

    init(prompt: HarshModePrompt) {
        self.promptID = prompt.id
        self.titleText = prompt.sessionTitle
        self.goalsText = Self.initialGoalsText(for: prompt)
        self.selectedRating = SessionRating.fromNotes(prompt.notes)
        self.selectedAlignment = SessionAlignment.fromNotes(prompt.notes)
    }

    private static func initialGoalsText(for prompt: HarshModePrompt) -> String {
        let existingGoals = HarshModeSessionNotes.goals(from: prompt.notes)
        if !existingGoals.isEmpty {
            return existingGoals.joined(separator: "\n")
        }
        return ""
    }
}

private struct HarshModeTextArea: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let isFocused: Bool
    let canSubmit: Bool
    let onSubmit: () -> Void
    var onFocusChange: (Bool) -> Void = { _ in }
    var onCurrentLineChange: (String, NSRange) -> Void = { _, _ in }

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
        private var lastLine: String = ""
        private var lastLineRange = NSRange(location: NSNotFound, length: 0)

        init(parent: HarshModeTextArea) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updateCurrentLine(textView)
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange(true)
            if let textView = notification.object as? NSTextView {
                updateCurrentLine(textView)
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onFocusChange(false)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            updateCurrentLine(textView)
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

        func updateCurrentLine(_ textView: NSTextView) {
            let nsText = textView.string as NSString
            let location = min(textView.selectedRange().location, nsText.length)
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            nsText.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let lineRange = NSRange(location: lineStart, length: max(0, contentsEnd - lineStart))
            let line = nsText
                .substring(with: lineRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard line != lastLine ||
                    lineRange.location != lastLineRange.location ||
                    lineRange.length != lastLineRange.length else {
                return
            }
            lastLine = line
            lastLineRange = lineRange
            parent.onCurrentLineChange(line, lineRange)
        }
    }
}

private struct HarshModeSuggestionList: View {
    let suggestions: [String]
    let accentColor: Color
    let onSelect: (String) -> Void

    @State private var hoveredSuggestion: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: "111827"))
                .shadow(color: Color.black.opacity(0.45), radius: 16, x: 0, y: 10)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            onSelect(suggestion)
                        } label: {
                            Text(suggestion)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .foregroundColor(hoveredSuggestion == suggestion ? .white : Color(hex: "F8FAFC"))
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(hoveredSuggestion == suggestion ? accentColor.opacity(0.95) : Color.clear)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            hoveredSuggestion = hovering ? suggestion : nil
                        }
                    }
                }
                .padding(5)
            }
        }
        .frame(maxHeight: 142)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

private enum HarshModeFocusedTextArea {
    case goals
    case review
}

private struct HarshModeOverlayView: View {
    let prompt: HarshModePrompt
    @ObservedObject var awarenessService: SessionAwarenessService
    @ObservedObject var state: HarshModeOverlayState
    @ObservedObject private var timeState: SessionTimeState
    @ObservedObject private var nameHistory = SessionNameHistory.shared
    @ObservedObject private var taskLineHistory = TaskLineHistory.shared
    let panelID: UUID
    let onActivate: () -> Void
    let onSubmitGoals: (String, [String]) -> Bool
    let onSubmitReview: (String, SessionRating?, SessionAlignment?, String, [String]) -> Bool
    let onDelayPrompt: (Int) -> Bool
    let onEmergencyBreak: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isTitleFocused: Bool
    @State private var isTitleInlineEditing = false
    @State private var focusedTextArea: HarshModeFocusedTextArea?
    @State private var titleSuggestionsVisible = false
    @State private var goalSuggestionsVisible = false
    @State private var goalsAreFocused = false

    init(
        prompt: HarshModePrompt,
        awarenessService: SessionAwarenessService,
        state: HarshModeOverlayState,
        panelID: UUID,
        onActivate: @escaping () -> Void,
        onSubmitGoals: @escaping (String, [String]) -> Bool,
        onSubmitReview: @escaping (String, SessionRating?, SessionAlignment?, String, [String]) -> Bool,
        onDelayPrompt: @escaping (Int) -> Bool,
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
        self.onDelayPrompt = onDelayPrompt
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

    private var startGoalsRequired: Bool {
        awarenessService.config.harshModeRequireStartGoals
    }

    private var hasRequiredStartGoals: Bool {
        goalLines.count >= max(1, awarenessService.config.harshModeMinimumGoals)
    }

    private var canSubmitGoals: Bool {
        !startGoalsRequired || hasRequiredStartGoals
    }

    private var canSubmitReview: Bool {
        (!awarenessService.config.harshModeRequireEndRating || (state.selectedRating != nil && state.selectedAlignment != nil)) &&
            (!awarenessService.config.harshModeRequireReviewNote || !state.reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var availableDelayMinutes: [Int] {
        awarenessService.availableHarshDelayMinutes(for: prompt)
    }

    private var titleSuggestions: [String] {
        guard let sessionType = prompt.sessionType else { return [] }
        let query = state.titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let names = nameHistory.getNames(for: sessionType)
        guard !query.isEmpty else { return Array(names.prefix(6)) }
        return names
            .filter {
                $0.localizedCaseInsensitiveContains(query) &&
                $0.localizedCaseInsensitiveCompare(query) != .orderedSame
            }
            .prefix(6)
            .map { $0 }
    }

    private var goalSuggestions: [String] {
        guard let sessionType = prompt.sessionType else { return [] }
        let query = state.currentGoalLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = taskLineHistory.getLines(for: sessionType)
        guard !query.isEmpty else { return Array(lines.prefix(7)) }
        return lines
            .filter {
                $0.localizedCaseInsensitiveContains(query) &&
                $0.localizedCaseInsensitiveCompare(query) != .orderedSame
            }
            .prefix(7)
            .map { $0 }
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
        .onAppear {
            if isActivePanel {
                focusDefaultField()
            }
        }
        .onChange(of: isActivePanel) { _, active in
            if active {
                focusDefaultField()
            }
        }
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

            Button(role: .destructive) {
                onEmergencyBreak()
            } label: {
                Label("Emergency Exit", systemImage: "escape")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Emergency Exit")
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
            if isTitleInlineEditing {
                inlineTitleEditor
            } else {
                titleDisplay
            }

            Text(prompt.phase == .start ? "Decide what this session is for." : "Close the loop before moving on.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    private var titleDisplay: some View {
        Text(state.titleText.isEmpty ? prompt.sessionTitle : state.titleText)
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundColor(.primary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                beginTitleInlineEdit()
            }
            .help("Double-click to edit session title")
    }

    private var inlineTitleEditor: some View {
        TextField("Session title", text: $state.titleText)
            .textFieldStyle(.plain)
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(blockerAccent.opacity(0.46), lineWidth: 1)
            )
            .focused($isTitleFocused)
            .onSubmit(finishTitleInlineEdit)
            .onChange(of: isTitleFocused) { _, focused in
                if !focused && isTitleInlineEditing {
                    finishTitleInlineEdit()
                }
            }
    }

    private var startForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            nextTaskRow

            if !isTitleInlineEditing {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Session title", systemImage: "textformat")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)

                    TextField("Session title", text: $state.titleText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(Color.black.opacity(0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                        .focused($isTitleFocused)
                        .onTapGesture {
                            titleSuggestionsVisible = true
                        }
                        .onSubmit(submitGoals)
                        .onChange(of: isTitleFocused) { _, focused in
                            if focused {
                                titleSuggestionsVisible = true
                            } else {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    if !isTitleFocused {
                                        titleSuggestionsVisible = false
                                    }
                                }
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if titleSuggestionsVisible && !titleSuggestions.isEmpty {
                                HarshModeSuggestionList(
                                    suggestions: titleSuggestions,
                                    accentColor: blockerAccent,
                                    onSelect: applyTitleSuggestion
                                )
                                .frame(maxWidth: .infinity)
                                .offset(y: 42)
                                .zIndex(20)
                            }
                        }
                        .zIndex(titleSuggestionsVisible ? 20 : 0)
                }
                .zIndex(titleSuggestionsVisible ? 100 : 0)
            }

            HStack {
                Label("Goals for this session", systemImage: "scope")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
                Button {
                    copyTitleToGoals()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Copy session title into goals")
                .disabled(state.titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text("\(goalLines.count) goal\(goalLines.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(canSubmitGoals ? Color(hex: "86EFAC") : Color(hex: "FCA5A5"))
            }

            HarshModeTextArea(
                text: $state.goalsText,
                fontSize: 16,
                isFocused: focusedTextArea == .goals,
                canSubmit: canSubmitGoals,
                onSubmit: submitGoals,
                onFocusChange: { focused in
                    goalsAreFocused = focused
                    if focused {
                        focusedTextArea = .goals
                    } else if focusedTextArea == .goals {
                        focusedTextArea = nil
                    }
                    if focused {
                        goalSuggestionsVisible = true
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            if !goalsAreFocused {
                                goalSuggestionsVisible = false
                            }
                        }
                    }
                },
                onCurrentLineChange: { line, range in
                    guard state.currentGoalLine != line ||
                            state.currentGoalLineRange.location != range.location ||
                            state.currentGoalLineRange.length != range.length else {
                        return
                    }
                    state.currentGoalLine = line
                    state.currentGoalLineRange = range
                    if goalsAreFocused {
                        goalSuggestionsVisible = true
                    }
                }
            )
            .padding(10)
            .frame(height: 104)
            .background(Color.black.opacity(0.26))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(canSubmitGoals ? Color.green.opacity(0.42) : Color.red.opacity(0.45), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if goalSuggestionsVisible && !goalSuggestions.isEmpty {
                    HarshModeSuggestionList(
                        suggestions: goalSuggestions,
                        accentColor: blockerAccent,
                        onSelect: applyGoalSuggestion
                    )
                    .frame(maxWidth: .infinity)
                    .offset(y: 10)
                    .zIndex(20)
                }
            }
            .zIndex(goalSuggestionsVisible ? 100 : 0)

            VStack(alignment: .leading, spacing: 10) {
                Text(startGoalRequirementText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                promptActionRow(
                    askLaterHelp: "Move this Calendar event later and ask again at the new start time",
                    primaryTitle: "Start Session",
                    primaryIcon: "play.fill",
                    isPrimaryEnabled: canSubmitGoals,
                    primaryAction: submitGoals
                )
            }
        }
    }

    private var endForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            nextTaskRow

            VStack(alignment: .leading, spacing: 8) {
                Label("Session goals", systemImage: "scope")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)

                HarshModeTextArea(
                    text: $state.goalsText,
                    fontSize: 14,
                    isFocused: focusedTextArea == .goals,
                    canSubmit: false,
                    onSubmit: {},
                    onFocusChange: { focused in
                        if focused {
                            focusedTextArea = .goals
                        } else if focusedTextArea == .goals {
                            focusedTextArea = nil
                        }
                    }
                )
                .padding(10)
                .frame(height: 64)
                .background(Color.black.opacity(0.20))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
            }

            Text("How did it go?")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)

            Text("Focus")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                ForEach(SessionRating.allCases, id: \.rawValue) { rating in
                    ratingButton(rating)
                }
            }

            Text("Alignment")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(SessionAlignment.allCases, id: \.rawValue) { alignment in
                    alignmentButton(alignment)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Review notes", systemImage: "text.bubble")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)

                HarshModeTextArea(
                    text: $state.reflectionText,
                    fontSize: 14,
                    isFocused: focusedTextArea == .review,
                    canSubmit: canSubmitReview,
                    onSubmit: submitReview,
                    onFocusChange: { focused in
                        if focused {
                            focusedTextArea = .review
                        } else if focusedTextArea == .review {
                            focusedTextArea = nil
                        }
                    }
                )
                .padding(10)
                .frame(height: 72)
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

                promptActionRow(
                    askLaterHelp: "Extend this Calendar event and ask again later",
                    primaryTitle: "Save and Close",
                    primaryIcon: "checkmark.circle.fill",
                    isPrimaryEnabled: canSubmitReview,
                    primaryAction: submitReview
                )
            }
        }
    }

    private var nextTaskRow: some View {
        HStack(spacing: 8) {
            Image(systemName: prompt.nextTaskTitle == nil ? "calendar" : "arrow.forward.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            if let title = prompt.nextTaskTitle, let startTime = prompt.nextTaskStartTime {
                Text("Next: \(title) at \(formatSessionTime(startTime))")
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("No next task in the current schedule window")
                    .lineLimit(1)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func promptActionRow(
        askLaterHelp: String,
        primaryTitle: String,
        primaryIcon: String,
        isPrimaryEnabled: Bool,
        primaryAction: @escaping () -> Void
    ) -> some View {
        let delayMinutes = availableDelayMinutes

        return HStack(spacing: 10) {
            Menu {
                ForEach(delayMinutes, id: \.self) { minutes in
                    Button {
                        delayPrompt(minutes: minutes)
                    } label: {
                        Text("\(minutes) min")
                    }
                }

                if delayMinutes.isEmpty {
                    Text("No room before next task")
                }
            } label: {
                Label("Ask Later", systemImage: "clock.badge.plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(minHeight: 34)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(delayMinutes.isEmpty ? "No safe delay before the next task" : askLaterHelp)

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
            return "Focus, Alignment, and review notes are required, then saved into this Calendar event."
        case (true, false):
            return "Focus and Alignment are required. Review notes are optional."
        case (false, true):
            return "Review notes are required. Focus and Alignment are optional."
        case (false, false):
            return "Review is optional and saved into this Calendar event when present."
        }
    }

    private var startGoalRequirementText: String {
        if startGoalsRequired {
            return "One goal per line. Minimum: \(max(1, awarenessService.config.harshModeMinimumGoals)). Saved into this Calendar event."
        }
        return "Goals are optional. Add one per line to save them into this Calendar event."
    }

    private var titleRequiredMessage: String {
        prompt.phase == .start ? "Keep a session title before starting." : "Keep a session title before closing."
    }

    private func focusDefaultField() {
        if prompt.phase == .start {
            focusedTextArea = nil
            isTitleFocused = true
        } else if focusedTextArea == nil && !isTitleInlineEditing {
            isTitleFocused = false
            focusedTextArea = .review
        }
    }

    private func beginTitleInlineEdit() {
        isTitleInlineEditing = true
        focusedTextArea = nil
        titleSuggestionsVisible = false
        goalSuggestionsVisible = false
        DispatchQueue.main.async {
            isTitleFocused = true
        }
    }

    private func finishTitleInlineEdit() {
        let cleanedTitle = state.titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else {
            state.errorMessage = titleRequiredMessage
            DispatchQueue.main.async {
                isTitleFocused = true
            }
            return
        }
        state.titleText = cleanedTitle
        state.errorMessage = nil
        isTitleInlineEditing = false
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
                Text(rating.shortLabel)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(isSelected ? color : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(isSelected ? color.opacity(0.18) : Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color.opacity(0.6) : Color.white.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .hoverEffect(brightness: 0.12)
        .help(rating.label)
    }

    private func alignmentButton(_ alignment: SessionAlignment) -> some View {
        let isSelected = state.selectedAlignment == alignment
        let color = awarenessAlignmentColor(alignment, isDark: true)

        return Button {
            state.selectedAlignment = alignment
            state.errorMessage = nil
        } label: {
            VStack(spacing: 6) {
                Image(systemName: alignment.icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(alignment.shortLabel)
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundColor(isSelected ? color : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(isSelected ? color.opacity(0.16) : Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isSelected ? color.opacity(0.55) : Color.white.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .hoverEffect(brightness: 0.12)
        .help("\(alignment.label): \(alignment.description)")
    }

    private func submitGoals() {
        let title = state.titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            state.errorMessage = "Keep a session title before starting."
            return
        }
        guard canSubmitGoals else {
            state.errorMessage = "Add at least \(max(1, awarenessService.config.harshModeMinimumGoals)) goal\(awarenessService.config.harshModeMinimumGoals == 1 ? "" : "s") before starting."
            return
        }
        state.errorMessage = onSubmitGoals(title, goalLines) ? nil : "Could not save session details to Calendar."
    }

    private func submitReview() {
        let title = state.titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            state.errorMessage = "Keep a session title before closing."
            beginTitleInlineEdit()
            return
        }
        guard canSubmitReview else {
            if awarenessService.config.harshModeRequireEndRating && state.selectedRating == nil {
                state.errorMessage = "Choose a Focus rating before stopping."
            } else if awarenessService.config.harshModeRequireEndRating && state.selectedAlignment == nil {
                state.errorMessage = "Choose an Alignment rating before stopping."
            } else {
                state.errorMessage = "Write a review note before stopping."
            }
            return
        }
        state.titleText = title
        isTitleInlineEditing = false
        state.errorMessage = onSubmitReview(title, state.selectedRating, state.selectedAlignment, state.reflectionText, goalLines) ? nil : "Could not save review to Calendar."
    }

    private func applyTitleSuggestion(_ suggestion: String) {
        state.titleText = suggestion
        titleSuggestionsVisible = false
        state.errorMessage = nil
    }

    private func applyGoalSuggestion(_ suggestion: String) {
        let text = state.goalsText as NSString
        let safeRange: NSRange
        if state.currentGoalLineRange.location <= text.length &&
            state.currentGoalLineRange.location + state.currentGoalLineRange.length <= text.length {
            safeRange = state.currentGoalLineRange
        } else {
            safeRange = NSRange(location: text.length, length: 0)
        }

        state.goalsText = text.replacingCharacters(in: safeRange, with: suggestion)
        state.currentGoalLine = suggestion
        goalSuggestionsVisible = false
        state.errorMessage = nil
    }

    private func delayPrompt(minutes: Int) {
        state.errorMessage = onDelayPrompt(minutes) ? nil : "Could not delay before the next task."
    }

    private func copyTitleToGoals() {
        let title = state.titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var lines = HarshModeSessionNotes.goalLines(from: state.goalsText)
        guard !lines.contains(title) else { return }
        lines.append(title)
        state.goalsText = lines.joined(separator: "\n")
        state.errorMessage = nil
    }

}

struct HarshModeGuide: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentPage = 0
    @State private var demoGoals = "Ship the hard part\nWrite down the next step"
    @State private var selectedRating: SessionRating? = .completed
    @State private var selectedAlignment: SessionAlignment? = .direct
    @State private var reflection = "Stayed on task after defining the target."

    private var colors: AppColors {
        AppColors(isDark: colorScheme == .dark)
    }

    private let pages: [(title: String, subtitle: String, icon: String, color: Color)] = [
        (
            title: "Start With Goals",
            subtitle: "When a tagged SessionFlow task starts, Commit Mode covers every display until you confirm the start gate. Goals can be required or optional.",
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
            subtitle: "When the session ends, Commit Mode blocks again until you rate Focus, choose Alignment, and optionally add review notes.",
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

                HStack(spacing: 6) {
                    ForEach(SessionAlignment.allCases, id: \.rawValue) { alignment in
                        guideAlignmentButton(alignment)
                    }
                }

                TextEditor(text: $reflection)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(colors.subtleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    if selectedRating != nil && selectedAlignment != nil {
                        dismiss()
                    }
                } label: {
                    Label("Save and Close", systemImage: "checkmark.circle.fill")
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
                .disabled(selectedRating == nil || selectedAlignment == nil)
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
                Text(rating.shortLabel)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
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
        .help(rating.label)
    }

    private func guideAlignmentButton(_ alignment: SessionAlignment) -> some View {
        let color = awarenessAlignmentColor(alignment, isDark: colorScheme == .dark)
        let isSelected = selectedAlignment == alignment
        return Button {
            selectedAlignment = alignment
        } label: {
            VStack(spacing: 5) {
                Image(systemName: alignment.icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(alignment.shortLabel)
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? color : colors.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(isSelected ? color.opacity(0.14) : colors.subtleBackground)
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

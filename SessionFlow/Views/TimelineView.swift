import SwiftUI
import Combine
import AppKit

// MARK: - Diagonal Stripes Background

/// Draws repeating diagonal stripes matching the screenshot reference:
/// lighter bands over a base color, clipped to the parent shape.
struct DiagonalStripesPattern: View {
    var color: Color
    var stripeWidth: CGFloat = 5
    var gapWidth: CGFloat = 5
    var angle: Double = 45

    var body: some View {
        Canvas { context, size in
            let step = stripeWidth + gapWidth
            let radians = angle * .pi / 180
            let hyp = size.width + size.height // enough to cover rotated area

            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.rotate(by: .radians(-radians))
            context.translateBy(x: -hyp / 2, y: -hyp / 2)

            var x: CGFloat = 0
            while x < hyp {
                let rect = CGRect(x: x, y: 0, width: stripeWidth, height: hyp)
                context.fill(Path(rect), with: .color(color))
                x += step
            }
        }
    }
}

@MainActor
final class EventCreationCoordinator: ObservableObject {
    @Published var startTime: Date? = nil
    @Published var durationMinutes: Int = 30
    @Published var draftTitle: String = ""
    @Published var calendarColor: Color = .blue
    @Published var draftIsFlexible: Bool = false
    var onCommit: ((String, Date, Date, CalendarDescriptor, Bool) -> Void)?

    var isActive: Bool { startTime != nil }

    func dismiss() {
        startTime = nil
        durationMinutes = 30
        draftTitle = ""
        calendarColor = .blue
        draftIsFlexible = false
        onCommit = nil
    }
}

@MainActor
final class TimelineActionContext: ObservableObject {
    var selectedDate: Date = Date()
    var startTime: Date = Date()
}

struct TimelineView: View {
    let selectedDate: Date
    let startTime: Date
    var useNowTime: Bool = true
    var onCopySuccess: ((CopyToastInfo) -> Void)? = nil
    var onModeToast: ((String) -> Void)? = nil

    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var schedulingEngine: SchedulingEngine
    @EnvironmentObject var sessionAwarenessService: SessionAwarenessService
    @EnvironmentObject var recentEventsStore: RecentEventsStore
    @EnvironmentObject var eventCreationCoordinator: EventCreationCoordinator

    private var scheduleCoordinator: ScheduleCoordinator {
        ScheduleCoordinator(engine: schedulingEngine, calendar: calendarService)
    }
    
    private let hourHeight: CGFloat = 90 // Zoomed in from 60
    private let timeColumnWidth: CGFloat = 55
    private let compactBlockLayoutHeight: CGFloat = 30
    @State private var clockTimer: Timer? = nil
    
    
    // Detail Sheet State
    @State private var selectedSession: ScheduledSession?
    @State private var selectedBusySlot: BusyTimeSlot?
    
    // Inline Editing State (only for BusyTimeSlot)
    @State private var isEditingTitle = false
    @State private var isEditingNotes = false
    @State private var isEditingURL = false
    @State private var editingTitle: String = ""
    @State private var editingNotes: String = ""
    @State private var editingURL: String = ""
    @State private var originalTitle: String = ""
    @State private var originalNotes: String = ""
    @State private var originalURL: String = ""
    @State private var isCanceling = false
    @State private var autoFocusField: EditField? = nil
    @FocusState private var focusedField: EditField?
    
    enum EditField {
        case title
        case notes
        case url
    }
    
    // Width tracking for adaptive UI - default to 0 to start compact
    @State private var containerWidth: CGFloat = 0
    @State private var showingLegendPopover = false

    // Timeline intro bar dismissal
    @AppStorage("timelineIntroBarDismissed") private var introBarDismissed = false
    @AppStorage("devNowLineOverrideEnabled") private var devNowLineOverrideEnabled = false
    @AppStorage("devNowLineOverrideHour") private var devNowLineOverrideHour = 10
    @AppStorage("devNowLineOverrideMinute") private var devNowLineOverrideMinute = 30
    @State private var showNod = false
    @State private var currentTime = Date()

    // MARK: - Selection State (busy slots)
    @State private var selectedBusySlotIds: Set<String> = []

    // MARK: - Drag Interaction State
    @State private var dragSlotId: String? = nil
    @State private var dragSessionId: UUID? = nil
    @State private var dragPreviewStartTime: Date? = nil
    @State private var dragPreviewEndTime: Date? = nil
    @State private var dragMode: DragMode = .none
    @State private var isShiftHeld: Bool = false
    @State private var isCommandHeld: Bool = false
    @State private var isOptionHeld: Bool = false
    @State private var flagsMonitor: Any? = nil
    // Group drag: original times of every selected slot at drag start, and live preview targets.
    @State private var groupDragOriginalTimes: [String: (start: Date, end: Date)] = [:]
    @State private var groupDragPreviewTimes: [String: (start: Date, end: Date)] = [:]
    @State private var keyDownMonitor: Any? = nil
    @State private var mouseDownMonitor: Any? = nil
    @StateObject private var eventUndoManager = EventUndoManager()
    @StateObject private var actionContext = TimelineActionContext()
    @State private var eventsLocked: Bool = false
    @State private var isTimelinePanelHovered: Bool = false
    @State private var elasticOriginalBusySlots: [BusyTimeSlot]? = nil
    @State private var elasticStagedBusySlots: [BusyTimeSlot] = []
    @State private var elasticPreDragBusySlots: [BusyTimeSlot]? = nil
    @State private var elasticUndoStack: [ElasticEditSnapshot] = []
    @State private var elasticRedoStack: [ElasticEditSnapshot] = []
    @State private var elasticDisplacementMode: ElasticDisplacementMode = .bubble
    @State private var elasticEmptySpaceAfterBySlotId: [String: TimeInterval] = [:]
    @State private var showingUnfreezeConfirmation: Bool = false
    @State private var showingCopyDatePicker: Bool = false
    @State private var copyTargetDate: Date = Date()
    @State private var copySlotId: String? = nil
    @State private var renamingSessionId: UUID? = nil
    @State private var renameText: String = ""

    // Feedback badge
    @State private var feedbackPopoverEventId: String? = nil

    // Throttle for real-time recalculation during drag
    @State private var lastDragRecalcTime: Date = .distantPast
    private let dragRecalcInterval: TimeInterval = 0.15 // 150ms throttle
    // Snapshot of sessions before displacement began (for clean displacement each frame)
    @State private var preDisplacementSessions: [ScheduledSession]? = nil
    // Prevents drag re-initialization after Esc while mouse button is still held
    @State private var dragCancelled: Bool = false
    // Auto-scroll during drag
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var lastAutoScrollTime: Date = .distantPast
    @State private var scrollViewFrame: CGRect = .zero
    /// Last hour we scrolled to; used to avoid resetting scroll on every timer tick (only scroll when hour changes)
    @State private var lastScrolledStartHour: Int? = nil

    private enum DragMode: Equatable {
        case none
        case move
        case resizeTop
        case resizeBottom
    }

    private struct ElasticEditSnapshot {
        let slots: [BusyTimeSlot]
        let emptySpaceAfterBySlotId: [String: TimeInterval]
    }
    
    private var isNarrow: Bool {
        // Use a reasonable threshold for narrow width
        containerWidth < 750
    }

    private var isExtraNarrow: Bool {
        // Use a reasonable threshold for narrow width
        containerWidth < 400
    }

    private var isElasticEditing: Bool {
        elasticOriginalBusySlots != nil
    }

    private var elasticChangeCount: Int {
        elasticTimeChanges().count
    }
    
    private var showingDetailSheet: Bool {
        currentSelectedSession != nil || currentSelectedBusySlot != nil
    }

    private var currentSelectedSession: ScheduledSession? {
        guard let selectedSession else { return nil }
        return filteredProjectedSessions.first { $0.id == selectedSession.id }
    }

    private var currentSelectedBusySlot: BusyTimeSlot? {
        guard let selectedBusySlot else { return nil }
        return filteredBusySlots.first { $0.id == selectedBusySlot.id }
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                VStack(alignment: .leading, spacing: 12) {
                    headerView
                    if !introBarDismissed {
                        timelineLegendBar
                    }
                    timelineScrollView
                }
                
                // Detail sheet overlay
                if showingDetailSheet {
                    detailSheetOverlay
                }

            }
            .onAppear {
                actionContext.selectedDate = selectedDate
                actionContext.startTime = startTime
                containerWidth = geo.size.width
                flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                    isShiftHeld = event.modifierFlags.contains(.shift)
                    isCommandHeld = event.modifierFlags.contains(.command)
                    isOptionHeld = event.modifierFlags.contains(.option)
                    return event
                }
                // Use keyDown monitor for Esc (cancel drag) and undo/redo.
                keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    // Esc cancels active drag/resize, closes detail sheet, or closes event creation
                    if event.keyCode == 53 {
                        if dragMode != .none {
                            cancelDrag()
                            return nil
                        }
                        if isElasticEditing {
                            cancelElasticEditing()
                            return nil
                        }
                        if eventCreationCoordinator.isActive {
                            withAnimation(.easeOut(duration: 0.15)) {
                                eventCreationCoordinator.dismiss()
                            }
                            return nil
                        }
                        if showingDetailSheet {
                            withAnimation(.easeOut(duration: 0.2)) {
                                selectedSession = nil
                                selectedBusySlot = nil
                                resetEditingState()
                            }
                            return nil
                        }
                        if !selectedBusySlotIds.isEmpty {
                            selectedBusySlotIds.removeAll()
                            return nil
                        }
                    }
                    // Delete (51) or Forward Delete (117) — remove selected events.
                    if event.keyCode == 51 || event.keyCode == 117 {
                        if let responder = NSApp.keyWindow?.firstResponder,
                           responder is NSTextView {
                            return event
                        }
                        if !selectedBusySlotIds.isEmpty {
                            let slotsToDelete = timelineBusySlots(for: actionContext.selectedDate)
                                .filter { selectedBusySlotIds.contains($0.id) }
                            deleteSelectedSlots(slotsToDelete)
                            return nil
                        }
                    }
                    // Physical key code 6 = Z key on any layout.
                    guard event.modifierFlags.contains(.command), event.keyCode == 6 else {
                        return event
                    }
                    // Don't intercept when a text field is active (let system undo handle it)
                    if let responder = NSApp.keyWindow?.firstResponder,
                       responder is NSTextView {
                        return event
                    }
                    if isElasticEditing {
                        if event.modifierFlags.contains(.shift) {
                            guard !elasticRedoStack.isEmpty else { return event }
                            redoElasticChange()
                        } else {
                            guard !elasticUndoStack.isEmpty else { return event }
                            undoElasticChange()
                        }
                        return nil
                    }
                    if event.modifierFlags.contains(.shift) {
                        guard eventUndoManager.canRedo else { return event }
                        performRedo()
                    } else {
                        guard eventUndoManager.canUndo else { return event }
                        performUndo()
                    }
                    return nil
                }
                // Restore window focus after context menu / popover / sheet dismissal.
                // macOS SwiftUI can leave the responder chain in a broken state,
                // blocking gestures and button clicks until the app is restarted.
                mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
                    if let window = event.window, !window.isKeyWindow {
                        window.makeKeyAndOrderFront(nil)
                    }
                    // Clear stuck drag state (context menu can interrupt a gesture
                    // so .onEnded never fires, leaving dragMode stuck)
                    if dragMode != .none, event.type == .leftMouseDown {
                        resetDragState()
                    }
                    return event
                }
            }
            .onDisappear {
                if let monitor = flagsMonitor {
                    NSEvent.removeMonitor(monitor)
                    flagsMonitor = nil
                }
                if let monitor = keyDownMonitor {
                    NSEvent.removeMonitor(monitor)
                    keyDownMonitor = nil
                }
                if let monitor = mouseDownMonitor {
                    NSEvent.removeMonitor(monitor)
                    mouseDownMonitor = nil
                }
            }
            .onChange(of: geo.size.width) { _, newWidth in
                containerWidth = newWidth
            }
            .onChange(of: selectedDate) { _, _ in
                cancelElasticEditing(showToast: false)
                actionContext.selectedDate = selectedDate
                eventUndoManager.clear()
                selectedBusySlotIds.removeAll()
                if eventCreationCoordinator.isActive {
                    withAnimation(.easeOut(duration: 0.15)) {
                        eventCreationCoordinator.dismiss()
                    }
                }
            }
            .onChange(of: startTime) { _, _ in
                actionContext.startTime = startTime
            }
            .onChange(of: calendarService.busySlots.map { $0.id }) { _, _ in
                // Prune selection of slots that no longer exist.
                let live = Set(timelineBusySlots(for: actionContext.selectedDate).map { $0.id })
                let pruned = selectedBusySlotIds.intersection(live)
                if pruned.count != selectedBusySlotIds.count {
                    selectedBusySlotIds = pruned
                }
                if let selectedBusySlot, !live.contains(selectedBusySlot.id) {
                    self.selectedBusySlot = nil
                    resetEditingState()
                }
            }
            .onChange(of: schedulingEngine.projectedSessions.map { $0.id }) { _, sessionIds in
                if let selectedSession, !sessionIds.contains(selectedSession.id) {
                    self.selectedSession = nil
                }
            }
            .onAppear {
                guard clockTimer == nil else { return }
                clockTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
                    DispatchQueue.main.async {
                        currentTime = Date()
                    }
                }
            }
            .onDisappear {
                clockTimer?.invalidate()
                clockTimer = nil
            }
            .sheet(isPresented: $showingCopyDatePicker) {
                VStack(spacing: 16) {
                    Text("Copy event to date")
                        .font(.headline)
                    DatePicker("Date", selection: $copyTargetDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                    HStack {
                        Button("Cancel") {
                            showingCopyDatePicker = false
                        }
                        Spacer()
                        Button("Copy") {
                            if let slotId = copySlotId,
                               let slot = filteredBusySlots.first(where: { $0.id == slotId }) {
                                let formatter = DateFormatter()
                                formatter.dateFormat = "EEE, MMM d"
                                let label = formatter.string(from: copyTargetDate)
                                let result = calendarService.copyEventToDay(eventId: slotId, targetDate: copyTargetDate)
                                if result.success, let eventId = result.newEventId, let targetStart = result.targetStartTime {
                                    onCopySuccess?(CopyToastInfo(title: slot.title, targetLabel: label, targetDate: copyTargetDate, targetStartTime: targetStart, newEventId: eventId))
                                    Task { await calendarService.fetchEvents(for: actionContext.selectedDate) }
                                } else {
                                    schedulingEngine.schedulingMessage = "Failed to copy \"\(slot.title)\""
                                }
                            }
                            showingCopyDatePicker = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(20)
                .frame(width: 300)
            }
            .alert("Rename Session", isPresented: Binding(
                get: { renamingSessionId != nil },
                set: { if !$0 { renamingSessionId = nil } }
            )) {
                TextField("Session name", text: $renameText)
                Button("Cancel", role: .cancel) { renamingSessionId = nil }
                Button("Save") {
                    if let id = renamingSessionId,
                       let idx = schedulingEngine.projectedSessions.firstIndex(where: { $0.id == id }),
                       !renameText.isEmpty {
                        schedulingEngine.projectedSessions[idx].title = renameText
                    }
                    renamingSessionId = nil
                }
            }
        }
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            Text(formattedDate)
                .font(.system(size: isNarrow ? 17 : 20, weight: .bold, design: .rounded))
                .foregroundColor(colors.textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            
            Spacer(minLength: 8)
            
            if calendarService.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.5)
            }
            
            legendView
        }
    }

    private var timelineLegendBar: some View {
        let iconSize: CGFloat = isNarrow ? 11 : 14
        let textSize: CGFloat = isNarrow ? 11 : 14
        
        return HStack(spacing: 8) {
            HStack(spacing: 0) {
                // Left half label
                HStack {
                    Image(systemName: "arrow.turn.left.down")
                        .font(.system(size: iconSize))
                    Image(systemName: "calendar")
                        .font(.system(size: iconSize))
                    Text("Existing Events")
                        .font(.system(size: textSize, weight: .medium))
                }
                .foregroundColor(colors.textSecondary)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .help("Events from your selected calendars appear on the left side")
                
                // Center divider
                Rectangle()
                    .fill(colors.border)
                    .frame(width: 1, height: 20)
                
                // Right half label
                HStack {
                    Image(systemName: "sparkles")
                        .font(.system(size: iconSize))
                    Text("Projected Tasks")
                        .font(.system(size: textSize, weight: .medium))
                    Image(systemName: "arrow.turn.right.down")
                        .font(.system(size: iconSize))
                }
                .foregroundColor(colors.textSecondary)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .help("Smartly scheduled tasks appear on the right side, ready to be added to your calendars")
            }
            .padding(.leading, timeColumnWidth + 8)
            
            // Dismiss button
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    introBarDismissed = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colors.textMuted)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: 0.3)
            .help("Dismiss this hint")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(Color.blue.opacity(0.12))
        .offset(y: showNod ? -8 : 0)
        .animation(
            .interpolatingSpring(stiffness: 200, damping: 12)
                .delay(0.15),
            value: showNod
        )
        .onAppear {
            showNod = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                showNod = false
            }
        }
        .cornerRadius(6)
    }
    
    private var timelineScrollView: some View {
        ZStack(alignment: .topLeading) {
            ScrollView(.vertical, showsIndicators: true) {
                ScrollViewReader { proxy in
                    HStack(alignment: .top, spacing: 0) {
                        timeColumnView
                        eventsAreaView
                    }
                    .padding(.vertical, 20)
                    .frame(height: CGFloat(visibleHours.count) * hourHeight + 40)
                    .onAppear {
                        scrollProxy = proxy
                        lastScrolledStartHour = Calendar.current.component(.hour, from: startTime)
                        scrollToStartTime(proxy: proxy)
                    }
                    .onChange(of: startTime) { _, new in
                        let hour = Calendar.current.component(.hour, from: new)
                        guard lastScrolledStartHour != hour else { return }
                        lastScrolledStartHour = hour
                        scrollToStartTime(proxy: proxy)
                    }
                }
            }
            .background(
                GeometryReader { geo in
                    colors.subtleBackground
                        .onAppear { scrollViewFrame = geo.frame(in: .global) }
                        .onChange(of: geo.frame(in: .global)) { _, newFrame in scrollViewFrame = newFrame }
                }
            )
            .cornerRadius(12)
            .simultaneousGesture(TapGesture().onEnded { _ in
                NSApp.keyWindow?.makeFirstResponder(nil)
            })

            if shouldShowTimelineCornerControls {
                timelineCornerControls
                    .padding(.top, 10)
                    .padding(.leading, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                    .zIndex(20)
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isTimelinePanelHovered = hovering
            }
        }
    }
    
    private var eventsAreaView: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                hourGridLines
                
                if shouldShowCurrentTimeIndicator {
                    currentTimeIndicator(currentTime: effectiveNowTimeForIndicator, width: geometry.size.width)
                }

                if !useNowTime {
                    customStartIndicator(startTime: startTime, width: geometry.size.width)
                }
                
                // Background tap target for event creation (left half only)
                eventCreationBackgroundLayer(containerWidth: geometry.size.width)

                // Background tap target for deselection (right half)
                rightHalfDeselectLayer(containerWidth: geometry.size.width)

                // Existing events - left half
                ForEach(busySlotsWithLayout) { positionedSlot in
                    eventBlock(for: positionedSlot, containerWidth: geometry.size.width)
                }

                if let creationStart = eventCreationCoordinator.startTime,
                   Calendar.current.isDate(creationStart, inSameDayAs: selectedDate) {
                    eventCreationGhostBlock(
                        startTime: creationStart,
                        durationMinutes: eventCreationCoordinator.durationMinutes,
                        title: eventCreationCoordinator.draftTitle,
                        color: eventCreationCoordinator.calendarColor,
                        containerWidth: geometry.size.width
                    )
                }

                // Projected sessions - right half
                ForEach(filteredProjectedSessions) { session in
                    projectedSessionBlock(for: session, containerWidth: geometry.size.width)
                }

                // Drag preview overlay — busy slot
                if dragMode != .none,
                   let newStart = dragPreviewStartTime,
                   let newEnd = dragPreviewEndTime,
                   let slotId = dragSlotId,
                   let slot = filteredBusySlots.first(where: { $0.id == slotId }) {

                    // Snap indicator line (anchor slot)
                    let snapY = calculateYPosition(for: newStart)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: snapY))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: snapY))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundColor(colors.isDark ? Color.blue.opacity(0.4) : Color.blue.opacity(0.7))
                    .allowsHitTesting(false)

                    // Preview block at new position (anchor)
                    dragPreviewBlock(
                        slot: slot,
                        newStart: newStart,
                        newEnd: newEnd,
                        containerWidth: geometry.size.width
                    )

                    // Group drag: render preview blocks for every other selected slot.
                    if dragMode == .move {
                        ForEach(filteredBusySlots.filter { $0.id != slotId && groupDragPreviewTimes[$0.id] != nil }, id: \.id) { otherSlot in
                            if let target = groupDragPreviewTimes[otherSlot.id] {
                                dragPreviewBlock(
                                    slot: otherSlot,
                                    newStart: target.start,
                                    newEnd: target.end,
                                    containerWidth: geometry.size.width
                                )
                            }
                        }
                    }
                }

                // Drag preview overlay — projected session
                if dragMode != .none,
                   let newStart = dragPreviewStartTime,
                   let newEnd = dragPreviewEndTime,
                   let sessionId = dragSessionId,
                   let session = filteredProjectedSessions.first(where: { $0.id == sessionId }) {

                    let snapY = calculateYPosition(for: newStart)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: snapY))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: snapY))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundColor(colors.isDark ? Color.blue.opacity(0.4) : Color.blue.opacity(0.7))
                    .allowsHitTesting(false)

                    sessionDragPreviewBlock(
                        session: session,
                        newStart: newStart,
                        newEnd: newEnd,
                        containerWidth: geometry.size.width
                    )
                }
            }
            .clipped()
        }
    }

    private func dragPreviewBlock(
        slot: BusyTimeSlot,
        newStart: Date,
        newEnd: Date,
        containerWidth: CGFloat
    ) -> some View {
        let yPos = calculateYPosition(for: newStart)
        let height = calculateHeight(from: newStart, to: newEnd)
        let blockHeight = max(height, 8)
        let blockWidth = max((containerWidth / 2) - 16, 10)
        let centerX = 8 + blockWidth / 2
        let centerY = yPos + blockHeight / 2

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(slot.calendarColor.opacity(colors.isDark ? 0.5 : 0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.blue.opacity(0.8), lineWidth: 2)
                )
                .shadow(color: Color.blue.opacity(0.3), radius: 8, y: 2)

            if blockHeight >= 16 {
                if blockHeight <= 30 {
                    HStack(spacing: 3) {
                        Text(slot.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text(startAndDurationString(start: newStart, end: newEnd))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                    .padding(4)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(slot.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if blockHeight > 30 {
                            Text(startAndDurationString(start: newStart, end: newEnd))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding(4)
                }
            }
        }
        .frame(width: blockWidth, height: blockHeight)
        .clipped()
        .position(x: centerX, y: centerY)
        .allowsHitTesting(false)
    }

    private func eventCreationGhostBlock(
        startTime: Date,
        durationMinutes: Int,
        title: String,
        color: Color,
        containerWidth: CGFloat
    ) -> some View {
        let endTime = startTime.addingTimeInterval(Double(max(5, durationMinutes)) * 60)
        let yPos = calculateYPosition(for: startTime)
        let height = calculateHeight(from: startTime, to: endTime)
        let blockHeight = max(height, 20)
        let blockWidth = max((containerWidth / 2) - 16, 10)
        let centerX = 8 + blockWidth / 2
        let centerY = yPos + blockHeight / 2
        let displayTitle = title.isEmpty ? "New Event" : title

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                )

            DiagonalStripesPattern(color: color.opacity(colors.isDark ? 0.12 : 0.06), stripeWidth: 4, gapWidth: 6)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)

                Text(startAndDurationString(start: startTime, end: endTime))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(1)
            }
            .padding(4)
        }
        .frame(width: blockWidth, height: blockHeight)
        .clipped()
        .position(x: centerX, y: centerY)
        .allowsHitTesting(false)
    }

    private var nextDayLabel: String {
        let cal = Calendar.current
        if let nextDay = cal.date(byAdding: .day, value: 1, to: selectedDate) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, MMM d"
            return formatter.string(from: nextDay)
        }
        return "NEXT DAY"
    }

    private var hourGridLines: some View {
        VStack(spacing: 0) {
            ForEach(visibleHours, id: \.self) { hour in
                VStack(spacing: 0) {
                    if hour == 24 && effectiveEndHour > 24 {
                        // Midnight separator
                        Rectangle()
                            .fill(Color.orange.opacity(0.5))
                            .frame(height: 2)
                    } else {
                        Rectangle()
                            .fill(colors.divider)
                            .frame(height: 1)
                    }
                    Spacer()
                }
                .frame(height: hourHeight)
            }
            // Bottom edge line
            Rectangle()
                .fill(colors.divider)
                .frame(height: 1)
        }
    }
    
    private func scrollToStartTime(proxy: ScrollViewProxy) {
        let hour = Calendar.current.component(.hour, from: startTime)
        let visibleStart = schedulingEngine.hideNightHours ? schedulingEngine.dayStartHour : 0
        let targetHour = max(visibleStart, hour)
        proxy.scrollTo("hour-\(targetHour)", anchor: .center)
    }

    /// During drag, scroll the timeline when the mouse is near the top/bottom edge of the scroll view.
    private func autoScrollDuringDrag() {
        guard dragMode != .none, let proxy = scrollProxy else { return }
        let now = Date()
        guard now.timeIntervalSince(lastAutoScrollTime) >= 0.12 else { return }

        guard let window = NSApp.keyWindow,
              let contentView = window.contentView else { return }

        // Mouse in window coords (AppKit: origin bottom-left), flip to top-left
        let mouseInWindow = window.mouseLocationOutsideOfEventStream
        let mouseInView = contentView.convert(mouseInWindow, from: nil)
        let flippedY = contentView.bounds.height - mouseInView.y

        // scrollViewFrame is in SwiftUI .global coords (origin = top-left of window content)
        let topEdge: CGFloat = 50   // larger zone on top to account for title/header
        let bottomEdge: CGFloat = 30
        let distFromTop = flippedY - scrollViewFrame.minY
        let distFromBottom = scrollViewFrame.maxY - flippedY

        let targetTime: Date?
        if distFromTop >= 0 && distFromTop < topEdge {
            if let t = dragPreviewStartTime {
                targetTime = t.addingTimeInterval(-3600)
            } else { targetTime = nil }
        } else if distFromBottom >= 0 && distFromBottom < bottomEdge {
            if let t = dragPreviewEndTime {
                targetTime = t.addingTimeInterval(3600)
            } else { targetTime = nil }
        } else {
            return
        }
        guard let time = targetTime else { return }

        let cal = Calendar.current
        let hour: Int
        if cal.isDate(time, inSameDayAs: selectedDate) {
            hour = cal.component(.hour, from: time)
        } else {
            let startOfSelectedDay = cal.startOfDay(for: selectedDate)
            let diff = time.timeIntervalSince(startOfSelectedDay)
            hour = Int(diff / 3600)
        }

        let firstVisible = schedulingEngine.hideNightHours ? schedulingEngine.dayStartHour : 0
        let clampedHour = max(firstVisible, min(hour, effectiveEndHour - 1))
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("hour-\(clampedHour)", anchor: .center)
        }
        lastAutoScrollTime = now
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        if isExtraNarrow {
            formatter.dateFormat = "MMM d, yyyy"
        } else {
            formatter.dateFormat = "EEEE, MMMM d, yyyy"
        }
        return formatter.string(from: selectedDate)
    }
    
    private var legendView: some View {
        HStack(spacing: 12) {
            if isNarrow {
                // Compact Legend: Just the "Legend" button, no color boxes
                Button {
                    showingLegendPopover.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text("Legend")
                            .font(.system(size: 11, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .black))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(colors.border)
                    .foregroundColor(colors.textPrimary)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .hoverEffect(brightness: 0.15)
                .popover(isPresented: $showingLegendPopover, arrowEdge: .bottom) {
                    legendPopoverContent
                }
            } else {
                // Wide Legend: Dots with labels
                HStack(spacing: 16) {
                    ForEach(SessionType.allCases) { type in
                        legendItem(color: type.color, label: type.rawValue)
                    }
                }
            }

        }
    }

    private var shouldShowTimelineCornerControls: Bool {
        isTimelinePanelHovered || isElasticEditing
    }

    private var timelineCornerControls: some View {
        HStack(spacing: 6) {
            timelineNightHoursButton
            timelineLockButton

            if isElasticEditing {
                springEditingControls
                    .transition(.scale(scale: 0.96, anchor: .topLeading).combined(with: .opacity))
            } else if !eventsLocked {
                timelineSpringButton
            }
        }
    }

    private var timelineNightHoursButton: some View {
        Button {
            withAnimation {
                schedulingEngine.hideNightHours.toggle()
            }
            onModeToast?(schedulingEngine.hideNightHours ? "Night hours hidden" : "Night hours visible")
        } label: {
            Image(systemName: schedulingEngine.hideNightHours ? "moon.stars.fill" : "moon.stars")
                .frame(width: 16, height: 16)
                .padding(8)
                .background(colors.panelBackground.opacity(0.92))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .hoverEffect(brightness: 0.2)
        .help(schedulingEngine.hideNightHours ? "Show 00:00 - 06:00" : "Hide 00:00 - 06:00")
    }

    private var timelineLockButton: some View {
        let lockColor = Color(hex: "EF4444")
        let background = eventsLocked
            ? lockColor.opacity(colors.isDark ? 0.24 : 0.16)
            : colors.panelBackground.opacity(0.92)
        let border = eventsLocked
            ? lockColor.opacity(0.58)
            : colors.border.opacity(0.65)

        return Button {
            toggleEventsLocked()
        } label: {
            Image(systemName: eventsLocked ? "hand.raised.slash" : "hand.draw")
                .frame(width: 16, height: 16)
                .padding(8)
                .background(background)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(border, lineWidth: 1)
                )
                .cornerRadius(6)
                .foregroundColor(eventsLocked ? lockColor : colors.textPrimary)
        }
        .buttonStyle(.plain)
        .hoverEffect(brightness: 0.2)
        .help(eventsLocked ? "Unlock dragging & resizing events and sessions" : "Lock all event and session positions")
    }

    private var timelineSpringButton: some View {
        Button {
            toggleElasticEditing()
        } label: {
            TimelineSpringIcon()
                .frame(width: 16, height: 16)
                .padding(8)
                .background(colors.panelBackground.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.clear, lineWidth: 1)
                )
                .cornerRadius(6)
                .foregroundColor(colors.textPrimary)
        }
        .buttonStyle(.plain)
        .hoverEffect(brightness: 0.2)
        .help("""
Elastic edit: stage calendar moves before saving.
⌥ Option-drag: Bubble
⌥⌘ Option-Command-drag: Push down
""")
    }

    private var springEditingControls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                TimelineSpringIcon()
                    .frame(width: 17, height: 17)
                Text("Spring")
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundColor(Color(hex: "3B82F6"))

            Divider()
                .frame(height: 22)

            Picker("", selection: $elasticDisplacementMode) {
                ForEach(ElasticDisplacementMode.allCases) { mode in
                    Text(mode.shortLabel).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: isExtraNarrow ? 92 : 112)
            .help("""
Elastic displacement mode.
Bubble: only colliding flexible events move.
Push: downstream flexible events move together after a collision.
""")

            Text("\(elasticChangeCount) staged")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Color(hex: "3B82F6"))
                .cornerRadius(6)
                .help("\(elasticChangeCount) staged elastic changes")

            Button {
                cancelElasticEditing()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 14, height: 14)
                    .padding(7)
            }
            .buttonStyle(.plain)
            .background(colors.panelBackground.opacity(0.9))
            .cornerRadius(6)
            .hoverEffect(brightness: 0.2)
            .help("Cancel staged elastic changes")

            Button {
                saveElasticEditing()
            } label: {
                Image(systemName: "checkmark")
                    .frame(width: 14, height: 14)
                    .padding(7)
            }
            .buttonStyle(.plain)
            .background(elasticChangeCount == 0 ? colors.panelBackground.opacity(0.9) : Color(hex: "10B981"))
            .foregroundColor(elasticChangeCount == 0 ? colors.textMuted : .white)
            .cornerRadius(6)
            .disabled(elasticChangeCount == 0)
            .hoverEffect(brightness: elasticChangeCount == 0 ? 0 : 0.15)
            .help("Save staged elastic changes")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "3B82F6").opacity(colors.isDark ? 0.18 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(hex: "3B82F6").opacity(0.55), lineWidth: 1)
        )
        .help("Spring mode is active: moves are staged until saved or canceled")
    }
    
    private var legendPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session Types")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(colors.textPrimary)
            
            Divider().background(colors.divider)
            
            ForEach(SessionType.allCases) { type in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(type.color)
                        .frame(width: 14, height: 14)
                    Text(type.rawValue)
                        .font(.system(size: 12))
                        .foregroundColor(colors.textPrimary)
                    Spacer()
                }
            }
        }
        .padding(12)
        .frame(width: 160)
    }
    
    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .foregroundColor(colors.textSecondary)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TimelineSpringIcon: View {
    var body: some View {
        SpringShape()
            .stroke(style: StrokeStyle(lineWidth: 2.15, lineCap: .round, lineJoin: .round))
    }
}

private struct SpringShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let amplitude = rect.height * 0.30
        let left = rect.minX + rect.width * 0.07
        let right = rect.maxX - rect.width * 0.07
        let lead = rect.width * 0.14
        let coilStart = left + lead
        let coilEnd = right - lead
        let coils = 4
        let step = (coilEnd - coilStart) / CGFloat(coils)

        path.move(to: CGPoint(x: left, y: midY))
        path.addLine(to: CGPoint(x: coilStart, y: midY))

        for index in 0..<coils {
            let x = coilStart + CGFloat(index) * step
            let half = step / 2
            let quarter = step / 4
            path.addCurve(
                to: CGPoint(x: x + half, y: midY),
                control1: CGPoint(x: x + quarter * 0.55, y: midY - amplitude),
                control2: CGPoint(x: x + half - quarter * 0.55, y: midY - amplitude)
            )
            path.addCurve(
                to: CGPoint(x: x + step, y: midY),
                control1: CGPoint(x: x + half + quarter * 0.55, y: midY + amplitude),
                control2: CGPoint(x: x + step - quarter * 0.55, y: midY + amplitude)
            )
        }

        path.addLine(to: CGPoint(x: right, y: midY))
        return path
    }
}

extension TimelineView {
    
    private struct PositionedBusySlot: Identifiable {
        let slot: BusyTimeSlot
        let column: Int
        var totalColumns: Int
        var id: String { slot.id }
    }
    
    private var filteredBusySlots: [BusyTimeSlot] {
        let excluded = calendarService.excludedCalendarIDs
        let slots = timelineBusySlots(for: selectedDate)
        guard !excluded.isEmpty else { return slots }
        return slots.filter { slot in
            guard let identifier = slot.calendarIdentifier else { return true }
            return !excluded.contains(identifier)
        }
    }
    
    private var filteredProjectedSessions: [ScheduledSession] {
        let excluded = calendarService.excludedCalendarIDs
        guard !excluded.isEmpty else { return schedulingEngine.projectedSessions }
        return schedulingEngine.projectedSessions.filter { session in
            if let identifier = session.calendarIdentifier {
                return !excluded.contains(identifier)
            }
            guard let calendar = calendarService.availableCalendars.first(where: { $0.title == session.calendarName }) else {
                return true
            }
            return !excluded.contains(calendar.calendarIdentifier)
        }
    }
    
    private var busySlotsWithLayout: [PositionedBusySlot] {
        layoutBusySlots(filteredBusySlots)
    }

    private func timelineBusySlots(for date: Date) -> [BusyTimeSlot] {
        if isElasticEditing, Calendar.current.isDate(date, inSameDayAs: selectedDate) {
            return elasticStagedBusySlots
        }
        return calendarService.busySlotsForFetchedDate(date)
    }

    private var timelineDisplacementFloor: Date {
        if shouldShowCurrentTimeIndicator {
            return effectiveNowTimeForIndicator
        }
        return Calendar.current.startOfDay(for: selectedDate)
    }

    private func clampedToDisplacementFloor(_ date: Date) -> Date {
        max(date, timelineDisplacementFloor)
    }

    private func clampedForElasticDrag(_ date: Date) -> Date {
        isElasticEditing ? clampedToDisplacementFloor(date) : date
    }

    private var elasticAwareEarliestTime: Date {
        isElasticEditing ? max(actionContext.startTime, timelineDisplacementFloor) : actionContext.startTime
    }

    private func toggleEventsLocked() {
        if eventsLocked {
            withAnimation { eventsLocked = false }
            onModeToast?("Events unlocked")
            return
        }

        if isElasticEditing {
            if elasticChangeCount > 0 {
                onModeToast?("Save or cancel elastic edits before locking")
                return
            }
            cancelElasticEditing(showToast: false)
        }

        withAnimation { eventsLocked = true }
        onModeToast?("Events locked")
    }

    private func toggleElasticEditing() {
        if isElasticEditing {
            if elasticChangeCount == 0 {
                cancelElasticEditing()
            } else {
                onModeToast?("Save or cancel elastic edits")
            }
        } else {
            beginElasticEditing()
        }
    }

    private func beginElasticEditing(mode: ElasticDisplacementMode = .bubble, showToast: Bool = true, preserveSelection: Bool = false) {
        guard !eventsLocked else {
            onModeToast?("Unlock events to use elastic editing")
            return
        }
        guard !isElasticEditing else { return }

        let preservedSelection = selectedBusySlotIds
        dismissTransientInteractionState()
        if preserveSelection {
            selectedBusySlotIds = preservedSelection
        }
        let snapshot = calendarService.busySlotsForFetchedDate(actionContext.selectedDate)
        elasticOriginalBusySlots = snapshot
        elasticStagedBusySlots = snapshot
        elasticPreDragBusySlots = nil
        elasticEmptySpaceAfterBySlotId = calculateElasticEmptySpaceAfterBySlotId(for: snapshot)
        elasticUndoStack.removeAll()
        elasticRedoStack.removeAll()
        elasticDisplacementMode = mode

        if showToast {
            onModeToast?("Elastic editing enabled")
        }
    }

    private func requestedElasticModeForDrag() -> ElasticDisplacementMode? {
        let flags = NSEvent.modifierFlags
        let optionHeld = flags.contains(.option) || isOptionHeld
        let commandHeld = flags.contains(.command) || isCommandHeld
        if optionHeld && commandHeld {
            return .pushDown
        }
        if optionHeld {
            return .bubble
        }
        return nil
    }

    private func activateElasticModeForDragIfNeeded() {
        guard let requestedMode = requestedElasticModeForDrag() else { return }
        if isElasticEditing {
            elasticDisplacementMode = requestedMode
        } else {
            beginElasticEditing(mode: requestedMode, preserveSelection: true)
        }
    }

    private func cancelElasticEditing(showToast: Bool = true) {
        guard isElasticEditing else { return }
        elasticOriginalBusySlots = nil
        elasticStagedBusySlots = []
        elasticPreDragBusySlots = nil
        elasticEmptySpaceAfterBySlotId = [:]
        elasticUndoStack.removeAll()
        elasticRedoStack.removeAll()
        selectedBusySlotIds.removeAll()
        resetDragState()
        recalculateWithOriginalSlots()

        if showToast {
            onModeToast?("Elastic edits discarded")
        }
    }

    private func saveElasticEditing() {
        let changes = elasticTimeChanges()
        guard !changes.isEmpty else {
            cancelElasticEditing()
            return
        }

        let updates = changes.map {
            (eventId: $0.eventId, newStart: $0.newStartTime, newEnd: $0.newEndTime)
        }

        guard calendarService.updateEventTimes(updates) else {
            onModeToast?("Failed to save elastic edits")
            return
        }

        eventUndoManager.recordBatch(changes)
        for change in changes {
            optimisticallyUpdateSlot(id: change.eventId, newStart: change.newStartTime, newEnd: change.newEndTime)
        }

        let savedCount = changes.count
        elasticOriginalBusySlots = nil
        elasticStagedBusySlots = []
        elasticPreDragBusySlots = nil
        elasticEmptySpaceAfterBySlotId = [:]
        elasticUndoStack.removeAll()
        elasticRedoStack.removeAll()
        selectedBusySlotIds.removeAll()
        resetDragState()

        onModeToast?(savedCount == 1 ? "Saved 1 event move" : "Saved \(savedCount) event moves")
        Task { await calendarService.fetchEvents(for: actionContext.selectedDate) }
    }

    private func recordElasticUndoSnapshot(_ snapshot: [BusyTimeSlot]) {
        elasticUndoStack.append(
            ElasticEditSnapshot(
                slots: snapshot,
                emptySpaceAfterBySlotId: elasticEmptySpaceAfterBySlotId
            )
        )
        if elasticUndoStack.count > 50 {
            elasticUndoStack.removeFirst()
        }
        elasticRedoStack.removeAll()
    }

    private func undoElasticChange() {
        guard let previous = elasticUndoStack.popLast() else { return }
        elasticRedoStack.append(
            ElasticEditSnapshot(
                slots: elasticStagedBusySlots,
                emptySpaceAfterBySlotId: elasticEmptySpaceAfterBySlotId
            )
        )
        elasticStagedBusySlots = previous.slots
        elasticEmptySpaceAfterBySlotId = previous.emptySpaceAfterBySlotId
        recalculateProjectedSchedule(using: elasticStagedBusySlots)
        onModeToast?("Undid elastic move")
    }

    private func redoElasticChange() {
        guard let next = elasticRedoStack.popLast() else { return }
        elasticUndoStack.append(
            ElasticEditSnapshot(
                slots: elasticStagedBusySlots,
                emptySpaceAfterBySlotId: elasticEmptySpaceAfterBySlotId
            )
        )
        elasticStagedBusySlots = next.slots
        elasticEmptySpaceAfterBySlotId = next.emptySpaceAfterBySlotId
        recalculateProjectedSchedule(using: elasticStagedBusySlots)
        onModeToast?("Redid elastic move")
    }

    private func elasticTimeChanges() -> [EventUndoManager.EventTimeChange] {
        guard let original = elasticOriginalBusySlots else { return [] }
        let originalsById = Dictionary(uniqueKeysWithValues: original.map { ($0.id, $0) })

        return elasticStagedBusySlots
            .compactMap { staged -> EventUndoManager.EventTimeChange? in
                guard let old = originalsById[staged.id],
                      old.startTime != staged.startTime || old.endTime != staged.endTime else {
                    return nil
                }
                return EventUndoManager.EventTimeChange(
                    eventId: staged.id,
                    oldStartTime: old.startTime,
                    oldEndTime: old.endTime,
                    newStartTime: staged.startTime,
                    newEndTime: staged.endTime,
                    description: "Elastic move \(staged.title)"
                )
            }
            .sorted { $0.oldStartTime < $1.oldStartTime }
    }

    private func busySlot(_ slot: BusyTimeSlot, replacingStart start: Date, end: Date) -> BusyTimeSlot {
        TimelineEditPlanner.busySlot(slot, replacingStart: start, end: end)
    }

    private func applyingTimeUpdates(
        to slots: [BusyTimeSlot],
        updates: [String: (start: Date, end: Date)]
    ) -> [BusyTimeSlot] {
        TimelineEditPlanner.applyingTimeUpdates(to: slots, updates: updates)
    }

    private func calculateElasticEmptySpaceAfterBySlotId(for slots: [BusyTimeSlot]) -> [String: TimeInterval] {
        TimelineEditPlanner.calculateEmptySpaceAfterBySlotId(for: slots)
    }

    private func elasticGapMap(
        adjustingForDraggedUpdates draggedUpdates: [String: (start: Date, end: Date)],
        in baseSlots: [BusyTimeSlot]
    ) -> [String: TimeInterval] {
        TimelineEditPlanner.adjustedGapMap(
            existingGapMap: elasticEmptySpaceAfterBySlotId,
            draggedUpdates: draggedUpdates,
            in: baseSlots
        )
    }

    private func displaceBusySlots(
        baseSlots: [BusyTimeSlot],
        draggedUpdates: [String: (start: Date, end: Date)],
        commitDraggedSlots: Bool,
        gapAfterBySlotId: [String: TimeInterval]? = nil
    ) -> [BusyTimeSlot] {
        let existingGapMap = gapAfterBySlotId ?? elasticGapMap(
            adjustingForDraggedUpdates: draggedUpdates,
            in: baseSlots
        )
        return TimelineEditPlanner.displaceBusySlots(
            baseSlots: baseSlots,
            draggedUpdates: draggedUpdates,
            commitDraggedSlots: commitDraggedSlots,
            existingGapMap: existingGapMap,
            mode: elasticDisplacementMode,
            floor: timelineDisplacementFloor
        )
    }
    
    private var timeColumnView: some View {
        VStack(spacing: 0) {
            ForEach(visibleHours, id: \.self) { hour in
                HStack {
                    if hour == 24 && effectiveEndHour > 24 {
                        Text("next day")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(colors.isDark ? .orange.opacity(0.6) : Color(hex: "C2410C"))
                            .offset(y: -7)
                    } else {
                        Text(formattedHour(hour))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(hour >= 24 ? (colors.isDark ? .orange.opacity(0.5) : Color(hex: "C2410C")) : colors.textSecondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .offset(y: -7)
                    }
                }
                .frame(width: timeColumnWidth, height: hourHeight, alignment: .topTrailing)
                .padding(.trailing, 8)
                .id("hour-\(hour)")
            }
            
            // End of day mark
            HStack {
                Text(formattedHour(effectiveEndHour))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(effectiveEndHour >= 24 ? (colors.isDark ? .orange.opacity(0.5) : Color(hex: "C2410C")) : colors.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(y: -7)
            }
            .frame(width: timeColumnWidth, height: 0, alignment: .topTrailing)
            .padding(.trailing, 8)
        }
    }
    
    private func formattedHour(_ hour: Int) -> String {
        let normalizedHour = ((hour % 24) + 24) % 24

        if uses12HourClock {
            let displayHour = normalizedHour % 12 == 0 ? 12 : normalizedHour % 12
            let period = normalizedHour < 12 ? "AM" : "PM"
            return "\(displayHour) \(period)"
        }

        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = normalizedHour
        
        // Handle hour 24 and beyond for formatting by shifting to next day
        if hour >= 24 {
            if let date = calendar.date(from: components),
               let nextDay = calendar.date(byAdding: .day, value: 1, to: date) {
                let formatter = DateFormatter()
                formatter.dateStyle = .none
                formatter.timeStyle = .short
                return formatter.string(from: nextDay)
            }
        }
        
        
        if let date = calendar.date(from: components) {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return "\(hour):00"
    }
    
    /// The upper bound for visible hours.
    /// `dayEndHour` controls visibility when `hideNightHours` is on; we extend it
    /// up to `scheduleEndHour` so scheduled sessions are never clipped off the
    /// timeline. When night hours are shown, we expose a full 24h minimum.
    private var effectiveEndHour: Int {
        if schedulingEngine.hideNightHours {
            return max(schedulingEngine.dayEndHour, schedulingEngine.scheduleEndHour)
        } else {
            return max(24, schedulingEngine.scheduleEndHour)
        }
    }

    private var visibleHours: [Int] {
        if schedulingEngine.hideNightHours {
            return Array(schedulingEngine.dayStartHour..<effectiveEndHour)
        } else {
            return Array(0..<effectiveEndHour)
        }
    }

    /// Effective "now" for the red line: real time or dev override.
    private var effectiveNowTimeForIndicator: Date {
        guard devNowLineOverrideEnabled else { return currentTime }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: selectedDate)
        return cal.date(byAdding: .hour, value: devNowLineOverrideHour, to: dayStart)
            .flatMap { cal.date(byAdding: .minute, value: devNowLineOverrideMinute, to: $0) } ?? currentTime
    }

    /// Show current-time indicator when viewing today, or when viewing yesterday
    /// and the current time falls within the extended hours (past midnight).
    /// With dev override enabled, always show so screenshots can use any date.
    private var shouldShowCurrentTimeIndicator: Bool {
        if devNowLineOverrideEnabled { return true }
        let cal = Calendar.current
        if cal.isDateInToday(selectedDate) { return true }
        if effectiveEndHour > 24,
           let yesterday = cal.date(byAdding: .day, value: -1, to: Date()),
           cal.isDate(selectedDate, inSameDayAs: yesterday) {
            let dayStart = cal.startOfDay(for: selectedDate)
            let hoursFromStart = Date().timeIntervalSince(dayStart) / 3600
            return hoursFromStart < Double(effectiveEndHour)
        }
        return false
    }
    
    private func layoutBusySlots(_ slots: [BusyTimeSlot]) -> [PositionedBusySlot] {
        struct ActiveSlot {
            let slot: BusyTimeSlot
            let column: Int
            let positionedIndex: Int
        }
        
        let sortedSlots = slots.sorted { $0.startTime < $1.startTime }
        var positionedSlots: [PositionedBusySlot] = []
        var activeSlots: [ActiveSlot] = []
        var currentClusterIndices: [Int] = []
        var currentClusterMaxColumns = 0
        
        func finalizeCluster() {
            guard !currentClusterIndices.isEmpty else { return }
            let totalColumns = max(currentClusterMaxColumns, 1)
            for index in currentClusterIndices {
                positionedSlots[index].totalColumns = totalColumns
            }
            currentClusterIndices.removeAll()
            currentClusterMaxColumns = 0
        }
        
        for slot in sortedSlots {
            activeSlots.removeAll { active in
                active.slot.endTime <= slot.startTime
            }
            
            if activeSlots.isEmpty {
                finalizeCluster()
            }
            
            let usedColumns = Set(activeSlots.map { $0.column })
            var column = 0
            while usedColumns.contains(column) {
                column += 1
            }
            
            let positionedSlot = PositionedBusySlot(slot: slot, column: column, totalColumns: 1)
            let positionedIndex = positionedSlots.count
            positionedSlots.append(positionedSlot)
            activeSlots.append(ActiveSlot(slot: slot, column: column, positionedIndex: positionedIndex))
            currentClusterIndices.append(positionedIndex)
            currentClusterMaxColumns = max(currentClusterMaxColumns, column + 1)
        }
        
        finalizeCluster()
        return positionedSlots
    }
    
    
    
    private func currentTimeIndicator(currentTime: Date, width: CGFloat) -> some View {
        let yPos = calculateYPosition(for: currentTime)

        return ZStack(alignment: .topLeading) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .position(x: 5, y: yPos)

            Path { path in
                path.move(to: CGPoint(x: 10, y: yPos))
                path.addLine(to: CGPoint(x: width, y: yPos))
            }
            .stroke(Color.red, lineWidth: 2)
        }
    }

    private func customStartIndicator(startTime: Date, width: CGFloat) -> some View {
        let yPos = calculateYPosition(for: startTime)
        let lilac = Color(hex: "C084FC")

        return ZStack(alignment: .topLeading) {
            Circle()
                .fill(lilac)
                .frame(width: 8, height: 8)
                .position(x: 5, y: yPos)

            Path { path in
                path.move(to: CGPoint(x: 10, y: yPos))
                path.addLine(to: CGPoint(x: width, y: yPos))
            }
            .stroke(lilac, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
        .allowsHitTesting(false)
    }
    
    // ... (rest of file)
    
    // MARK: - Event Block (Busy) - Left Half
    
    private func eventBlock(for positionedSlot: PositionedBusySlot, containerWidth: CGFloat) -> some View {
        let slot = positionedSlot.slot
        let isAnchorDragging = dragSlotId == slot.id && dragMode != .none
        let isGroupMemberDragging = dragMode == .move
            && dragSlotId != nil
            && dragSlotId != slot.id
            && groupDragOriginalTimes[slot.id] != nil
        let isDragging = isAnchorDragging || isGroupMemberDragging
        let isSelected = selectedBusySlotIds.contains(slot.id)
        let yPos = calculateYPosition(for: slot.startTime)
        let height = calculateHeight(from: slot.startTime, to: slot.endTime)
        let columns = max(1, positionedSlot.totalColumns)
        let columnSpacing: CGFloat = 4
        let availableWidth = max((containerWidth / 2) - 16, 10)
        let totalSpacing = columnSpacing * CGFloat(max(0, columns - 1))
        let blockWidth = max((availableWidth - totalSpacing) / CGFloat(columns), 8)
        let blockHeight = max(height, 20)
        let columnOffset = CGFloat(positionedSlot.column) * (blockWidth + columnSpacing)

        // Calculate center position for .position() modifier
        let centerX = 8 + blockWidth / 2 + columnOffset
        let centerY = yPos + blockHeight / 2
        let edgeZone: CGFloat = min(8, blockHeight / 3)

        let fillOpacity: Double = isSelected ? 0.5 : 0.3
        let borderOpacity: Double = isSelected ? 1.0 : 0.5
        let borderWidth: CGFloat = isSelected ? 2 : 1

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(slot.calendarColor.opacity(fillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(slot.calendarColor.opacity(borderOpacity), lineWidth: borderWidth)
                )

            let showsFeedbackBadge = slot.endTime < Date() && sessionAwarenessService.config.enabled && sessionAwarenessService.config.productivityEnabled
            let goals = HarshModeSessionNotes.goals(from: slot.notes)
            let showsGoalReminder = !goals.isEmpty
            let urlMinimumHeight: CGFloat = showsGoalReminder ? 76 : 35
            let notesMinimumHeight: CGFloat = showsGoalReminder ? 92 : 45

            VStack(alignment: .leading, spacing: 1) {
                if height <= compactBlockLayoutHeight {
                    HStack(spacing: 3) {
                        flowFlexibilityIndicator(for: slot, size: 10)
                        Text(slot.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.textPrimary)
                            .lineLimit(1)

                        if showsGoalReminder {
                            busySlotGoalReminder(goals, inline: true, compact: true)
                        }

                        Spacer(minLength: 2)
                        Text(startAndDurationString(start: slot.startTime, end: slot.endTime))
                            .font(.system(size: 10))
                            .foregroundColor(colors.textSecondary)
                            .lineLimit(1)
                            .layoutPriority(1)
                            .padding(.trailing, showsFeedbackBadge ? 16 : 0)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        flowFlexibilityIndicator(for: slot, size: 11)
                        Text(slot.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colors.textPrimary)
                            .lineLimit(showsGoalReminder ? 1 : nil)
                            .fixedSize(horizontal: false, vertical: !showsGoalReminder)

                        if showsGoalReminder {
                            busySlotGoalReminder(goals, inline: true)
                        }
                    }

                    Text(startAndDurationString(start: slot.startTime, end: slot.endTime))
                        .font(.system(size: 10))
                        .foregroundColor(colors.textSecondary)
                }

                if let url = slot.url, height > urlMinimumHeight {
                    Text(url.absoluteString)
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "3B82F6"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let notes = editableNotes(from: SessionAwarenessService.strippedNotes(slot.notes)), height > notesMinimumHeight {
                    Text(notes)
                        .font(.system(size: 9))
                        .foregroundColor(colors.textSecondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: false)
                }
            }
            .padding(4)

            // Feedback badge for past events
            if showsFeedbackBadge {
                feedbackBadge(for: slot)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(2)
            }
        }
        .frame(width: blockWidth, height: blockHeight)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            guard !eventsLocked, dragMode == .none else { return }
            switch phase {
            case .active(let location):
                if location.y < edgeZone {
                    NSCursor.resizeUp.set()
                } else if location.y > blockHeight - edgeZone {
                    NSCursor.resizeDown.set()
                } else {
                    NSCursor.openHand.set()
                }
            case .ended:
                NSCursor.arrow.set()
            }
        }
        .opacity(isDragging ? 0.3 : 1.0)
        // Single unified drag gesture — determines mode from start location
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    guard !eventsLocked, !dragCancelled else { return }
                    // Determine mode on first movement
                    if dragMode == .none {
                        let startY = value.startLocation.y
                        if startY < edgeZone {
                            dragMode = .resizeTop
                        } else if startY > blockHeight - edgeZone {
                            dragMode = .resizeBottom
                        } else {
                            activateElasticModeForDragIfNeeded()
                            dragMode = .move
                            NSCursor.closedHand.push()
                            if isElasticEditing {
                                elasticPreDragBusySlots = elasticStagedBusySlots
                            }
                            // If dragged slot isn't part of the selection, reset selection to it.
                            // Resize stays single-event (no selection change).
                            if !selectedBusySlotIds.contains(slot.id) {
                                selectedBusySlotIds = [slot.id]
                            }
                            // Snapshot original times for every selected slot (for group drag).
                            if selectedBusySlotIds.count > 1 {
                                let slotsById = Dictionary(uniqueKeysWithValues: timelineBusySlots(for: actionContext.selectedDate).map { ($0.id, $0) })
                                var snapshot: [String: (start: Date, end: Date)] = [:]
                                for id in selectedBusySlotIds {
                                    if let s = slotsById[id] {
                                        snapshot[id] = (s.startTime, s.endTime)
                                    }
                                }
                                groupDragOriginalTimes = snapshot
                                groupDragPreviewTimes = snapshot
                            }
                        }
                        if isElasticEditing, dragMode != .move {
                            elasticPreDragBusySlots = elasticStagedBusySlots
                        }
                        dragSlotId = slot.id
                    }

                    switch dragMode {
                    case .move:
                        let duration = slot.endTime.timeIntervalSince(slot.startTime)
                        let originalY = calculateYPosition(for: slot.startTime)
                        let newY = originalY + value.translation.height
                        let rawDate = dateFromYOffset(newY)
                        let newStart = clampedForElasticDrag(isShiftHeld ? rawDate : snapToInterval(rawDate))
                        dragPreviewStartTime = newStart
                        dragPreviewEndTime = newStart.addingTimeInterval(duration)

                        // Group drag: translate every other selected event by the same delta.
                        if !groupDragOriginalTimes.isEmpty {
                            let translation = newStart.timeIntervalSince(slot.startTime)
                            var live: [String: (start: Date, end: Date)] = [:]
                            for (id, orig) in groupDragOriginalTimes {
                                live[id] = (
                                    orig.start.addingTimeInterval(translation),
                                    orig.end.addingTimeInterval(translation)
                                )
                            }
                            groupDragPreviewTimes = live
                        }

                    case .resizeTop:
                        let originalY = calculateYPosition(for: slot.startTime)
                        let newY = originalY + value.translation.height
                        let rawDate = dateFromYOffset(newY)
                        let newStart = clampedForElasticDrag(isShiftHeld ? rawDate : snapToInterval(rawDate))
                        let maxStart = slot.endTime.addingTimeInterval(-5 * 60)
                        dragPreviewStartTime = min(newStart, maxStart)
                        dragPreviewEndTime = slot.endTime

                    case .resizeBottom:
                        let originalY = calculateYPosition(for: slot.endTime)
                        let newY = originalY + value.translation.height
                        let rawDate = dateFromYOffset(newY)
                        let newEnd = isShiftHeld ? rawDate : snapToInterval(rawDate)
                        let minEnd = slot.startTime.addingTimeInterval(5 * 60)
                        dragPreviewStartTime = slot.startTime
                        dragPreviewEndTime = max(newEnd, minEnd)

                    case .none:
                        break
                    }

                    // Real-time recalculation with throttle
                    if let previewStart = dragPreviewStartTime,
                       let previewEnd = dragPreviewEndTime {
                        let now = Date()
                        if now.timeIntervalSince(lastDragRecalcTime) >= dragRecalcInterval {
                            lastDragRecalcTime = now
                            if isElasticEditing {
                                let updates: [String: (start: Date, end: Date)] = !groupDragPreviewTimes.isEmpty
                                    ? groupDragPreviewTimes
                                    : [slot.id: (start: previewStart, end: previewEnd)]
                                let baseSlots = elasticPreDragBusySlots ?? elasticStagedBusySlots
                                let displaced = displaceBusySlots(
                                    baseSlots: baseSlots,
                                    draggedUpdates: updates,
                                    commitDraggedSlots: false
                                )
                                elasticStagedBusySlots = displaced
                                recalculateProjectedSchedule(using: applyingTimeUpdates(to: displaced, updates: updates))
                            } else if !groupDragOriginalTimes.isEmpty {
                                recalculateWithDraggedSlots(groupDragPreviewTimes)
                            } else {
                                recalculateWithDraggedSlot(slot, newStart: previewStart, newEnd: previewEnd)
                            }
                        }
                    }
                    autoScrollDuringDrag()
                }
                .onEnded { _ in
                    guard !dragCancelled else { dragCancelled = false; return }
                    if dragMode == .move { NSCursor.pop() }
                    commitDrag(for: slot)
                }
        )
        .position(x: centerX, y: centerY)
        .onTapGesture(count: 2) {
            selectedSession = nil
            selectedBusySlot = slot
            autoFocusField = nil
        }
        .onTapGesture(count: 1) {
            if isCommandHeld || NSEvent.modifierFlags.contains(.command) {
                if selectedBusySlotIds.contains(slot.id) {
                    selectedBusySlotIds.remove(slot.id)
                } else {
                    selectedBusySlotIds.insert(slot.id)
                }
            } else {
                selectedBusySlotIds = [slot.id]
            }
        }
        .contextMenu {
            Button("View & Edit Event Details") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    selectedSession = nil
                    selectedBusySlot = slot
                }
            }
            Button(slot.isFlowFlexible ? "Mark Fixed" : "Mark Flexible") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    setBusySlotFlexible(slot, isFlexible: !slot.isFlowFlexible)
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    deleteBusySlot(slot)
                }
            }
            Divider()
            Button("Duplicate") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    let result = calendarService.duplicateEvent(eventId: slot.id)
                    if result.success, let eventId = result.newEventId, let targetStart = result.targetStartTime {
                        onCopySuccess?(CopyToastInfo(title: slot.title, targetLabel: "the same day", targetDate: actionContext.selectedDate, targetStartTime: targetStart, newEventId: eventId))
                        Task { await calendarService.fetchEvents(for: actionContext.selectedDate) }
                    } else {
                        schedulingEngine.schedulingMessage = "Failed to duplicate \"\(slot.title)\""
                    }
                }
            }
            Menu("Copy to...") {
                ForEach(copyTargetDays(), id: \.date) { target in
                    Button(target.label) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            let result = calendarService.copyEventToDay(eventId: slot.id, targetDate: target.date)
                            if result.success, let eventId = result.newEventId, let targetStart = result.targetStartTime {
                                onCopySuccess?(CopyToastInfo(title: slot.title, targetLabel: target.label, targetDate: target.date, targetStartTime: targetStart, newEventId: eventId))
                                Task { await calendarService.fetchEvents(for: actionContext.selectedDate) }
                            } else {
                                schedulingEngine.schedulingMessage = "Failed to copy \"\(slot.title)\""
                            }
                        }
                    }
                }
                Divider()
                Button("Custom...") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        copySlotId = slot.id
                        copyTargetDate = actionContext.selectedDate
                        showingCopyDatePicker = true
                    }
                }
            }
        }
    }

    private func busySlotGoalReminder(_ goals: [String], inline: Bool = false, compact: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Image(systemName: "scope")
                .font(.system(size: compact ? 8 : 9, weight: .semibold))
                .foregroundColor(busySlotGoalColor)
                .frame(width: compact ? 8 : 9, height: compact ? 8 : 9, alignment: .center)

            Text(busySlotGoalReminderText(goals))
                .font(.system(size: compact ? 8 : (sessionAwarenessService.config.harshModeReminderStyle == .prominent ? 10 : 9), weight: .semibold))
                .foregroundColor(busySlotGoalColor)
                .lineLimit(inline ? 1 : (sessionAwarenessService.config.harshModeReminderStyle == .prominent ? 2 : 1))
                .truncationMode(.tail)
        }
        .padding(.horizontal, sessionAwarenessService.config.harshModeReminderStyle == .prominent ? (compact ? 3 : 5) : 0)
        .padding(.vertical, sessionAwarenessService.config.harshModeReminderStyle == .prominent && !compact ? 2 : 0)
        .background(busySlotGoalBackground)
        .overlay(busySlotGoalBorder)
        .cornerRadius(4)
        .layoutPriority(inline ? 1 : 0)
    }

    private func busySlotGoalReminderText(_ goals: [String]) -> String {
        switch sessionAwarenessService.config.harshModeReminderStyle {
        case .compact:
            return goals.first ?? ""
        case .prominent:
            return goals.prefix(2).joined(separator: " / ")
        }
    }

    private var busySlotGoalColor: Color {
        colors.isDark ? .orange.opacity(0.95) : Color(hex: "C2410C")
    }

    @ViewBuilder
    private var busySlotGoalBackground: some View {
        if sessionAwarenessService.config.harshModeReminderStyle == .prominent {
            colors.isDark ? Color.orange.opacity(0.12) : Color(hex: "FFEDD5")
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var busySlotGoalBorder: some View {
        if sessionAwarenessService.config.harshModeReminderStyle == .prominent {
            RoundedRectangle(cornerRadius: 4)
                .stroke(colors.isDark ? Color.orange.opacity(0.22) : Color(hex: "FDBA74"), lineWidth: 1)
        }
    }
    
    // MARK: - Projected Session Block - Right Half with Tooltip
    
    private func projectedSessionBlock(for session: ScheduledSession, containerWidth: CGFloat) -> some View {
        let isBigRest = session.type == .bigRest
        let minuteHeight = hourHeight / 60
        let visualInset: CGFloat = isBigRest ? minuteHeight : 0 // 1 min inset per edge
        let yPos = calculateYPosition(for: session.startTime) + visualInset
        let height = calculateHeight(from: session.startTime, to: session.endTime) - (visualInset * 2)
        let blockHeight = max(height, 20)
        let blockWidth = (containerWidth / 2) - 24  // Extra space for scrollbar
        let xOffset = containerWidth / 2 + 8
        let isCompact = height <= compactBlockLayoutHeight
        let isDraggingSession = dragSessionId == session.id && dragMode != .none
        let edgeZone: CGFloat = min(8, blockHeight / 3)

        // Calculate center position for .position() modifier
        let centerX = xOffset + blockWidth / 2
        let centerY = yPos + blockHeight / 2

        return ZStack(alignment: .topLeading) {
            if isBigRest {
                // Hollow block with dashed border for big break
                RoundedRectangle(cornerRadius: 4)
                    .fill(session.type.color.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .foregroundColor(session.type.color.opacity(0.6))
                    )
            } else {
                // Striped background for projected sessions
                RoundedRectangle(cornerRadius: 4)
                    .fill(session.type.color.opacity(colors.isDark ? 0.55 : 0.22))
                    .overlay(
                        DiagonalStripesPattern(
                            color: session.type.color.opacity(colors.isDark ? 0.4 : 0.12),
                            stripeWidth: 5,
                            gapWidth: 5,
                            angle: 45
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
                            .foregroundColor(session.type.color)
                    )
                    .shadow(color: session.type.color.opacity(0.3), radius: 3, y: 1)
            }

            if isCompact {
                HStack(spacing: 3) {
                    Image(systemName: session.type.icon)
                        .font(.system(size: 10))
                    Text(session.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(startAndDurationString(start: session.startTime, end: session.endTime))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(colors.textPrimary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                .foregroundColor(colors.textPrimary)
                .padding(3)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .top, spacing: 3) {
                        Image(systemName: session.type.icon)
                            .font(.system(size: 11))
                            .padding(.top, 1)
                        Text(session.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundColor(colors.textPrimary)

                    Text(startAndDurationString(start: session.startTime, end: session.endTime))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(colors.textPrimary)
                }
                .padding(4)
            }
        }
        .frame(width: blockWidth, height: blockHeight)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            guard !eventsLocked, dragMode == .none else { return }
            switch phase {
            case .active(let location):
                if !isBigRest && location.y < edgeZone {
                    NSCursor.resizeUp.set()
                } else if !isBigRest && location.y > blockHeight - edgeZone {
                    NSCursor.resizeDown.set()
                } else {
                    NSCursor.openHand.set()
                }
            case .ended:
                NSCursor.arrow.set()
            }
        }
        .opacity(isDraggingSession ? 0.3 : 1.0)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    guard !eventsLocked, !dragCancelled else { return }
                    if dragMode == .none {
                        let startY = value.startLocation.y
                        if !isBigRest && startY < edgeZone {
                            dragMode = .resizeTop
                        } else if !isBigRest && startY > blockHeight - edgeZone {
                            dragMode = .resizeBottom
                        } else {
                            dragMode = .move
                            NSCursor.closedHand.push()
                        }
                        dragSessionId = session.id
                        // Auto-freeze on first drag
                        if !schedulingEngine.sessionsFrozen {
                            schedulingEngine.sessionsFrozen = true
                        }
                        // Snapshot sessions before displacement
                        preDisplacementSessions = schedulingEngine.projectedSessions
                    }

                    switch dragMode {
                    case .move:
                        let duration = session.endTime.timeIntervalSince(session.startTime)
                        let originalY = calculateYPosition(for: session.startTime)
                        let newY = originalY + value.translation.height
                        let rawDate = dateFromYOffset(newY)
                        let newStart = clampedForElasticDrag(isShiftHeld ? rawDate : snapToInterval(rawDate))
                        dragPreviewStartTime = newStart
                        dragPreviewEndTime = newStart.addingTimeInterval(duration)

                    case .resizeTop:
                        let originalY = calculateYPosition(for: session.startTime)
                        let newY = originalY + value.translation.height
                        let rawDate = dateFromYOffset(newY)
                        let newStart = clampedForElasticDrag(isShiftHeld ? rawDate : snapToInterval(rawDate))
                        let maxStart = session.endTime.addingTimeInterval(-5 * 60)
                        dragPreviewStartTime = min(newStart, maxStart)
                        dragPreviewEndTime = session.endTime

                    case .resizeBottom:
                        let originalY = calculateYPosition(for: session.endTime)
                        let newY = originalY + value.translation.height
                        let rawDate = dateFromYOffset(newY)
                        let newEnd = isShiftHeld ? rawDate : snapToInterval(rawDate)
                        let minEnd = session.startTime.addingTimeInterval(5 * 60)
                        dragPreviewStartTime = session.startTime
                        dragPreviewEndTime = max(newEnd, minEnd)

                    case .none:
                        break
                    }

                    // Displacement with throttle
                    if let previewStart = dragPreviewStartTime,
                       let previewEnd = dragPreviewEndTime {
                        let now = Date()
                        if now.timeIntervalSince(lastDragRecalcTime) >= dragRecalcInterval {
                            lastDragRecalcTime = now
                            // Restore from snapshot before each displacement pass
                            if let snapshot = preDisplacementSessions {
                                schedulingEngine.projectedSessions = snapshot
                            }
                            schedulingEngine.displaceProjectedSessions(
                                draggedSessionId: session.id,
                                draggedStart: previewStart,
                                draggedEnd: previewEnd,
                                busySlots: timelineBusySlots(for: actionContext.selectedDate),
                                earliestTime: elasticAwareEarliestTime
                            )
                        }
                    }
                    autoScrollDuringDrag()
                }
                .onEnded { _ in
                    guard !dragCancelled else { dragCancelled = false; return }
                    if dragMode == .move { NSCursor.pop() }
                    commitSessionDrag(for: session)
                }
        )
        .position(x: centerX, y: centerY)
        .onTapGesture(count: 2) {
            selectedBusySlot = nil
            selectedSession = session
        }
        .contextMenu {
            Button {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    selectedBusySlot = nil
                    selectedSession = session
                }
            } label: {
                Label("View Details", systemImage: "info.circle")
            }
            if !isBigRest {
                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        scheduleProjectedSession(session)
                    }
                } label: {
                    Label("Schedule Session", systemImage: "calendar.badge.plus")
                }
                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        scheduleProjectedSessionsUpTo(session)
                    }
                } label: {
                    Label("Schedule All Up to Here", systemImage: "calendar.badge.checkmark")
                }
                Divider()
                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        renameText = session.title
                        renamingSessionId = session.id
                        if !schedulingEngine.sessionsFrozen {
                            schedulingEngine.sessionsFrozen = true
                        }
                    }
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
            }
        }
    }
    
    // MARK: - Detail Sheet Overlay
    
    private var detailSheetOverlay: some View {
        ZStack {
            // Dimmed background - click to dismiss
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        if selectedBusySlot != nil {
                            closeBusySlotDetailSavingDirty()
                        } else {
                            selectedSession = nil
                            selectedBusySlot = nil
                            resetEditingState()
                        }
                    }
                }
            
            // Detail card
            VStack(alignment: .leading, spacing: 12) {
                if let session = currentSelectedSession {
                    sessionDetailContent(session)
                } else if let slot = currentSelectedBusySlot {
                    busySlotDetailContent(slot)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colors.panelBackground)
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            )
            .frame(maxWidth: 280)
            .transition(.scale.combined(with: .opacity))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingDetailSheet)
    }

    private func scheduleProjectedSession(_ session: ScheduledSession) {
        let result = calendarService.createSessions([session])
        if result.success > 0 {
            eventUndoManager.recordSchedule(EventUndoManager.ScheduleSnapshot(
                eventIds: result.eventIds,
                sessions: [session]
            ))
            schedulingEngine.projectedSessions.removeAll { $0.id == session.id }
            if selectedSession?.id == session.id {
                selectedSession = nil
            }
            onModeToast?("Scheduled \(session.title)")
            Task {
                await calendarService.fetchEvents(for: actionContext.selectedDate)
            }
        } else {
            onModeToast?("Failed to schedule \(session.title)")
        }
    }

    private func scheduleProjectedSessionsUpTo(_ session: ScheduledSession) {
        let sessionsToSchedule = schedulingEngine.projectedSessions.filter {
            $0.type != .bigRest && $0.startTime <= session.startTime
        }
        guard !sessionsToSchedule.isEmpty else { return }

        let result = calendarService.createSessions(sessionsToSchedule)
        if result.success > 0 {
            eventUndoManager.recordSchedule(EventUndoManager.ScheduleSnapshot(
                eventIds: result.eventIds,
                sessions: sessionsToSchedule
            ))
            let scheduledIds = Set(sessionsToSchedule.map { $0.id })
            schedulingEngine.projectedSessions.removeAll { scheduledIds.contains($0.id) }
            if let sel = selectedSession, scheduledIds.contains(sel.id) {
                selectedSession = nil
            }
            onModeToast?("Scheduled \(result.success) session\(result.success == 1 ? "" : "s")")
            Task {
                await calendarService.fetchEvents(for: actionContext.selectedDate)
            }
        } else {
            onModeToast?("Failed to schedule sessions")
        }
    }
    
    private func sessionDetailContent(_ session: ScheduledSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: session.type.icon)
                    .font(.system(size: 18))
                    .foregroundColor(session.type.color)
                    .frame(width: 18)
                Text(session.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                Spacer()
                Button {
                    selectedSession = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(colors.textSecondary)
                }
                .buttonStyle(.plain)
                .hoverEffect(brightness: 0.3)
            }

            Divider().background(colors.divider)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .frame(width: 18)
                    Text(timeRangeString(start: session.startTime, end: session.endTime))
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .frame(width: 18)
                    Text("\(session.durationMinutes) minutes")
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .frame(width: 18)
                    Text(session.calendarName)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "number.square")
                        .frame(width: 18)
                    Text(session.hashtag())
                }
            }
            .font(.system(size: 14))
            .foregroundColor(colors.textSecondary)
        }
    }
    
    private func busySlotDetailContent(_ slot: BusyTimeSlot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Image(systemName: "calendar")
                        .font(.system(size: 18))
                        .foregroundColor(slot.calendarColor)
                        .frame(width: 18)

                    flowFlexibilityIndicator(for: slot, size: 14)
                        .padding(.top, 2)
                
                // Inline editable title
                if isEditingTitle {
                    TextField("Event title", text: $editingTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                        .focused($focusedField, equals: .title)
                        .onSubmit {
                            saveTitle(for: slot)
                        }
                        .onKeyPress(.escape) {
                            cancelTitleEdit()
                            return .handled
                        }
                } else {
                    Text(slot.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            originalTitle = slot.title
                            editingTitle = slot.title
                            isEditingTitle = true
                            focusedField = .title
                        }
                }
                
                Spacer()
                Button {
                    closeBusySlotDetailSavingDirty()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(colors.textSecondary)
                }
                .buttonStyle(.plain)
                .hoverEffect(brightness: 0.3)
            }
            
            Divider().background(colors.divider)
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .frame(width: 16)
                    Text(timeRangeString(start: slot.startTime, end: slot.endTime))
                }
                .help("To change time, use Calendar app")
                
                HStack(spacing: 8) {
                    Image(systemName: "tray")
                        .frame(width: 16)
                    Text(slot.calendarName)
                }
                .help("To change calendar, use Calendar app")

                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.and.right")
                        .frame(width: 16)
                    Toggle("Flexible", isOn: Binding(
                        get: { slot.isFlowFlexible },
                        set: { setBusySlotFlexible(slot, isFlexible: $0) }
                    ))
                    .toggleStyle(.checkbox)
                }
                .contentShape(Rectangle())
                .help(flexibilityHelpText(for: slot))

                // Notes section with inline editing
                VStack(alignment: .leading, spacing: 4) {
                    Divider().background(colors.divider)
                    
                    if isEditingNotes {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes:")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(colors.textSecondary)
                            TextEditor(text: $editingNotes)
                                .font(.system(size: 12))
                                .foregroundColor(colors.textPrimary)
                                .scrollContentBackground(.hidden)
                                .background(colors.subtleBackground)
                                .cornerRadius(4)
                                .frame(minHeight: 60, maxHeight: 100)
                                .focused($focusedField, equals: .notes)
                                .onKeyPress(.escape) {
                                    cancelNotesEdit()
                                    return .handled
                                }
                                .onKeyPress(phases: .down) { press in
                                    // ENTER without modifiers = save
                                    if press.key == .return && press.modifiers.isEmpty {
                                        saveNotes(for: slot)
                                        return .handled
                                    }
                                    // SHIFT+ENTER = insert newline (let through)
                                    if press.key == .return && press.modifiers.contains(.shift) {
                                        return .ignored
                                    }
                                    return .ignored
                                }
                        }
                    } else if let displayNotes = editableNotes(from: slot.notes), !displayNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes:")
                                .font(.system(size: 12, weight: .bold))
                            Text(displayNotes)
                                .font(.system(size: 12))
                                .foregroundColor(colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let stripped = editableNotes(from: slot.notes) ?? ""
                            originalNotes = stripped
                            editingNotes = stripped
                            isEditingNotes = true
                            focusedField = .notes
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 11))
                            Text("Add note")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            originalNotes = ""
                            editingNotes = ""
                            isEditingNotes = true
                            focusedField = .notes
                        }
                    }
                }
                
                // Feedback rating picker
                if slot.endTime < Date() && sessionAwarenessService.config.enabled && sessionAwarenessService.config.productivityEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        Divider().background(colors.divider)
                        feedbackPicker(for: slot)
                        if shouldShowAlignmentPicker(for: slot) {
                            alignmentPicker(for: slot)
                        }
                    }
                }

                // URL section with inline editing
                VStack(alignment: .leading, spacing: 4) {
                    Divider().background(colors.divider)

                    if isEditingURL {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("URL:")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(colors.textSecondary)
                            TextField("https://example.com", text: $editingURL)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .foregroundColor(colors.textSecondary)
                                .padding(6)
                                .background(colors.subtleBackground)
                                .cornerRadius(4)
                                .focused($focusedField, equals: .url)
                                .onSubmit {
                                    saveURL(for: slot)
                                }
                                .onKeyPress(.escape) {
                                    cancelURLEdit()
                                    return .handled
                                }
                        }
                    } else if let url = slot.url {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("URL:")
                                .font(.system(size: 12, weight: .bold))
                            Link(url.absoluteString, destination: url)
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "3B82F6"))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            originalURL = url.absoluteString
                            editingURL = url.absoluteString
                            isEditingURL = true
                            focusedField = .url
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 11))
                            Text("Add URL")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            originalURL = ""
                            editingURL = ""
                            isEditingURL = true
                            focusedField = .url
                        }
                    }
                }
            }
            .font(.system(size: 14))
            .foregroundColor(colors.textSecondary)
        }
        .onChange(of: focusedField) { oldValue, newValue in
            // Don't auto-save if we're canceling
            guard !isCanceling else { return }
            
            // Auto-save when focus leaves a field
            if oldValue == .title && newValue != .title && isEditingTitle {
                saveTitle(for: slot)
            }
            if oldValue == .notes && newValue != .notes && isEditingNotes {
                saveNotes(for: slot)
            }
            if oldValue == .url && newValue != .url && isEditingURL {
                saveURL(for: slot)
            }
        }
        .onAppear {
            // Auto-focus on field when detail view opens
            if let field = autoFocusField {
                switch field {
                case .title:
                    originalTitle = slot.title
                    editingTitle = slot.title
                    isEditingTitle = true
                    focusedField = .title
                case .notes:
                    let stripped = editableNotes(from: slot.notes) ?? ""
                    originalNotes = stripped
                    editingNotes = stripped
                    isEditingNotes = true
                    focusedField = .notes
                case .url:
                    originalURL = slot.url?.absoluteString ?? ""
                    editingURL = slot.url?.absoluteString ?? ""
                    isEditingURL = true
                    focusedField = .url
                }
                // Clear auto-focus after applying it
                autoFocusField = nil
            }
        }
    }

    private func editableNotes(from notes: String?) -> String? {
        FlowFlexibilityNotes.strippingTags(from: SessionAlignment.stripAlignmentTags(SessionRating.stripFeedbackTags(notes)))
    }

    private func reviewTags(from notes: String?) -> String {
        var tags: [String] = []
        if let rating = SessionRating.fromNotes(notes) {
            tags.append(rating.tag)
        }
        if let alignment = SessionAlignment.fromNotes(notes) {
            tags.append(alignment.tag)
        }
        return tags.isEmpty ? "" : " " + tags.joined(separator: " ")
    }

    private func setBusySlotFlexible(_ slot: BusyTimeSlot, isFlexible: Bool) {
        guard calendarService.setEventFlexible(eventId: slot.id, isFlexible: isFlexible) else {
            onModeToast?("Failed to update flexibility")
            return
        }

        let updatedNotes = FlowFlexibilityNotes.applyingFlexible(isFlexible, to: slot.notes)
        optimisticallyUpdateSlotNotes(id: slot.id, notes: updatedNotes)
        if selectedBusySlot?.id == slot.id,
           let updated = timelineBusySlots(for: actionContext.selectedDate).first(where: { $0.id == slot.id }) {
            selectedBusySlot = updated
        }
        onModeToast?(isFlexible ? "Marked flexible" : "Marked fixed")
        Task { await calendarService.fetchEvents(for: actionContext.selectedDate) }
    }

    private func flexibilityHelpText(for slot: BusyTimeSlot) -> String {
        if slot.isSessionFlowOwned {
            return "Flexible SessionFlow events can move when you rearrange the timeline. Turn this off to pin the event in place so elastic edits work around it."
        }
        return "Flexible external events can be moved by SessionFlow during elastic timeline editing. Leave this off for real-world commitments that should stay fixed."
    }

    @ViewBuilder
    private func flowFlexibilityIndicator(for slot: BusyTimeSlot, size: CGFloat) -> some View {
        if slot.isFlowFlexible && !slot.isSessionFlowOwned {
            TimelineSpringIcon()
                .frame(width: size, height: size)
                .foregroundColor(colors.textSecondary)
        } else if slot.isSessionFlowOwned && !slot.isFlowFlexible {
            Image(systemName: "pin.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(colors.textSecondary)
                .frame(width: size, height: size)
        }
    }
    
    // MARK: - Copy Target Days

    private struct CopyTarget: Hashable {
        let label: String
        let date: Date
        func hash(into hasher: inout Hasher) { hasher.combine(label) }
        static func == (lhs: CopyTarget, rhs: CopyTarget) -> Bool { lhs.label == rhs.label }
    }

    private func copyTargetDays() -> [CopyTarget] {
        let cal = Calendar.current
        let today = Date()
        var targets: [CopyTarget] = []
        for offset in 0...6 {
            let date = cal.date(byAdding: .day, value: offset, to: today) ?? today
            if cal.isDate(date, inSameDayAs: selectedDate) { continue }
            let label: String
            switch offset {
            case 0: label = "Today"
            case 1: label = "Tomorrow"
            default:
                let formatter = DateFormatter()
                formatter.dateFormat = "EEE, MMM d"
                label = formatter.string(from: date)
            }
            targets.append(CopyTarget(label: label, date: date))
        }
        return targets
    }

    private func deleteBusySlot(_ slot: BusyTimeSlot) {
        guard !isElasticEditing else {
            onModeToast?("Save or cancel elastic edits first")
            return
        }
        let snapshot = EventDeleteSnapshot(
            eventId: slot.id,
            title: slot.title,
            notes: slot.notes,
            url: slot.url,
            startDate: slot.startTime,
            endDate: slot.endTime,
            calendarIdentifier: slot.calendarIdentifier,
            calendarName: slot.calendarName
        )
        if calendarService.deleteEvent(identifier: slot.id) {
            eventUndoManager.recordDelete(snapshot)
            dismissTransientInteractionState()
            Task { await calendarService.fetchEvents(for: actionContext.selectedDate) }
        }
    }

    /// Atomically deletes multiple slots — one undo step for the whole batch.
    private func deleteSelectedSlots(_ slots: [BusyTimeSlot]) {
        guard !isElasticEditing else {
            onModeToast?("Save or cancel elastic edits first")
            return
        }
        guard !slots.isEmpty else { return }
        var snapshots: [EventDeleteSnapshot] = []
        for slot in slots {
            let snapshot = EventDeleteSnapshot(
                eventId: slot.id, title: slot.title, notes: slot.notes, url: slot.url,
                startDate: slot.startTime, endDate: slot.endTime,
                calendarIdentifier: slot.calendarIdentifier, calendarName: slot.calendarName
            )
            if calendarService.deleteEvent(identifier: slot.id) {
                snapshots.append(snapshot)
            }
        }
        guard !snapshots.isEmpty else { return }
        eventUndoManager.recordDeleteBatch(snapshots)
        dismissTransientInteractionState()
        Task { await calendarService.fetchEvents(for: actionContext.selectedDate) }
    }

    // MARK: - Event Creation from Timeline

    /// Transparent left-half layer that captures double-click on empty space.
    private func eventCreationBackgroundLayer(containerWidth: CGFloat) -> some View {
        let leftHalfWidth = max((containerWidth / 2), 10)
        return Color.clear
            .frame(width: leftHalfWidth, height: CGFloat(visibleHours.count) * hourHeight + 40)
            .contentShape(Rectangle())
            .position(x: leftHalfWidth / 2, y: (CGFloat(visibleHours.count) * hourHeight + 40) / 2)
            .onTapGesture(count: 2) { location in
                let clickedTime = snapToInterval(dateFromYOffset(location.y))
                beginEventCreation(at: clickedTime)
            }
            .onTapGesture(count: 1) {
                if !selectedBusySlotIds.isEmpty {
                    selectedBusySlotIds.removeAll()
                }
            }
    }

    /// Transparent right-half layer that deselects events on single click.
    private func rightHalfDeselectLayer(containerWidth: CGFloat) -> some View {
        let halfWidth = max((containerWidth / 2), 10)
        return Color.clear
            .frame(width: halfWidth, height: CGFloat(visibleHours.count) * hourHeight + 40)
            .contentShape(Rectangle())
            .position(x: containerWidth - halfWidth / 2, y: (CGFloat(visibleHours.count) * hourHeight + 40) / 2)
            .onTapGesture {
                if !selectedBusySlotIds.isEmpty {
                    selectedBusySlotIds.removeAll()
                }
            }
            .allowsHitTesting(!selectedBusySlotIds.isEmpty)
    }

    private func beginEventCreation(at time: Date) {
        guard !eventsLocked else {
            onModeToast?("Events locked")
            return
        }
        guard !isElasticEditing else {
            onModeToast?("Save or cancel elastic edits first")
            return
        }
        // Close any open detail sheet
        selectedSession = nil
        selectedBusySlot = nil
        resetEditingState()

        eventCreationCoordinator.onCommit = { title, start, end, calendar, isFlexible in
            createEventFromTimeline(title: title, startDate: start, endDate: end, calendar: calendar, isFlexible: isFlexible)
        }
        eventCreationCoordinator.durationMinutes = 30
        eventCreationCoordinator.draftTitle = ""
        eventCreationCoordinator.calendarColor = .blue
        eventCreationCoordinator.draftIsFlexible = false

        withAnimation(.easeOut(duration: 0.15)) {
            eventCreationCoordinator.startTime = time
        }
    }

    private func createEventFromTimeline(title: String, startDate: Date, endDate: Date, calendar: CalendarDescriptor, isFlexible: Bool) {
        let notes = FlowFlexibilityNotes.applyingFlexible(isFlexible, to: nil)
        guard let eventId = calendarService.createEventReturningId(
            title: title,
            startDate: startDate,
            endDate: endDate,
            calendar: calendar,
            notes: notes
        ) else {
            onModeToast?("Failed to create event")
            return
        }

        // Record in undo stack
        let snapshot = EventDeleteSnapshot(
            eventId: eventId,
            title: title,
            notes: notes,
            url: nil,
            startDate: startDate,
            endDate: endDate,
            calendarIdentifier: calendar.identifier,
            calendarName: calendar.name
        )
        eventUndoManager.recordCreate(snapshot)

        // Record in recents
        let durationMinutes = Int(endDate.timeIntervalSince(startDate) / 60)
        recentEventsStore.record(
            title: title,
            durationMinutes: durationMinutes,
            calendarName: calendar.name,
            calendarIdentifier: calendar.identifier,
            eventId: eventId,
            isFlexible: isFlexible
        )

        // Close popover and refresh
        withAnimation(.easeOut(duration: 0.15)) {
            eventCreationCoordinator.dismiss()
        }
        onModeToast?("Created \"\(title)\"")
        Task { await calendarService.fetchEvents(for: actionContext.selectedDate) }
    }

    // MARK: - Position Calculations

    private func calculateYPosition(for date: Date) -> CGFloat {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: selectedDate)
        let secondsSinceStart = date.timeIntervalSince(dayStart)
        let hours = secondsSinceStart / 3600

        let finalHours = hours - (schedulingEngine.hideNightHours ? CGFloat(schedulingEngine.dayStartHour) : 0)
        return finalHours * hourHeight
    }

    /// Inverse of calculateYPosition — converts a Y offset back to a Date.
    private func dateFromYOffset(_ yPosition: CGFloat) -> Date {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: selectedDate)
        let offsetHours = schedulingEngine.hideNightHours ? CGFloat(schedulingEngine.dayStartHour) : 0
        let hours = yPosition / hourHeight + offsetHours
        return dayStart.addingTimeInterval(Double(hours) * 3600)
    }

    private func snapToInterval(_ date: Date) -> Date {
        TimeSnapping.snapToNearest(date, intervalMinutes: 5)
    }

    private func calculateHeight(from start: Date, to end: Date) -> CGFloat {
        let duration = end.timeIntervalSince(start)
        let hours = duration / 3600
        return CGFloat(hours) * hourHeight
    }
    
    private func timeRangeString(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private func startAndDurationString(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let durationMinutes = Int(end.timeIntervalSince(start) / 60)
        return "\(formatter.string(from: start)) - \(formatter.string(from: end)) \u{2022} \(durationMinutes) min"
    }
    
    // MARK: - Feedback Badge

    @ViewBuilder
    private func feedbackBadge(for slot: BusyTimeSlot) -> some View {
        let rating = SessionRating.fromNotes(slot.notes)
        let alignment = SessionAlignment.fromNotes(slot.notes)
        let isShowingPopover = Binding(
            get: { feedbackPopoverEventId == slot.id },
            set: { if !$0 { feedbackPopoverEventId = nil } }
        )

        Button {
            feedbackPopoverEventId = (feedbackPopoverEventId == slot.id) ? nil : slot.id
        } label: {
            ZStack(alignment: .bottomLeading) {
                if let rating = rating {
                    feedbackBadgeIcon(for: rating)
                } else {
                    // Empty feedback target needs a real edge in dark mode, otherwise it blends into session borders.
                    Circle()
                        .fill(colors.isDark ? Color(hex: "0F172A").opacity(0.95) : Color.white.opacity(0.82))
                        .frame(width: colors.isDark ? 16 : 14, height: colors.isDark ? 16 : 14)
                        .overlay(
                            Circle()
                                .stroke(colors.isDark ? Color.white.opacity(0.9) : Color.white.opacity(0.65),
                                        lineWidth: colors.isDark ? 1.3 : 1)
                        )
                        .shadow(color: colors.isDark ? Color.black.opacity(0.5) : .clear,
                                radius: 1.5, x: 0, y: 0)
                }

                if let alignment = alignment {
                    alignmentBadgeDot(for: alignment)
                        .offset(x: -5, y: 5)
                }
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(brightness: 0.2)
        .popover(isPresented: isShowingPopover, arrowEdge: .trailing) {
            feedbackPopoverContent(for: slot, existingRating: rating, existingAlignment: alignment)
        }
    }

    private func feedbackBadgeIcon(for rating: SessionRating) -> some View {
        let (color, icon, darkIconColor): (Color, String, Color) = {
            switch rating {
            case .rocket: return (Color(hex: "F97316"), "flame.fill", .white)
            case .completed: return (Color(hex: "22C55E"), "checkmark", .white)
            case .partial:
                return (colors.isDark ? Color(hex: "FACC15") : Color(hex: "92400E"),
                        "circle.lefthalf.filled",
                        Color(hex: "422006"))
            case .procrastinated: return (Color(hex: "EF4444"), "iphone", .white)
            case .skipped:
                return (colors.isDark ? Color(hex: "94A3B8") : Color(hex: "64748B"),
                        "xmark",
                        .white)
            }
        }()
        let badgeSize: CGFloat = colors.isDark ? 16 : 14
        let iconSize: CGFloat = colors.isDark ? 8 : 7

        return Circle()
            .fill(colors.isDark ? color : Color.white.opacity(0.92))
            .frame(width: badgeSize, height: badgeSize)
            .overlay(
                Circle()
                    .stroke(colors.isDark ? Color.white.opacity(0.95) : Color.white.opacity(0.7),
                            lineWidth: colors.isDark ? 1.2 : 0.8)
            )
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundColor(colors.isDark ? darkIconColor : color)
            )
            .shadow(color: colors.isDark ? Color.black.opacity(0.55) : .clear,
                    radius: 1.5, x: 0, y: 0)
            .help(rating.label)
    }

    private func alignmentBadgeDot(for alignment: SessionAlignment) -> some View {
        Circle()
            .fill(alignmentColor(alignment))
            .frame(width: 9, height: 9)
            .overlay(
                Circle()
                    .stroke(colors.isDark ? Color.white.opacity(0.9) : Color.white.opacity(0.85), lineWidth: 0.8)
            )
            .shadow(color: colors.isDark ? Color.black.opacity(0.5) : .clear, radius: 1, x: 0, y: 0)
            .help(alignment.label)
    }

    private func feedbackPopoverContent(for slot: BusyTimeSlot, existingRating: SessionRating?, existingAlignment: SessionAlignment?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existingRating != nil ? "Update Focus" : "How focused was this session?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            Text("Focus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(SessionRating.allCases, id: \.rawValue) { rating in
                    Button {
                        updatePopoverFeedback(for: slot, rating: rating)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: rating.icon)
                                .font(.system(size: 12, weight: .medium))
                            Text(rating.shortLabel)
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(existingRating == rating
                                    ? ratingColor(rating).opacity(0.35)
                                    : Color.clear)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(ratingColor(rating).opacity(existingRating == rating ? 0.8 : 0.3), lineWidth: existingRating == rating ? 2 : 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(brightness: 0.15)
                    .foregroundColor(ratingColor(rating))
                }
            }

            Divider()

            Text("Alignment")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                ForEach(SessionAlignment.allCases, id: \.rawValue) { alignment in
                    Button {
                        updatePopoverFeedback(for: slot, alignment: alignment)
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: alignment.icon)
                                .font(.system(size: 11, weight: .medium))
                            Text(alignment.shortLabel)
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(existingAlignment == alignment ? alignmentColor(alignment).opacity(0.28) : Color.clear)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(alignmentColor(alignment).opacity(existingAlignment == alignment ? 0.75 : 0.25), lineWidth: existingAlignment == alignment ? 1.5 : 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(brightness: 0.15)
                    .foregroundColor(alignmentColor(alignment))
                    .help("\(alignment.label): \(alignment.description)")
                }
            }
        }
        .padding(14)
        .frame(minWidth: 380)
    }

    private func updatePopoverFeedback(for slot: BusyTimeSlot, rating: SessionRating) {
        let currentNotes = currentReviewNotes(for: slot)
        let oldRating = SessionRating.fromNotes(currentNotes)
        let newRating: SessionRating? = oldRating == rating ? nil : rating
        let updatedNotes: String?

        if let newRating {
            guard calendarService.setFeedbackTag(eventId: slot.id, rating: newRating) else { return }
            updatedNotes = newRating.applyTo(notes: currentNotes)
        } else {
            guard calendarService.clearFeedbackTag(eventId: slot.id) else { return }
            updatedNotes = SessionRating.stripFeedbackTags(currentNotes)
        }

        eventUndoManager.recordFeedback(EventUndoManager.FeedbackChange(
            eventId: slot.id,
            oldRating: oldRating,
            newRating: newRating
        ))
        finishPopoverFeedbackUpdate(for: slot, notes: updatedNotes)
    }

    private func updatePopoverFeedback(for slot: BusyTimeSlot, alignment: SessionAlignment) {
        let currentNotes = currentReviewNotes(for: slot)
        let oldAlignment = SessionAlignment.fromNotes(currentNotes)
        let newAlignment: SessionAlignment? = oldAlignment == alignment ? nil : alignment
        let updatedNotes: String?

        if let newAlignment {
            guard calendarService.setAlignmentTag(eventId: slot.id, alignment: newAlignment) else { return }
            updatedNotes = newAlignment.applyTo(notes: currentNotes)
        } else {
            guard calendarService.clearAlignmentTag(eventId: slot.id) else { return }
            updatedNotes = SessionAlignment.stripAlignmentTags(currentNotes)
        }

        eventUndoManager.recordAlignment(EventUndoManager.AlignmentChange(
            eventId: slot.id,
            oldAlignment: oldAlignment,
            newAlignment: newAlignment
        ))
        finishPopoverFeedbackUpdate(for: slot, notes: updatedNotes)
    }

    private func currentReviewNotes(for slot: BusyTimeSlot) -> String? {
        timelineBusySlots(for: actionContext.selectedDate).first(where: { $0.id == slot.id })?.notes
            ?? calendarService.busySlots.first(where: { $0.id == slot.id })?.notes
            ?? slot.notes
    }

    private func finishPopoverFeedbackUpdate(for slot: BusyTimeSlot, notes: String?) {
        optimisticallyUpdateSlotNotes(id: slot.id, notes: notes)

        let rating = SessionRating.fromNotes(notes)
        let alignment = SessionAlignment.fromNotes(notes)
        feedbackPopoverEventId = rating != nil && alignment != nil ? nil : slot.id

        Task {
            await calendarService.fetchEvents(for: actionContext.selectedDate)
            if let updated = calendarService.busySlots.first(where: { $0.id == slot.id }),
               selectedBusySlot?.id == slot.id {
                selectedBusySlot = updated
            }
        }
    }

    private func ratingColor(_ rating: SessionRating) -> Color {
        awarenessRatingColor(rating, isDark: colors.isDark)
    }

    private func alignmentColor(_ alignment: SessionAlignment) -> Color {
        awarenessAlignmentColor(alignment, isDark: colors.isDark)
    }

    // MARK: - Feedback Picker (in event details)

    private func feedbackPicker(for slot: BusyTimeSlot) -> some View {
        let currentRating = SessionRating.fromNotes(slot.notes)

        return HStack(spacing: 5) {
            Text("Focus:")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(colors.textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 2)

            // "Not set" button
            Button {
                clearFeedbackTag(for: slot)
            } label: {
                Text("–")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(currentRating == nil ? colors.textSecondary : colors.textMuted)
                    .frame(width: 24, height: 22)
                    .background(currentRating == nil ? colors.divider : Color.clear)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(currentRating == nil ? colors.borderStrong : colors.divider, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: 0.2)
            .help("Not set")

            ForEach(SessionRating.allCases, id: \.rawValue) { rating in
                Button {
                    let oldRating = currentRating
                    calendarService.setFeedbackTag(eventId: slot.id, rating: rating)
                    eventUndoManager.recordFeedback(EventUndoManager.FeedbackChange(
                        eventId: slot.id, oldRating: oldRating, newRating: rating))
                    Task {
                        await calendarService.fetchEvents(for: actionContext.selectedDate)
                        if let updated = calendarService.busySlots.first(where: { $0.id == slot.id }) {
                            selectedBusySlot = updated
                        }
                    }
                } label: {
                    Image(systemName: rating.icon)
                        .font(.system(size: 12))
                        .foregroundColor(ratingColor(rating).opacity(currentRating == rating ? 1.0 : 0.5))
                        .frame(width: 24, height: 22)
                        .background(currentRating == rating ? ratingColor(rating).opacity(0.25) : Color.clear)
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(ratingColor(rating).opacity(currentRating == rating ? 0.6 : 0.15), lineWidth: currentRating == rating ? 1.5 : 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect(brightness: 0.2)
                .help(rating.label)
            }
        }
    }

    private func clearFeedbackTag(for slot: BusyTimeSlot) {
        let oldRating = SessionRating.fromNotes(slot.notes)
        calendarService.clearFeedbackTag(eventId: slot.id)
        eventUndoManager.recordFeedback(EventUndoManager.FeedbackChange(
            eventId: slot.id, oldRating: oldRating, newRating: nil))
        Task {
            await calendarService.fetchEvents(for: actionContext.selectedDate)
            if let updated = calendarService.busySlots.first(where: { $0.id == slot.id }) {
                selectedBusySlot = updated
            }
        }
    }

    private func shouldShowAlignmentPicker(for slot: BusyTimeSlot) -> Bool {
        FlowFlexibilityNotes.countsTowardAlignmentScore(
            slot.notes,
            alignment: SessionAlignment.fromNotes(slot.notes)
        )
    }

    private func alignmentPicker(for slot: BusyTimeSlot) -> some View {
        let currentAlignment = SessionAlignment.fromNotes(slot.notes)

        return HStack(spacing: 5) {
            Text("Alignment:")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(colors.textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 2)

            Button {
                clearAlignmentTag(for: slot)
            } label: {
                Text("–")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(currentAlignment == nil ? colors.textSecondary : colors.textMuted)
                    .frame(width: 24, height: 22)
                    .background(currentAlignment == nil ? colors.divider : Color.clear)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(currentAlignment == nil ? colors.borderStrong : colors.divider, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: 0.2)
            .help("Not set")

            ForEach(SessionAlignment.allCases, id: \.rawValue) { alignment in
                Button {
                    let oldAlignment = currentAlignment
                    calendarService.setAlignmentTag(eventId: slot.id, alignment: alignment)
                    eventUndoManager.recordAlignment(EventUndoManager.AlignmentChange(
                        eventId: slot.id, oldAlignment: oldAlignment, newAlignment: alignment))
                    Task {
                        await calendarService.fetchEvents(for: actionContext.selectedDate)
                        if let updated = calendarService.busySlots.first(where: { $0.id == slot.id }) {
                            selectedBusySlot = updated
                        }
                    }
                } label: {
                    Image(systemName: alignment.icon)
                        .font(.system(size: 11))
                        .foregroundColor(alignmentColor(alignment).opacity(currentAlignment == alignment ? 1.0 : 0.5))
                        .frame(width: 24, height: 22)
                        .background(currentAlignment == alignment ? alignmentColor(alignment).opacity(0.22) : Color.clear)
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(alignmentColor(alignment).opacity(currentAlignment == alignment ? 0.6 : 0.15), lineWidth: currentAlignment == alignment ? 1.5 : 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect(brightness: 0.2)
                .help("\(alignment.label): \(alignment.description)")
            }
        }
    }

    private func clearAlignmentTag(for slot: BusyTimeSlot) {
        let oldAlignment = SessionAlignment.fromNotes(slot.notes)
        calendarService.clearAlignmentTag(eventId: slot.id)
        eventUndoManager.recordAlignment(EventUndoManager.AlignmentChange(
            eventId: slot.id, oldAlignment: oldAlignment, newAlignment: nil))
        Task {
            await calendarService.fetchEvents(for: actionContext.selectedDate)
            if let updated = calendarService.busySlots.first(where: { $0.id == slot.id }) {
                selectedBusySlot = updated
            }
        }
    }

    // MARK: - Inline Editing Helpers
    
    private func saveTitle(for slot: BusyTimeSlot) {
        // Validate title is not empty
        guard !editingTitle.isEmpty else {
            isEditingTitle = false
            editingTitle = ""
            originalTitle = ""
            return
        }
        
        // Only save if actually changed
        guard editingTitle != originalTitle else {
            isEditingTitle = false
            editingTitle = ""
            originalTitle = ""
            return
        }
        
        let success = calendarService.updateEvent(
            eventId: slot.id,
            title: editingTitle,
            notes: nil,
            url: nil
        )

        if success {
            eventUndoManager.recordContent(EventUndoManager.EventContentChange(
                eventId: slot.id,
                change: .title(old: originalTitle, new: editingTitle),
                description: "Rename Event"
            ))
            Task {
                await calendarService.fetchEvents(for: actionContext.selectedDate)
                // Update the selected slot with fresh data
                if let updatedSlot = calendarService.busySlots.first(where: { $0.id == slot.id }) {
                    selectedBusySlot = updatedSlot
                }
                isEditingTitle = false
                editingTitle = ""
                originalTitle = ""
            }
        } else {
            // On failure, exit edit mode but keep the popup open
            isEditingTitle = false
            editingTitle = ""
            originalTitle = ""
        }
    }

    private func saveNotes(for slot: BusyTimeSlot) {
        // Normalize empty strings to nil for comparison
        let normalizedNew = editingNotes.isEmpty ? nil : editingNotes
        let normalizedOriginal = originalNotes.isEmpty ? nil : originalNotes

        // Only save if actually changed
        guard normalizedNew != normalizedOriginal else {
            isEditingNotes = false
            editingNotes = ""
            originalNotes = ""
            return
        }

        // Preserve review tags from the original notes (session type tags are user-editable).
        let finalNotes = (normalizedNew ?? "") + reviewTags(from: slot.notes)
        let trimmedNotes: String? = finalNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : finalNotes
        let notesToSave = FlowFlexibilityNotes.applyingFlexible(slot.isFlowFlexible, to: trimmedNotes)

        let success = calendarService.updateEvent(
            eventId: slot.id,
            title: nil,
            notes: notesToSave,
            url: nil
        )

        if success {
            let oldNotesForUndo = FlowFlexibilityNotes.applyingFlexible(slot.isFlowFlexible, to: normalizedOriginal)
            eventUndoManager.recordContent(EventUndoManager.EventContentChange(
                eventId: slot.id,
                change: .notes(old: oldNotesForUndo, new: notesToSave),
                description: "Edit Notes"
            ))
            Task {
                await calendarService.fetchEvents(for: actionContext.selectedDate)
                // Update the selected slot with fresh data
                if let updatedSlot = calendarService.busySlots.first(where: { $0.id == slot.id }) {
                    selectedBusySlot = updatedSlot
                }
                isEditingNotes = false
                editingNotes = ""
                originalNotes = ""
            }
        } else {
            // On failure, exit edit mode but keep the popup open
            isEditingNotes = false
            editingNotes = ""
            originalNotes = ""
        }
    }
    
    private func saveURL(for slot: BusyTimeSlot) {
        // Normalize and prepare URL
        let urlToSave: URL?
        if editingURL.isEmpty {
            urlToSave = nil
        } else {
            // Try to create URL, add https:// if no scheme
            var urlString = editingURL.trimmingCharacters(in: .whitespaces)
            if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
                urlString = "https://" + urlString
            }
            // URL encode the string to handle spaces and special characters
            if let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                urlToSave = URL(string: encoded)
            } else {
                urlToSave = URL(string: urlString)
            }
        }
        
        // Only save if actually changed
        let originalURLString = originalURL.isEmpty ? nil : originalURL
        let newURLString = editingURL.isEmpty ? nil : editingURL.trimmingCharacters(in: .whitespaces)
        
        guard newURLString != originalURLString else {
            isEditingURL = false
            editingURL = ""
            originalURL = ""
            return
        }
        
        let success = calendarService.updateEvent(
            eventId: slot.id,
            title: nil,
            notes: nil,
            url: urlToSave,
            updateURL: true
        )

        if success {
            let oldURL: URL? = originalURL.isEmpty ? nil : URL(string: originalURL)
            eventUndoManager.recordContent(EventUndoManager.EventContentChange(
                eventId: slot.id,
                change: .url(old: oldURL, new: urlToSave),
                description: "Edit URL"
            ))
            Task {
                await calendarService.fetchEvents(for: actionContext.selectedDate)
                // Update the selected slot with fresh data
                if let updatedSlot = calendarService.busySlots.first(where: { $0.id == slot.id }) {
                    selectedBusySlot = updatedSlot
                }
                isEditingURL = false
                editingURL = ""
                originalURL = ""
            }
        } else {
            // On failure, exit edit mode but keep the popup open
            isEditingURL = false
            editingURL = ""
            originalURL = ""
        }
    }
    
    private func resetEditingState() {
        isEditingTitle = false
        isEditingNotes = false
        isEditingURL = false
        editingTitle = ""
        editingNotes = ""
        editingURL = ""
        originalTitle = ""
        originalNotes = ""
        originalURL = ""
        isCanceling = false
        focusedField = nil
        autoFocusField = nil
    }

    private func dismissTransientInteractionState() {
        if dragMode != .none {
            resetDragState()
        }
        selectedSession = nil
        selectedBusySlot = nil
        selectedBusySlotIds.removeAll()
        feedbackPopoverEventId = nil
        showingCopyDatePicker = false
        copySlotId = nil
        renamingSessionId = nil
        showingLegendPopover = false
        if eventCreationCoordinator.isActive {
            eventCreationCoordinator.dismiss()
        }
        resetEditingState()
    }

    /// Closes the busy-slot detail popover, auto-saving any uncommitted edits
    /// (rename / notes / URL). Mirrors save{Title,Notes,URL} logic but bypasses
    /// the popover re-selection that those helpers do, since we're closing.
    /// ESC dismissals must call resetEditingState() directly (cancel semantics).
    private func closeBusySlotDetailSavingDirty() {
        guard let slot = selectedBusySlot else {
            selectedSession = nil
            selectedBusySlot = nil
            resetEditingState()
            return
        }

        // Suppress focus-loss onChange auto-save; we're saving synchronously here.
        isCanceling = true
        var didChange = false

        // Title
        if isEditingTitle, !editingTitle.isEmpty, editingTitle != originalTitle {
            if calendarService.updateEvent(eventId: slot.id, title: editingTitle, notes: nil, url: nil) {
                eventUndoManager.recordContent(EventUndoManager.EventContentChange(
                    eventId: slot.id,
                    change: .title(old: originalTitle, new: editingTitle),
                    description: "Rename Event"
                ))
                didChange = true
            }
        }

        // Notes
        if isEditingNotes {
            let normalizedNew: String? = editingNotes.isEmpty ? nil : editingNotes
            let normalizedOriginal: String? = originalNotes.isEmpty ? nil : originalNotes
            if normalizedNew != normalizedOriginal {
                let finalNotes = (normalizedNew ?? "") + reviewTags(from: slot.notes)
                let trimmedNotes: String? = finalNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : finalNotes
                let notesToSave = FlowFlexibilityNotes.applyingFlexible(slot.isFlowFlexible, to: trimmedNotes)
                if calendarService.updateEvent(eventId: slot.id, title: nil, notes: notesToSave, url: nil) {
                    let oldNotesForUndo = FlowFlexibilityNotes.applyingFlexible(slot.isFlowFlexible, to: normalizedOriginal)
                    eventUndoManager.recordContent(EventUndoManager.EventContentChange(
                        eventId: slot.id,
                        change: .notes(old: oldNotesForUndo, new: notesToSave),
                        description: "Edit Notes"
                    ))
                    didChange = true
                }
            }
        }

        // URL
        if isEditingURL {
            let originalURLString = originalURL.isEmpty ? nil : originalURL
            let newURLString = editingURL.isEmpty ? nil : editingURL.trimmingCharacters(in: .whitespaces)
            if newURLString != originalURLString {
                let urlToSave: URL?
                if editingURL.isEmpty {
                    urlToSave = nil
                } else {
                    var urlString = editingURL.trimmingCharacters(in: .whitespaces)
                    if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
                        urlString = "https://" + urlString
                    }
                    if let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                        urlToSave = URL(string: encoded)
                    } else {
                        urlToSave = URL(string: urlString)
                    }
                }
                if calendarService.updateEvent(eventId: slot.id, title: nil, notes: nil, url: urlToSave, updateURL: true) {
                    let oldURL: URL? = originalURLString.flatMap { URL(string: $0) }
                    eventUndoManager.recordContent(EventUndoManager.EventContentChange(
                        eventId: slot.id,
                        change: .url(old: oldURL, new: urlToSave),
                        description: "Edit URL"
                    ))
                    didChange = true
                }
            }
        }

        selectedSession = nil
        selectedBusySlot = nil
        resetEditingState()

        if didChange {
            Task { await calendarService.fetchEvents(for: actionContext.selectedDate) }
        }
    }
    
    private func cancelTitleEdit() {
        isCanceling = true
        isEditingTitle = false
        editingTitle = ""
        originalTitle = ""
        focusedField = nil
        // onChange(of: focusedField) fires on the next runloop; clear the guard
        // after it has had a chance to run.
        DispatchQueue.main.async { isCanceling = false }
    }

    private func cancelNotesEdit() {
        isCanceling = true
        isEditingNotes = false
        editingNotes = ""
        originalNotes = ""
        focusedField = nil
        DispatchQueue.main.async { isCanceling = false }
    }

    private func cancelURLEdit() {
        isCanceling = true
        isEditingURL = false
        editingURL = ""
        originalURL = ""
        focusedField = nil
        DispatchQueue.main.async { isCanceling = false }
    }

    // MARK: - Drag Commit

    private func commitDrag(for slot: BusyTimeSlot) {
        guard let newStart = dragPreviewStartTime,
              let newEnd = dragPreviewEndTime else {
            resetDragState()
            return
        }

        if isElasticEditing {
            commitElasticDrag(for: slot, newStart: newStart, newEnd: newEnd)
            return
        }

        // Group drag commits every selected slot atomically.
        if dragMode == .move && !groupDragOriginalTimes.isEmpty {
            commitGroupDrag()
            return
        }

        // Don't save if nothing changed
        guard newStart != slot.startTime || newEnd != slot.endTime else {
            resetDragState()
            return
        }

        let description = dragMode == .move ? "Move \(slot.title)" : "Resize \(slot.title)"
        eventUndoManager.record(EventUndoManager.EventTimeChange(
            eventId: slot.id,
            oldStartTime: slot.startTime,
            oldEndTime: slot.endTime,
            newStartTime: newStart,
            newEndTime: newEnd,
            description: description
        ))

        let success = calendarService.updateEventTime(
            eventId: slot.id,
            newStart: newStart,
            newEnd: newEnd
        )

        if !success {
            _ = eventUndoManager.undo()
        } else {
            optimisticallyUpdateSlot(id: slot.id, newStart: newStart, newEnd: newEnd)
            // Final recalculation with committed position
            recalculateWithDraggedSlot(slot, newStart: newStart, newEnd: newEnd)
        }

        Task {
            await calendarService.fetchEvents(for: actionContext.selectedDate)
        }

        resetDragState()
    }

    private func commitElasticDrag(for slot: BusyTimeSlot, newStart: Date, newEnd: Date) {
        let updates: [String: (start: Date, end: Date)]
        if dragMode == .move && !groupDragPreviewTimes.isEmpty {
            updates = groupDragPreviewTimes
        } else {
            updates = [slot.id: (start: newStart, end: newEnd)]
        }

        let baseSlots = elasticPreDragBusySlots ?? elasticStagedBusySlots
        let originalsById = Dictionary(uniqueKeysWithValues: baseSlots.map { ($0.id, $0) })
        let hasChanges = updates.contains { entry in
            guard let original = originalsById[entry.key] else { return false }
            let target = entry.value
            return original.startTime != target.start || original.endTime != target.end
        }

        guard hasChanges else {
            elasticStagedBusySlots = baseSlots
            recalculateProjectedSchedule(using: baseSlots)
            resetDragState()
            return
        }

        let adjustedGapAfterBySlotId = elasticGapMap(
            adjustingForDraggedUpdates: updates,
            in: baseSlots
        )

        recordElasticUndoSnapshot(baseSlots)
        elasticStagedBusySlots = displaceBusySlots(
            baseSlots: baseSlots,
            draggedUpdates: updates,
            commitDraggedSlots: true,
            gapAfterBySlotId: adjustedGapAfterBySlotId
        )
        elasticEmptySpaceAfterBySlotId = adjustedGapAfterBySlotId
        recalculateProjectedSchedule(using: elasticStagedBusySlots)
        onModeToast?("\(elasticChangeCount) staged")

        resetDragState()
    }

    /// Commit a group drag — every selected slot moves by the same translation atomically.
    private func commitGroupDrag() {
        let slotsById = Dictionary(uniqueKeysWithValues: timelineBusySlots(for: actionContext.selectedDate).map { ($0.id, $0) })

        var changes: [EventUndoManager.EventTimeChange] = []
        var committed: [(id: String, newStart: Date, newEnd: Date)] = []

        for (id, target) in groupDragPreviewTimes {
            guard let original = groupDragOriginalTimes[id],
                  let liveSlot = slotsById[id] else { continue }
            guard target.start != original.start || target.end != original.end else { continue }

            let success = calendarService.updateEventTime(
                eventId: id,
                newStart: target.start,
                newEnd: target.end
            )
            if success {
                changes.append(EventUndoManager.EventTimeChange(
                    eventId: id,
                    oldStartTime: original.start,
                    oldEndTime: original.end,
                    newStartTime: target.start,
                    newEndTime: target.end,
                    description: "Move \(liveSlot.title)"
                ))
                committed.append((id, target.start, target.end))
            }
        }

        if !changes.isEmpty {
            eventUndoManager.recordBatch(changes)
            for c in committed {
                optimisticallyUpdateSlot(id: c.id, newStart: c.newStart, newEnd: c.newEnd)
            }
            let finalMap = Dictionary(uniqueKeysWithValues: committed.map { ($0.id, (start: $0.newStart, end: $0.newEnd)) })
            recalculateWithDraggedSlots(finalMap)
        }

        Task {
            await calendarService.fetchEvents(for: actionContext.selectedDate)
        }

        resetDragState()
    }

    private func resetDragState() {
        if dragMode == .move { NSCursor.pop() }
        dragMode = .none
        dragSlotId = nil
        dragSessionId = nil
        dragPreviewStartTime = nil
        dragPreviewEndTime = nil
        preDisplacementSessions = nil
        elasticPreDragBusySlots = nil
        groupDragOriginalTimes.removeAll()
        groupDragPreviewTimes.removeAll()
    }

    /// Cancel drag and revert all changes (called on Escape).
    private func cancelDrag() {
        // Revert displaced projected sessions
        if let snapshot = preDisplacementSessions {
            schedulingEngine.projectedSessions = snapshot
        }
        if isElasticEditing, let snapshot = elasticPreDragBusySlots {
            elasticStagedBusySlots = snapshot
        }
        // Revert real-time schedule recalculation (calendar event drag)
        if dragSlotId != nil, !schedulingEngine.sessionsFrozen {
            if isElasticEditing {
                recalculateProjectedSchedule(using: elasticStagedBusySlots)
            } else {
                recalculateWithOriginalSlots()
            }
        }
        dragCancelled = true
        resetDragState()
    }

    /// Recalculates schedule using the original (unmodified) busy slots.
    private func recalculateWithOriginalSlots() {
        recalculateProjectedSchedule(using: timelineBusySlots(for: actionContext.selectedDate))
    }

    private func recalculateProjectedSchedule(using busySlots: [BusyTimeSlot]) {
        guard !schedulingEngine.sessionsFrozen else { return }

        _ = scheduleCoordinator.regeneratePreviewFromFetched(
            date: actionContext.selectedDate,
            startTime: actionContext.startTime,
            busySlots: busySlots
        )
    }

    /// Recalculates projected schedule using a map of slot id → new (start, end).
    /// Used for group drag where many busy slots shift simultaneously.
    private func recalculateWithDraggedSlots(_ updates: [String: (start: Date, end: Date)]) {
        guard !schedulingEngine.sessionsFrozen else { return }

        let operationDate = actionContext.selectedDate
        var modifiedSlots = timelineBusySlots(for: operationDate)
        for i in modifiedSlots.indices {
            if let target = updates[modifiedSlots[i].id] {
                let old = modifiedSlots[i]
                modifiedSlots[i] = BusyTimeSlot(
                    id: old.id, title: old.title, startTime: target.start, endTime: target.end,
                    notes: old.notes, url: old.url, calendarName: old.calendarName,
                    calendarColor: old.calendarColor, calendarIdentifier: old.calendarIdentifier
                )
            }
        }

        recalculateProjectedSchedule(using: modifiedSlots)
    }

    /// Recalculates projected schedule using modified busy slots (during calendar event drag).
    private func recalculateWithDraggedSlot(_ slot: BusyTimeSlot, newStart: Date, newEnd: Date) {
        guard !schedulingEngine.sessionsFrozen else { return }

        // Build modified busy slots with the dragged event at its new position
        let operationDate = actionContext.selectedDate
        var modifiedSlots = timelineBusySlots(for: operationDate)
        if let idx = modifiedSlots.firstIndex(where: { $0.id == slot.id }) {
            let old = modifiedSlots[idx]
            modifiedSlots[idx] = BusyTimeSlot(
                id: old.id, title: old.title, startTime: newStart, endTime: newEnd,
                notes: old.notes, url: old.url, calendarName: old.calendarName,
                calendarColor: old.calendarColor, calendarIdentifier: old.calendarIdentifier
            )
        }

        recalculateProjectedSchedule(using: modifiedSlots)
    }

    private func commitSessionDrag(for session: ScheduledSession) {
        guard let newStart = dragPreviewStartTime,
              let newEnd = dragPreviewEndTime else {
            // Restore original positions if drag was a no-op
            if let snapshot = preDisplacementSessions {
                schedulingEngine.projectedSessions = snapshot
            }
            resetDragState()
            return
        }
        guard newStart != session.startTime || newEnd != session.endTime else {
            // Restore original positions if nothing changed
            if let snapshot = preDisplacementSessions {
                schedulingEngine.projectedSessions = snapshot
            }
            resetDragState()
            return
        }

        // Restore from snapshot, commit dragged session, then do final displacement
        if let snapshot = preDisplacementSessions {
            schedulingEngine.projectedSessions = snapshot
        }
        if let idx = schedulingEngine.projectedSessions.firstIndex(where: { $0.id == session.id }) {
            schedulingEngine.projectedSessions[idx].startTime = newStart
            schedulingEngine.projectedSessions[idx].endTime = newEnd
        }

        // Final displacement pass
        schedulingEngine.displaceProjectedSessions(
            draggedSessionId: session.id,
            draggedStart: newStart,
            draggedEnd: newEnd,
            busySlots: timelineBusySlots(for: actionContext.selectedDate),
            earliestTime: elasticAwareEarliestTime
        )

        // Record undo with pre-drag snapshot and post-displacement snapshot
        let description = dragMode == .move ? "Move \(session.title)" : "Resize \(session.title)"
        eventUndoManager.record(EventUndoManager.EventTimeChange(
            sessionId: session.id,
            oldStartTime: session.startTime,
            oldEndTime: session.endTime,
            newStartTime: newStart,
            newEndTime: newEnd,
            description: description,
            sessionsSnapshot: preDisplacementSessions,
            postSnapshot: schedulingEngine.projectedSessions
        ))

        resetDragState()
    }

    private func sessionDragPreviewBlock(
        session: ScheduledSession,
        newStart: Date,
        newEnd: Date,
        containerWidth: CGFloat
    ) -> some View {
        let yPos = calculateYPosition(for: newStart)
        let height = calculateHeight(from: newStart, to: newEnd)
        let blockHeight = max(height, 8)
        let blockWidth = (containerWidth / 2) - 24
        let xOffset = containerWidth / 2 + 8
        let centerX = xOffset + blockWidth / 2
        let centerY = yPos + blockHeight / 2

        let isCompact = blockHeight <= compactBlockLayoutHeight

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(session.type.color.opacity(colors.isDark ? 0.5 : 0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.blue.opacity(0.8), lineWidth: 2)
                )
                .shadow(color: Color.blue.opacity(0.3), radius: 8, y: 2)

            if isCompact {
                HStack(spacing: 3) {
                    Image(systemName: session.type.icon)
                        .font(.system(size: 10))
                    Text(session.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(startAndDurationString(start: newStart, end: newEnd))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                .foregroundColor(.white)
                .padding(3)
            } else if blockHeight >= 16 {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .top, spacing: 3) {
                        Image(systemName: session.type.icon)
                            .font(.system(size: 11))
                            .padding(.top, 1)
                        Text(session.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(.white)
                    if blockHeight > 30 {
                        Text(startAndDurationString(start: newStart, end: newEnd))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .padding(4)
            }
        }
        .frame(width: blockWidth, height: blockHeight)
        .clipped()
        .position(x: centerX, y: centerY)
        .allowsHitTesting(false)
    }

    // MARK: - Undo / Redo

    private func performUndo() {
        let operationDate = actionContext.selectedDate
        guard let change = eventUndoManager.undo() else { return }
        dismissTransientInteractionState()
        switch change {
        case .time(let tc):
            if tc.sessionId != nil {
                if let snapshot = tc.sessionsSnapshot {
                    schedulingEngine.projectedSessions = snapshot
                } else if let sessionId = tc.sessionId,
                          let idx = schedulingEngine.projectedSessions.firstIndex(where: { $0.id == sessionId }) {
                    schedulingEngine.projectedSessions[idx].startTime = tc.newStartTime
                    schedulingEngine.projectedSessions[idx].endTime = tc.newEndTime
                }
                if schedulingEngine.sessionsFrozen && !eventUndoManager.hasSessionChanges {
                    schedulingEngine.sessionsFrozen = false
                }
            } else {
                let success = calendarService.updateEventTime(
                    eventId: tc.eventId,
                    newStart: tc.newStartTime,
                    newEnd: tc.newEndTime
                )
                if success {
                    optimisticallyUpdateSlot(id: tc.eventId, newStart: tc.newStartTime, newEnd: tc.newEndTime)
                    Task { await calendarService.fetchEvents(for: operationDate) }
                }
            }
        case .timeBatch(let items):
            for tc in items {
                if calendarService.updateEventTime(eventId: tc.eventId, newStart: tc.newStartTime, newEnd: tc.newEndTime) {
                    optimisticallyUpdateSlot(id: tc.eventId, newStart: tc.newStartTime, newEnd: tc.newEndTime)
                }
            }
            Task { await calendarService.fetchEvents(for: operationDate) }
        case .delete(let snap):
            if let newId = calendarService.restoreEvent(snap) {
                eventUndoManager.pushRedoForRestoredDelete(original: snap, newEventId: newId)
                Task { await calendarService.fetchEvents(for: operationDate) }
            }
        case .deleteBatch(let snaps):
            var newIds: [String] = []
            for snap in snaps {
                if let newId = calendarService.restoreEvent(snap) {
                    newIds.append(newId)
                }
            }
            if !newIds.isEmpty {
                let restoredSnaps = Array(snaps.prefix(newIds.count))
                eventUndoManager.pushRedoForRestoredDeleteBatch(originals: restoredSnaps, newEventIds: newIds)
                Task { await calendarService.fetchEvents(for: operationDate) }
            }
        case .schedule(let snap):
            // Undo: delete created events, restore projected sessions.
            // Freeze before the fetch so the subsequent regeneration can't
            // overwrite the restored snapshot with fresh UUIDs, which would
            // leave the undo stack pointing at sessions that no longer exist.
            for eventId in snap.eventIds {
                _ = calendarService.deleteEvent(identifier: eventId)
            }
            schedulingEngine.projectedSessions.append(contentsOf: snap.sessions)
            schedulingEngine.projectedSessions.sort { $0.startTime < $1.startTime }
            schedulingEngine.sessionsFrozen = true
            Task { await calendarService.fetchEvents(for: operationDate) }
        case .create(let snap):
            // Undo create = delete the event
            if calendarService.deleteEvent(identifier: snap.eventId) {
                eventUndoManager.pushRedoForUndoneCreate(snap)
                Task { await calendarService.fetchEvents(for: operationDate) }
            }
        case .feedback(let fc):
            if let rating = fc.newRating {
                _ = calendarService.setFeedbackTag(eventId: fc.eventId, rating: rating)
            } else {
                _ = calendarService.clearFeedbackTag(eventId: fc.eventId)
            }
            Task {
                await calendarService.fetchEvents(for: operationDate)
                if let updated = calendarService.busySlots.first(where: { $0.id == fc.eventId }) {
                    if selectedBusySlot?.id == fc.eventId { selectedBusySlot = updated }
                }
            }
        case .alignment(let ac):
            if let alignment = ac.newAlignment {
                _ = calendarService.setAlignmentTag(eventId: ac.eventId, alignment: alignment)
            } else {
                _ = calendarService.clearAlignmentTag(eventId: ac.eventId)
            }
            Task {
                await calendarService.fetchEvents(for: operationDate)
                if let updated = calendarService.busySlots.first(where: { $0.id == ac.eventId }) {
                    if selectedBusySlot?.id == ac.eventId { selectedBusySlot = updated }
                }
            }
        case .content(let cc):
            applyContentChange(cc)
        }
    }

    private func performRedo() {
        let operationDate = actionContext.selectedDate
        guard let change = eventUndoManager.redo() else { return }
        dismissTransientInteractionState()
        switch change {
        case .time(let tc):
            if tc.sessionId != nil {
                if !schedulingEngine.sessionsFrozen {
                    schedulingEngine.sessionsFrozen = true
                }
                if let postSnapshot = tc.postSnapshot {
                    schedulingEngine.projectedSessions = postSnapshot
                } else if let sessionId = tc.sessionId,
                          let idx = schedulingEngine.projectedSessions.firstIndex(where: { $0.id == sessionId }) {
                    schedulingEngine.projectedSessions[idx].startTime = tc.newStartTime
                    schedulingEngine.projectedSessions[idx].endTime = tc.newEndTime
                }
            } else {
                let success = calendarService.updateEventTime(
                    eventId: tc.eventId,
                    newStart: tc.newStartTime,
                    newEnd: tc.newEndTime
                )
                if success {
                    optimisticallyUpdateSlot(id: tc.eventId, newStart: tc.newStartTime, newEnd: tc.newEndTime)
                    Task { await calendarService.fetchEvents(for: operationDate) }
                }
            }
        case .timeBatch(let items):
            for tc in items {
                if calendarService.updateEventTime(eventId: tc.eventId, newStart: tc.newStartTime, newEnd: tc.newEndTime) {
                    optimisticallyUpdateSlot(id: tc.eventId, newStart: tc.newStartTime, newEnd: tc.newEndTime)
                }
            }
            Task { await calendarService.fetchEvents(for: operationDate) }
        case .delete(let snap):
            if calendarService.deleteEvent(identifier: snap.eventId) {
                Task { await calendarService.fetchEvents(for: operationDate) }
            }
        case .deleteBatch(let snaps):
            var anyDeleted = false
            for snap in snaps {
                if calendarService.deleteEvent(identifier: snap.eventId) { anyDeleted = true }
            }
            if anyDeleted { Task { await calendarService.fetchEvents(for: operationDate) } }
        case .schedule(let snap):
            // Redo: re-create the sessions and remove them from projected
            let result = calendarService.createSessions(snap.sessions)
            if result.success > 0 {
                let scheduledIds = Set(snap.sessions.map { $0.id })
                schedulingEngine.projectedSessions.removeAll { scheduledIds.contains($0.id) }
                eventUndoManager.pushRedoForScheduleUndo(EventUndoManager.ScheduleSnapshot(
                    eventIds: result.eventIds,
                    sessions: snap.sessions
                ))
                Task { await calendarService.fetchEvents(for: operationDate) }
            }
        case .feedback(let fc):
            if let rating = fc.newRating {
                _ = calendarService.setFeedbackTag(eventId: fc.eventId, rating: rating)
            } else {
                _ = calendarService.clearFeedbackTag(eventId: fc.eventId)
            }
            Task {
                await calendarService.fetchEvents(for: operationDate)
                if let updated = calendarService.busySlots.first(where: { $0.id == fc.eventId }) {
                    if selectedBusySlot?.id == fc.eventId { selectedBusySlot = updated }
                }
            }
        case .alignment(let ac):
            if let alignment = ac.newAlignment {
                _ = calendarService.setAlignmentTag(eventId: ac.eventId, alignment: alignment)
            } else {
                _ = calendarService.clearAlignmentTag(eventId: ac.eventId)
            }
            Task {
                await calendarService.fetchEvents(for: operationDate)
                if let updated = calendarService.busySlots.first(where: { $0.id == ac.eventId }) {
                    if selectedBusySlot?.id == ac.eventId { selectedBusySlot = updated }
                }
            }
        case .create(let snap):
            // Redo create = restore the event
            if let newId = calendarService.restoreEvent(snap) {
                // Update the undo stack entry with the new event ID
                let updatedSnap = EventDeleteSnapshot(
                    eventId: newId,
                    title: snap.title,
                    notes: snap.notes,
                    url: snap.url,
                    startDate: snap.startDate,
                    endDate: snap.endDate,
                    calendarIdentifier: snap.calendarIdentifier,
                    calendarName: snap.calendarName
                )
                // Replace the top of the undo stack with updated ID
                eventUndoManager.updateTopUndoCreateId(updatedSnap)
                Task { await calendarService.fetchEvents(for: operationDate) }
            }
        case .content(let cc):
            applyContentChange(cc)
        }
    }

    /// Applies a content (title/notes/URL) change to the underlying calendar event.
    /// Used by both undo (inverted change) and redo (original change).
    private func applyContentChange(_ cc: EventUndoManager.EventContentChange) {
        let success: Bool
        switch cc.change {
        case .title(_, let new):
            success = calendarService.updateEvent(eventId: cc.eventId, title: new, notes: nil, url: nil)
        case .notes(_, let new):
            // updateEvent skips nil notes — pass empty string to clear.
            success = calendarService.updateEvent(eventId: cc.eventId, title: nil, notes: new ?? "", url: nil)
        case .url(_, let new):
            success = calendarService.updateEvent(eventId: cc.eventId, title: nil, notes: nil, url: new, updateURL: true)
        }
        guard success else { return }
        let operationDate = actionContext.selectedDate
        Task {
            await calendarService.fetchEvents(for: operationDate)
            if let updated = calendarService.busySlots.first(where: { $0.id == cc.eventId }),
               selectedBusySlot?.id == cc.eventId {
                selectedBusySlot = updated
            }
        }
    }

    private func optimisticallyUpdateSlot(id: String, newStart: Date, newEnd: Date) {
        if let idx = calendarService.busySlots.firstIndex(where: { $0.id == id }) {
            let old = calendarService.busySlots[idx]
            calendarService.busySlots[idx] = BusyTimeSlot(
                id: old.id, title: old.title, startTime: newStart, endTime: newEnd,
                notes: old.notes, url: old.url, calendarName: old.calendarName,
                calendarColor: old.calendarColor, calendarIdentifier: old.calendarIdentifier
            )
        }
    }

    private func optimisticallyUpdateSlotNotes(id: String, notes: String?) {
        if let idx = calendarService.busySlots.firstIndex(where: { $0.id == id }) {
            let old = calendarService.busySlots[idx]
            calendarService.busySlots[idx] = BusyTimeSlot(
                id: old.id, title: old.title, startTime: old.startTime, endTime: old.endTime,
                notes: notes, url: old.url, calendarName: old.calendarName,
                calendarColor: old.calendarColor, calendarIdentifier: old.calendarIdentifier
            )
        }
        if let idx = elasticStagedBusySlots.firstIndex(where: { $0.id == id }) {
            let old = elasticStagedBusySlots[idx]
            elasticStagedBusySlots[idx] = BusyTimeSlot(
                id: old.id, title: old.title, startTime: old.startTime, endTime: old.endTime,
                notes: notes, url: old.url, calendarName: old.calendarName,
                calendarColor: old.calendarColor, calendarIdentifier: old.calendarIdentifier
            )
        }
        if var originals = elasticOriginalBusySlots,
           let idx = originals.firstIndex(where: { $0.id == id }) {
            let old = originals[idx]
            originals[idx] = BusyTimeSlot(
                id: old.id, title: old.title, startTime: old.startTime, endTime: old.endTime,
                notes: notes, url: old.url, calendarName: old.calendarName,
                calendarColor: old.calendarColor, calendarIdentifier: old.calendarIdentifier
            )
            elasticOriginalBusySlots = originals
        }
    }
}

#Preview {
    TimelineView(selectedDate: Date(), startTime: Date())
        .environmentObject(CalendarService())
        .environmentObject(SchedulingEngine())
        .frame(width: 600, height: 800)

}

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
    @State private var inlineEditor = TimelineInlineEditor()
    @FocusState private var focusedField: TimelineInlineEditField?
    
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
    @State private var dragMode: TimelineDragMode = .none
    @State private var isShiftHeld: Bool = false
    @State private var isCommandHeld: Bool = false
    @State private var isOptionHeld: Bool = false
    @State private var flagsMonitor: Any? = nil
    @State private var groupDrag = TimelineGroupDrag()
    @State private var keyDownMonitor: Any? = nil
    @State private var mouseDownMonitor: Any? = nil
    @StateObject private var eventUndoManager = EventUndoManager()
    @StateObject private var actionContext = TimelineActionContext()
    @State private var eventsLocked: Bool = false
    @State private var isTimelinePanelHovered: Bool = false
    @State private var elasticEditor = TimelineElasticEditor()
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
    @State private var projectedSessionDrag = TimelineProjectedSessionDrag()
    // Prevents drag re-initialization after Esc while mouse button is still held
    @State private var dragCancelled: Bool = false
    // Auto-scroll during drag
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var lastAutoScrollTime: Date = .distantPast
    @State private var scrollViewFrame: CGRect = .zero
    /// Last hour we scrolled to; used to avoid resetting scroll on every timer tick (only scroll when hour changes)
    @State private var lastScrolledStartHour: Int? = nil

    private var isNarrow: Bool {
        // Use a reasonable threshold for narrow width
        containerWidth < 750
    }

    private var isExtraNarrow: Bool {
        // Use a reasonable threshold for narrow width
        containerWidth < 400
    }

    private var isElasticEditing: Bool {
        elasticEditor.isEditing
    }

    private var elasticChangeCount: Int {
        elasticEditor.changeCount
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

    private var timelineTimeScale: TimelineTimeScale {
        TimelineTimeScale(
            selectedDate: selectedDate,
            hourHeight: hourHeight,
            hideNightHours: schedulingEngine.hideNightHours,
            dayStartHour: schedulingEngine.dayStartHour,
            dayEndHour: schedulingEngine.dayEndHour,
            scheduleEndHour: schedulingEngine.scheduleEndHour
        )
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
                            guard elasticEditor.canRedo else { return event }
                            redoElasticChange()
                        } else {
                            guard elasticEditor.canUndo else { return event }
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
                                copyBusySlot(slot, toCustomDate: copyTargetDate)
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
                    .frame(height: timelineTimeScale.contentHeight)
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
                        ForEach(filteredBusySlots.filter { $0.id != slotId && groupDrag.preview(for: $0.id) != nil }, id: \.id) { otherSlot in
                            if let target = groupDrag.preview(for: otherSlot.id) {
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

            Picker("", selection: $elasticEditor.displacementMode) {
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
    
    private var busySlotsWithLayout: [TimelineBusySlotLayout.PositionedSlot] {
        TimelineBusySlotLayout.positionedSlots(for: filteredBusySlots)
    }

    private func timelineBusySlots(for date: Date) -> [BusyTimeSlot] {
        if isElasticEditing, Calendar.current.isDate(date, inSameDayAs: selectedDate) {
            return elasticEditor.stagedSlots
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
        elasticEditor.begin(with: snapshot, mode: mode)

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
            elasticEditor.displacementMode = requestedMode
        } else {
            beginElasticEditing(mode: requestedMode, preserveSelection: true)
        }
    }

    private func cancelElasticEditing(showToast: Bool = true) {
        guard isElasticEditing else { return }
        elasticEditor.reset()
        selectedBusySlotIds.removeAll()
        resetDragState()
        recalculateWithOriginalSlots()

        if showToast {
            onModeToast?("Elastic edits discarded")
        }
    }

    private func saveElasticEditing() {
        let changes = elasticEditor.timeChanges()
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
        elasticEditor.reset()
        selectedBusySlotIds.removeAll()
        resetDragState()

        onModeToast?(savedCount == 1 ? "Saved 1 event move" : "Saved \(savedCount) event moves")
        Task { await calendarService.fetchEvents(for: actionContext.selectedDate) }
    }

    private func recordElasticUndoSnapshot(_ snapshot: [BusyTimeSlot]) {
        elasticEditor.recordUndoSnapshot(snapshot)
    }

    private func undoElasticChange() {
        guard elasticEditor.undo() else { return }
        recalculateProjectedSchedule(using: elasticEditor.stagedSlots)
        onModeToast?("Undid elastic move")
    }

    private func redoElasticChange() {
        guard elasticEditor.redo() else { return }
        recalculateProjectedSchedule(using: elasticEditor.stagedSlots)
        onModeToast?("Redid elastic move")
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

    private func elasticGapMap(
        adjustingForDraggedUpdates draggedUpdates: [String: (start: Date, end: Date)],
        in baseSlots: [BusyTimeSlot]
    ) -> [String: TimeInterval] {
        elasticEditor.adjustedGapMap(forDraggedUpdates: draggedUpdates, in: baseSlots)
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
        return elasticEditor.displacedSlots(
            baseSlots: baseSlots,
            draggedUpdates: draggedUpdates,
            commitDraggedSlots: commitDraggedSlots,
            gapAfterBySlotId: existingGapMap,
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
        timelineTimeScale.formattedHour(hour, uses12HourClock: uses12HourClock)
    }
    
    /// The upper bound for visible hours.
    /// `dayEndHour` controls visibility when `hideNightHours` is on; we extend it
    /// up to `scheduleEndHour` so scheduled sessions are never clipped off the
    /// timeline. When night hours are shown, we expose a full 24h minimum.
    private var effectiveEndHour: Int {
        timelineTimeScale.effectiveEndHour
    }

    private var visibleHours: [Int] {
        timelineTimeScale.visibleHours
    }

    /// Effective "now" for the red line: real time or dev override.
    private var effectiveNowTimeForIndicator: Date {
        timelineTimeScale.effectiveNowTime(
            currentTime: currentTime,
            overrideEnabled: devNowLineOverrideEnabled,
            overrideHour: devNowLineOverrideHour,
            overrideMinute: devNowLineOverrideMinute
        )
    }

    /// Show current-time indicator when viewing today, or when viewing yesterday
    /// and the current time falls within the extended hours (past midnight).
    /// With dev override enabled, always show so screenshots can use any date.
    private var shouldShowCurrentTimeIndicator: Bool {
        timelineTimeScale.shouldShowCurrentTimeIndicator(
            currentDate: Date(),
            overrideEnabled: devNowLineOverrideEnabled
        )
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
    
    private func eventBlock(
        for positionedSlot: TimelineBusySlotLayout.PositionedSlot,
        containerWidth: CGFloat
    ) -> some View {
        let slot = positionedSlot.slot
        let isAnchorDragging = dragSlotId == slot.id && dragMode != .none
        let isGroupMemberDragging = dragMode == .move
            && dragSlotId != nil
            && dragSlotId != slot.id
            && groupDrag.contains(slot.id)
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

            let showsFeedbackBadge = TimelineEventContent.showsFeedbackBadge(
                eventEnd: slot.endTime,
                awarenessEnabled: sessionAwarenessService.config.enabled,
                productivityEnabled: sessionAwarenessService.config.productivityEnabled
            )
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

                if let notes = TimelineEventContent.blockDisplayNotes(from: slot.notes), height > notesMinimumHeight {
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
                        dragMode = TimelineDragPreview.mode(
                            startY: value.startLocation.y,
                            blockHeight: blockHeight,
                            edgeZone: edgeZone,
                            canResize: true
                        )
                        if dragMode == .move {
                            activateElasticModeForDragIfNeeded()
                            NSCursor.closedHand.push()
                            if isElasticEditing {
                                elasticEditor.capturePreDragSnapshot()
                            }
                            // If dragged slot isn't part of the selection, reset selection to it.
                            // Resize stays single-event (no selection change).
                            if !selectedBusySlotIds.contains(slot.id) {
                                selectedBusySlotIds = [slot.id]
                            }
                            // Snapshot original times for every selected slot (for group drag).
                            if selectedBusySlotIds.count > 1 {
                                groupDrag.begin(
                                    selectedIds: selectedBusySlotIds,
                                    slots: timelineBusySlots(for: actionContext.selectedDate)
                                )
                            }
                        }
                        if isElasticEditing, dragMode != .move {
                            elasticEditor.capturePreDragSnapshot()
                        }
                        dragSlotId = slot.id
                    }

                    if let preview = TimelineDragPreview.timeRange(
                        mode: dragMode,
                        originalStart: slot.startTime,
                        originalEnd: slot.endTime,
                        translationY: value.translation.height,
                        yPosition: calculateYPosition,
                        dateFromYOffset: dateFromYOffset,
                        snap: snapToInterval,
                        clampStart: clampedForElasticDrag,
                        preservesRawTime: isShiftHeld
                    ) {
                        dragPreviewStartTime = preview.start
                        dragPreviewEndTime = preview.end

                        // Group drag: translate every other selected event by the same delta.
                        if dragMode == .move && groupDrag.isActive {
                            groupDrag.updateTranslation(from: slot.startTime, to: preview.start)
                        }
                    }

                    // Real-time recalculation with throttle
                    if let previewStart = dragPreviewStartTime,
                       let previewEnd = dragPreviewEndTime {
                        let now = Date()
                        if now.timeIntervalSince(lastDragRecalcTime) >= dragRecalcInterval {
                            lastDragRecalcTime = now
                            if isElasticEditing {
                                let updates: [String: (start: Date, end: Date)] = groupDrag.isActive
                                    ? groupDrag.previewTimes
                                    : [slot.id: (start: previewStart, end: previewEnd)]
                                let baseSlots = elasticEditor.dragBaseSlots
                                let displaced = displaceBusySlots(
                                    baseSlots: baseSlots,
                                    draggedUpdates: updates,
                                    commitDraggedSlots: false
                                )
                                elasticEditor.stagedSlots = displaced
                                recalculateProjectedSchedule(using: applyingTimeUpdates(to: displaced, updates: updates))
                            } else if groupDrag.isActive {
                                recalculateWithDraggedSlots(groupDrag.previewTimes)
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
            inlineEditor.autoFocusField = nil
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
                performContextMenuAction {
                    selectedSession = nil
                    selectedBusySlot = slot
                }
            }
            Button(slot.isFlowFlexible ? "Mark Fixed" : "Mark Flexible") {
                performContextMenuAction {
                    setBusySlotFlexible(slot, isFlexible: !slot.isFlowFlexible)
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                performContextMenuAction {
                    deleteBusySlot(slot)
                }
            }
            Divider()
            Button("Duplicate") {
                performContextMenuAction {
                    duplicateBusySlot(slot)
                }
            }
            Menu("Copy to...") {
                ForEach(TimelineEventActions.copyTargets(selectedDate: selectedDate), id: \.date) { target in
                    Button(target.label) {
                        performContextMenuAction {
                            copyBusySlot(slot, to: target)
                        }
                    }
                }
                Divider()
                Button("Custom...") {
                    performContextMenuAction {
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
        TimelineEventContent.goalReminderText(goals, style: sessionAwarenessService.config.harshModeReminderStyle)
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
                        dragMode = TimelineDragPreview.mode(
                            startY: value.startLocation.y,
                            blockHeight: blockHeight,
                            edgeZone: edgeZone,
                            canResize: !isBigRest
                        )
                        if dragMode == .move {
                            NSCursor.closedHand.push()
                        }
                        dragSessionId = session.id
                        // Auto-freeze on first drag
                        if !schedulingEngine.sessionsFrozen {
                            schedulingEngine.sessionsFrozen = true
                        }
                        projectedSessionDrag.begin(with: schedulingEngine.projectedSessions)
                    }

                    if let preview = TimelineDragPreview.timeRange(
                        mode: dragMode,
                        originalStart: session.startTime,
                        originalEnd: session.endTime,
                        translationY: value.translation.height,
                        yPosition: calculateYPosition,
                        dateFromYOffset: dateFromYOffset,
                        snap: snapToInterval,
                        clampStart: clampedForElasticDrag,
                        preservesRawTime: isShiftHeld
                    ) {
                        dragPreviewStartTime = preview.start
                        dragPreviewEndTime = preview.end
                    }

                    // Displacement with throttle
                    if let previewStart = dragPreviewStartTime,
                       let previewEnd = dragPreviewEndTime {
                        let now = Date()
                        if now.timeIntervalSince(lastDragRecalcTime) >= dragRecalcInterval {
                            lastDragRecalcTime = now
                            if let snapshot = projectedSessionDrag.sessionsForDisplacementPass() {
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
                if inlineEditor.title.isEditing {
                    TextField("Event title", text: $inlineEditor.title.draft)
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
                            inlineEditor.begin(.title, original: slot.title)
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
                    
                    if inlineEditor.notes.isEditing {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes:")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(colors.textSecondary)
                            TextEditor(text: $inlineEditor.notes.draft)
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
                    } else if let displayNotes = TimelineEventContent.detailEditableNotes(from: slot.notes), !displayNotes.isEmpty {
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
                            let stripped = TimelineEventContent.detailEditableNotes(from: slot.notes) ?? ""
                            inlineEditor.begin(.notes, original: stripped)
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
                            inlineEditor.begin(.notes, original: "")
                            focusedField = .notes
                        }
                    }
                }
                
                // Feedback rating picker
                if TimelineEventContent.showsFeedbackBadge(
                    eventEnd: slot.endTime,
                    awarenessEnabled: sessionAwarenessService.config.enabled,
                    productivityEnabled: sessionAwarenessService.config.productivityEnabled
                ) {
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

                    if inlineEditor.url.isEditing {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("URL:")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(colors.textSecondary)
                            TextField("https://example.com", text: $inlineEditor.url.draft)
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
                            inlineEditor.begin(.url, original: url.absoluteString)
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
                            inlineEditor.begin(.url, original: "")
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
            guard !inlineEditor.isCanceling else { return }
            
            // Auto-save when focus leaves a field
            if oldValue == .title && newValue != .title && inlineEditor.title.isEditing {
                saveTitle(for: slot)
            }
            if oldValue == .notes && newValue != .notes && inlineEditor.notes.isEditing {
                saveNotes(for: slot)
            }
            if oldValue == .url && newValue != .url && inlineEditor.url.isEditing {
                saveURL(for: slot)
            }
        }
        .onAppear {
            // Auto-focus on field when detail view opens
            if let field = inlineEditor.autoFocusField {
                switch field {
                case .title:
                    inlineEditor.begin(.title, original: slot.title)
                    focusedField = .title
                case .notes:
                    let stripped = TimelineEventContent.detailEditableNotes(from: slot.notes) ?? ""
                    inlineEditor.begin(.notes, original: stripped)
                    focusedField = .notes
                case .url:
                    inlineEditor.begin(.url, original: slot.url?.absoluteString ?? "")
                    focusedField = .url
                }
                // Clear auto-focus after applying it
                inlineEditor.autoFocusField = nil
            }
        }
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
    
    // MARK: - Busy Slot Actions

    private func performContextMenuAction(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + TimelineEventActions.contextMenuActionDelay) {
            action()
        }
    }

    private func duplicateBusySlot(_ slot: BusyTimeSlot) {
        let result = calendarService.duplicateEvent(eventId: slot.id)
        handleCopyOutcome(TimelineEventActions.duplicateOutcome(
            title: slot.title,
            selectedDate: actionContext.selectedDate,
            result: TimelineEventActions.calendarCopyResult(
                success: result.success,
                newEventId: result.newEventId,
                targetStartTime: result.targetStartTime
            )
        ))
    }

    private func copyBusySlot(_ slot: BusyTimeSlot, to target: TimelineEventActions.CopyTarget) {
        let result = calendarService.copyEventToDay(eventId: slot.id, targetDate: target.date)
        handleCopyOutcome(TimelineEventActions.copyOutcome(
            title: slot.title,
            target: target,
            result: TimelineEventActions.calendarCopyResult(
                success: result.success,
                newEventId: result.newEventId,
                targetStartTime: result.targetStartTime
            )
        ))
    }

    private func copyBusySlot(_ slot: BusyTimeSlot, toCustomDate targetDate: Date) {
        let result = calendarService.copyEventToDay(eventId: slot.id, targetDate: targetDate)
        handleCopyOutcome(TimelineEventActions.customCopyOutcome(
            title: slot.title,
            targetDate: targetDate,
            result: TimelineEventActions.calendarCopyResult(
                success: result.success,
                newEventId: result.newEventId,
                targetStartTime: result.targetStartTime
            )
        ))
    }

    private func handleCopyOutcome(_ outcome: TimelineEventActions.CopyOutcome) {
        switch outcome {
        case .success(let toast):
            onCopySuccess?(CopyToastInfo(
                title: toast.title,
                targetLabel: toast.targetLabel,
                targetDate: toast.targetDate,
                targetStartTime: toast.targetStartTime,
                newEventId: toast.newEventId
            ))
            Task { await calendarService.fetchEvents(for: actionContext.selectedDate) }
        case .failure(let message):
            schedulingEngine.schedulingMessage = message
        }
    }

    private func deleteBusySlot(_ slot: BusyTimeSlot) {
        guard !isElasticEditing else {
            onModeToast?(TimelineEventActions.elasticEditBlockedMessage)
            return
        }
        let snapshot = TimelineEventActions.deleteSnapshot(for: slot)
        if calendarService.deleteEvent(identifier: slot.id) {
            eventUndoManager.recordDelete(snapshot)
            dismissTransientInteractionState()
            Task { await calendarService.fetchEvents(for: actionContext.selectedDate) }
        }
    }

    /// Atomically deletes multiple slots — one undo step for the whole batch.
    private func deleteSelectedSlots(_ slots: [BusyTimeSlot]) {
        guard !isElasticEditing else {
            onModeToast?(TimelineEventActions.elasticEditBlockedMessage)
            return
        }
        guard !slots.isEmpty else { return }
        var snapshots: [EventDeleteSnapshot] = []
        for slot in slots {
            let snapshot = TimelineEventActions.deleteSnapshot(for: slot)
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
            .frame(width: leftHalfWidth, height: timelineTimeScale.contentHeight)
            .contentShape(Rectangle())
            .position(x: leftHalfWidth / 2, y: timelineTimeScale.contentHeight / 2)
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
            .frame(width: halfWidth, height: timelineTimeScale.contentHeight)
            .contentShape(Rectangle())
            .position(x: containerWidth - halfWidth / 2, y: timelineTimeScale.contentHeight / 2)
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
            onModeToast?(TimelineEventActions.elasticEditBlockedMessage)
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
        timelineTimeScale.yPosition(for: date)
    }

    /// Inverse of calculateYPosition — converts a Y offset back to a Date.
    private func dateFromYOffset(_ yPosition: CGFloat) -> Date {
        timelineTimeScale.date(fromYOffset: yPosition)
    }

    private func snapToInterval(_ date: Date) -> Date {
        timelineTimeScale.snapToInterval(date)
    }

    private func calculateHeight(from start: Date, to end: Date) -> CGFloat {
        timelineTimeScale.height(from: start, to: end)
    }
    
    private func timeRangeString(start: Date, end: Date) -> String {
        timelineTimeScale.timeRangeString(start: start, end: end)
    }

    private func startAndDurationString(start: Date, end: Date) -> String {
        timelineTimeScale.startAndDurationString(start: start, end: end)
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
        guard let result = TimelineReviewUpdate.setFeedback(
            eventId: slot.id,
            currentNotes: currentNotes,
            rating: rating,
            toggleWhenAlreadySelected: true,
            calendar: calendarService
        ) else { return }

        eventUndoManager.recordFeedback(result.undoChange)
        finishPopoverFeedbackUpdate(for: slot, notes: result.updatedNotes)
    }

    private func updatePopoverFeedback(for slot: BusyTimeSlot, alignment: SessionAlignment) {
        let currentNotes = currentReviewNotes(for: slot)
        guard let result = TimelineReviewUpdate.setAlignment(
            eventId: slot.id,
            currentNotes: currentNotes,
            alignment: alignment,
            toggleWhenAlreadySelected: true,
            calendar: calendarService
        ) else { return }

        eventUndoManager.recordAlignment(result.undoChange)
        finishPopoverFeedbackUpdate(for: slot, notes: result.updatedNotes)
    }

    private func currentReviewNotes(for slot: BusyTimeSlot) -> String? {
        timelineBusySlots(for: actionContext.selectedDate).first(where: { $0.id == slot.id })?.notes
            ?? calendarService.busySlots.first(where: { $0.id == slot.id })?.notes
            ?? slot.notes
    }

    private func finishPopoverFeedbackUpdate(for slot: BusyTimeSlot, notes: String?) {
        optimisticallyUpdateSlotNotes(id: slot.id, notes: notes)

        feedbackPopoverEventId = TimelineReviewUpdate.shouldKeepPopoverOpen(afterNotes: notes) ? slot.id : nil

        Task {
            await calendarService.fetchEvents(for: actionContext.selectedDate)
            if let updated = calendarService.busySlots.first(where: { $0.id == slot.id }),
               selectedBusySlot?.id == slot.id {
                selectedBusySlot = updated
            }
        }
    }

    private func finishDetailReviewUpdate(for slot: BusyTimeSlot, notes: String?) {
        optimisticallyUpdateSlotNotes(id: slot.id, notes: notes)
        refreshSelectedBusySlot(slot.id)

        Task {
            await calendarService.fetchEvents(for: actionContext.selectedDate)
            refreshSelectedBusySlot(slot.id)
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
                    if let result = TimelineReviewUpdate.setFeedback(
                        eventId: slot.id,
                        currentNotes: currentReviewNotes(for: slot),
                        rating: rating,
                        calendar: calendarService
                    ) {
                        eventUndoManager.recordFeedback(result.undoChange)
                        finishDetailReviewUpdate(for: slot, notes: result.updatedNotes)
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
        guard let result = TimelineReviewUpdate.clearFeedback(
            eventId: slot.id,
            currentNotes: currentReviewNotes(for: slot),
            calendar: calendarService
        ) else { return }

        eventUndoManager.recordFeedback(result.undoChange)
        finishDetailReviewUpdate(for: slot, notes: result.updatedNotes)
    }

    private func shouldShowAlignmentPicker(for slot: BusyTimeSlot) -> Bool {
        TimelineEventContent.shouldShowAlignmentPicker(for: slot.notes)
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
                    if let result = TimelineReviewUpdate.setAlignment(
                        eventId: slot.id,
                        currentNotes: currentReviewNotes(for: slot),
                        alignment: alignment,
                        calendar: calendarService
                    ) {
                        eventUndoManager.recordAlignment(result.undoChange)
                        finishDetailReviewUpdate(for: slot, notes: result.updatedNotes)
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
        guard let result = TimelineReviewUpdate.clearAlignment(
            eventId: slot.id,
            currentNotes: currentReviewNotes(for: slot),
            calendar: calendarService
        ) else { return }

        eventUndoManager.recordAlignment(result.undoChange)
        finishDetailReviewUpdate(for: slot, notes: result.updatedNotes)
    }

    // MARK: - Inline Editing Helpers

    private func saveTitle(for slot: BusyTimeSlot) {
        saveInlineEdit(.title, for: slot)
    }

    private func saveNotes(for slot: BusyTimeSlot) {
        saveInlineEdit(.notes, for: slot)
    }

    private func saveURL(for slot: BusyTimeSlot) {
        saveInlineEdit(.url, for: slot)
    }

    private func saveInlineEdit(_ field: TimelineInlineEditField, for slot: BusyTimeSlot) {
        guard let commit = inlineEditor.commitPlan(
            for: field,
            existingNotes: slot.notes,
            isFlowFlexible: slot.isFlowFlexible
        ) else {
            inlineEditor.reset(field)
            return
        }

        let success = applyInlineEditCommit(commit, for: slot)
        inlineEditor.reset(field)

        if success {
            Task {
                await calendarService.fetchEvents(for: actionContext.selectedDate)
                refreshSelectedBusySlot(slot.id)
            }
        }
    }

    private func applyInlineEditCommit(_ commit: TimelineInlineEditCommit, for slot: BusyTimeSlot) -> Bool {
        let success: Bool
        let undoChange: EventUndoManager.EventContentChange.FieldChange

        switch commit.change {
        case .title(let old, let new):
            success = calendarService.updateEvent(eventId: slot.id, title: new, notes: nil, url: nil)
            undoChange = .title(old: old, new: new)
        case .notes(let old, let new):
            success = calendarService.updateEvent(eventId: slot.id, title: nil, notes: new, url: nil)
            undoChange = .notes(old: old, new: new)
        case .url(let old, let new):
            success = calendarService.updateEvent(eventId: slot.id, title: nil, notes: nil, url: new, updateURL: true)
            undoChange = .url(old: old, new: new)
        }

        guard success else { return false }

        eventUndoManager.recordContent(EventUndoManager.EventContentChange(
            eventId: slot.id,
            change: undoChange,
            description: commit.description
        ))
        return true
    }

    private func refreshSelectedBusySlot(_ slotId: String) {
        if let updatedSlot = calendarService.busySlots.first(where: { $0.id == slotId }) {
            selectedBusySlot = updatedSlot
        }
    }
    
    private func resetEditingState() {
        inlineEditor.resetAll()
        focusedField = nil
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
        inlineEditor.isCanceling = true
        let commits = inlineEditor.dirtyCommitPlans(
            existingNotes: slot.notes,
            isFlowFlexible: slot.isFlowFlexible
        )
        let didChange = commits.reduce(false) { changed, commit in
            applyInlineEditCommit(commit, for: slot) || changed
        }

        selectedSession = nil
        selectedBusySlot = nil
        resetEditingState()

        if didChange {
            Task { await calendarService.fetchEvents(for: actionContext.selectedDate) }
        }
    }
    
    private func cancelTitleEdit() {
        inlineEditor.cancel(.title)
        focusedField = nil
        // onChange(of: focusedField) fires on the next runloop; clear the guard
        // after it has had a chance to run.
        DispatchQueue.main.async { inlineEditor.clearCancelGuard() }
    }

    private func cancelNotesEdit() {
        inlineEditor.cancel(.notes)
        focusedField = nil
        DispatchQueue.main.async { inlineEditor.clearCancelGuard() }
    }

    private func cancelURLEdit() {
        inlineEditor.cancel(.url)
        focusedField = nil
        DispatchQueue.main.async { inlineEditor.clearCancelGuard() }
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
        if dragMode == .move && groupDrag.isActive {
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
        if dragMode == .move && groupDrag.isActive {
            updates = groupDrag.previewTimes
        } else {
            updates = [slot.id: (start: newStart, end: newEnd)]
        }

        let baseSlots = elasticEditor.dragBaseSlots
        let originalsById = Dictionary(uniqueKeysWithValues: baseSlots.map { ($0.id, $0) })
        let hasChanges = updates.contains { entry in
            guard let original = originalsById[entry.key] else { return false }
            let target = entry.value
            return original.startTime != target.start || original.endTime != target.end
        }

        guard hasChanges else {
            elasticEditor.stagedSlots = baseSlots
            recalculateProjectedSchedule(using: baseSlots)
            resetDragState()
            return
        }

        let adjustedGapAfterBySlotId = elasticGapMap(
            adjustingForDraggedUpdates: updates,
            in: baseSlots
        )

        recordElasticUndoSnapshot(baseSlots)
        elasticEditor.stagedSlots = displaceBusySlots(
            baseSlots: baseSlots,
            draggedUpdates: updates,
            commitDraggedSlots: true,
            gapAfterBySlotId: adjustedGapAfterBySlotId
        )
        elasticEditor.emptySpaceAfterBySlotId = adjustedGapAfterBySlotId
        recalculateProjectedSchedule(using: elasticEditor.stagedSlots)
        onModeToast?("\(elasticChangeCount) staged")

        resetDragState()
    }

    /// Commit a group drag — every selected slot moves by the same translation atomically.
    private func commitGroupDrag() {
        let slotsById = Dictionary(uniqueKeysWithValues: timelineBusySlots(for: actionContext.selectedDate).map { ($0.id, $0) })

        var changes: [EventUndoManager.EventTimeChange] = []
        var committed: [(id: String, newStart: Date, newEnd: Date)] = []

        for (id, target) in groupDrag.previewTimes {
            guard let original = groupDrag.originalTimes[id],
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
        projectedSessionDrag.reset()
        elasticEditor.clearPreDragSnapshot()
        groupDrag.reset()
    }

    /// Cancel drag and revert all changes (called on Escape).
    private func cancelDrag() {
        // Revert displaced projected sessions
        if let snapshot = projectedSessionDrag.sessionsForDisplacementPass() {
            schedulingEngine.projectedSessions = snapshot
        }
        if isElasticEditing, let snapshot = elasticEditor.restorePreDragSnapshot() {
            elasticEditor.stagedSlots = snapshot
        }
        // Revert real-time schedule recalculation (calendar event drag)
        if dragSlotId != nil, !schedulingEngine.sessionsFrozen {
            if isElasticEditing {
                recalculateProjectedSchedule(using: elasticEditor.stagedSlots)
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
        let decision = projectedSessionDrag.prepareCommit(
            for: session,
            previewStart: dragPreviewStartTime,
            previewEnd: dragPreviewEndTime,
            currentSessions: schedulingEngine.projectedSessions
        )

        switch decision {
        case .restore(let snapshot):
            if let snapshot {
                schedulingEngine.projectedSessions = snapshot
            }
            resetDragState()
            return

        case .commit(let plan):
            schedulingEngine.projectedSessions = plan.sessions

            schedulingEngine.displaceProjectedSessions(
                draggedSessionId: plan.sessionId,
                draggedStart: plan.draggedStart,
                draggedEnd: plan.draggedEnd,
                busySlots: timelineBusySlots(for: actionContext.selectedDate),
                earliestTime: elasticAwareEarliestTime
            )

            let description = dragMode == .move ? "Move \(session.title)" : "Resize \(session.title)"
            eventUndoManager.record(plan.undoChange(
                description: description,
                postSnapshot: schedulingEngine.projectedSessions
            ))

            resetDragState()
        }
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
        applyUndoRedoChange(
            change,
            direction: .undo(hasRemainingSessionChanges: eventUndoManager.hasSessionChanges),
            operationDate: operationDate
        )
    }

    private func performRedo() {
        let operationDate = actionContext.selectedDate
        guard let change = eventUndoManager.redo() else { return }
        dismissTransientInteractionState()
        applyUndoRedoChange(change, direction: .redo, operationDate: operationDate)
    }

    private func applyUndoRedoChange(
        _ change: EventUndoManager.UndoableChange,
        direction: TimelineUndoRedoApplier.Direction,
        operationDate: Date
    ) {
        var scheduleState = TimelineUndoRedoApplier.ScheduleState(
            projectedSessions: schedulingEngine.projectedSessions,
            sessionsFrozen: schedulingEngine.sessionsFrozen
        )
        let result = TimelineUndoRedoApplier.apply(
            change,
            direction: direction,
            calendar: calendarService,
            schedule: &scheduleState
        )

        if schedulingEngine.projectedSessions != scheduleState.projectedSessions {
            schedulingEngine.projectedSessions = scheduleState.projectedSessions
        }
        if schedulingEngine.sessionsFrozen != scheduleState.sessionsFrozen {
            schedulingEngine.sessionsFrozen = scheduleState.sessionsFrozen
        }

        for followUp in result.undoManagerFollowUps {
            applyUndoManagerFollowUp(followUp)
        }
        for update in result.optimisticTimeUpdates {
            optimisticallyUpdateSlot(id: update.eventId, newStart: update.newStart, newEnd: update.newEnd)
        }

        guard result.shouldFetchEvents else { return }
        Task {
            await calendarService.fetchEvents(for: operationDate)
            if let id = result.selectedSlotRefreshId,
               let updated = calendarService.busySlots.first(where: { $0.id == id }),
               selectedBusySlot?.id == id {
                selectedBusySlot = updated
            }
        }
    }

    private func applyUndoManagerFollowUp(_ followUp: TimelineUndoRedoApplier.UndoManagerFollowUp) {
        switch followUp {
        case .pushRedoForRestoredDelete(let original, let newEventId):
            eventUndoManager.pushRedoForRestoredDelete(original: original, newEventId: newEventId)
        case .pushRedoForRestoredDeleteBatch(let originals, let newEventIds):
            eventUndoManager.pushRedoForRestoredDeleteBatch(originals: originals, newEventIds: newEventIds)
        case .pushRedoForUndoneCreate(let snapshot):
            eventUndoManager.pushRedoForUndoneCreate(snapshot)
        case .updateTopUndoCreate(let snapshot):
            eventUndoManager.updateTopUndoCreateId(snapshot)
        case .updateTopUndoSchedule(let snapshot):
            eventUndoManager.updateTopUndoSchedule(snapshot)
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
        if let idx = elasticEditor.stagedSlots.firstIndex(where: { $0.id == id }) {
            let old = elasticEditor.stagedSlots[idx]
            elasticEditor.stagedSlots[idx] = BusyTimeSlot(
                id: old.id, title: old.title, startTime: old.startTime, endTime: old.endTime,
                notes: notes, url: old.url, calendarName: old.calendarName,
                calendarColor: old.calendarColor, calendarIdentifier: old.calendarIdentifier
            )
        }
        if var originals = elasticEditor.originalSlots,
           let idx = originals.firstIndex(where: { $0.id == id }) {
            let old = originals[idx]
            originals[idx] = BusyTimeSlot(
                id: old.id, title: old.title, startTime: old.startTime, endTime: old.endTime,
                notes: notes, url: old.url, calendarName: old.calendarName,
                calendarColor: old.calendarColor, calendarIdentifier: old.calendarIdentifier
            )
            elasticEditor.replaceOriginalSlots(originals)
        }
    }
}

#Preview {
    TimelineView(selectedDate: Date(), startTime: Date())
        .environmentObject(CalendarService())
        .environmentObject(SchedulingEngine())
        .frame(width: 600, height: 800)

}

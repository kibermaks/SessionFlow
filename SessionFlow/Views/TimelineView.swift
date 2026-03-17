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

struct TimelineView: View {
    let selectedDate: Date
    let startTime: Date
    var onCopySuccess: ((CopyToastInfo) -> Void)? = nil
    var onModeToast: ((String) -> Void)? = nil

    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var schedulingEngine: SchedulingEngine
    @EnvironmentObject var sessionAwarenessService: SessionAwarenessService
    
    private let hourHeight: CGFloat = 90 // Zoomed in from 60
    private let timeColumnWidth: CGFloat = 55
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

    // MARK: - Drag Interaction State
    @State private var dragSlotId: String? = nil
    @State private var dragSessionId: UUID? = nil
    @State private var dragPreviewStartTime: Date? = nil
    @State private var dragPreviewEndTime: Date? = nil
    @State private var dragMode: DragMode = .none
    @State private var isShiftHeld: Bool = false
    @State private var flagsMonitor: Any? = nil
    @State private var keyDownMonitor: Any? = nil
    @State private var mouseDownMonitor: Any? = nil
    @StateObject private var eventUndoManager = EventUndoManager()
    @State private var eventsLocked: Bool = false
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
    
    private var isNarrow: Bool {
        // Use a reasonable threshold for narrow width
        containerWidth < 750
    }

    private var isExtraNarrow: Bool {
        // Use a reasonable threshold for narrow width
        containerWidth < 400
    }
    
    private var showingDetailSheet: Bool {
        selectedSession != nil || selectedBusySlot != nil
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
                containerWidth = geo.size.width
                flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                    isShiftHeld = event.modifierFlags.contains(.shift)
                    return event
                }
                // Use keyDown monitor for Esc (cancel drag) and undo/redo.
                keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    // Esc cancels active drag/resize or closes detail sheet
                    if event.keyCode == 53 {
                        if dragMode != .none {
                            cancelDrag()
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
                eventUndoManager.clear()
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
                                    Task { await calendarService.fetchEvents(for: selectedDate) }
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
                .foregroundColor(.white)
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
                .foregroundColor(.white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .help("Events from your selected calendars appear on the left side")
                
                // Center divider
                Rectangle()
                    .fill(Color.white.opacity(0.2))
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
                .foregroundColor(.white.opacity(0.5))
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
                    .foregroundColor(.white.opacity(0.4))
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
                Color.white.opacity(0.02)
                    .onAppear { scrollViewFrame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in scrollViewFrame = newFrame }
            }
        )
        .cornerRadius(12)
        .simultaneousGesture(TapGesture().onEnded { _ in
            NSApp.keyWindow?.makeFirstResponder(nil)
        })
    }
    
    private var eventsAreaView: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                hourGridLines
                
                if shouldShowCurrentTimeIndicator {
                    currentTimeIndicator(currentTime: effectiveNowTimeForIndicator, width: geometry.size.width)
                }
                
                // Existing events - left half
                ForEach(busySlotsWithLayout) { positionedSlot in
                    eventBlock(for: positionedSlot, containerWidth: geometry.size.width)
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

                    // Snap indicator line
                    let snapY = calculateYPosition(for: newStart)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: snapY))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: snapY))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundColor(Color.blue.opacity(0.4))
                    .allowsHitTesting(false)

                    // Preview block at new position
                    dragPreviewBlock(
                        slot: slot,
                        newStart: newStart,
                        newEnd: newEnd,
                        containerWidth: geometry.size.width
                    )
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
                    .foregroundColor(Color.blue.opacity(0.4))
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
                .fill(slot.calendarColor.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.blue.opacity(0.8), lineWidth: 2)
                )
                .shadow(color: Color.blue.opacity(0.3), radius: 8, y: 2)

            if blockHeight >= 16 {
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
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 1)
                    }
                    Spacer()
                }
                .frame(height: hourHeight)
            }
            // Bottom edge line
            Rectangle()
                .fill(Color.white.opacity(0.1))
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
                    .background(Color.white.opacity(0.15))
                    .foregroundColor(.white)
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

            // Lock/unlock event dragging
            Button {
                withAnimation { eventsLocked.toggle() }
                onModeToast?(eventsLocked ? "Events locked" : "Events unlocked")
            } label: {
                Image(systemName: eventsLocked ? "hand.raised.slash" : "hand.draw")
                    .frame(width: 16, height: 16)
                    .padding(8)
                    .background(eventsLocked ? Color.white.opacity(0.05) : Color.white.opacity(0.1))
                    .cornerRadius(6)
                    .foregroundColor(eventsLocked ? .white.opacity(0.35) : .white)
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: 0.2)
            .help(eventsLocked ? "Unlock dragging & resizing events and sessions" : "Lock all event and session positions")

            // Toggle night button
            Button(action: {
                withAnimation {
                    schedulingEngine.hideNightHours.toggle()
                }
                onModeToast?(schedulingEngine.hideNightHours ? "Night hours hidden" : "Night hours visible")
            }) {
                Image(systemName: schedulingEngine.hideNightHours ? "moon.stars.fill" : "moon.stars")
                    .padding(8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: 0.2)
            .help(schedulingEngine.hideNightHours ? "Show 00:00 - 06:00" : "Hide 00:00 - 06:00")
        }
    }
    
    private var legendPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session Types")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
            
            Divider().background(Color.white.opacity(0.1))
            
            ForEach(SessionType.allCases) { type in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(type.color)
                        .frame(width: 14, height: 14)
                    Text(type.rawValue)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.9))
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
                .foregroundColor(.white.opacity(0.7))
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

extension TimelineView {
    
    private struct PositionedBusySlot: Identifiable {
        let slot: BusyTimeSlot
        let column: Int
        var totalColumns: Int
        var id: String { slot.id }
    }
    
    private var filteredBusySlots: [BusyTimeSlot] {
        let excluded = calendarService.excludedCalendarIDs
        guard !excluded.isEmpty else { return calendarService.busySlots }
        return calendarService.busySlots.filter { slot in
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
    
    private var timeColumnView: some View {
        VStack(spacing: 0) {
            ForEach(visibleHours, id: \.self) { hour in
                HStack {
                    if hour == 24 && effectiveEndHour > 24 {
                        Text("next day")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange.opacity(0.6))
                            .offset(y: -7)
                    } else {
                        Text(formattedHour(hour))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(hour >= 24 ? .orange.opacity(0.5) : .white.opacity(0.5))
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
                    .foregroundColor(effectiveEndHour >= 24 ? .orange.opacity(0.5) : .white.opacity(0.5))
                    .offset(y: -7)
            }
            .frame(width: timeColumnWidth, height: 0, alignment: .topTrailing)
            .padding(.trailing, 8)
        }
    }
    
    private func formattedHour(_ hour: Int) -> String {
        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = hour
        
        // Handle hour 24 and beyond for formatting by shifting to next day
        if hour >= 24 {
            components.hour = hour - 24
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
    
    /// The upper bound for visible hours — driven by Schedule Until.
    private var effectiveEndHour: Int {
        if schedulingEngine.hideNightHours {
            return schedulingEngine.scheduleEndHour
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
    
    // ... (rest of file)
    
    // MARK: - Event Block (Busy) - Left Half
    
    private func eventBlock(for positionedSlot: PositionedBusySlot, containerWidth: CGFloat) -> some View {
        let slot = positionedSlot.slot
        let isDragging = dragSlotId == slot.id && dragMode != .none
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

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(slot.calendarColor.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(slot.calendarColor.opacity(0.5), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 1) {
                if height <= 25 {
                    HStack(spacing: 3) {
                        Text(slot.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text(startAndDurationString(start: slot.startTime, end: slot.endTime))
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                } else {
                    Text(slot.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(startAndDurationString(start: slot.startTime, end: slot.endTime))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                }

                if let url = slot.url, height > 35 {
                    Text(url.absoluteString)
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "3B82F6"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let notes = SessionAwarenessService.strippedNotes(slot.notes), height > 45 {
                    Text(notes)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: false)
                }
            }
            .padding(4)

            // Feedback badge for past events
            if slot.endTime < Date() && sessionAwarenessService.config.enabled && sessionAwarenessService.config.productivityEnabled {
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
                            dragMode = .move
                            NSCursor.closedHand.push()
                        }
                        dragSlotId = slot.id
                    }

                    switch dragMode {
                    case .move:
                        let duration = slot.endTime.timeIntervalSince(slot.startTime)
                        let originalY = calculateYPosition(for: slot.startTime)
                        let newY = originalY + value.translation.height
                        let rawDate = dateFromYOffset(newY)
                        let newStart = isShiftHeld ? rawDate : snapToInterval(rawDate)
                        dragPreviewStartTime = newStart
                        dragPreviewEndTime = newStart.addingTimeInterval(duration)

                    case .resizeTop:
                        let originalY = calculateYPosition(for: slot.startTime)
                        let newY = originalY + value.translation.height
                        let rawDate = dateFromYOffset(newY)
                        let newStart = isShiftHeld ? rawDate : snapToInterval(rawDate)
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
                            recalculateWithDraggedSlot(slot, newStart: previewStart, newEnd: previewEnd)
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
        .contextMenu {
            Button("View & Edit Event Details") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    selectedSession = nil
                    selectedBusySlot = slot
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    deleteBusySlot(slot)
                }
            }
            Divider()
            Menu("Copy to...") {
                ForEach(copyTargetDays(), id: \.date) { target in
                    Button(target.label) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            let result = calendarService.copyEventToDay(eventId: slot.id, targetDate: target.date)
                            if result.success, let eventId = result.newEventId, let targetStart = result.targetStartTime {
                                onCopySuccess?(CopyToastInfo(title: slot.title, targetLabel: target.label, targetDate: target.date, targetStartTime: targetStart, newEventId: eventId))
                                Task { await calendarService.fetchEvents(for: selectedDate) }
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
                        copyTargetDate = Date()
                        showingCopyDatePicker = true
                    }
                }
            }
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
        let isCompact = height < 25
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
                    .fill(session.type.color.opacity(0.55))
                    .overlay(
                        DiagonalStripesPattern(
                            color: session.type.color.opacity(0.4),
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
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                .foregroundColor(.white)
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
                    .foregroundColor(.white)

                    Text(startAndDurationString(start: session.startTime, end: session.endTime))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
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
                        let newStart = isShiftHeld ? rawDate : snapToInterval(rawDate)
                        dragPreviewStartTime = newStart
                        dragPreviewEndTime = newStart.addingTimeInterval(duration)

                    case .resizeTop:
                        let originalY = calculateYPosition(for: session.startTime)
                        let newY = originalY + value.translation.height
                        let rawDate = dateFromYOffset(newY)
                        let newStart = isShiftHeld ? rawDate : snapToInterval(rawDate)
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
                                busySlots: calendarService.busySlots,
                                earliestTime: startTime
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
                        selectedSession = nil
                        selectedBusySlot = nil
                        resetEditingState()
                    }
                }
            
            // Detail card
            VStack(alignment: .leading, spacing: 12) {
                if let session = selectedSession {
                    sessionDetailContent(session)
                } else if let slot = selectedBusySlot {
                    busySlotDetailContent(slot)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "1E293B"))
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
                await calendarService.fetchEvents(for: selectedDate)
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
                await calendarService.fetchEvents(for: selectedDate)
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
                    .foregroundColor(.white)
                Spacer()
                Button {
                    selectedSession = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .hoverEffect(brightness: 0.3)
            }

            Divider().background(Color.white.opacity(0.1))

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
            .foregroundColor(.white.opacity(0.8))
        }
    }
    
    private func busySlotDetailContent(_ slot: BusyTimeSlot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "calendar")
                    .font(.system(size: 18))
                    .foregroundColor(slot.calendarColor)
                    .frame(width: 18)
                
                // Inline editable title
                if isEditingTitle {
                    TextField("Event title", text: $editingTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
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
                        .foregroundColor(.white)
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
                    selectedBusySlot = nil
                    resetEditingState()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .hoverEffect(brightness: 0.3)
            }
            
            Divider().background(Color.white.opacity(0.1))
            
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
                
                // Notes section with inline editing
                VStack(alignment: .leading, spacing: 4) {
                    Divider().background(Color.white.opacity(0.1))
                    
                    if isEditingNotes {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes:")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                            TextEditor(text: $editingNotes)
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                                .scrollContentBackground(.hidden)
                                .background(Color.white.opacity(0.05))
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
                    } else if let displayNotes = SessionRating.stripFeedbackTags(slot.notes), !displayNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes:")
                                .font(.system(size: 12, weight: .bold))
                            Text(displayNotes)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let stripped = SessionRating.stripFeedbackTags(slot.notes) ?? ""
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
                        .foregroundColor(.white.opacity(0.5))
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
                        Divider().background(Color.white.opacity(0.1))
                        feedbackPicker(for: slot)
                    }
                }

                // URL section with inline editing
                VStack(alignment: .leading, spacing: 4) {
                    Divider().background(Color.white.opacity(0.1))

                    if isEditingURL {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("URL:")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                            TextField("https://example.com", text: $editingURL)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(6)
                                .background(Color.white.opacity(0.05))
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
                        .foregroundColor(.white.opacity(0.5))
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
            .foregroundColor(.white.opacity(0.8))
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
                    let stripped = SessionRating.stripFeedbackTags(slot.notes) ?? ""
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
        eventUndoManager.recordDelete(snapshot)
        if calendarService.deleteEvent(identifier: slot.id) {
            selectedBusySlot = nil
            selectedSession = nil
            Task { await calendarService.fetchEvents(for: selectedDate) }
        }
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
        let isShowingPopover = Binding(
            get: { feedbackPopoverEventId == slot.id },
            set: { if !$0 { feedbackPopoverEventId = nil } }
        )

        Button {
            feedbackPopoverEventId = (feedbackPopoverEventId == slot.id) ? nil : slot.id
        } label: {
            if let rating = rating {
                feedbackBadgeIcon(for: rating)
            } else {
                // No feedback yet — show subtle empty badge
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(brightness: 0.2)
        .popover(isPresented: isShowingPopover, arrowEdge: .trailing) {
            feedbackPopoverContent(for: slot, existingRating: rating)
        }
    }

    private func feedbackBadgeIcon(for rating: SessionRating) -> some View {
        let (color, icon): (Color, String) = {
            switch rating {
            case .rocket: return (.orange, "flame.fill")
            case .completed: return (.green, "checkmark")
            case .partial: return (.yellow, "circle.lefthalf.filled")
            case .skipped: return (.red, "xmark")
            }
        }()

        return Circle()
            .fill(color.opacity(0.25))
            .frame(width: 14, height: 14)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(color)
            )
    }

    private func feedbackPopoverContent(for slot: BusyTimeSlot, existingRating: SessionRating?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existingRating != nil ? "Update feedback" : "How was this session?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            HStack(spacing: 8) {
                ForEach(SessionRating.allCases, id: \.rawValue) { rating in
                    Button {
                        calendarService.setFeedbackTag(eventId: slot.id, rating: rating)
                        Task { await calendarService.fetchEvents(for: selectedDate) }
                        feedbackPopoverEventId = nil
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: rating.icon)
                                .font(.system(size: 11, weight: .medium))
                            Text(rating.label)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
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
        }
        .padding(14)
        .frame(minWidth: 360)
    }

    private func ratingColor(_ rating: SessionRating) -> Color {
        switch rating {
        case .rocket: return .orange
        case .completed: return .green
        case .partial: return .yellow
        case .skipped: return .red
        }
    }

    // MARK: - Feedback Picker (in event details)

    private func feedbackPicker(for slot: BusyTimeSlot) -> some View {
        let currentRating = SessionRating.fromNotes(slot.notes)

        return HStack(spacing: 6) {
            Text("Feedback:")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.8))

            Spacer()

            // "Not set" button
            Button {
                clearFeedbackTag(for: slot)
            } label: {
                Text("–")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(currentRating == nil ? 0.8 : 0.35))
                    .frame(width: 24, height: 22)
                    .background(currentRating == nil ? Color.white.opacity(0.12) : Color.clear)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(currentRating == nil ? 0.25 : 0.1), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: 0.2)
            .help("Not set")

            ForEach(SessionRating.allCases, id: \.rawValue) { rating in
                Button {
                    calendarService.setFeedbackTag(eventId: slot.id, rating: rating)
                    Task {
                        await calendarService.fetchEvents(for: selectedDate)
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
        calendarService.clearFeedbackTag(eventId: slot.id)
        Task {
            await calendarService.fetchEvents(for: selectedDate)
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
            Task {
                await calendarService.fetchEvents(for: selectedDate)
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

        // Preserve feedback tag from the original notes (session type tags are user-editable)
        let rawNotes = slot.notes ?? ""
        var feedbackTag = ""
        for tag in SessionRating.allTags {
            if rawNotes.contains(tag) { feedbackTag = " " + tag; break }
        }
        let finalNotes = (normalizedNew ?? "") + feedbackTag

        let success = calendarService.updateEvent(
            eventId: slot.id,
            title: nil,
            notes: finalNotes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : finalNotes,
            url: nil
        )
        
        if success {
            Task {
                await calendarService.fetchEvents(for: selectedDate)
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
            Task {
                await calendarService.fetchEvents(for: selectedDate)
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
    
    private func cancelTitleEdit() {
        isCanceling = true
        isEditingTitle = false
        editingTitle = ""
        originalTitle = ""
        focusedField = nil
        isCanceling = false
    }
    
    private func cancelNotesEdit() {
        isCanceling = true
        isEditingNotes = false
        editingNotes = ""
        originalNotes = ""
        focusedField = nil
        isCanceling = false
    }
    
    private func cancelURLEdit() {
        isCanceling = true
        isEditingURL = false
        editingURL = ""
        originalURL = ""
        focusedField = nil
        isCanceling = false
    }

    // MARK: - Drag Commit

    private func commitDrag(for slot: BusyTimeSlot) {
        guard let newStart = dragPreviewStartTime,
              let newEnd = dragPreviewEndTime else {
            resetDragState()
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
            await calendarService.fetchEvents(for: selectedDate)
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
    }

    /// Cancel drag and revert all changes (called on Escape).
    private func cancelDrag() {
        // Revert displaced projected sessions
        if let snapshot = preDisplacementSessions {
            schedulingEngine.projectedSessions = snapshot
        }
        // Revert real-time schedule recalculation (calendar event drag)
        if dragSlotId != nil, !schedulingEngine.sessionsFrozen {
            recalculateWithOriginalSlots()
        }
        dragCancelled = true
        resetDragState()
    }

    /// Recalculates schedule using the original (unmodified) busy slots.
    private func recalculateWithOriginalSlots() {
        let planningExists = calendarService.hasPlanningSession(for: selectedDate)
        let existing = calendarService.countExistingSessions(
            for: selectedDate,
            workCalendar: CalendarDescriptor(
                name: schedulingEngine.workCalendarName,
                identifier: schedulingEngine.workCalendarIdentifier
            ),
            sideCalendar: CalendarDescriptor(
                name: schedulingEngine.sideCalendarName,
                identifier: schedulingEngine.sideCalendarIdentifier
            ),
            deepConfig: schedulingEngine.deepSessionConfig
        )
        _ = schedulingEngine.generateSchedule(
            startTime: startTime,
            baseDate: selectedDate,
            busySlots: calendarService.busySlots,
            includePlanning: !planningExists,
            existingSessions: (work: existing.work, side: existing.side, deep: existing.deep),
            existingTitles: existing.titles
        )
    }

    /// Recalculates projected schedule using modified busy slots (during calendar event drag).
    private func recalculateWithDraggedSlot(_ slot: BusyTimeSlot, newStart: Date, newEnd: Date) {
        guard !schedulingEngine.sessionsFrozen else { return }

        // Build modified busy slots with the dragged event at its new position
        var modifiedSlots = calendarService.busySlots
        if let idx = modifiedSlots.firstIndex(where: { $0.id == slot.id }) {
            let old = modifiedSlots[idx]
            modifiedSlots[idx] = BusyTimeSlot(
                id: old.id, title: old.title, startTime: newStart, endTime: newEnd,
                notes: old.notes, url: old.url, calendarName: old.calendarName,
                calendarColor: old.calendarColor, calendarIdentifier: old.calendarIdentifier
            )
        }

        let planningExists = calendarService.hasPlanningSession(for: selectedDate)
        let existing = calendarService.countExistingSessions(
            for: selectedDate,
            workCalendar: CalendarDescriptor(
                name: schedulingEngine.workCalendarName,
                identifier: schedulingEngine.workCalendarIdentifier
            ),
            sideCalendar: CalendarDescriptor(
                name: schedulingEngine.sideCalendarName,
                identifier: schedulingEngine.sideCalendarIdentifier
            ),
            deepConfig: schedulingEngine.deepSessionConfig
        )

        _ = schedulingEngine.generateSchedule(
            startTime: startTime,
            baseDate: selectedDate,
            busySlots: modifiedSlots,
            includePlanning: !planningExists,
            existingSessions: (work: existing.work, side: existing.side, deep: existing.deep),
            existingTitles: existing.titles
        )
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
            busySlots: calendarService.busySlots,
            earliestTime: startTime
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

        let isCompact = blockHeight < 25

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(session.type.color.opacity(0.5))
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
        guard let change = eventUndoManager.undo() else { return }
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
                    Task { await calendarService.fetchEvents(for: selectedDate) }
                }
            }
        case .delete(let snap):
            if let newId = calendarService.restoreEvent(snap) {
                eventUndoManager.pushRedoForRestoredDelete(original: snap, newEventId: newId)
                Task { await calendarService.fetchEvents(for: selectedDate) }
            }
        case .schedule(let snap):
            // Undo: delete created events, restore projected sessions
            for eventId in snap.eventIds {
                _ = calendarService.deleteEvent(identifier: eventId)
            }
            schedulingEngine.projectedSessions.append(contentsOf: snap.sessions)
            schedulingEngine.projectedSessions.sort { $0.startTime < $1.startTime }
            Task { await calendarService.fetchEvents(for: selectedDate) }
        }
    }

    private func performRedo() {
        guard let change = eventUndoManager.redo() else { return }
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
                    Task { await calendarService.fetchEvents(for: selectedDate) }
                }
            }
        case .delete(let snap):
            if calendarService.deleteEvent(identifier: snap.eventId) {
                Task { await calendarService.fetchEvents(for: selectedDate) }
            }
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
                Task { await calendarService.fetchEvents(for: selectedDate) }
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
}

#Preview {
    TimelineView(selectedDate: Date(), startTime: Date())
        .environmentObject(CalendarService())
        .environmentObject(SchedulingEngine())
        .frame(width: 600, height: 800)
        .background(Color(hex: "0F172A"))
}

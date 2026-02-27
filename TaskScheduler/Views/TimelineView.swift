import SwiftUI
import Combine
import AppKit

struct TimelineView: View {
    let selectedDate: Date
    let startTime: Date
    
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var schedulingEngine: SchedulingEngine
    
    private let hourHeight: CGFloat = 90 // Zoomed in from 60
    private let timeColumnWidth: CGFloat = 55
    private let currentTimeTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    
    
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
    @State private var showNod = false
    @State private var currentTime = Date()

    // MARK: - Drag Interaction State
    @State private var dragSlotId: String? = nil
    @State private var dragPreviewStartTime: Date? = nil
    @State private var dragPreviewEndTime: Date? = nil
    @State private var dragMode: DragMode = .none
    @State private var isShiftHeld: Bool = false
    @State private var flagsMonitor: Any? = nil
    @State private var keyDownMonitor: Any? = nil
    @StateObject private var eventUndoManager = EventUndoManager()
    @State private var eventsLocked: Bool = false

    private enum DragMode: Equatable {
        case none
        case move
        case resizeTop
        case resizeBottom
    }
    
    private var isNarrow: Bool {
        // Use a reasonable threshold for narrow width
        containerWidth < 650
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
                // Use keyDown monitor for undo/redo so it works regardless of keyboard layout.
                // Physical key code 6 = Z key on any layout.
                keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
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
            }
            .onChange(of: geo.size.width) { _, newWidth in
                containerWidth = newWidth
            }
            .onChange(of: selectedDate) { _, _ in
                eventUndoManager.clear()
            }
            .onReceive(currentTimeTimer) { date in
                currentTime = date
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
                    .scaleEffect(0.8)
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
                .onAppear { scrollToStartTime(proxy: proxy) }
                .onChange(of: startTime) { _, _ in scrollToStartTime(proxy: proxy) }
            }
        }
        .background(Color.white.opacity(0.02))
        .cornerRadius(12)
    }
    
    private var eventsAreaView: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                hourGridLines
                
                if Calendar.current.isDateInToday(selectedDate) {
                    currentTimeIndicator(currentTime: currentTime, width: geometry.size.width)
                }
                
                // Existing events - left half
                ForEach(busySlotsWithLayout) { positionedSlot in
                    eventBlock(for: positionedSlot, containerWidth: geometry.size.width)
                }
                
                // Projected sessions - right half
                ForEach(filteredProjectedSessions) { session in
                    projectedSessionBlock(for: session, containerWidth: geometry.size.width)
                }

                // Drag preview overlay
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
                        Text(timeRangeString(start: newStart, end: newEnd))
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
    
    private var hourGridLines: some View {
        VStack(spacing: 0) {
            ForEach(visibleHours, id: \.self) { _ in
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 1)
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
            } label: {
                Image(systemName: eventsLocked ? "hand.raised.slash" : "hand.draw")
                    .frame(width: 16, height: 16)
                    .padding(8)
                    .background(eventsLocked ? Color.white.opacity(0.05) : Color.white.opacity(0.1))
                    .cornerRadius(6)
                    .foregroundColor(eventsLocked ? .white.opacity(0.35) : .white)
            }
            .buttonStyle(.plain)
            .help(eventsLocked ? "Click to drag & resize calendar events" : "Click to lock calendar event positions")

            // Toggle night button
            Button(action: {
                withAnimation {
                    schedulingEngine.hideNightHours.toggle()
                }
            }) {
                Image(systemName: schedulingEngine.hideNightHours ? "moon.stars.fill" : "moon.stars")
                    .padding(8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
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
                    Text(formattedHour(hour))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .offset(y: -7)
                }
                .frame(width: timeColumnWidth, height: hourHeight, alignment: .topTrailing)
                .padding(.trailing, 8)
                .id("hour-\(hour)")
            }
            
            // End of day mark
            HStack {
                let endHour = schedulingEngine.hideNightHours ? schedulingEngine.dayEndHour : 24
                Text(formattedHour(endHour))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
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
    
    private var visibleHours: [Int] {
        if schedulingEngine.hideNightHours {
            return Array(schedulingEngine.dayStartHour..<schedulingEngine.dayEndHour)
        } else {
            return Array(0..<24)
        }
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
                Text(slot.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                if height > 25 {
                    Text(timeRangeString(start: slot.startTime, end: slot.endTime))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                }

                if let url = slot.url, height > 40 {
                    Text(url.absoluteString)
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "3B82F6"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let notes = slot.notes, !notes.isEmpty, height > 45 {
                    Text(notes)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: false)
                }
            }
            .padding(4)
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
                    guard !eventsLocked else { return }
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
                }
                .onEnded { _ in
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
                selectedSession = nil
                selectedBusySlot = slot
            }
        }
    }
    
    // MARK: - Projected Session Block - Right Half with Tooltip
    
    private func projectedSessionBlock(for session: ScheduledSession, containerWidth: CGFloat) -> some View {
        let yPos = calculateYPosition(for: session.startTime)
        let height = calculateHeight(from: session.startTime, to: session.endTime)
        let blockHeight = max(height, 20)
        let blockWidth = (containerWidth / 2) - 24  // Extra space for scrollbar
        let xOffset = containerWidth / 2 + 8
        let isCompact = height < 25
        
        // Calculate center position for .position() modifier
        let centerX = xOffset + blockWidth / 2
        let centerY = yPos + blockHeight / 2
        
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(session.type.color.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
                        .foregroundColor(session.type.color)
                )
                .shadow(color: session.type.color.opacity(0.3), radius: 3, y: 1)
            
            if isCompact {
                HStack(spacing: 3) {
                    Image(systemName: session.type.icon)
                        .font(.system(size: 10))
                    Text(session.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
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
                    
                    Text(timeRangeString(start: session.startTime, end: session.endTime))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                    
                    if height > 65 {
                        Text("\(session.durationMinutes) min")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(4)
            }
        }
        .frame(width: blockWidth, height: blockHeight)
        .position(x: centerX, y: centerY)
        .onTapGesture(count: 2) {
            selectedBusySlot = nil
            selectedSession = session
        }
        .contextMenu {
            Button {
                selectedBusySlot = nil
                selectedSession = session
            } label: {
                Label("View Details", systemImage: "info.circle")
            }
            Button {
                scheduleProjectedSession(session)
            } label: {
                Label("Schedule Session", systemImage: "calendar.badge.plus")
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
            schedulingEngine.schedulingMessage = "Scheduled \(session.title) -> \(session.calendarName)"
            schedulingEngine.projectedSessions.removeAll { $0.id == session.id }
            if selectedSession?.id == session.id {
                selectedSession = nil
            }
            Task {
                await calendarService.fetchEvents(for: selectedDate)
            }
        } else {
            schedulingEngine.schedulingMessage = "Failed to schedule \(session.title)."
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
                    } else if let notes = slot.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes:")
                                .font(.system(size: 12, weight: .bold))
                            Text(notes)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            originalNotes = notes
                            editingNotes = notes
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
                    originalNotes = slot.notes ?? ""
                    editingNotes = slot.notes ?? ""
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
        
        let success = calendarService.updateEvent(
            eventId: slot.id,
            title: nil,
            notes: normalizedNew,
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
        }

        Task {
            await calendarService.fetchEvents(for: selectedDate)
        }

        resetDragState()
    }

    private func resetDragState() {
        dragMode = .none
        dragSlotId = nil
        dragPreviewStartTime = nil
        dragPreviewEndTime = nil
    }

    // MARK: - Undo / Redo

    private func performUndo() {
        guard let change = eventUndoManager.undo() else { return }
        let success = calendarService.updateEventTime(
            eventId: change.eventId,
            newStart: change.newStartTime,
            newEnd: change.newEndTime
        )
        if success {
            Task { await calendarService.fetchEvents(for: selectedDate) }
        }
    }

    private func performRedo() {
        guard let change = eventUndoManager.redo() else { return }
        let success = calendarService.updateEventTime(
            eventId: change.eventId,
            newStart: change.newStartTime,
            newEnd: change.newEndTime
        )
        if success {
            Task { await calendarService.fetchEvents(for: selectedDate) }
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

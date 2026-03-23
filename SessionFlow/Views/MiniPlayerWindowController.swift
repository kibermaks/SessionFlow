import AppKit
import SwiftUI
import Combine

class MiniPlayerWindowController: NSObject, ObservableObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private weak var awarenessService: SessionAwarenessService?
    private var mouseMonitor: Any?
    private var cursorMonitor: Any?
    private var cursorOnEdge = false
    private var windowObserver: Any?

    private enum DragMode { case resizeLeft, resizeRight }
    private var dragMode: DragMode?
    private var dragStartMouse: NSPoint = .zero
    private var dragStartFrame: NSRect = .zero
    private let edgeWidth: CGFloat = 8

    func setup(awarenessService: SessionAwarenessService, audioService: SessionAudioService) {
        self.awarenessService = awarenessService

        awarenessService.$isCollapsed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] collapsed in
                if collapsed {
                    self?.showPanel(awarenessService: awarenessService, audioService: audioService)
                } else if self?.panel != nil {
                    self?.hidePanel()
                }
            }
            .store(in: &cancellables)
    }

    private func showPanel(awarenessService: SessionAwarenessService, audioService: SessionAudioService) {
        guard panel == nil else { return }

        if let mainWindow = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) {
            let frame = mainWindow.frame
            awarenessService.config.mainWindowFrame = CodableRect(
                x: frame.origin.x, y: frame.origin.y,
                width: frame.size.width, height: frame.size.height
            )
            mainWindow.orderOut(nil)
        }

        let miniView = MiniPlayerView(awarenessService: awarenessService, audioService: audioService, onHeightChange: { [weak self] height in
            DispatchQueue.main.async {
                self?.updatePanelHeight(height)
            }
        })
        let hostingView = NSHostingView(rootView: miniView)
        hostingView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hostingView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let defaultWidth: CGFloat = 620
        let minWidth: CGFloat = 500
        let defaultHeight: CGFloat = 56

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let defaultRect = NSRect(
            x: screenFrame.midX - defaultWidth / 2,
            y: screenFrame.maxY - defaultHeight - 40,
            width: defaultWidth,
            height: defaultHeight
        )

        let panelRect: NSRect
        if let saved = awarenessService.config.miniPlayerFrame {
            let clampedWidth = max(minWidth, saved.width)
            let candidate = NSRect(x: saved.x, y: saved.y, width: clampedWidth, height: defaultHeight)
            panelRect = isRectOnScreen(candidate) ? candidate : defaultRect
        } else {
            panelRect = defaultRect
        }

        let newPanel = NSPanel(
            contentRect: panelRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .floating
        newPanel.hidesOnDeactivate = false
        newPanel.isMovableByWindowBackground = true
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let containerView = NSView()
        containerView.addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        newPanel.contentView = containerView
        newPanel.delegate = self
        newPanel.minSize = NSSize(width: minWidth, height: defaultHeight)
        newPanel.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 200)
        newPanel.acceptsMouseMovedEvents = true
        newPanel.orderFront(nil)

        self.panel = newPanel

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self = self, let panel = self.panel else { return event }
            guard event.window === panel else { return event }
            return self.handlePanelMouse(event)
        }

        // When main window appears while mini player is active (e.g. dock icon click),
        // close the mini player and properly restore the main window frame
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self, self.panel != nil,
                  let window = notification.object as? NSWindow,
                  !(window is NSPanel) else { return }
            // Restore saved frame if it's still on a connected screen
            if let saved = self.awarenessService?.config.mainWindowFrame {
                let rect = NSRect(x: saved.x, y: saved.y, width: saved.width, height: saved.height)
                if self.isRectOnScreen(rect) {
                    window.setFrame(rect, display: true)
                }
            }
            // Collapse the mini player normally
            self.awarenessService?.isCollapsed = false
        }

        cursorMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseEntered, .mouseExited]) { [weak self] event in
            guard let self = self, let panel = self.panel else { return event }
            guard event.window === panel else {
                if self.cursorOnEdge { NSCursor.arrow.set(); self.cursorOnEdge = false }
                return event
            }
            let loc = event.locationInWindow
            let onEdge = loc.x <= self.edgeWidth || loc.x >= panel.frame.width - self.edgeWidth
            if onEdge && !self.cursorOnEdge {
                NSCursor.resizeLeftRight.push()
                self.cursorOnEdge = true
            } else if !onEdge && self.cursorOnEdge {
                NSCursor.pop()
                self.cursorOnEdge = false
            }
            return event
        }
    }

    private func handlePanelMouse(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDown:
            let loc = event.locationInWindow
            guard let panel = panel else { return event }
            dragStartMouse = NSEvent.mouseLocation
            dragStartFrame = panel.frame

            if loc.x <= edgeWidth {
                dragMode = .resizeLeft
                return nil
            } else if loc.x >= panel.frame.width - edgeWidth {
                dragMode = .resizeRight
                return nil
            }
            dragMode = nil
            return event // pass through — system handles native window drag

        case .leftMouseDragged:
            guard let panel = panel, let mode = dragMode else { return event }
            let mouse = NSEvent.mouseLocation
            let dx = mouse.x - dragStartMouse.x

            var newFrame = dragStartFrame
            switch mode {
            case .resizeLeft:
                let maxDx = dragStartFrame.width - panel.minSize.width
                let clamped = min(dx, maxDx)
                newFrame.origin.x = dragStartFrame.origin.x + clamped
                newFrame.size.width = dragStartFrame.width - clamped
            case .resizeRight:
                newFrame.size.width = max(panel.minSize.width, dragStartFrame.width + dx)
            }
            panel.setFrame(newFrame, display: false)
            return nil

        case .leftMouseUp:
            if dragMode != nil {
                dragMode = nil
                savePanelFrame()
                return nil
            }
            return event

        default:
            return event
        }
    }

    private func savePanelFrame() {
        guard let panel = panel else { return }
        let frame = panel.frame
        awarenessService?.config.miniPlayerFrame = CodableRect(
            x: frame.origin.x, y: frame.origin.y,
            width: frame.size.width, height: frame.size.height
        )
    }

    private func hidePanel() {
        if let monitor = mouseMonitor { NSEvent.removeMonitor(monitor); mouseMonitor = nil }
        if let monitor = cursorMonitor { NSEvent.removeMonitor(monitor); cursorMonitor = nil }
        if let observer = windowObserver { NotificationCenter.default.removeObserver(observer); windowObserver = nil }
        if cursorOnEdge { NSCursor.pop(); cursorOnEdge = false }

        guard let panel = panel else { return }

        savePanelFrame()

        panel.orderOut(nil)
        self.panel = nil

        if let mainWindow = NSApp.windows.first(where: { !($0 is NSPanel) }) {
            if let saved = awarenessService?.config.mainWindowFrame {
                let rect = NSRect(x: saved.x, y: saved.y, width: saved.width, height: saved.height)
                if isRectOnScreen(rect) {
                    mainWindow.setFrame(rect, display: true)
                }
            }
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func updatePanelHeight(_ newHeight: CGFloat) {
        guard let panel = panel else { return }
        guard dragMode == nil else { return }
        guard newHeight > 0, abs(panel.frame.height - newHeight) > 1 else { return }

        var frame = panel.frame
        frame.origin.y += frame.size.height - newHeight
        frame.size.height = newHeight

        panel.minSize.height = newHeight
        panel.maxSize.height = newHeight

        panel.setFrame(frame, display: true)
    }

    /// Check if at least a portion of the rect is visible on any connected screen.
    private func isRectOnScreen(_ rect: NSRect) -> Bool {
        let minVisible: CGFloat = 50
        return NSScreen.screens.contains { screen in
            let intersection = screen.frame.intersection(rect)
            return intersection.width >= minVisible && intersection.height >= minVisible
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        savePanelFrame()
    }

    func windowDidResize(_ notification: Notification) {
        savePanelFrame()
    }
}


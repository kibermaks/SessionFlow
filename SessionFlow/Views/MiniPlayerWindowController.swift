import AppKit
import SwiftUI
import Combine

class MiniPlayerWindowController: NSObject, ObservableObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private weak var awarenessService: SessionAwarenessService?

    func setup(awarenessService: SessionAwarenessService, audioService: SessionAudioService) {
        self.awarenessService = awarenessService

        // React to both collapsed state and active session changes
        awarenessService.$isCollapsed
            .combineLatest(awarenessService.$isActive)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] collapsed, isActive in
                if collapsed && isActive {
                    self?.showPanel(awarenessService: awarenessService, audioService: audioService)
                } else {
                    if self?.panel != nil {
                        self?.hidePanel()
                    }
                    // Reset collapsed state when session ends
                    if !isActive && collapsed {
                        awarenessService.isCollapsed = false
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func showPanel(awarenessService: SessionAwarenessService, audioService: SessionAudioService) {
        guard panel == nil else { return }

        // Save main window frame and hide it
        if let mainWindow = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) {
            let frame = mainWindow.frame
            awarenessService.config.mainWindowFrame = CodableRect(
                x: frame.origin.x, y: frame.origin.y,
                width: frame.size.width, height: frame.size.height
            )
            mainWindow.orderOut(nil)
        }

        let miniView = MiniPlayerView(awarenessService: awarenessService, audioService: audioService)
        let hostingView = NSHostingView(rootView: miniView)

        let defaultWidth: CGFloat = 620
        let defaultHeight: CGFloat = 80

        let panelRect: NSRect
        if let saved = awarenessService.config.miniPlayerFrame {
            panelRect = NSRect(x: saved.x, y: saved.y, width: saved.width, height: saved.height)
        } else {
            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
            panelRect = NSRect(
                x: screenFrame.midX - defaultWidth / 2,
                y: screenFrame.maxY - defaultHeight - 40,
                width: defaultWidth,
                height: defaultHeight
            )
        }

        let newPanel = NSPanel(
            contentRect: panelRect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .floating
        newPanel.isMovableByWindowBackground = true
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.contentView = hostingView
        newPanel.delegate = self
        newPanel.minSize = NSSize(width: 500, height: defaultHeight)
        newPanel.maxSize = NSSize(width: 960, height: defaultHeight)
        newPanel.orderFront(nil)

        self.panel = newPanel
    }

    private func hidePanel() {
        guard let panel = panel else { return }

        // Save mini-player frame
        let frame = panel.frame
        awarenessService?.config.miniPlayerFrame = CodableRect(
            x: frame.origin.x, y: frame.origin.y,
            width: frame.size.width, height: frame.size.height
        )

        panel.orderOut(nil)
        self.panel = nil

        // Restore and show main window
        if let mainWindow = NSApp.windows.first(where: { !($0 is NSPanel) }) {
            if let saved = awarenessService?.config.mainWindowFrame {
                let rect = NSRect(x: saved.x, y: saved.y, width: saved.width, height: saved.height)
                mainWindow.setFrame(rect, display: true)
            }
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard let panel = panel else { return }
        let frame = panel.frame
        awarenessService?.config.miniPlayerFrame = CodableRect(
            x: frame.origin.x, y: frame.origin.y,
            width: frame.size.width, height: frame.size.height
        )
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel = panel else { return }
        let frame = panel.frame
        awarenessService?.config.miniPlayerFrame = CodableRect(
            x: frame.origin.x, y: frame.origin.y,
            width: frame.size.width, height: frame.size.height
        )
    }
}

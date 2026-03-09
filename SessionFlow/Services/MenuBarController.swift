import AppKit
import Combine
import SwiftUI

class MenuBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private weak var awarenessService: SessionAwarenessService?

    func setup(awarenessService: SessionAwarenessService) {
        self.awarenessService = awarenessService

        // Observe config changes to show/hide (both showMenuBarItem AND enabled)
        awarenessService.$config
            .map { $0.showMenuBarItem && $0.enabled }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                if show { self?.show() } else { self?.hide() }
            }
            .store(in: &cancellables)

        // Observe session state for updates
        awarenessService.objectWillChange
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                }
            }
            .store(in: &cancellables)
    }

    func show() {
        guard statusItem == nil else { return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(statusItemClicked(_:))
        statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem?.menu = nil
        updateStatusItem()
    }

    func hide() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "SessionFlow"
        let headerItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        // Reset menu so left-click works normally again
        statusItem?.menu = nil
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button, let service = awarenessService else { return }

        if service.isActive {
            // Show session type icon + time metric
            let iconName = service.isBusySlotMode ? "calendar" : (service.currentSessionType?.icon ?? "circle")
            let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Session")
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = image?.withSymbolConfiguration(config)

            // Time text
            let time: TimeInterval
            let suffix: String
            switch service.timeDisplayMode {
            case .remaining:
                time = service.remaining
                suffix = ""
            case .elapsed:
                time = service.elapsed
                suffix = ""
            }
            let totalSeconds = max(0, Int(time))
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60
            let timeStr = hours > 0
                ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
                : String(format: "%02d:%02d", minutes, seconds)
            let attributed = NSAttributedString(
                string: " \(timeStr)\(suffix)",
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)]
            )
            button.attributedTitle = attributed
        } else {
            // Idle: show generic icon, no title
            let image = NSImage(systemSymbolName: "eye.circle", accessibilityDescription: "Session Awareness")
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            button.image = image?.withSymbolConfiguration(config)
            button.attributedTitle = NSAttributedString(string: "")
        }
    }
}

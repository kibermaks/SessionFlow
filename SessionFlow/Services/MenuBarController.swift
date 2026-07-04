import AppKit
import Combine
import SwiftUI

class MenuBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var flashGeneration = 0
    private var menuTrackingTimer: Timer?
    private weak var awarenessService: SessionAwarenessService?
    private var openMainWindow: (() -> Void)?
    private lazy var statusStackedLensIcon = makeStackedLensIcon(size: 18)
    private lazy var menuStackedLensIcon = makeStackedLensIcon(size: 16)
    private lazy var smallStackedLensIcon = makeStackedLensIcon(size: 14)

    func setup(awarenessService: SessionAwarenessService, openMainWindow: @escaping () -> Void) {
        self.openMainWindow = openMainWindow

        if self.awarenessService === awarenessService, !cancellables.isEmpty {
            return
        }

        cancellables.removeAll()
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

        // Observe session state for updates — subscribe to timeState for 1 Hz ticks
        // (awarenessService.objectWillChange no longer fires every second)
        Publishers.Merge(
            awarenessService.timeState.objectWillChange.map { _ in () },
            awarenessService.objectWillChange.map { _ in () }
        )
        .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
        .sink { [weak self] _ in
            self?.updateStatusItem()
        }
        .store(in: &cancellables)

        // Flash effect (single flash for menu bar)
        awarenessService.$flashTrigger
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] type in
                self?.flashStatusItem(type: type)
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
        showDetailsMenu()
    }

    private func showDetailsMenu() {
        guard let service = awarenessService else { return }

        let menu = NSMenu()
        menu.autoenablesItems = false

        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "SessionFlow"
        let headerItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        headerItem.image = menuStackedLensIcon
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

        if let feedback = service.sessionFeedbackPending {
            addFeedbackSection(feedback, service: service, to: menu)
            if service.nextSessionTitle != nil {
                menu.addItem(NSMenuItem.separator())
                addNextSessionSection(service, to: menu)
            }
        } else if service.isActive {
            addActiveSection(service, to: menu)
            if service.nextSessionTitle != nil {
                menu.addItem(NSMenuItem.separator())
                addNextSessionSection(service, to: menu)
            }
        } else if service.isResting {
            addRestSection(service, to: menu)
            if service.nextSessionTitle != nil {
                menu.addItem(NSMenuItem.separator())
                addNextSessionSection(service, to: menu)
            }
        } else if service.nextSessionTitle != nil {
            addNextSessionSection(service, to: menu)
        } else {
            addIdleSection(to: menu)
        }

        menu.addItem(NSMenuItem.separator())

        let openItem = NSMenuItem(title: "Open SessionFlow", action: #selector(openSessionFlow), keyEquivalent: "")
        openItem.target = self
        openItem.image = symbolImage("macwindow", pointSize: 13)
        openItem.isEnabled = true
        menu.addItem(openItem)

        if service.isActive || service.isResting {
            let muteTitle = service.isSessionMuted ? "Resume session sounds" : "Mute until next session"
            let muteItem = NSMenuItem(title: muteTitle, action: #selector(toggleSessionMuteFromMenu), keyEquivalent: "")
            muteItem.target = self
            muteItem.image = symbolImage(service.isSessionMuted ? "speaker.wave.2.fill" : "speaker.slash.fill", pointSize: 13)
            muteItem.isEnabled = true
            menu.addItem(muteItem)
        }

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        statusItem?.menu = menu
        startMenuTrackingTimer()
        statusItem?.button?.performClick(nil)
        stopMenuTrackingTimer()
        // Reset menu so left-click works normally again
        statusItem?.menu = nil
    }

    private func addFeedbackSection(_ feedback: SessionFeedback, service: SessionAwarenessService, to menu: NSMenu) {
        addInfoItem("Focus review needed\(typeSuffix(feedback.sessionType, isBusySlot: feedback.sessionType == nil))", systemImage: "checkmark.circle.badge.questionmark", to: menu, isHeader: true)
        addInfoItem("Focus on \"\(truncate(feedback.sessionTitle, maxLength: 56))\"?", systemImage: "quote.bubble", to: menu)
        addInfoItem("Time: \(timeRange(start: feedback.startTime, end: feedback.endTime))", systemImage: "clock", to: menu)

        menu.addItem(NSMenuItem.separator())

        for rating in SessionRating.displayOrder {
            let item = NSMenuItem(title: rating.label, action: nil, keyEquivalent: "")
            item.image = symbolImage(rating.icon, pointSize: 13)
            item.isEnabled = true

            let alignmentMenu = NSMenu()
            for alignment in SessionAlignment.displayOrder {
                let alignmentItem = NSMenuItem(title: alignment.label, action: #selector(submitFeedbackWithAlignmentFromMenu(_:)), keyEquivalent: "")
                alignmentItem.target = self
                alignmentItem.representedObject = "\(rating.rawValue)|\(alignment.rawValue)"
                alignmentItem.image = symbolImage(alignment.icon, pointSize: 12)
                alignmentItem.isEnabled = true
                alignmentMenu.addItem(alignmentItem)
            }
            item.submenu = alignmentMenu
            menu.addItem(item)
        }

        let dismissItem = NSMenuItem(title: "Dismiss feedback", action: #selector(dismissFeedbackFromMenu), keyEquivalent: "")
        dismissItem.target = self
        dismissItem.image = symbolImage("xmark", pointSize: 12)
        dismissItem.isEnabled = true
        menu.addItem(dismissItem)
    }

    private func addActiveSection(_ service: SessionAwarenessService, to menu: NSMenu) {
        let sectionTitle = service.isBusySlotMode
            ? "Current calendar event"
            : "Current session\(typeSuffix(service.currentSessionType, isBusySlot: false))"
        addInfoItem(sectionTitle, systemImage: awarenessIconName(service: service), to: menu, isHeader: true)
        addInfoItem(truncate(service.currentSessionTitle, maxLength: 64), systemImage: awarenessIconName(service: service), to: menu)

        if let start = service.sessionStartTime, let end = service.sessionEndTime {
            addInfoItem("Time: \(timeRange(start: start, end: end))", systemImage: "clock", to: menu)
        }

        if service.isBusySlotMode {
            addInfoItem("Calendar: \(service.busySlotCalendarName ?? "Calendar")", systemImage: "calendar", to: menu)
        }

        if let notes = SessionAwarenessService.strippedNotes(service.currentEventNotes) {
            addInfoItem("Notes: \(truncate(notes, maxLength: 80))", systemImage: "note.text", to: menu)
        }
    }

    private func addRestSection(_ service: SessionAwarenessService, to menu: NSMenu) {
        addInfoItem("Rest", systemImage: "cup.and.saucer.fill", to: menu, isHeader: true)

        if let type = service.restAfterSessionType {
            addInfoItem("After: \(type.rawValue)", systemImage: type.icon, to: menu)
        }

        if let start = service.restStartTime, let end = service.restEndTime {
            addInfoItem("Time: \(timeRange(start: start, end: end))", systemImage: "clock", to: menu)
        }

    }

    private func addNextSessionSection(_ service: SessionAwarenessService, to menu: NSMenu) {
        addInfoItem("Next\(typeSuffix(service.nextSessionType, isBusySlot: service.nextSessionIsBusySlot))", systemImage: service.nextSessionIsBusySlot ? "calendar" : (service.nextSessionType?.icon ?? "calendar.badge.clock"), to: menu, isHeader: true)

        if let title = service.nextSessionTitle {
            addInfoItem(truncate(title, maxLength: 64), systemImage: service.nextSessionIsBusySlot ? "calendar" : service.nextSessionType?.icon, to: menu)
        }

        if let start = service.nextSessionStartTime, let end = service.nextSessionEndTime {
            addInfoItem("Time: \(timeRange(start: start, end: end))", systemImage: "clock", to: menu)
        }
    }

    private func addIdleSection(to menu: NSMenu) {
        addInfoItem("No active event", image: smallStackedLensIcon, to: menu, isHeader: true)
        addInfoItem("No more tracked sessions today", systemImage: "moon.zzz", to: menu)
    }

    private func addInfoItem(_ title: String, systemImage: String? = nil, to menu: NSMenu, isHeader: Bool = false) {
        addInfoItem(title, image: systemImage.flatMap { symbolImage($0, pointSize: isHeader ? 13 : 12) }, to: menu, isHeader: isHeader)
    }

    private func addInfoItem(_ title: String, image: NSImage?, to menu: NSMenu, isHeader: Bool = false) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = image
        item.isEnabled = false
        if isHeader {
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
        }
        menu.addItem(item)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func openSessionFlow() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = SessionFlowWindowIdentity.mainWindow(preferVisible: true), window.isVisible {
            window.makeKeyAndOrderFront(nil)
        } else if let panel = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible }) {
            // Mini-player mode: show where the floating panel is.
            MiniPlayerAttentionEffect.pulse(panel)
        } else {
            NSApp.unhide(nil)
            openMainWindow?()
            DispatchQueue.main.async {
                SessionFlowWindowIdentity.mainWindow(preferVisible: true)?.makeKeyAndOrderFront(nil)
            }
        }
    }

    @objc private func submitFeedbackFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let rating = SessionRating(rawValue: rawValue) else { return }
        awarenessService?.submitFeedback(rating: rating)
    }

    @objc private func submitFeedbackWithAlignmentFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String else { return }
        let parts = rawValue.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let rating = SessionRating(rawValue: parts[0]),
              let alignment = SessionAlignment(rawValue: parts[1]) else { return }
        awarenessService?.submitFeedback(rating: rating, alignment: alignment)
    }

    @objc private func dismissFeedbackFromMenu() {
        awarenessService?.dismissFeedback()
    }

    @objc private func toggleSessionMuteFromMenu() {
        awarenessService?.toggleSessionMute()
    }

    private func flashStatusItem(type: SessionAwarenessService.FlashType) {
        guard let button = statusItem?.button else { return }
        flashGeneration += 1
        let gen = flashGeneration
        button.contentTintColor = nil

        let color: NSColor
        switch type {
        case .endingSoon: color = .systemRed
        case .presenceReminder: color = .orange
        case .sessionStarted: color = .systemGreen
        }
        let steps: [(TimeInterval, NSColor?)] = [
            (0, color), (0.55, nil), (0.65, color), (1.2, nil),
        ]
        for (delay, tint) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard self?.flashGeneration == gen else { return }
                button.contentTintColor = tint
            }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button, let service = awarenessService else { return }
        let now = menuReferenceTime()

        if service.sessionFeedbackPending != nil {
            button.image = statusStackedLensIcon
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "Focus review needed"
        } else if service.isActive {
            // Show session type icon + time metric
            let iconName = service.isBusySlotMode ? "calendar" : (service.currentSessionType?.icon ?? "circle")
            button.image = symbolImage(iconName, pointSize: 14, weight: .medium)

            // Time text
            let time: TimeInterval
            let suffix: String
            switch service.timeDisplayMode {
            case .remaining:
                if let end = service.sessionEndTime {
                    time = end.timeIntervalSince(now)
                } else {
                    time = service.remaining
                }
                suffix = ""
            case .elapsed:
                if let start = service.sessionStartTime {
                    time = now.timeIntervalSince(start)
                } else {
                    time = service.elapsed
                }
                suffix = ""
            }
            button.attributedTitle = formattedTime(time, suffix: suffix)
            button.toolTip = statusToolTip(for: service)
        } else if service.isResting {
            // Rest: cup icon + remaining countdown
            button.image = symbolImage("cup.and.saucer.fill", pointSize: 14, weight: .medium)
            if let end = service.restEndTime {
                button.attributedTitle = formattedTime(end.timeIntervalSince(now))
            } else {
                button.attributedTitle = formattedTime(service.restRemaining)
            }
            button.toolTip = statusToolTip(for: service)
        } else {
            // Idle/next-up: show the SessionFlow lens stack, no title
            button.image = statusStackedLensIcon
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = statusToolTip(for: service)
        }
    }

    private func formattedTime(_ time: TimeInterval, suffix: String = "") -> NSAttributedString {
        let totalSeconds = max(0, Int(time))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let timeStr = hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
        return NSAttributedString(
            string: " \(timeStr)\(suffix)",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)]
        )
    }

    private func startMenuTrackingTimer() {
        stopMenuTrackingTimer()

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStatusItem()
        }
        menuTrackingTimer = timer
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    private func stopMenuTrackingTimer() {
        menuTrackingTimer?.invalidate()
        menuTrackingTimer = nil
        updateStatusItem()
    }

    private func statusToolTip(for service: SessionAwarenessService) -> String {
        if let feedback = service.sessionFeedbackPending {
            return "Focus review needed for \(feedback.sessionTitle)"
        }
        if service.isActive {
            return service.currentSessionTitle.isEmpty ? "Current session" : service.currentSessionTitle
        }
        if service.isResting {
            if let type = service.restAfterSessionType {
                return "Rest after \(type.rawValue)"
            }
            return "Rest"
        }
        if let next = service.nextSessionTitle {
            return "Next: \(next)"
        }
        return "SessionFlow Awareness"
    }

    private func symbolImage(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .regular) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)) else {
            return nil
        }
        image.isTemplate = true
        return image
    }

    private func makeStackedLensIcon(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let scale = min(rect.width, rect.height) / 18
            let centerX = rect.midX
            let lenses: [(width: CGFloat, height: CGFloat, y: CGFloat, alpha: CGFloat)] = [
                (16.2, 4.1, 2.1, 0.22),
                (13.2, 3.6, 5.7, 0.24),
                (10.1, 3.1, 9.0, 0.26),
                (7.2, 2.6, 12.0, 0.28)
            ]

            for lens in lenses {
                let lensRect = NSRect(
                    x: centerX - lens.width * scale / 2,
                    y: rect.minY + lens.y * scale,
                    width: lens.width * scale,
                    height: lens.height * scale
                )
                let path = NSBezierPath(ovalIn: lensRect)
                NSColor.black.withAlphaComponent(lens.alpha).setFill()
                path.fill()
                NSColor.black.withAlphaComponent(0.86).setStroke()
                path.lineWidth = max(1, 1.15 * scale)
                path.stroke()

                let highlightRect = lensRect.insetBy(dx: lensRect.width * 0.16, dy: lensRect.height * 0.28)
                let highlight = NSBezierPath()
                highlight.appendArc(
                    withCenter: NSPoint(x: highlightRect.midX, y: highlightRect.midY),
                    radius: highlightRect.width / 2,
                    startAngle: 18,
                    endAngle: 162
                )
                NSColor.black.withAlphaComponent(0.35).setStroke()
                highlight.lineWidth = max(0.7, 0.75 * scale)
                highlight.stroke()
            }

            return true
        }
        image.isTemplate = true
        return image
    }

    private func timeRange(start: Date, end: Date) -> String {
        "\(formatSessionTime(start)) - \(formatSessionTime(end)) (\(durationMinutes(start: start, end: end)) min)"
    }

    private func menuReferenceTime() -> Date {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "devNowLineOverrideEnabled") else { return Date() }

        let hour = defaults.integer(forKey: "devNowLineOverrideHour")
        let minute = defaults.integer(forKey: "devNowLineOverrideMinute")
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .hour, value: hour, to: dayStart)
            .flatMap { calendar.date(byAdding: .minute, value: minute, to: $0) } ?? Date()
    }

    private func durationMinutes(start: Date, end: Date) -> Int {
        max(0, Int(end.timeIntervalSince(start) / 60))
    }

    private func typeSuffix(_ type: SessionType?, isBusySlot: Bool) -> String {
        if isBusySlot {
            return " (Calendar event)"
        }
        if let type {
            return " (\(type.rawValue))"
        }
        return ""
    }

    private func truncate(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let end = text.index(text.startIndex, offsetBy: maxLength - 1)
        return "\(text[..<end])..."
    }
}

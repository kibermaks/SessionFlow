import AppKit
import SwiftUI
import Combine

class DockProgressController {
    private var cancellables = Set<AnyCancellable>()
    private var customView: DockTileProgressView?
    private var flashGeneration = 0
    private weak var awarenessService: SessionAwarenessService?

    func setup(awarenessService: SessionAwarenessService) {
        if self.awarenessService === awarenessService, !cancellables.isEmpty {
            return
        }

        cancellables.removeAll()
        self.awarenessService = awarenessService

        awarenessService.$isActive
            .combineLatest(
                awarenessService.timeState.$progress,
                awarenessService.$currentSessionType,
                awarenessService.$isBusySlotMode
            )
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive, progress, sessionType, isBusySlot in
                let enabled = awarenessService.config.showDockProgress
                let busyColor: NSColor? = awarenessService.busySlotCalendarColor.map { NSColor($0) }
                let mode = awarenessService.timeDisplayMode
                self?.update(
                    isActive: isActive && enabled,
                    progress: progress,
                    sessionType: sessionType,
                    isBusySlot: isBusySlot,
                    busyColor: busyColor,
                    timeDisplayMode: mode
                )
            }
            .store(in: &cancellables)

        // Flash the dock donut when presence reminder or ending soon fires
        awarenessService.$flashTrigger
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] type in
                guard awarenessService.config.showDockProgress else { return }
                self?.flashDockDonut(type: type)
            }
            .store(in: &cancellables)
    }

    private func update(isActive: Bool, progress: Double, sessionType: SessionType?, isBusySlot: Bool, busyColor: NSColor?, timeDisplayMode: TimeDisplayMode) {
        guard isActive else {
            // Remove custom dock tile, restore default
            if customView != nil {
                NSApp.dockTile.contentView = nil
                NSApp.dockTile.display()
                customView = nil
            }
            return
        }

        let color: NSColor
        if isBusySlot {
            color = busyColor ?? .gray
        } else if let type = sessionType {
            color = NSColor(type.color)
        } else {
            color = .gray
        }

        if customView == nil {
            let view = DockTileProgressView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
            customView = view
            NSApp.dockTile.contentView = view
        }

        customView?.progress = progress
        customView?.progressColor = color
        customView?.isRemainingMode = (timeDisplayMode == .remaining)
        NSApp.dockTile.display()
    }

    // MARK: - Flash

    private func flashDockDonut(type: SessionAwarenessService.FlashType) {
        guard customView != nil else { return }

        flashGeneration &+= 1
        let gen = flashGeneration
        let flashColor: NSColor = type == .endingSoon ? .systemRed : .systemOrange

        // Double-blink pattern matching menu bar: on → off → on → off
        let steps: [(delay: Double, color: NSColor?)] = [
            (0,    flashColor),
            (0.55, nil),
            (0.65, flashColor),
            (1.2,  nil),
        ]

        for step in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + step.delay) { [weak self] in
                guard let self, self.flashGeneration == gen, let view = self.customView else { return }
                view.flashColor = step.color
                NSApp.dockTile.display()
            }
        }
    }
}

// MARK: - Custom Dock Tile View

private class DockTileProgressView: NSView {
    var progress: Double = 0
    var progressColor: NSColor = .white
    var isRemainingMode: Bool = true
    var flashColor: NSColor?  // non-nil during flash — tints the donut background

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw app icon as base
        if let appIcon = NSApp.applicationIconImage {
            appIcon.draw(in: bounds)
        }

        // Progress donut (top-left) with a white round background.
        // The background is intentionally a few pixels larger than the donut ("skirt"),
        // so you see a white rim around the ring.
        let donutDiameter: CGFloat = bounds.width * 0.32
        let ringLineWidth: CGFloat = donutDiameter * 0.22
        let donutOuterRadius: CGFloat = donutDiameter / 2
        let skirtOutset: CGFloat = max(3, bounds.width * 0.025) // ~3–4 px at typical dock tile sizes
        let badgeRadius: CGFloat = donutOuterRadius + skirtOutset
        let badgeDiameter: CGFloat = badgeRadius * 2
        let padding: CGFloat = 5
        let center = NSPoint(
            x: bounds.minX + badgeRadius + padding,
            y: bounds.maxY - badgeRadius - padding
        )

        // White round background
        let badgeRect = NSRect(
            x: center.x - badgeDiameter / 2,
            y: center.y - badgeDiameter / 2,
            width: badgeDiameter,
            height: badgeDiameter
        )

        let badgePath = NSBezierPath(ovalIn: badgeRect)
        NSGraphicsContext.current?.saveGraphicsState()
        NSShadow().apply {
            $0.shadowOffset = NSSize(width: 0, height: -1)
            $0.shadowBlurRadius = 2.5
            $0.shadowColor = NSColor.black.withAlphaComponent(0.25)
            $0.set()
        }
        let badgeFill = flashColor?.withAlphaComponent(0.85) ?? NSColor.white.withAlphaComponent(0.95)
        badgeFill.setFill()
        badgePath.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        let badgeStroke = flashColor?.withAlphaComponent(0.5) ?? NSColor.black.withAlphaComponent(0.12)
        badgeStroke.setStroke()
        badgePath.lineWidth = 1
        badgePath.stroke()

        let ringRadius: CGFloat = donutOuterRadius - ringLineWidth / 2

        // Background track
        let trackPath = NSBezierPath()
        trackPath.appendArc(withCenter: center, radius: ringRadius, startAngle: 0, endAngle: 360)
        trackPath.lineWidth = ringLineWidth
        NSColor.black.withAlphaComponent(0.14).setStroke()
        trackPath.stroke()

        // Progress arc
        let startAngle: CGFloat = 90  // top in AppKit coordinates

        if isRemainingMode {
            // Remaining: full donut eaten counterclockwise from 12 o'clock
            // Colored arc = remaining portion, clockwise from the eaten edge back to 12
            let remainingFraction = 1.0 - progress
            guard remainingFraction > 0 else { return }
            let endAngle: CGFloat = startAngle - CGFloat(remainingFraction) * 360

            let progressPath = NSBezierPath()
            progressPath.appendArc(withCenter: center, radius: ringRadius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            progressPath.lineWidth = ringLineWidth
            progressPath.lineCapStyle = .round
            progressColor.withAlphaComponent(0.95).setStroke()
            progressPath.stroke()
        } else {
            // Elapsed: empty donut fills clockwise as time passes
            guard progress > 0 else { return }
            let endAngle: CGFloat = startAngle - CGFloat(progress) * 360

            let progressPath = NSBezierPath()
            progressPath.appendArc(withCenter: center, radius: ringRadius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            progressPath.lineWidth = ringLineWidth
            progressPath.lineCapStyle = .round
            progressColor.withAlphaComponent(0.95).setStroke()
            progressPath.stroke()
        }
    }
}

private extension NSShadow {
    func apply(_ configure: (NSShadow) -> Void) {
        configure(self)
    }
}

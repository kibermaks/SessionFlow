import AppKit
import SwiftUI
import Combine

class DockProgressController {
    private var cancellables = Set<AnyCancellable>()
    private var customView: DockTileProgressView?

    func setup(awarenessService: SessionAwarenessService) {
        awarenessService.$isActive
            .combineLatest(
                awarenessService.$progress,
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
}

// MARK: - Custom Dock Tile View

private class DockTileProgressView: NSView {
    var progress: Double = 0
    var progressColor: NSColor = .white
    var isRemainingMode: Bool = true

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
        NSColor.white.withAlphaComponent(0.95).setFill()
        badgePath.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        NSColor.black.withAlphaComponent(0.12).setStroke()
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

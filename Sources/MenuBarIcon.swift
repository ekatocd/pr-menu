import AppKit

enum MenuBarIcon {
    static func aggregateColor(for statuses: [PRStatus]) -> PRStatus {
        guard !statuses.isEmpty else { return .unknown }
        return statuses.max() ?? .unknown
    }

    static func badgeText(for count: Int) -> String? {
        count > 0 ? "\(count)" : nil
    }

    static func badgeText(mine: Int, team: Int) -> String? {
        if team > 0 {
            return "\(mine)|\(team)"
        }
        return mine > 0 ? "\(mine)" : nil
    }

    static func nsColor(for status: PRStatus) -> NSColor {
        switch status {
        case .clear:
            return .systemGreen
        case .pending:
            return .systemOrange
        case .unresolvedComments:
            return .systemPurple
        case .attention:
            return .systemRed
        case .changesRequested:
            return .systemRed
        case .unknown:
            return .secondaryLabelColor
        }
    }

    static func createIcon(status: PRStatus, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer {
            image.unlockFocus()
            image.isTemplate = false
        }

        let color = nsColor(for: status)
        let lineWidth = max(1.5, size * 0.11)
        let dotRadius = max(1.5, size * 0.12)
        let leftX = size * 0.3
        let bottomY = size * 0.18
        let branchY = size * 0.72
        let rightX = size * 0.76
        let rightY = size * 0.46

        color.setStroke()
        color.setFill()

        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: leftX, y: bottomY))
        path.line(to: NSPoint(x: leftX, y: branchY))
        path.move(to: NSPoint(x: leftX, y: branchY))
        path.curve(
            to: NSPoint(x: rightX, y: rightY),
            controlPoint1: NSPoint(x: size * 0.46, y: branchY),
            controlPoint2: NSPoint(x: size * 0.58, y: rightY)
        )
        path.stroke()

        [
            NSPoint(x: leftX, y: bottomY),
            NSPoint(x: leftX, y: branchY),
            NSPoint(x: rightX, y: rightY),
        ].forEach { point in
            NSBezierPath(
                ovalIn: NSRect(
                    x: point.x - dotRadius,
                    y: point.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
            ).fill()
        }

        return image
    }
}

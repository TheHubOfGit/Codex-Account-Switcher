import AppKit

enum MenuBarIcon {
    private static let iconSize = NSSize(width: 20, height: 18)

    private enum PaceRing {
        static let center = NSPoint(x: 10, y: 9)

        static let outerRadius: CGFloat = 7.1
        static let outerLineWidth: CGFloat = 2.5

        static let innerRadius: CGFloat = 3.9

        static let trackOpacity: CGFloat = 0.18
        static let combinedOpacity: CGFloat = 0.60

        static let tickInnerRadius: CGFloat = 8.05
        static let tickOuterRadius: CGFloat = 8.75
        static let tickLineWidth: CGFloat = 1.35
    }

    static func paceRing(state: MenuBarQuotaMeterState) -> NSImage {
        let image = NSImage(size: iconSize)

        image.lockFocus()
        drawRing(
            radius: PaceRing.outerRadius,
            lineWidth: PaceRing.outerLineWidth,
            remainingFraction: state.fillFraction,
            remainingOpacity: state.isStale ? 0.55 : 1
        )
        drawPie(
            radius: PaceRing.innerRadius,
            remainingFraction: state.combinedFillFraction,
            remainingOpacity: PaceRing.combinedOpacity
        )
        drawPaceTick(progress: state.resetProgressFraction)
        image.unlockFocus()

        image.isTemplate = true
        image.accessibilityDescription = "Codex Account Switcher, \(state.accessibilityDescription)"
        return image
    }

    private static func drawRing(
        radius: CGFloat,
        lineWidth: CGFloat,
        remainingFraction: Double?,
        remainingOpacity: CGFloat
    ) {
        let track = NSBezierPath()
        track.appendArc(
            withCenter: PaceRing.center,
            radius: radius,
            startAngle: 0,
            endAngle: 360
        )
        track.lineWidth = lineWidth
        NSColor.labelColor.withAlphaComponent(PaceRing.trackOpacity).setStroke()
        track.stroke()

        guard let remainingFraction else {
            return
        }

        let remaining = min(max(remainingFraction, 0), 1)
        guard remaining > 0 else {
            return
        }

        let available = NSBezierPath()
        available.lineWidth = lineWidth
        available.lineCapStyle = .butt

        if remaining >= 1 {
            available.appendArc(
                withCenter: PaceRing.center,
                radius: radius,
                startAngle: 0,
                endAngle: 360
            )
        } else {
            let used = 1 - remaining
            let remainingStartAngle = 90 - (used * 360)
            available.appendArc(
                withCenter: PaceRing.center,
                radius: radius,
                startAngle: remainingStartAngle,
                endAngle: 90,
                clockwise: true
            )
        }

        NSColor.labelColor.withAlphaComponent(remainingOpacity).setStroke()
        available.stroke()
    }

    private static func drawPie(
        radius: CGFloat,
        remainingFraction: Double?,
        remainingOpacity: CGFloat
    ) {
        let pieRect = NSRect(
            x: PaceRing.center.x - radius,
            y: PaceRing.center.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        NSColor.labelColor.withAlphaComponent(PaceRing.trackOpacity).setFill()
        NSBezierPath(ovalIn: pieRect).fill()

        guard let remainingFraction else {
            return
        }

        let remaining = min(max(remainingFraction, 0), 1)
        guard remaining > 0 else {
            return
        }

        let available = NSBezierPath()
        if remaining >= 1 {
            available.appendOval(in: pieRect)
        } else {
            let used = 1 - remaining
            let remainingStartAngle = 90 - (used * 360)
            available.move(to: PaceRing.center)
            available.line(to: point(
                radius: radius,
                angle: remainingStartAngle * .pi / 180
            ))
            available.appendArc(
                withCenter: PaceRing.center,
                radius: radius,
                startAngle: remainingStartAngle,
                endAngle: 90,
                clockwise: true
            )
            available.close()
        }

        NSColor.labelColor.withAlphaComponent(remainingOpacity).setFill()
        available.fill()
    }

    private static func drawPaceTick(progress: Double?) {
        guard let progress else {
            return
        }

        let clampedProgress = min(max(progress, 0), 1)
        let angle = (.pi / 2) - (2 * .pi * clampedProgress)
        let tick = NSBezierPath()
        tick.lineWidth = PaceRing.tickLineWidth
        tick.lineCapStyle = .round
        tick.move(to: point(radius: PaceRing.tickInnerRadius, angle: angle))
        tick.line(to: point(radius: PaceRing.tickOuterRadius, angle: angle))

        NSColor.labelColor.setStroke()
        tick.stroke()
    }

    private static func point(radius: CGFloat, angle: CGFloat) -> NSPoint {
        NSPoint(
            x: PaceRing.center.x + cos(angle) * radius,
            y: PaceRing.center.y + sin(angle) * radius
        )
    }
}

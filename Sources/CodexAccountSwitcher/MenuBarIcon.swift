import AppKit

enum MenuBarIcon {
    private static let iconSize = NSSize(width: 24, height: 18)
    private static let meteredIconSize = NSSize(width: 34, height: 18)

    static func multiAuth() -> NSImage {
        let image = NSImage(size: iconSize)

        image.lockFocus()
        drawMultiAuthGlyph()
        image.unlockFocus()

        image.isTemplate = true
        image.accessibilityDescription = "Multiple authenticated Codex accounts"
        return image
    }

    static func multiAuthWithFiveHourMeter(state: MenuBarQuotaMeterState) -> NSImage {
        let image = NSImage(size: meteredIconSize)

        image.lockFocus()
        drawMultiAuthGlyph(offsetX: 0)
        drawFiveHourMeter(state: state)
        image.unlockFocus()

        image.isTemplate = false
        image.accessibilityDescription = "Codex Account Switcher, \(state.accessibilityDescription)"
        return image
    }

    private static func drawMultiAuthGlyph(offsetX: CGFloat = 0) {
        NSColor.labelColor.setStroke()
        NSColor.labelColor.setFill()

        let primaryHead = NSBezierPath(ovalIn: NSRect(x: offsetX + 7.5, y: 10.4, width: 5.8, height: 5.8))
        primaryHead.fill()

        let secondaryHead = NSBezierPath(ovalIn: NSRect(x: offsetX + 2.7, y: 8.9, width: 5.1, height: 5.1))
        secondaryHead.fill()

        let secondaryBody = NSBezierPath(
            roundedRect: NSRect(x: offsetX + 1.9, y: 3.2, width: 8.4, height: 6.5),
            xRadius: 3.2,
            yRadius: 3.2
        )
        secondaryBody.fill()

        let primaryBody = NSBezierPath(
            roundedRect: NSRect(x: offsetX + 5.7, y: 2.1, width: 10.2, height: 8.1),
            xRadius: 4,
            yRadius: 4
        )
        primaryBody.fill()

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(x: offsetX + 13.2, y: 4.5, width: 8.7, height: 8.2)).fill()
        NSColor.labelColor.setStroke()

        let keyRing = NSBezierPath(ovalIn: NSRect(x: offsetX + 13.6, y: 8.2, width: 5.5, height: 5.5))
        keyRing.lineWidth = 1.7
        keyRing.stroke()

        let keyStem = NSBezierPath()
        keyStem.lineWidth = 1.9
        keyStem.lineCapStyle = .round
        keyStem.move(to: NSPoint(x: offsetX + 17.9, y: 9.1))
        keyStem.line(to: NSPoint(x: offsetX + 22, y: 5))
        keyStem.stroke()

        let keyTooth = NSBezierPath()
        keyTooth.lineWidth = 1.6
        keyTooth.lineCapStyle = .square
        keyTooth.move(to: NSPoint(x: offsetX + 20.1, y: 6.9))
        keyTooth.line(to: NSPoint(x: offsetX + 21.7, y: 8.5))
        keyTooth.move(to: NSPoint(x: offsetX + 21.1, y: 5.9))
        keyTooth.line(to: NSPoint(x: offsetX + 22.6, y: 7.4))
        keyTooth.stroke()
    }

    private static func drawFiveHourMeter(state: MenuBarQuotaMeterState) {
        let trackRect = NSRect(x: 26, y: 3, width: 5, height: 12)
        let track = NSBezierPath(roundedRect: trackRect, xRadius: 2.5, yRadius: 2.5)

        NSColor.tertiaryLabelColor.withAlphaComponent(0.35).setFill()
        track.fill()

        guard state.remainingPercent != nil else {
            return
        }

        let fillHeight = max(1.5, trackRect.height * state.fillFraction)
        let fillRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: trackRect.width,
            height: fillHeight
        )
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: 2.5, yRadius: 2.5)

        meterColor(for: state).setFill()
        fill.fill()
    }

    private static func meterColor(for state: MenuBarQuotaMeterState) -> NSColor {
        guard let remaining = state.remainingPercent else {
            return .tertiaryLabelColor
        }

        if state.isStale {
            return .systemGray
        }

        if remaining <= 10 {
            return .systemRed
        }

        if remaining <= 30 {
            return .systemOrange
        }

        return .systemGreen
    }
}

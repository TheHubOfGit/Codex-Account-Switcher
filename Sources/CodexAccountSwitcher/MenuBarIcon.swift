import AppKit

enum MenuBarIcon {
    static func multiAuth() -> NSImage {
        let size = NSSize(width: 24, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.black.setStroke()
        NSColor.black.setFill()

        let primaryHead = NSBezierPath(ovalIn: NSRect(x: 7.5, y: 10.4, width: 5.8, height: 5.8))
        primaryHead.fill()

        let secondaryHead = NSBezierPath(ovalIn: NSRect(x: 2.7, y: 8.9, width: 5.1, height: 5.1))
        secondaryHead.fill()

        let secondaryBody = NSBezierPath(
            roundedRect: NSRect(x: 1.9, y: 3.2, width: 8.4, height: 6.5),
            xRadius: 3.2,
            yRadius: 3.2
        )
        secondaryBody.fill()

        let primaryBody = NSBezierPath(
            roundedRect: NSRect(x: 5.7, y: 2.1, width: 10.2, height: 8.1),
            xRadius: 4,
            yRadius: 4
        )
        primaryBody.fill()

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(x: 13.2, y: 4.5, width: 8.7, height: 8.2)).fill()

        let keyRing = NSBezierPath(ovalIn: NSRect(x: 13.6, y: 8.2, width: 5.5, height: 5.5))
        keyRing.lineWidth = 1.7
        keyRing.stroke()

        let keyStem = NSBezierPath()
        keyStem.lineWidth = 1.9
        keyStem.lineCapStyle = .round
        keyStem.move(to: NSPoint(x: 17.9, y: 9.1))
        keyStem.line(to: NSPoint(x: 22, y: 5))
        keyStem.stroke()

        let keyTooth = NSBezierPath()
        keyTooth.lineWidth = 1.6
        keyTooth.lineCapStyle = .square
        keyTooth.move(to: NSPoint(x: 20.1, y: 6.9))
        keyTooth.line(to: NSPoint(x: 21.7, y: 8.5))
        keyTooth.move(to: NSPoint(x: 21.1, y: 5.9))
        keyTooth.line(to: NSPoint(x: 22.6, y: 7.4))
        keyTooth.stroke()

        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "Multiple authenticated Codex accounts"
        return image
    }
}

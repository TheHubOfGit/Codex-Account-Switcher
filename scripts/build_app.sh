#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Codex Account Switcher"
PRODUCT_NAME="CodexAccountSwitcher"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/debug"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE_PATH="$BUILD_DIR/$PRODUCT_NAME"
ICONSET_DIR="$ROOT_DIR/.build/AppIcon.iconset"
ICON_PATH="$RESOURCES_DIR/AppIcon.icns"

cd "$ROOT_DIR"
swift build

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$PRODUCT_NAME"

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

ICONSET_DIR="$ICONSET_DIR" /usr/bin/swift - <<'SWIFT'
import AppKit
import Foundation

let iconsetURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ICONSET_DIR"]!)
let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let scale = size / 1024
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale)
    }
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: x * scale, y: y * scale)
    }

    let background = NSBezierPath(roundedRect: rect(64, 64, 896, 896), xRadius: 210 * scale, yRadius: 210 * scale)
    NSColor(calibratedRed: 0.08, green: 0.14, blue: 0.20, alpha: 1).setFill()
    background.fill()

    let accent = NSBezierPath(roundedRect: rect(106, 106, 812, 812), xRadius: 176 * scale, yRadius: 176 * scale)
    NSColor(calibratedRed: 0.12, green: 0.46, blue: 0.58, alpha: 1).setStroke()
    accent.lineWidth = 34 * scale
    accent.stroke()

    NSColor(calibratedRed: 0.94, green: 0.98, blue: 1, alpha: 1).setFill()
    NSBezierPath(ovalIn: rect(340, 545, 190, 190)).fill()
    NSBezierPath(roundedRect: rect(278, 258, 315, 245), xRadius: 122 * scale, yRadius: 122 * scale).fill()

    NSColor(calibratedRed: 0.70, green: 0.84, blue: 0.90, alpha: 1).setFill()
    NSBezierPath(ovalIn: rect(178, 505, 160, 160)).fill()
    NSBezierPath(roundedRect: rect(128, 292, 260, 196), xRadius: 98 * scale, yRadius: 98 * scale).fill()

    NSColor(calibratedRed: 0.67, green: 0.98, blue: 0.82, alpha: 1).setStroke()
    let ring = NSBezierPath(ovalIn: rect(585, 525, 182, 182))
    ring.lineWidth = 54 * scale
    ring.stroke()

    let stem = NSBezierPath()
    stem.lineWidth = 62 * scale
    stem.lineCapStyle = .round
    stem.move(to: point(724, 553))
    stem.line(to: point(865, 412))
    stem.stroke()

    let teeth = NSBezierPath()
    teeth.lineWidth = 52 * scale
    teeth.lineCapStyle = .square
    teeth.move(to: point(792, 484))
    teeth.line(to: point(852, 544))
    teeth.move(to: point(830, 446))
    teeth.line(to: point(890, 506))
    teeth.stroke()

    image.unlockFocus()
    return image
}

for (name, size) in sizes {
    let image = drawIcon(size: size)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to render \(name)")
    }
    try data.write(to: iconsetURL.appendingPathComponent(name))
}
SWIFT

iconutil -c icns "$ICONSET_DIR" -o "$ICON_PATH"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Codex Account Switcher</string>
    <key>CFBundleExecutable</key>
    <string>CodexAccountSwitcher</string>
    <key>CFBundleIdentifier</key>
    <string>com.michaelbrancazio.codex-account-switcher.local</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Codex Account Switcher</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
</dict>
</plist>
PLIST

cat > "$CONTENTS_DIR/PkgInfo" <<'PKG'
APPL???? 
PKG

codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "$APP_DIR"

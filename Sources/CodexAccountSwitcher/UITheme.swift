import SwiftUI

/// Centralised spacing values used across the popover and Settings surfaces.
/// Keeping the values here makes future polish passes cheaper and prevents
/// the kind of drift that produced the original mix of 6 / 8 / 10 / 14 paddings.
enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 6
    static let m: CGFloat = 10
    static let l: CGFloat = 14
    static let xl: CGFloat = 20
}

/// Corner-radius tokens shared by cards, pills, and hoverable rows.
enum Radius {
    /// Use for small inline rectangles (e.g. row backgrounds at small sizes).
    static let small: CGFloat = 6
    /// Use for hoverable / selectable account rows.
    static let medium: CGFloat = 8
    /// Use for the larger fleet / settings cards.
    static let card: CGFloat = 10
    /// Pill height divided by two; works for any pill via `.clipShape(Capsule())`
    /// but exposed here for explicit `RoundedRectangle` callers.
    static let pill: CGFloat = 999
}

/// Codex-flavoured colour palette. Values intentionally reach into AppKit
/// semantic colours so dark/light mode handling stays automatic.
extension Color {
    /// Subtle Codex-ish accent used for primary CTAs and the active row tint.
    /// Defaults to the system accent so the user's macOS accent preference
    /// still wins, with a fixed teal fallback when `.accentColor` is not
    /// available (e.g. previews without an environment).
    static var codexAccent: Color {
        Color.accentColor
    }

    /// Background fill for popover cards.
    static var codexCardFill: Color {
        Color(nsColor: .windowBackgroundColor).opacity(0.55)
    }

    /// Resting fill for account rows. It remains quieter than the fleet card
    /// while keeping adjacent accounts visually distinct without borders.
    static var codexAccountFill: Color {
        Color(nsColor: .windowBackgroundColor).opacity(0.32)
    }

    /// Hover fill for selectable rows. Slightly cooler than `.quaternary`
    /// so it reads as an interaction state, not a static surface.
    static var codexHoverFill: Color {
        Color(nsColor: .controlAccentColor).opacity(0.08)
    }

    /// Active-row fill — same hue as hover, a touch stronger so the
    /// selected account stays distinguishable when the cursor moves away.
    static var codexActiveFill: Color {
        Color(nsColor: .controlAccentColor).opacity(0.14)
    }

    /// Quiet accent-tinted surface reserved for earned usage-reset details.
    static var codexResetFill: Color {
        Color(nsColor: .controlAccentColor).opacity(0.075)
    }
}

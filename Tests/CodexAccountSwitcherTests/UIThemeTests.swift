import SwiftUI
import Testing
@testable import CodexAccountSwitcher

struct UIThemeTests {
    @Test
    func spacingTokensAreOrderedFromTightestToLoosest() {
        #expect(Spacing.xs < Spacing.s)
        #expect(Spacing.s < Spacing.m)
        #expect(Spacing.m < Spacing.l)
        #expect(Spacing.l < Spacing.xl)
    }

    @Test
    func spacingTokensAreNonNegative() {
        #expect(Spacing.xs >= 0)
        #expect(Spacing.s >= 0)
        #expect(Spacing.m >= 0)
        #expect(Spacing.l >= 0)
        #expect(Spacing.xl >= 0)
    }

    @Test
    func radiusTokensAreOrderedFromSmallestToLargest() {
        #expect(Radius.small < Radius.medium)
        #expect(Radius.medium < Radius.card)
        #expect(Radius.card < Radius.pill)
    }

    @Test
    func codexColorTokensAreReachable() {
        // We can't compare Color values structurally, but referencing the
        // tokens guarantees the symbols compile and remain available to the
        // SwiftUI views that depend on them.
        _ = Color.codexAccent
        _ = Color.codexCardFill
        _ = Color.codexAccountFill
        _ = Color.codexHoverFill
        _ = Color.codexActiveFill
    }
}

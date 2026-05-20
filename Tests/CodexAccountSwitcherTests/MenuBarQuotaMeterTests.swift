import Foundation
import Testing
@testable import CodexAccountSwitcher

struct MenuBarQuotaMeterTests {
    @Test
    func stateUsesActiveAccountsFiveHourRemainingPercent() {
        let account = AccountSnapshot(
            accountKey: "acct-1",
            email: "one@example.com",
            alias: nil,
            accountName: nil,
            plan: "Team",
            isActive: true,
            fiveHour: QuotaWindowState(usedPercent: 37, resetAt: nil, isStale: false),
            weekly: QuotaWindowState(usedPercent: 20, resetAt: nil, isStale: false),
            lastRefresh: nil
        )

        let state = MenuBarQuotaMeterState(activeAccount: account)

        #expect(state.remainingPercent == 63)
        #expect(state.fillFraction == 0.63)
        #expect(state.accessibilityDescription == "5 hour limit 63 percent left")
    }

    @Test
    func stateClampsFillFraction() {
        let exhausted = MenuBarQuotaMeterState(remainingPercent: -10, isStale: false)
        let overFull = MenuBarQuotaMeterState(remainingPercent: 125, isStale: false)

        #expect(exhausted.fillFraction == 0)
        #expect(overFull.fillFraction == 1)
    }

    @Test
    func stateIncludesStaleAndUnavailableDescriptions() {
        let stale = MenuBarQuotaMeterState(remainingPercent: 42, isStale: true)
        let unavailable = MenuBarQuotaMeterState(activeAccount: nil)

        #expect(stale.accessibilityDescription == "5 hour limit 42 percent left, stale")
        #expect(unavailable.remainingPercent == nil)
        #expect(unavailable.fillFraction == 0)
        #expect(unavailable.accessibilityDescription == "5 hour limit unavailable")
    }
}

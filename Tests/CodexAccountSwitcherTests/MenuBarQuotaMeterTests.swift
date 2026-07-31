import Foundation
import Testing
@testable import CodexAccountSwitcher

struct MenuBarQuotaMeterTests {
    @Test
    func stateUsesActiveAccountsWeeklyRemainingPercent() {
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

        let state = MenuBarQuotaMeterState(activeAccount: account, accounts: [account])

        #expect(state.remainingPercent == 80)
        #expect(state.fillFraction == 0.8)
        #expect(state.combinedRemainingPercent == 80)
        #expect(state.combinedFillFraction == 0.8)
        #expect(
            state.accessibilityDescription
                == "Weekly active account 80 percent left; all accounts average 80 percent left"
        )
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

        #expect(stale.accessibilityDescription == "Weekly active account 42 percent left, stale")
        #expect(unavailable.remainingPercent == nil)
        #expect(unavailable.fillFraction == 0)
        #expect(unavailable.accessibilityDescription == "Weekly limit unavailable")
    }

    @Test
    func stateAveragesFreshWeeklyQuotaAcrossAccounts() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let accounts = [
            account(key: "one", weeklyUsed: 20, resetAt: now.addingTimeInterval(4 * 24 * 60 * 60)),
            account(key: "two", weeklyUsed: 60, resetAt: now.addingTimeInterval(4 * 24 * 60 * 60)),
        ]

        let state = MenuBarQuotaMeterState(
            activeAccount: accounts[0],
            accounts: accounts,
            now: now
        )

        #expect(state.combinedRemainingPercent == 60)
    }

    @Test
    func stateCalculatesWeeklyResetProgressForPaceTick() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetAt = now.addingTimeInterval(3.5 * 24 * 60 * 60)
        let active = account(key: "one", weeklyUsed: 20, resetAt: resetAt)

        let state = MenuBarQuotaMeterState(
            activeAccount: active,
            accounts: [active],
            now: now
        )

        #expect(state.resetProgressFraction == 0.5)
    }

    private func account(
        key: String,
        weeklyUsed: Int,
        resetAt: Date
    ) -> AccountSnapshot {
        AccountSnapshot(
            accountKey: key,
            email: "\(key)@example.com",
            alias: nil,
            accountName: nil,
            plan: "Team",
            isActive: key == "one",
            fiveHour: QuotaWindowState(usedPercent: 0, resetAt: nil, isStale: false),
            weekly: QuotaWindowState(
                usedPercent: weeklyUsed,
                resetAt: resetAt,
                checkedAt: resetAt.addingTimeInterval(-60)
            ),
            lastRefresh: nil
        )
    }
}

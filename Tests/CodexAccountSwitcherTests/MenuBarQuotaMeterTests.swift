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

        let state = MenuBarQuotaMeterState(activeAccount: account, accounts: [account])

        #expect(state.remainingPercent == 63)
        #expect(state.fillFraction == 0.63)
        #expect(state.combinedRemainingPercent == 63)
        #expect(state.combinedFillFraction == 0.63)
        #expect(
            state.accessibilityDescription
                == "5h active account 63 percent left; all accounts average 63 percent left"
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

        #expect(stale.accessibilityDescription == "5h active account 42 percent left, stale")
        #expect(unavailable.remainingPercent == nil)
        #expect(unavailable.fillFraction == 0)
        #expect(unavailable.accessibilityDescription == "5h limit unavailable")
    }

    @Test
    func stateAveragesFreshFiveHourQuotaAcrossAccounts() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let accounts = [
            account(key: "one", fiveHourUsed: 20, resetAt: now.addingTimeInterval(4 * 60 * 60)),
            account(key: "two", fiveHourUsed: 60, resetAt: now.addingTimeInterval(4 * 60 * 60)),
        ]

        let state = MenuBarQuotaMeterState(
            activeAccount: accounts[0],
            accounts: accounts,
            now: now
        )

        #expect(state.combinedRemainingPercent == 60)
    }

    @Test
    func stateCalculatesFiveHourResetProgressForPaceTick() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetAt = now.addingTimeInterval(2.5 * 60 * 60)
        let active = account(key: "one", fiveHourUsed: 20, resetAt: resetAt)

        let state = MenuBarQuotaMeterState(
            activeAccount: active,
            accounts: [active],
            now: now
        )

        #expect(state.resetProgressFraction == 0.5)
    }

    private func account(
        key: String,
        fiveHourUsed: Int,
        resetAt: Date
    ) -> AccountSnapshot {
        AccountSnapshot(
            accountKey: key,
            email: "\(key)@example.com",
            alias: nil,
            accountName: nil,
            plan: "Team",
            isActive: key == "one",
            fiveHour: QuotaWindowState(
                usedPercent: fiveHourUsed,
                resetAt: resetAt,
                checkedAt: resetAt.addingTimeInterval(-60)
            ),
            weekly: QuotaWindowState(
                usedPercent: 0,
                resetAt: nil,
                isStale: false
            ),
            lastRefresh: nil
        )
    }
}

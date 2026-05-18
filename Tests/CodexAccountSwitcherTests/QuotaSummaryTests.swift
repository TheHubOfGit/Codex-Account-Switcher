import Foundation
import Testing
@testable import CodexAccountSwitcher

struct QuotaSummaryTests {
    @Test
    func fiveHourLimitSummaryIncludesHoursUntilResetWhenAvailable() {
        let now = Date(timeIntervalSince1970: 1_000)

        let summary = QuotaSummary.fiveHourLimitLeft(
            for: QuotaWindowState(
                usedPercent: 35,
                resetAt: now.addingTimeInterval((2 * 60 * 60) + 1),
                isStale: false
            ),
            now: now
        )

        #expect(summary == "65% left (3 hours left)")
    }

    @Test
    func fiveHourLimitSummaryUsesMinutesUnderOneHour() {
        let now = Date(timeIntervalSince1970: 1_000)

        let summary = QuotaSummary.fiveHourLimitLeft(
            for: QuotaWindowState(
                usedPercent: 35,
                resetAt: now.addingTimeInterval((42 * 60) + 1),
                isStale: false
            ),
            now: now
        )

        #expect(summary == "65% left (43 minutes left)")
    }

    @Test
    func weeklyLimitSummaryIncludesDaysUntilResetWhenAvailable() {
        let now = Date(timeIntervalSince1970: 1_000)

        let summary = QuotaSummary.weeklyLimitLeft(
            for: QuotaWindowState(
                usedPercent: 35,
                resetAt: now.addingTimeInterval((6 * 24 * 60 * 60) + 1),
                isStale: false
            ),
            now: now
        )

        #expect(summary == "65% left (7 days left)")
    }

    @Test
    func weeklyLimitSummaryUsesHoursUnderOneDay() {
        let now = Date(timeIntervalSince1970: 1_000)

        let summary = QuotaSummary.weeklyLimitLeft(
            for: QuotaWindowState(
                usedPercent: 35,
                resetAt: now.addingTimeInterval((6 * 60 * 60) + 1),
                isStale: false
            ),
            now: now
        )

        #expect(summary == "65% left (7 hours left)")
    }

    @Test
    func weeklyLimitSummaryKeepsStaleMarkerWithDaysLeft() {
        let now = Date(timeIntervalSince1970: 1_000)

        let summary = QuotaSummary.weeklyLimitLeft(
            for: QuotaWindowState(
                usedPercent: 35,
                resetAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                isStale: true
            ),
            now: now
        )

        #expect(summary == "65% left (stale, 6 days left)")
    }
}

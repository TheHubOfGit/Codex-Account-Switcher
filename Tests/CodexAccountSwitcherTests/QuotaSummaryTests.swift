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

    @Test
    func compactResetDistanceIncludesDaysAndHours() {
        let now = Date(timeIntervalSince1970: 1_000)
        let resetAt = now.addingTimeInterval((2 * 24 * 60 * 60) + (7 * 60 * 60))

        #expect(QuotaSummary.compactResetDistance(resetAt: resetAt, now: now) == "in 2d 7h")
    }

    @Test
    func compactResetDistanceHandlesHoursMinutesAndOverdueTimes() {
        let now = Date(timeIntervalSince1970: 10_000)

        #expect(
            QuotaSummary.compactResetDistance(
                resetAt: now.addingTimeInterval(9 * 60 * 60),
                now: now
            ) == "in 9h"
        )
        #expect(
            QuotaSummary.compactResetDistance(
                resetAt: now.addingTimeInterval(42 * 60),
                now: now
            ) == "in 42m"
        )
        #expect(
            QuotaSummary.compactResetDistance(
                resetAt: now.addingTimeInterval(-3 * 60 * 60),
                now: now
            ) == "3h ago"
        )
    }
}

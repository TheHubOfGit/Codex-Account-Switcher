import Foundation
import Testing
@testable import CodexAccountSwitcher

struct ResetCreditsSummaryTests {
    @Test
    func showsAvailabilityAndEveryKnownExpiry() {
        let snapshot = RateLimitResetCreditsSnapshot(
            availableCount: 3,
            credits: [
                RateLimitResetCredit(
                    id: "one",
                    resetType: "codexRateLimits",
                    status: "available",
                    grantedAt: nil,
                    expiresAt: 1_785_026_400,
                    title: "Full reset",
                    description: nil
                ),
                RateLimitResetCredit(
                    id: "two",
                    resetType: "codexRateLimits",
                    status: "available",
                    grantedAt: nil,
                    expiresAt: 1_785_458_400,
                    title: "Full reset",
                    description: nil
                )
            ],
            checkedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(
            ResetCreditsSummary.availability(
                for: snapshot,
                now: Date(timeIntervalSince1970: 1_100)
            ) == "3 available"
        )
        let lines = ResetCreditsSummary.expiryLines(
            for: snapshot,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("Full reset · expires "))
        #expect(lines[2] == "1 more reset")
    }

    @Test
    func labelsPersistedResetAvailabilityAsCachedWhenOld() {
        let snapshot = RateLimitResetCreditsSnapshot(
            availableCount: 1,
            credits: [],
            checkedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(
            ResetCreditsSummary.availability(
                for: snapshot,
                now: Date(timeIntervalSince1970: 3_000)
            ) == "1 available · cached"
        )
    }

    @Test
    func formatsExpiryUrgencyForScanning() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let credit = RateLimitResetCredit(
            id: "soon",
            resetType: nil,
            status: "available",
            grantedAt: nil,
            expiresAt: now.addingTimeInterval(2 * 24 * 60 * 60).timeIntervalSince1970,
            title: "Full reset (Weekly + 5 hr)",
            description: nil
        )

        #expect(ResetCreditsSummary.title(for: credit) == "Full reset")
        #expect(ResetCreditsSummary.timeUntilExpiry(for: credit, now: now) == "in 2 days")
        #expect(ResetCreditsSummary.isExpiringSoon(credit, now: now))
    }

    @Test
    func formatsExpiryTimeAsCompactLowercaseTwelveHourTime() {
        var calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.timeZone = timeZone

        let morning = RateLimitResetCredit(
            id: "morning",
            resetType: nil,
            status: "available",
            grantedAt: nil,
            expiresAt: calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 31, hour: 9, minute: 5)
            )!.timeIntervalSince1970,
            title: "Full reset",
            description: nil
        )
        let evening = RateLimitResetCredit(
            id: "evening",
            resetType: nil,
            status: "available",
            grantedAt: nil,
            expiresAt: calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 31, hour: 21, minute: 42)
            )!.timeIntervalSince1970,
            title: "Full reset",
            description: nil
        )

        #expect(ResetCreditsSummary.expiryTime(for: morning, timeZone: timeZone) == "9:05am")
        #expect(ResetCreditsSummary.expiryTime(for: evening, timeZone: timeZone) == "9:42pm")
    }
}

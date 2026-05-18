import Foundation
import Testing
@testable import CodexAccountSwitcher

struct AccountRankingTests {
    @Test
    func prefersLowestEligibleQuotaPressure() {
        let winner = AccountRanking.bestCandidate(from: [
            makeAccount(email: "low@example.com", fiveHourRemaining: 10, weeklyRemaining: 80),
            makeAccount(email: "high@example.com", fiveHourRemaining: 90, weeklyRemaining: 1)
        ])

        #expect(winner?.email == "high@example.com")
    }

    @Test
    func breaksLowestQuotaTiesWithLowerAverageRemaining() {
        let winner = AccountRanking.bestCandidate(from: [
            makeAccount(email: "higher-average@example.com", fiveHourRemaining: 30, weeklyRemaining: 90),
            makeAccount(email: "lower-average@example.com", fiveHourRemaining: 30, weeklyRemaining: 50)
        ])

        #expect(winner?.email == "lower-average@example.com")
    }

    @Test
    func prefersNonActiveAccountOnQuotaTie() {
        let winner = AccountRanking.bestCandidate(from: [
            makeAccount(email: "active@example.com", fiveHourRemaining: 70, weeklyRemaining: 70, isActive: true),
            makeAccount(email: "inactive@example.com", fiveHourRemaining: 70, weeklyRemaining: 70, isActive: false)
        ])

        #expect(winner?.email == "inactive@example.com")
    }

    @Test
    func excludesStaleOrMissingQuotaData() {
        let winner = AccountRanking.bestCandidate(from: [
            makeAccount(email: "stale@example.com", fiveHourRemaining: 99, weeklyRemaining: 99, isStale: true),
            makeAccount(email: "missing@example.com", fiveHourRemaining: nil, weeklyRemaining: nil),
            makeAccount(email: "fresh@example.com", fiveHourRemaining: 40, weeklyRemaining: 50)
        ])

        #expect(winner?.email == "fresh@example.com")
    }

    @Test
    func excludesAccountsAtOrBelowThresholds() {
        let winner = AccountRanking.bestCandidate(
            from: [
                makeAccount(email: "five-hour-exhausted@example.com", fiveHourRemaining: 10, weeklyRemaining: 80),
                makeAccount(email: "weekly-exhausted@example.com", fiveHourRemaining: 80, weeklyRemaining: 5),
                makeAccount(email: "lowest-eligible@example.com", fiveHourRemaining: 11, weeklyRemaining: 20),
                makeAccount(email: "fuller@example.com", fiveHourRemaining: 40, weeklyRemaining: 40)
            ],
            fiveHourThreshold: 10,
            weeklyThreshold: 5
        )

        #expect(winner?.email == "lowest-eligible@example.com")
    }

    @Test
    func summarizesFreshFleetQuotaAverages() {
        let summary = FleetQuotaSummary.make(
            from: [
                makeAccount(email: "one@example.com", fiveHourRemaining: 20, weeklyRemaining: 60),
                makeAccount(email: "two@example.com", fiveHourRemaining: 40, weeklyRemaining: 80),
                makeAccount(email: "stale@example.com", fiveHourRemaining: 100, weeklyRemaining: 100, isStale: true),
                makeAccount(email: "exhausted@example.com", fiveHourRemaining: 5, weeklyRemaining: 70)
            ],
            fiveHourThreshold: 10,
            weeklyThreshold: 5
        )

        #expect(summary.totalAccounts == 4)
        #expect(summary.freshAccounts == 3)
        #expect(summary.staleAccounts == 1)
        #expect(summary.exhaustedAccounts == 1)
        #expect(summary.averageFiveHourRemaining == 21)
        #expect(summary.averageWeeklyRemaining == 70)
        #expect(summary.lowestFiveHourRemaining == 5)
        #expect(summary.lowestWeeklyRemaining == 60)
    }

    @Test
    func fiveHourStrengthCountsNearResetRecovery() {
        let now = Date(timeIntervalSince1970: 1_779_000_000)
        let summary = FleetQuotaSummary.make(
            from: [
                makeAccount(
                    email: "near-reset@example.com",
                    fiveHourRemaining: 10,
                    weeklyRemaining: 100,
                    fiveHourResetAt: now.addingTimeInterval(30 * 60)
                )
            ],
            now: now
        )

        #expect(summary.averageFiveHourRemaining == 10)
        #expect(summary.averageFiveHourStrength == 91)
    }

    @Test
    func fiveHourStrengthIsCappedByLowWeeklyStrength() {
        let now = Date(timeIntervalSince1970: 1_779_000_000)
        let summary = FleetQuotaSummary.make(
            from: [
                makeAccount(
                    email: "weekly-limited@example.com",
                    fiveHourRemaining: 10,
                    weeklyRemaining: 2,
                    fiveHourResetAt: now.addingTimeInterval(30 * 60),
                    weeklyResetAt: now.addingTimeInterval(6 * 24 * 60 * 60)
                )
            ],
            now: now
        )

        #expect(summary.averageFiveHourStrength == 16)
        #expect(summary.averageWeeklyStrength == 16)
    }

    @Test
    func fiveHourStrengthAllowsRecoveryWhenWeeklyResetIsAlsoNear() {
        let now = Date(timeIntervalSince1970: 1_779_000_000)
        let summary = FleetQuotaSummary.make(
            from: [
                makeAccount(
                    email: "both-near-reset@example.com",
                    fiveHourRemaining: 10,
                    weeklyRemaining: 8,
                    fiveHourResetAt: now.addingTimeInterval(30 * 60),
                    weeklyResetAt: now.addingTimeInterval(12 * 60 * 60)
                )
            ],
            now: now
        )

        #expect(summary.averageFiveHourStrength == 91)
        #expect(summary.averageWeeklyStrength == 93)
    }

    @Test
    func fiveHourStrengthIgnoresHealthyWeeklyQuota() {
        let now = Date(timeIntervalSince1970: 1_779_000_000)
        let summary = FleetQuotaSummary.make(
            from: [
                makeAccount(
                    email: "healthy-weekly@example.com",
                    fiveHourRemaining: 93,
                    weeklyRemaining: 70,
                    fiveHourResetAt: now.addingTimeInterval(5 * 60 * 60),
                    weeklyResetAt: now.addingTimeInterval(7 * 24 * 60 * 60)
                )
            ],
            now: now
        )

        #expect(summary.averageFiveHourStrength == 93)
        #expect(summary.averageWeeklyStrength == 70)
    }

    @Test
    func weeklyStrengthCountsNearResetRecovery() {
        let now = Date(timeIntervalSince1970: 1_779_000_000)
        let summary = FleetQuotaSummary.make(
            from: [
                makeAccount(
                    email: "weekly-near-reset@example.com",
                    fiveHourRemaining: 80,
                    weeklyRemaining: 20,
                    weeklyResetAt: now.addingTimeInterval(24 * 60 * 60)
                )
            ],
            now: now
        )

        #expect(summary.averageWeeklyRemaining == 20)
        #expect(summary.averageWeeklyStrength == 89)
    }

    @Test
    func weeklyPaceSegmentsUseMinimumDaysLeftMinusOne() {
        let now = Date(timeIntervalSince1970: 1_779_000_000)
        let summary = FleetQuotaSummary.make(
            from: [
                makeAccount(
                    email: "four-days-left@example.com",
                    fiveHourRemaining: 80,
                    weeklyRemaining: 80,
                    weeklyResetAt: now.addingTimeInterval((4 * 24 * 60 * 60) - 1)
                ),
                makeAccount(
                    email: "seven-days-left@example.com",
                    fiveHourRemaining: 90,
                    weeklyRemaining: 90,
                    weeklyResetAt: now.addingTimeInterval(7 * 24 * 60 * 60)
                )
            ],
            now: now
        )

        #expect(summary.weeklyPaceSegmentCount == 3)
    }

    @Test
    func weeklyPaceSegmentsClampToSixForAFullWeek() {
        let now = Date(timeIntervalSince1970: 1_779_000_000)
        let summary = FleetQuotaSummary.make(
            from: [
                makeAccount(
                    email: "full-week@example.com",
                    fiveHourRemaining: 90,
                    weeklyRemaining: 90,
                    weeklyResetAt: now.addingTimeInterval(7 * 24 * 60 * 60)
                )
            ],
            now: now
        )

        #expect(summary.weeklyPaceSegmentCount == 6)
    }

    @Test
    func weeklyPaceSegmentsIgnoreStaleAccountsAndMissingResets() {
        let now = Date(timeIntervalSince1970: 1_779_000_000)
        let summary = FleetQuotaSummary.make(
            from: [
                makeAccount(
                    email: "stale-sooner@example.com",
                    fiveHourRemaining: 80,
                    weeklyRemaining: 80,
                    isStale: true,
                    weeklyResetAt: now.addingTimeInterval(24 * 60 * 60)
                ),
                makeAccount(
                    email: "missing-reset@example.com",
                    fiveHourRemaining: 80,
                    weeklyRemaining: 80
                ),
                makeAccount(
                    email: "fresh@example.com",
                    fiveHourRemaining: 80,
                    weeklyRemaining: 80,
                    weeklyResetAt: now.addingTimeInterval(3 * 24 * 60 * 60)
                )
            ],
            now: now
        )

        #expect(summary.weeklyPaceSegmentCount == 2)
    }

    @Test
    func strengthFallsBackToRemainingWhenResetTimeIsMissing() {
        let summary = FleetQuotaSummary.make(from: [
            makeAccount(email: "missing-reset@example.com", fiveHourRemaining: 35, weeklyRemaining: 45)
        ])

        #expect(summary.averageFiveHourStrength == 35)
        #expect(summary.averageWeeklyStrength == 45)
    }

    @Test
    func strengthExcludesStaleAccounts() {
        let now = Date(timeIntervalSince1970: 1_779_000_000)
        let summary = FleetQuotaSummary.make(
            from: [
                makeAccount(
                    email: "stale@example.com",
                    fiveHourRemaining: 5,
                    weeklyRemaining: 5,
                    isStale: true,
                    fiveHourResetAt: now,
                    weeklyResetAt: now
                ),
                makeAccount(email: "fresh@example.com", fiveHourRemaining: 40, weeklyRemaining: 50)
            ],
            now: now
        )

        #expect(summary.averageFiveHourStrength == 40)
        #expect(summary.averageWeeklyStrength == 50)
    }

    @Test
    func strengthAveragesMultipleAccounts() {
        let now = Date(timeIntervalSince1970: 1_779_000_000)
        let summary = FleetQuotaSummary.make(
            from: [
                makeAccount(
                    email: "half-reset@example.com",
                    fiveHourRemaining: 50,
                    weeklyRemaining: 100,
                    fiveHourResetAt: now.addingTimeInterval(150 * 60)
                ),
                makeAccount(email: "no-reset@example.com", fiveHourRemaining: 20, weeklyRemaining: 100)
            ],
            now: now
        )

        #expect(summary.averageFiveHourStrength == 48)
    }

    private func makeAccount(
        email: String,
        fiveHourRemaining: Int?,
        weeklyRemaining: Int?,
        isActive: Bool = false,
        isStale: Bool = false,
        fiveHourResetAt: Date? = nil,
        weeklyResetAt: Date? = nil
    ) -> AccountSnapshot {
        AccountSnapshot(
            accountKey: email,
            email: email,
            alias: nil,
            accountName: nil,
            plan: "Team",
            isActive: isActive,
            fiveHour: QuotaWindowState(
                usedPercent: fiveHourRemaining.map { 100 - $0 },
                resetAt: fiveHourResetAt,
                isStale: isStale
            ),
            weekly: QuotaWindowState(
                usedPercent: weeklyRemaining.map { 100 - $0 },
                resetAt: weeklyResetAt,
                isStale: isStale
            ),
            lastRefresh: .now
        )
    }
}

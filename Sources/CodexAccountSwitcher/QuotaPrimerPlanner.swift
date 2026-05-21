import Foundation

enum QuotaPrimerPlanner {
    static let attemptCooldown: TimeInterval = 60 * 60

    enum Mode {
        case expiredOrMissing
        case allAccounts
    }

    static func eligibleAccounts(
        from accounts: [AccountSnapshot],
        now: Date = .now,
        recentAttempts: [String: Date],
        mode: Mode = .expiredOrMissing
    ) -> [AccountSnapshot] {
        accounts.filter { account in
            guard account.hasIdentity,
                  !account.isUsageStale,
                  !hasRecentAttempt(account, now: now, recentAttempts: recentAttempts) else {
                return false
            }

            if mode == .allAccounts {
                return true
            }

            return accountNeedsPrimer(account, now: now)
        }
    }

    private static func accountNeedsPrimer(_ account: AccountSnapshot, now: Date) -> Bool {
        if !account.hasQuotaData {
            return true
        }

        return resetHasPassed(account.fiveHour.resetAt, now: now)
            || resetHasPassed(account.weekly.resetAt, now: now)
    }

    private static func resetHasPassed(_ resetAt: Date?, now: Date) -> Bool {
        guard let resetAt else {
            return false
        }

        return resetAt <= now
    }

    private static func hasRecentAttempt(
        _ account: AccountSnapshot,
        now: Date,
        recentAttempts: [String: Date]
    ) -> Bool {
        guard let lastAttempt = recentAttempts[account.accountKey] else {
            return false
        }

        return now.timeIntervalSince(lastAttempt) < attemptCooldown
    }
}

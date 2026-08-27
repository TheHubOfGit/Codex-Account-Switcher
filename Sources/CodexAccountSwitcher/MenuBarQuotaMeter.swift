import Foundation

struct MenuBarQuotaMeterState: Equatable {
    private static let fiveHourWindowDuration: TimeInterval = 5 * 60 * 60

    let remainingPercent: Int?
    let combinedRemainingPercent: Int?
    let resetProgress: Double?
    let isStale: Bool
    let limitLabel: String

    init(
        activeAccount: AccountSnapshot?,
        accounts: [AccountSnapshot] = [],
        now: Date = .now
    ) {
        let summary = FleetQuotaSummary.make(from: accounts, now: now)

        self.init(
            remainingPercent: activeAccount?.fiveHour.remainingPercent,
            combinedRemainingPercent: summary.averageFiveHourRemaining,
            resetProgress: Self.resetProgress(
                resetAt: activeAccount?.fiveHour.resetAt,
                now: now
            ),
            isStale: activeAccount?.fiveHour.isStale(at: now) ?? false,
            limitLabel: "5h"
        )
    }

    init(
        remainingPercent: Int?,
        combinedRemainingPercent: Int? = nil,
        resetProgress: Double? = nil,
        isStale: Bool,
        limitLabel: String = "5h"
    ) {
        self.remainingPercent = remainingPercent
        self.combinedRemainingPercent = combinedRemainingPercent
        self.resetProgress = resetProgress
        self.isStale = isStale
        self.limitLabel = limitLabel
    }

    var fillFraction: Double {
        guard let remainingPercent else {
            return 0
        }

        return min(max(Double(remainingPercent) / 100, 0), 1)
    }

    var combinedFillFraction: Double? {
        combinedRemainingPercent.map {
            min(max(Double($0) / 100, 0), 1)
        }
    }

    var resetProgressFraction: Double? {
        resetProgress.map { min(max($0, 0), 1) }
    }

    var accessibilityDescription: String {
        guard let remainingPercent else {
            return "\(limitLabel) limit unavailable"
        }

        let staleDetail = isStale ? ", stale" : ""
        var details = ["\(limitLabel) active account \(remainingPercent) percent left\(staleDetail)"]

        if let combinedRemainingPercent {
            details.append("all accounts average \(combinedRemainingPercent) percent left")
        }

        if let resetProgressFraction {
            details.append("\(Int((resetProgressFraction * 100).rounded())) percent through reset window")
        }

        return details.joined(separator: "; ")
    }

    private static func resetProgress(resetAt: Date?, now: Date) -> Double? {
        guard let resetAt else {
            return nil
        }

        let timeRemaining = resetAt.timeIntervalSince(now)
        return 1 - min(max(timeRemaining / fiveHourWindowDuration, 0), 1)
    }
}

import Foundation

enum QuotaSummary {
    static func limitLeft(for state: QuotaWindowState) -> String {
        guard let remaining = state.remainingPercent else {
            return "Unavailable"
        }

        if state.isStale {
            return "\(remaining)% left (stale)"
        }

        return "\(remaining)% left"
    }

    static func fiveHourLimitLeft(
        for state: QuotaWindowState,
        now: Date = .now
    ) -> String {
        limitLeft(
            for: state,
            resetDetail: state.resetAt.map { fiveHourResetTimeLeftText(until: $0, now: now) }
        )
    }

    static func weeklyLimitLeft(
        for state: QuotaWindowState,
        now: Date = .now
    ) -> String {
        limitLeft(
            for: state,
            resetDetail: state.resetAt.map { weeklyResetTimeLeftText(until: $0, now: now) }
        )
    }

    private static func limitLeft(
        for state: QuotaWindowState,
        resetDetail: String?
    ) -> String {
        guard let remaining = state.remainingPercent else {
            return "Unavailable"
        }

        let details = details(for: state, resetDetail: resetDetail)
        guard !details.isEmpty else {
            return "\(remaining)% left"
        }

        return "\(remaining)% left (\(details.joined(separator: ", ")))"
    }

    private static func details(
        for state: QuotaWindowState,
        resetDetail: String?
    ) -> [String] {
        var details: [String] = []

        if state.isStale {
            details.append("stale")
        }

        if let resetDetail {
            details.append(resetDetail)
        }

        return details
    }

    private static func fiveHourResetTimeLeftText(until resetAt: Date, now: Date) -> String {
        let secondsLeft = max(0, resetAt.timeIntervalSince(now))
        let unit: ResetUnit = secondsLeft < ResetUnit.hour.seconds ? .minute : .hour

        return resetTimeLeftText(secondsLeft: secondsLeft, unit: unit)
    }

    private static func weeklyResetTimeLeftText(until resetAt: Date, now: Date) -> String {
        let secondsLeft = max(0, resetAt.timeIntervalSince(now))
        let unit: ResetUnit = secondsLeft < ResetUnit.day.seconds ? .hour : .day

        return resetTimeLeftText(secondsLeft: secondsLeft, unit: unit)
    }

    private static func resetTimeLeftText(secondsLeft: TimeInterval, unit: ResetUnit) -> String {
        let amount = Int(ceil(secondsLeft / unit.seconds))
        let noun = amount == 1 ? unit.singular : unit.plural

        return "\(amount) \(noun) left"
    }

    private enum ResetUnit {
        case minute
        case hour
        case day

        var seconds: TimeInterval {
            switch self {
            case .minute:
                return 60
            case .hour:
                return 60 * 60
            case .day:
                return 24 * 60 * 60
            }
        }

        var singular: String {
            switch self {
            case .minute:
                return "minute"
            case .hour:
                return "hour"
            case .day:
                return "day"
            }
        }

        var plural: String {
            "\(singular)s"
        }
    }
}

import Foundation

enum ResetCreditsSummary {
    static func availability(
        for snapshot: RateLimitResetCreditsSnapshot?,
        now: Date = .now,
        staleAfter: TimeInterval = 30 * 60
    ) -> String {
        guard let snapshot else { return "Unavailable" }
        let count = snapshot.availableCount
        let label = count == 1 ? "1 available" : "\(count) available"
        return now.timeIntervalSince(snapshot.checkedAt) > staleAfter ? "\(label) · cached" : label
    }

    static func expiryLines(
        for snapshot: RateLimitResetCreditsSnapshot?,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> [String] {
        guard let snapshot else { return [] }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMd")

        var lines = snapshot.credits.map { credit in
            let rawTitle = credit.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = rawTitle?.isEmpty == false ? rawTitle! : "Full reset"
            guard let timestamp = credit.expiresAt else {
                return title
            }
            let date = Date(timeIntervalSince1970: timestamp)
            return "\(title) · expires \(formatter.string(from: date)) at \(expiryTime(for: credit, timeZone: timeZone))"
        }
        let hiddenCount = max(0, snapshot.availableCount - snapshot.credits.count)
        if hiddenCount > 0 {
            lines.append(hiddenCount == 1 ? "1 more reset" : "\(hiddenCount) more resets")
        }
        return lines
    }

    static func title(for credit: RateLimitResetCredit) -> String {
        let raw = credit.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return "Full reset" }
        if raw.localizedCaseInsensitiveContains("full reset") {
            return "Full reset"
        }
        return raw
    }

    static func expiryDate(
        for credit: RateLimitResetCredit,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        guard let timestamp = credit.expiresAt else { return "Date unavailable" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    static func expiryTime(
        for credit: RateLimitResetCredit,
        timeZone: TimeZone = .current
    ) -> String {
        guard let timestamp = credit.expiresAt else { return "Time unavailable" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mma"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp)).lowercased()
    }

    static func timeUntilExpiry(
        for credit: RateLimitResetCredit,
        now: Date = .now,
        calendar sourceCalendar: Calendar = .current
    ) -> String {
        guard let timestamp = credit.expiresAt else { return "Expiry unavailable" }
        let calendar = sourceCalendar
        let today = calendar.startOfDay(for: now)
        let expiry = calendar.startOfDay(for: Date(timeIntervalSince1970: timestamp))
        let days = calendar.dateComponents([.day], from: today, to: expiry).day ?? 0
        switch days {
        case ..<0:
            return "Expired"
        case 0:
            return "Today"
        case 1:
            return "Tomorrow"
        default:
            return "in \(days) days"
        }
    }

    static func isExpiringSoon(
        _ credit: RateLimitResetCredit,
        now: Date = .now
    ) -> Bool {
        guard let timestamp = credit.expiresAt else { return false }
        return timestamp <= now.addingTimeInterval(3 * 24 * 60 * 60).timeIntervalSince1970
    }
}

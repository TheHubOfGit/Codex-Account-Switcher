import Foundation

enum UsageMode: String, Equatable {
    case api
    case local
    case unknown

    var displayName: String {
        switch self {
        case .api:
            return "API-backed"
        case .local:
            return "Local-only"
        case .unknown:
            return "Unknown"
        }
    }
}

struct AuthStatus: Equatable {
    var autoSwitchEnabled: Bool
    var serviceStatus: String?
    var threshold5hPercent: Int?
    var thresholdWeeklyPercent: Int?
    var usageMode: UsageMode
    var accountMode: String?

    static func parse(_ output: String) -> AuthStatus {
        var status = AuthStatus(
            autoSwitchEnabled: false,
            serviceStatus: nil,
            threshold5hPercent: nil,
            thresholdWeeklyPercent: nil,
            usageMode: .unknown,
            accountMode: nil
        )

        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.hasPrefix("auto-switch:") {
                status.autoSwitchEnabled = line.localizedCaseInsensitiveContains("on")
            } else if line.hasPrefix("service:") {
                status.serviceStatus = line.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("thresholds:") {
                let values = line.components(separatedBy: ":").dropFirst().joined(separator: ":")
                status.threshold5hPercent = values.firstMatch(for: #"5h<(\d+)%"#).flatMap(Int.init)
                status.thresholdWeeklyPercent = values.firstMatch(for: #"weekly<(\d+)%"#).flatMap(Int.init)
            } else if line.hasPrefix("usage:") {
                let value = line.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                status.usageMode = UsageMode(rawValue: value) ?? .unknown
            } else if line.hasPrefix("account:") {
                status.accountMode = line.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            }
        }

        return status
    }
}

struct RegistrySnapshot: Decodable, Equatable {
    let activeAccountKey: String?
    let autoSwitch: AutoSwitchConfig
    let api: APIConfig
    let accounts: [RegistryAccount]

    enum CodingKeys: String, CodingKey {
        case activeAccountKey = "active_account_key"
        case autoSwitch = "auto_switch"
        case api
        case accounts
    }

    static func decode(from data: Data) throws -> RegistrySnapshot {
        let decoder = JSONDecoder()
        return try decoder.decode(RegistrySnapshot.self, from: data)
    }

    func accountSnapshots(now: Date = .now, staleAfter seconds: TimeInterval = 30 * 60) -> [AccountSnapshot] {
        accounts.map { account in
            let isActive = account.accountKey == activeAccountKey
            let lastRefreshDate = account.lastUsageAt.map(Date.init(timeIntervalSince1970:))
            let isStale = lastRefreshDate.map { now.timeIntervalSince($0) > seconds } ?? true

            let fiveHour = QuotaWindowState(
                usedPercent: account.lastUsage?.primary?.usedPercent,
                resetAt: account.lastUsage?.primary?.resetsAt.map(Date.init(timeIntervalSince1970:)),
                isStale: isStale
            )
            let weekly = QuotaWindowState(
                usedPercent: account.lastUsage?.secondary?.usedPercent,
                resetAt: account.lastUsage?.secondary?.resetsAt.map(Date.init(timeIntervalSince1970:)),
                isStale: isStale
            )

            return AccountSnapshot(
                accountKey: account.accountKey,
                email: account.email,
                alias: account.alias.nilIfBlank,
                accountName: account.accountName?.nilIfBlank,
                plan: (account.lastUsage?.planType ?? account.plan)?.capitalized,
                isActive: isActive,
                fiveHour: fiveHour,
                weekly: weekly,
                lastRefresh: lastRefreshDate
            )
        }
        .sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive && !rhs.isActive
            }

            return lhs.sortKey < rhs.sortKey
        }
    }
}

struct AutoSwitchConfig: Decodable, Equatable {
    let enabled: Bool
    let threshold5hPercent: Int
    let thresholdWeeklyPercent: Int

    enum CodingKeys: String, CodingKey {
        case enabled
        case threshold5hPercent = "threshold_5h_percent"
        case thresholdWeeklyPercent = "threshold_weekly_percent"
    }
}

struct APIConfig: Decodable, Equatable {
    let usage: Bool
}

struct RegistryAccount: Decodable, Equatable {
    let accountKey: String
    let email: String
    let alias: String
    let accountName: String?
    let plan: String?
    let lastUsage: UsageSnapshot?
    let lastUsageAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case accountKey = "account_key"
        case email
        case alias
        case accountName = "account_name"
        case plan
        case lastUsage = "last_usage"
        case lastUsageAt = "last_usage_at"
    }
}

struct UsageSnapshot: Decodable, Equatable {
    let primary: UsageWindow?
    let secondary: UsageWindow?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case planType = "plan_type"
    }
}

struct UsageWindow: Decodable, Equatable {
    let usedPercent: Int?
    let windowMinutes: Int?
    let resetsAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}

struct QuotaWindowState: Equatable {
    let usedPercent: Int?
    let resetAt: Date?
    let isStale: Bool

    var remainingPercent: Int? {
        usedPercent.map { max(0, 100 - $0) }
    }

    var hasData: Bool {
        usedPercent != nil
    }
}

struct AccountSnapshot: Identifiable, Equatable {
    let accountKey: String
    let email: String
    let alias: String?
    let accountName: String?
    let plan: String?
    let isActive: Bool
    let fiveHour: QuotaWindowState
    let weekly: QuotaWindowState
    let lastRefresh: Date?

    var id: String { accountKey }

    var primaryLabel: String {
        alias ?? accountName ?? email
    }

    var secondaryLabel: String? {
        primaryLabel == email ? nil : email
    }

    var planLabel: String {
        plan ?? "Unknown"
    }

    var hasIdentity: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasQuotaData: Bool {
        fiveHour.hasData || weekly.hasData
    }

    var isUsageStale: Bool {
        fiveHour.isStale || weekly.isStale
    }

    var averageRemainingPercent: Int? {
        let values = [fiveHour.remainingPercent, weekly.remainingPercent].compactMap(\.self)
        guard !values.isEmpty else {
            return nil
        }

        return values.reduce(0, +) / values.count
    }

    var lowestRemainingPercent: Int? {
        [fiveHour.remainingPercent, weekly.remainingPercent].compactMap(\.self).min()
    }

    func isExhausted(fiveHourThreshold: Int, weeklyThreshold: Int) -> Bool {
        if let fiveHourRemaining = fiveHour.remainingPercent,
           fiveHourRemaining <= fiveHourThreshold {
            return true
        }

        if let weeklyRemaining = weekly.remainingPercent,
           weeklyRemaining <= weeklyThreshold {
            return true
        }

        return false
    }

    func isEligibleForExhaustion(fiveHourThreshold: Int, weeklyThreshold: Int) -> Bool {
        hasIdentity
            && hasQuotaData
            && !isUsageStale
            && !isExhausted(fiveHourThreshold: fiveHourThreshold, weeklyThreshold: weeklyThreshold)
    }

    var sortKey: String {
        "\(primaryLabel.lowercased())|\(email.lowercased())"
    }
}

enum AccountRanking {
    static func bestCandidate(
        from accounts: [AccountSnapshot],
        fiveHourThreshold: Int = 0,
        weeklyThreshold: Int = 0
    ) -> AccountSnapshot? {
        let candidates = accounts.filter { account in
            account.isEligibleForExhaustion(
                fiveHourThreshold: fiveHourThreshold,
                weeklyThreshold: weeklyThreshold
            )
        }

        guard !candidates.isEmpty else {
            return nil
        }

        return candidates.sorted { lhs, rhs in
            let lhsLowest = lhs.lowestRemainingPercent ?? Int.max
            let rhsLowest = rhs.lowestRemainingPercent ?? Int.max
            if lhsLowest != rhsLowest {
                return lhsLowest < rhsLowest
            }

            let lhsAverage = lhs.averageRemainingPercent ?? Int.max
            let rhsAverage = rhs.averageRemainingPercent ?? Int.max
            if lhsAverage != rhsAverage {
                return lhsAverage < rhsAverage
            }

            let lhsFive = lhs.fiveHour.remainingPercent ?? Int.max
            let rhsFive = rhs.fiveHour.remainingPercent ?? Int.max
            if lhsFive != rhsFive {
                return lhsFive < rhsFive
            }

            if lhs.isActive != rhs.isActive {
                return !lhs.isActive && rhs.isActive
            }

            return lhs.email.localizedCaseInsensitiveCompare(rhs.email) == .orderedAscending
        }.first
    }
}

struct FleetQuotaSummary: Equatable {
    private static let weeklyBottleneckThreshold = 30.0

    let totalAccounts: Int
    let freshAccounts: Int
    let staleAccounts: Int
    let exhaustedAccounts: Int
    let averageFiveHourStrength: Int?
    let averageWeeklyStrength: Int?
    let averageFiveHourRemaining: Int?
    let averageWeeklyRemaining: Int?
    let lowestFiveHourRemaining: Int?
    let lowestWeeklyRemaining: Int?

    var hasQuotaData: Bool {
        averageFiveHourRemaining != nil || averageWeeklyRemaining != nil
    }

    static func make(
        from accounts: [AccountSnapshot],
        now: Date = .now,
        fiveHourThreshold: Int = 0,
        weeklyThreshold: Int = 0
    ) -> FleetQuotaSummary {
        let freshAccounts = accounts.filter { $0.hasQuotaData && !$0.isUsageStale }
        let staleAccountCount = accounts.filter { $0.hasQuotaData && $0.isUsageStale }.count
        let exhaustedAccountCount = freshAccounts.filter {
            $0.isExhausted(fiveHourThreshold: fiveHourThreshold, weeklyThreshold: weeklyThreshold)
        }.count

        let fiveHourValues = freshAccounts.compactMap(\.fiveHour.remainingPercent)
        let weeklyValues = freshAccounts.compactMap(\.weekly.remainingPercent)
        let fiveHourStrengthValues = freshAccounts.compactMap {
            fiveHourStrength(for: $0, now: now)
        }
        let weeklyStrengthValues = freshAccounts.compactMap {
            strength(for: $0.weekly, windowDuration: 7 * 24 * 60 * 60, now: now)
        }

        return FleetQuotaSummary(
            totalAccounts: accounts.count,
            freshAccounts: freshAccounts.count,
            staleAccounts: staleAccountCount,
            exhaustedAccounts: exhaustedAccountCount,
            averageFiveHourStrength: averageStrength(fiveHourStrengthValues),
            averageWeeklyStrength: averageStrength(weeklyStrengthValues),
            averageFiveHourRemaining: average(fiveHourValues),
            averageWeeklyRemaining: average(weeklyValues),
            lowestFiveHourRemaining: fiveHourValues.min(),
            lowestWeeklyRemaining: weeklyValues.min()
        )
    }

    private static func average(_ values: [Int]) -> Int? {
        guard !values.isEmpty else {
            return nil
        }

        return values.reduce(0, +) / values.count
    }

    private static func fiveHourStrength(for account: AccountSnapshot, now: Date) -> Double? {
        guard let fiveHourStrength = strength(
            for: account.fiveHour,
            windowDuration: 5 * 60 * 60,
            now: now
        ) else {
            return nil
        }

        guard let weeklyStrength = strength(
            for: account.weekly,
            windowDuration: 7 * 24 * 60 * 60,
            now: now
        ) else {
            return fiveHourStrength
        }

        guard weeklyStrength < weeklyBottleneckThreshold else {
            return fiveHourStrength
        }

        return min(fiveHourStrength, weeklyStrength)
    }

    private static func strength(
        for state: QuotaWindowState,
        windowDuration: TimeInterval,
        now: Date
    ) -> Double? {
        guard let remaining = state.remainingPercent else {
            return nil
        }

        guard let resetAt = state.resetAt else {
            return Double(remaining)
        }

        let resetRatio = resetAt.timeIntervalSince(now) / windowDuration
        let resetProgress = 1 - min(max(resetRatio, 0), 1)
        return Double(remaining) + (Double(100 - remaining) * resetProgress)
    }

    private static func averageStrength(_ values: [Double]) -> Int? {
        guard !values.isEmpty else {
            return nil
        }

        return Int((values.reduce(0, +) / Double(values.count)).rounded())
    }
}

enum SetupIssue: Error, Equatable {
    case missingCodexAuth
    case missingRegistry
    case unreadableRegistry(String)

    var title: String {
        switch self {
        case .missingCodexAuth:
            return "codex-auth not found"
        case .missingRegistry:
            return "registry.json not found"
        case .unreadableRegistry:
            return "registry.json unreadable"
        }
    }

    var message: String {
        switch self {
        case .missingCodexAuth:
            return "Install @loongphy/codex-auth and make sure it is available in /opt/homebrew/bin, /usr/local/bin, or your PATH."
        case .missingRegistry:
            return "Run codex-auth login or codex-auth import so ~/.codex/accounts/registry.json exists."
        case .unreadableRegistry(let detail):
            return detail
        }
    }
}

extension String {
    fileprivate var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }

    fileprivate func firstMatch(for pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range),
              match.numberOfRanges > 1,
              let matchedRange = Range(match.range(at: 1), in: self) else {
            return nil
        }

        return String(self[matchedRange])
    }
}

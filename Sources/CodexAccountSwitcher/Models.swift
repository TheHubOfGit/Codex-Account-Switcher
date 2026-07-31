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

struct CodexAuthVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int

    static let minimumSupported = CodexAuthVersion(major: 0, minor: 2, patch: 10)

    init?(output: String) {
        guard let match = output.firstMatch(for: #"(\d+\.\d+\.\d+)"#) else {
            return nil
        }
        let parts = match.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        major = parts[0]
        minor = parts[1]
        patch = parts[2]
    }

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: CodexAuthVersion, rhs: CodexAuthVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
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
    var refreshedAt: Date?

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

    func accountSnapshots(
        now: Date = .now,
        staleAfter seconds: TimeInterval = 30 * 60,
        usageCheckedAtByAccountKey: [String: Date] = [:],
        resetCreditsByAccountKey: [String: RateLimitResetCreditsSnapshot] = [:]
    ) -> [AccountSnapshot] {
        return accounts.map { account in
            let isActive = account.accountKey == activeAccountKey
            let lastRefreshDate = account.lastUsageAt.map(Date.init(timeIntervalSince1970:))
            let checkedAt = usageCheckedAtByAccountKey[account.accountKey] ?? lastRefreshDate
            let windows = account.lastUsage?.classifiedWindows

            let fiveHour = QuotaWindowState(
                usedPercent: windows?.fiveHour?.usedPercent,
                resetAt: windows?.fiveHour?.resetsAt.map(Date.init(timeIntervalSince1970:)),
                checkedAt: checkedAt,
                staleAfter: seconds
            )
            let weekly = QuotaWindowState(
                usedPercent: windows?.weekly?.usedPercent,
                resetAt: windows?.weekly?.resetsAt.map(Date.init(timeIntervalSince1970:)),
                checkedAt: checkedAt,
                staleAfter: seconds
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
                lastRefresh: lastRefreshDate,
                resetCredits: resetCreditsByAccountKey[account.accountKey]
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
    let chatGPTAccountID: String?

    enum CodingKeys: String, CodingKey {
        case accountKey = "account_key"
        case email
        case alias
        case accountName = "account_name"
        case plan
        case lastUsage = "last_usage"
        case lastUsageAt = "last_usage_at"
        case chatGPTAccountID = "chatgpt_account_id"
    }

    init(
        accountKey: String,
        email: String,
        alias: String,
        accountName: String?,
        plan: String?,
        lastUsage: UsageSnapshot?,
        lastUsageAt: TimeInterval?,
        chatGPTAccountID: String? = nil
    ) {
        self.accountKey = accountKey
        self.email = email
        self.alias = alias
        self.accountName = accountName
        self.plan = plan
        self.lastUsage = lastUsage
        self.lastUsageAt = lastUsageAt
        self.chatGPTAccountID = chatGPTAccountID
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

    var classifiedWindows: (fiveHour: UsageWindow?, weekly: UsageWindow?) {
        let windows = [primary, secondary].compactMap(\.self)
        let fiveHour = windows.first { $0.windowMinutes == 5 * 60 }
        let weekly = windows.first { $0.windowMinutes == 7 * 24 * 60 }

        if fiveHour != nil || weekly != nil {
            return (fiveHour, weekly)
        }

        // Compatibility with older registry entries that did not record durations.
        return (primary, secondary)
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
    let checkedAt: Date?
    let staleAfter: TimeInterval
    private let staleOverride: Bool?

    init(
        usedPercent: Int?,
        resetAt: Date?,
        checkedAt: Date?,
        staleAfter: TimeInterval = 30 * 60
    ) {
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.checkedAt = checkedAt
        self.staleAfter = staleAfter
        staleOverride = nil
    }

    init(usedPercent: Int?, resetAt: Date?, isStale: Bool) {
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        checkedAt = nil
        staleAfter = 30 * 60
        staleOverride = isStale
    }

    var isStale: Bool {
        isStale(at: .now)
    }

    func isStale(at now: Date) -> Bool {
        if let staleOverride {
            return staleOverride
        }

        guard let checkedAt else {
            return true
        }

        return now.timeIntervalSince(checkedAt) > staleAfter
    }

    func isResetPending(at now: Date = .now) -> Bool {
        guard let resetAt else { return false }
        return resetAt <= now
    }

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
    let resetCredits: RateLimitResetCreditsSnapshot?

    init(
        accountKey: String,
        email: String,
        alias: String?,
        accountName: String?,
        plan: String?,
        isActive: Bool,
        fiveHour: QuotaWindowState,
        weekly: QuotaWindowState,
        lastRefresh: Date?,
        resetCredits: RateLimitResetCreditsSnapshot? = nil
    ) {
        self.accountKey = accountKey
        self.email = email
        self.alias = alias
        self.accountName = accountName
        self.plan = plan
        self.isActive = isActive
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.lastRefresh = lastRefresh
        self.resetCredits = resetCredits
    }

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
        isUsageStale(at: .now)
    }

    func isUsageStale(at now: Date) -> Bool {
        fiveHour.isStale(at: now) || weekly.isStale(at: now)
    }

    func hasResetPending(at now: Date = .now) -> Bool {
        fiveHour.isResetPending(at: now) || weekly.isResetPending(at: now)
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
            && !hasResetPending()
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
    private static let dayDuration: TimeInterval = 24 * 60 * 60

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
    let weeklyPaceSegmentCount: Int

    var hasQuotaData: Bool {
        averageFiveHourRemaining != nil || averageWeeklyRemaining != nil
    }

    static func make(
        from accounts: [AccountSnapshot],
        now: Date = .now,
        fiveHourThreshold: Int = 0,
        weeklyThreshold: Int = 0
    ) -> FleetQuotaSummary {
        let freshAccounts = accounts.filter {
            $0.hasQuotaData && !$0.isUsageStale(at: now) && !$0.hasResetPending(at: now)
        }
        let staleAccountCount = accounts.filter {
            $0.hasQuotaData && ($0.isUsageStale(at: now) || $0.hasResetPending(at: now))
        }.count
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
        let weeklyPaceSegmentCount = weeklyPaceSegmentCount(from: freshAccounts, now: now)

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
            lowestWeeklyRemaining: weeklyValues.min(),
            weeklyPaceSegmentCount: weeklyPaceSegmentCount
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

    private static func weeklyPaceSegmentCount(from accounts: [AccountSnapshot], now: Date) -> Int {
        let daysLeftValues = accounts.compactMap { account -> Int? in
            guard account.weekly.hasData,
                  let resetAt = account.weekly.resetAt else {
                return nil
            }

            let secondsLeft = max(0, resetAt.timeIntervalSince(now))
            return Int(ceil(secondsLeft / dayDuration))
        }

        guard let minimumDaysLeft = daysLeftValues.min() else {
            return 0
        }

        return min(max(minimumDaysLeft - 1, 0), 6)
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

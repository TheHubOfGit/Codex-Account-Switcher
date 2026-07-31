import Foundation

struct UsageRefreshResult: Equatable, Sendable {
    static let success = UsageRefreshResult()

    let successfulAccountEmails: Set<String>
    let failedAccounts: [String: String]
    let hadUnattributedFailure: Bool

    init(
        successfulAccountEmails: Set<String> = [],
        failedAccounts: [String: String] = [:],
        hadUnattributedFailure: Bool = false
    ) {
        self.successfulAccountEmails = Set(successfulAccountEmails.map { $0.lowercased() })
        self.failedAccounts = Dictionary(
            uniqueKeysWithValues: failedAccounts.map { ($0.key.lowercased(), $0.value) }
        )
        self.hadUnattributedFailure = hadUnattributedFailure
    }

    var hasFailures: Bool {
        hadUnattributedFailure || !failedAccounts.isEmpty
    }
}

struct PrimerAccountIdentity: Equatable, Sendable {
    let accountKey: String
    let email: String
    let chatGPTAccountID: String
}

struct PrimerDeliveryResult: Equatable, Sendable {
    let accountKey: String
    let response: String
}

struct RateLimitResetCredit: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let resetType: String?
    let status: String?
    let grantedAt: TimeInterval?
    let expiresAt: TimeInterval?
    let title: String?
    let description: String?
}

struct RateLimitResetCreditsSnapshot: Codable, Equatable, Sendable {
    let availableCount: Int
    let credits: [RateLimitResetCredit]
    let checkedAt: Date
}

protocol CodexAuthRunning: Sendable {
    func version() async throws -> String
    func refreshUsage() async throws -> UsageRefreshResult
    func readRateLimitResetCredits(account: PrimerAccountIdentity) async throws -> RateLimitResetCreditsSnapshot
    func status() async throws -> AuthStatus
    func switchAccount(query: String) async throws
    func primeUsage(account: PrimerAccountIdentity) async throws -> PrimerDeliveryResult
    func setAutoSwitch(enabled: Bool) async throws
    func setThresholds(fiveHour: Int, weekly: Int) async throws
    func setUsageAPI(enabled: Bool) async throws
    func executableExists() async -> Bool
}

extension CodexAuthRunning {
    func version() async throws -> String { "0.2.10" }

    func readRateLimitResetCredits(
        account: PrimerAccountIdentity
    ) async throws -> RateLimitResetCreditsSnapshot {
        throw CodexAuthError.invalidRateLimitResponse
    }
}

protocol RegistryStoring: AnyObject {
    func loadSnapshot() throws -> RegistrySnapshot
    func startWatching(onChange: @escaping () -> Void)
}

@MainActor
protocol CodexAppControlling: AnyObject {
    func quitCodex() async throws -> Bool
    func launchCodex() async throws
    func relaunchCodex() async throws
}

@MainActor
protocol NotificationManaging: AnyObject {
    func requestAuthorization()
    func notify(title: String, body: String)
    func promptForAutoSwitch(
        from currentAccount: AccountSnapshot,
        to candidate: AccountSnapshot,
        onConfirm: @escaping () async -> Void
    )
}

import Foundation
import Testing
@testable import CodexAccountSwitcher

@MainActor
struct AppStateSwitchTests {
    @Test
    func notificationApprovedSwitchDoesNotSendSuccessBanner() async {
        let target = makeAccountSnapshot(accountKey: "acct-2", email: "two@example.com")
        let notifications = RecordingNotifications()
        let codexController = RecordingCodexController()

        let appState = AppState(
            authRunner: RecordingAuthRunner(),
            registryStore: SnapshotRegistryStore(snapshot: makeRegistrySnapshot(activeAccountKey: "acct-2")),
            codexController: codexController,
            notifications: notifications,
            startAutomatically: false
        )

        await appState.switchToAccount(target, notifyOnSuccess: false)

        #expect(codexController.relaunchCount == 1)
        #expect(!notifications.delivered.contains { $0.title == "Account switched" })
    }

    @Test
    func backgroundRefreshDefaultsToOffWithTenMinuteInterval() async {
        let defaults = makeIsolatedDefaults()

        let appState = AppState(
            authRunner: RecordingAuthRunner(),
            registryStore: SnapshotRegistryStore(snapshot: makeRegistrySnapshot(activeAccountKey: "acct-2")),
            codexController: RecordingCodexController(),
            notifications: RecordingNotifications(),
            startAutomatically: false,
            userDefaults: defaults
        )

        #expect(!appState.backgroundRefreshEnabled)
        #expect(appState.backgroundRefreshIntervalMinutes == 10)
    }

    @Test
    func backgroundRefreshSettingsPersistAcrossAppStateInstances() async {
        let defaults = makeIsolatedDefaults()

        let appState = AppState(
            authRunner: RecordingAuthRunner(),
            registryStore: SnapshotRegistryStore(snapshot: makeRegistrySnapshot(activeAccountKey: "acct-2")),
            codexController: RecordingCodexController(),
            notifications: RecordingNotifications(),
            startAutomatically: false,
            userDefaults: defaults
        )

        appState.setBackgroundRefresh(enabled: true, intervalMinutes: 15)

        let reloadedState = AppState(
            authRunner: RecordingAuthRunner(),
            registryStore: SnapshotRegistryStore(snapshot: makeRegistrySnapshot(activeAccountKey: "acct-2")),
            codexController: RecordingCodexController(),
            notifications: RecordingNotifications(),
            startAutomatically: false,
            userDefaults: defaults
        )

        #expect(reloadedState.backgroundRefreshEnabled)
        #expect(reloadedState.backgroundRefreshIntervalMinutes == 15)
    }

    @Test
    func backgroundRefreshRejectsUnsupportedIntervals() async {
        let defaults = makeIsolatedDefaults()
        let appState = AppState(
            authRunner: RecordingAuthRunner(),
            registryStore: SnapshotRegistryStore(snapshot: makeRegistrySnapshot(activeAccountKey: "acct-2")),
            codexController: RecordingCodexController(),
            notifications: RecordingNotifications(),
            startAutomatically: false,
            userDefaults: defaults
        )

        appState.setBackgroundRefresh(enabled: true, intervalMinutes: 3)

        #expect(appState.backgroundRefreshEnabled)
        #expect(appState.backgroundRefreshIntervalMinutes == 10)
    }

    @Test
    func partialRefreshPersistsFreshnessOnlyForVerifiedAccount() async {
        let defaults = makeIsolatedDefaults()
        let snapshot = makeTwoAccountRegistrySnapshot()
        let result = UsageRefreshResult(
            successfulAccountEmails: ["fresh@example.com"],
            failedAccounts: ["failed@example.com": "401 Unauthorized"]
        )
        let firstState = AppState(
            authRunner: RecordingAuthRunner(refreshResult: result),
            registryStore: SnapshotRegistryStore(snapshot: snapshot),
            codexController: RecordingCodexController(),
            notifications: RecordingNotifications(),
            startAutomatically: false,
            userDefaults: defaults
        )

        await firstState.refreshAll(showNotifications: false)
        let firstFresh = firstState.accounts.first { $0.email == "fresh@example.com" }!
        let firstFailed = firstState.accounts.first { $0.email == "failed@example.com" }!
        #expect(!firstFresh.isUsageStale)
        #expect(firstFailed.isUsageStale)
        #expect(firstState.refreshWarningMessage?.contains("1 refreshed, 1 cached") == true)

        let reloadedState = AppState(
            authRunner: RecordingAuthRunner(),
            registryStore: SnapshotRegistryStore(snapshot: snapshot),
            codexController: RecordingCodexController(),
            notifications: RecordingNotifications(),
            startAutomatically: false,
            userDefaults: defaults
        )
        await reloadedState.refreshAll(showNotifications: false)

        #expect(!reloadedState.accounts.first { $0.email == "fresh@example.com" }!.isUsageStale)
        #expect(reloadedState.accounts.first { $0.email == "failed@example.com" }!.isUsageStale)

        let failedRefreshState = AppState(
            authRunner: RecordingAuthRunner(refreshThrows: true),
            registryStore: SnapshotRegistryStore(snapshot: snapshot),
            codexController: RecordingCodexController(),
            notifications: RecordingNotifications(),
            startAutomatically: false,
            userDefaults: defaults
        )
        await failedRefreshState.refreshAll(showNotifications: false)

        #expect(!failedRefreshState.accounts.first { $0.email == "fresh@example.com" }!.isUsageStale)
        #expect(failedRefreshState.accounts.first { $0.email == "failed@example.com" }!.isUsageStale)
    }
}

actor RecordingAuthRunner: CodexAuthRunning {
    private(set) var refreshUsageCount = 0
    private(set) var primeRequests: [RecordedPrimeRequest] = []
    private(set) var switchQueries: [String] = []
    private let refreshResult: UsageRefreshResult
    private let failedPrimeAccountKeys: Set<String>
    private let refreshThrows: Bool

    init(
        refreshResult: UsageRefreshResult = .success,
        failedPrimeAccountKeys: Set<String> = [],
        refreshThrows: Bool = false
    ) {
        self.refreshResult = refreshResult
        self.failedPrimeAccountKeys = failedPrimeAccountKeys
        self.refreshThrows = refreshThrows
    }

    func refreshUsage() async throws -> UsageRefreshResult {
        refreshUsageCount += 1
        if refreshThrows {
            throw RecordingAuthRunnerError.refreshFailed
        }
        return refreshResult
    }

    func status() async throws -> AuthStatus {
        AuthStatus(
            autoSwitchEnabled: true,
            serviceStatus: nil,
            threshold5hPercent: 10,
            thresholdWeeklyPercent: 5,
            usageMode: .local,
            accountMode: nil
        )
    }

    func switchAccount(query: String) async throws {
        switchQueries.append(query)
    }
    func primeUsage(account: PrimerAccountIdentity) async throws -> PrimerDeliveryResult {
        primeRequests.append(.init(accountKey: account.accountKey, accountQuery: account.email))
        if failedPrimeAccountKeys.contains(account.accountKey) {
            throw RecordingAuthRunnerError.primeFailed
        }
        return PrimerDeliveryResult(accountKey: account.accountKey, response: "hi")
    }

    func setAutoSwitch(enabled: Bool) async throws {}
    func setThresholds(fiveHour: Int, weekly: Int) async throws {}
    func setUsageAPI(enabled: Bool) async throws {}
    func executableExists() async -> Bool { true }
}

private enum RecordingAuthRunnerError: LocalizedError {
    case primeFailed
    case refreshFailed

    var errorDescription: String? {
        switch self {
        case .primeFailed: "Primer request failed"
        case .refreshFailed: "Refresh failed"
        }
    }
}

struct RecordedPrimeRequest: Equatable {
    let accountKey: String
    let accountQuery: String
}

final class SnapshotRegistryStore: RegistryStoring {
    let snapshot: RegistrySnapshot

    init(snapshot: RegistrySnapshot) {
        self.snapshot = snapshot
    }

    func loadSnapshot() throws -> RegistrySnapshot {
        snapshot
    }

    func startWatching(onChange: @escaping () -> Void) {}
}

@MainActor
final class RecordingCodexController: CodexAppControlling {
    private(set) var relaunchCount = 0
    private(set) var quitCount = 0
    private(set) var launchCount = 0
    var isCodexRunning = true

    func quitCodex() async throws -> Bool {
        quitCount += 1
        let wasRunning = isCodexRunning
        isCodexRunning = false
        return wasRunning
    }

    func launchCodex() async throws {
        launchCount += 1
        isCodexRunning = true
    }

    func relaunchCodex() async throws {
        relaunchCount += 1
    }
}

@MainActor
final class RecordingNotifications: NotificationManaging {
    private(set) var delivered: [(title: String, body: String)] = []

    func requestAuthorization() {}

    func notify(title: String, body: String) {
        delivered.append((title, body))
    }

    func promptForAutoSwitch(
        from currentAccount: AccountSnapshot,
        to candidate: AccountSnapshot,
        onConfirm: @escaping () async -> Void
    ) {}
}

private func makeAccountSnapshot(accountKey: String, email: String, isActive: Bool = false) -> AccountSnapshot {
    AccountSnapshot(
        accountKey: accountKey,
        email: email,
        alias: nil,
        accountName: nil,
        plan: "Team",
        isActive: isActive,
        fiveHour: QuotaWindowState(usedPercent: 20, resetAt: nil, isStale: false),
        weekly: QuotaWindowState(usedPercent: 30, resetAt: nil, isStale: false),
        lastRefresh: .now
    )
}

private func makeRegistrySnapshot(activeAccountKey: String) -> RegistrySnapshot {
    RegistrySnapshot(
        activeAccountKey: activeAccountKey,
        autoSwitch: AutoSwitchConfig(enabled: true, threshold5hPercent: 10, thresholdWeeklyPercent: 5),
        api: APIConfig(usage: false),
        accounts: [
            RegistryAccount(
                accountKey: activeAccountKey,
                email: "two@example.com",
                alias: "",
                accountName: nil,
                plan: "team",
                lastUsage: UsageSnapshot(
                    primary: UsageWindow(usedPercent: 20, windowMinutes: 300, resetsAt: nil),
                    secondary: UsageWindow(usedPercent: 30, windowMinutes: 10_080, resetsAt: nil),
                    planType: "team"
                ),
                lastUsageAt: Date.now.timeIntervalSince1970,
                chatGPTAccountID: "chatgpt-\(activeAccountKey)"
            )
        ]
    )
}

private func makeTwoAccountRegistrySnapshot() -> RegistrySnapshot {
    let oldTimestamp = Date.now.addingTimeInterval(-3_600).timeIntervalSince1970
    return RegistrySnapshot(
        activeAccountKey: "fresh",
        autoSwitch: AutoSwitchConfig(enabled: false, threshold5hPercent: 10, thresholdWeeklyPercent: 5),
        api: APIConfig(usage: true),
        accounts: [
            RegistryAccount(
                accountKey: "fresh",
                email: "fresh@example.com",
                alias: "",
                accountName: nil,
                plan: "team",
                lastUsage: UsageSnapshot(
                    primary: UsageWindow(usedPercent: 20, windowMinutes: 300, resetsAt: nil),
                    secondary: UsageWindow(usedPercent: 30, windowMinutes: 10_080, resetsAt: nil),
                    planType: "team"
                ),
                lastUsageAt: oldTimestamp,
                chatGPTAccountID: "chatgpt-fresh"
            ),
            RegistryAccount(
                accountKey: "failed",
                email: "failed@example.com",
                alias: "",
                accountName: nil,
                plan: "team",
                lastUsage: UsageSnapshot(
                    primary: UsageWindow(usedPercent: 40, windowMinutes: 300, resetsAt: nil),
                    secondary: UsageWindow(usedPercent: 50, windowMinutes: 10_080, resetsAt: nil),
                    planType: "team"
                ),
                lastUsageAt: oldTimestamp,
                chatGPTAccountID: "chatgpt-failed"
            )
        ]
    )
}

private func makeIsolatedDefaults() -> UserDefaults {
    let suiteName = "CodexAccountSwitcherTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

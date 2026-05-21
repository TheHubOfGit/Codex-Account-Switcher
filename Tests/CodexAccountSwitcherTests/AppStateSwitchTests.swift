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
}

actor RecordingAuthRunner: CodexAuthRunning {
    private(set) var refreshUsageCount = 0
    private(set) var primeRequests: [RecordedPrimeRequest] = []

    func refreshUsage() async throws {
        refreshUsageCount += 1
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

    func switchAccount(query: String) async throws {}
    func primeUsage(accountKey: String, accountQuery: String) async throws {
        primeRequests.append(.init(accountKey: accountKey, accountQuery: accountQuery))
    }

    func setAutoSwitch(enabled: Bool) async throws {}
    func setThresholds(fiveHour: Int, weekly: Int) async throws {}
    func setUsageAPI(enabled: Bool) async throws {}
    func executableExists() async -> Bool { true }
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
                lastUsageAt: Date.now.timeIntervalSince1970
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

import Foundation
import Testing
@testable import CodexAccountSwitcher

@MainActor
struct QuotaPrimerTests {
    @Test
    func quotaPrimerDefaultsToOffWithThirtyMinuteInterval() async {
        let defaults = makePrimerDefaults()

        let appState = AppState(
            authRunner: RecordingAuthRunner(),
            registryStore: SnapshotRegistryStore(snapshot: makePrimerRegistrySnapshot(accounts: [])),
            codexController: RecordingCodexController(),
            notifications: RecordingNotifications(),
            startAutomatically: false,
            userDefaults: defaults
        )

        #expect(!appState.quotaPrimerEnabled)
        #expect(appState.quotaPrimerIntervalMinutes == 30)
    }

    @Test
    func quotaPrimerSettingsPersistAcrossAppStateInstances() async {
        let defaults = makePrimerDefaults()
        let appState = AppState(
            authRunner: RecordingAuthRunner(),
            registryStore: SnapshotRegistryStore(snapshot: makePrimerRegistrySnapshot(accounts: [])),
            codexController: RecordingCodexController(),
            notifications: RecordingNotifications(),
            startAutomatically: false,
            userDefaults: defaults
        )

        appState.setQuotaPrimer(enabled: true, intervalMinutes: 60)

        let reloadedState = AppState(
            authRunner: RecordingAuthRunner(),
            registryStore: SnapshotRegistryStore(snapshot: makePrimerRegistrySnapshot(accounts: [])),
            codexController: RecordingCodexController(),
            notifications: RecordingNotifications(),
            startAutomatically: false,
            userDefaults: defaults
        )

        #expect(reloadedState.quotaPrimerEnabled)
        #expect(reloadedState.quotaPrimerIntervalMinutes == 60)
    }

    @Test
    func plannerIncludesExpiredAndMissingQuotaAccounts() {
        let now = Date(timeIntervalSince1970: 1_779_000_000)
        let accounts = [
            makePrimerAccount(accountKey: "active", email: "active@example.com", isActive: true, weeklyResetAt: now.addingTimeInterval(3_600)),
            makePrimerAccount(accountKey: "expired", email: "expired@example.com", weeklyResetAt: now.addingTimeInterval(-60)),
            makePrimerAccount(accountKey: "missing", email: "missing@example.com", hasUsage: false),
            makePrimerAccount(accountKey: "future", email: "future@example.com", weeklyResetAt: now.addingTimeInterval(86_400))
        ]

        let eligible = QuotaPrimerPlanner.eligibleAccounts(from: accounts, now: now, recentAttempts: [:])

        #expect(eligible.map(\.accountKey) == ["expired", "missing"])
    }

    @Test
    func plannerSkipsRecentlyAttemptedAccounts() {
        let now = Date(timeIntervalSince1970: 1_779_000_000)
        let accounts = [
            makePrimerAccount(accountKey: "expired", email: "expired@example.com", weeklyResetAt: now.addingTimeInterval(-60))
        ]

        let eligible = QuotaPrimerPlanner.eligibleAccounts(
            from: accounts,
            now: now,
            recentAttempts: ["expired": now.addingTimeInterval(-10 * 60)]
        )

        #expect(eligible.isEmpty)
    }

    @Test
    func scheduledPrimerPrimesEligibleAccountsAndRefreshesAfterward() async {
        let now = Date(timeIntervalSince1970: 1_779_000_000)
        let authRunner = RecordingAuthRunner()
        let appState = AppState(
            authRunner: authRunner,
            registryStore: SnapshotRegistryStore(
                snapshot: makePrimerRegistrySnapshot(
                    activeAccountKey: "active",
                    accounts: [
                        makePrimerRegistryAccount(accountKey: "active", email: "active@example.com", weeklyResetAt: now.addingTimeInterval(86_400)),
                        makePrimerRegistryAccount(accountKey: "expired", email: "expired@example.com", weeklyResetAt: now.addingTimeInterval(-60))
                    ]
                )
            ),
            codexController: RecordingCodexController(),
            notifications: RecordingNotifications(),
            startAutomatically: false,
            userDefaults: makePrimerDefaults()
        )

        await appState.refreshAll(showNotifications: false)
        appState.setQuotaPrimer(enabled: true)
        await appState.runQuotaPrimerNow(now: now)

        let requests = await authRunner.primeRequests
        #expect(requests == [
            .init(accountQuery: "expired@example.com", restoreQuery: "active@example.com")
        ])
        #expect(await authRunner.refreshUsageCount == 2)
    }
}

private func makePrimerDefaults() -> UserDefaults {
    let suiteName = "CodexAccountSwitcherQuotaPrimerTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private func makePrimerAccount(
    accountKey: String,
    email: String,
    isActive: Bool = false,
    hasUsage: Bool = true,
    weeklyResetAt: Date? = nil
) -> AccountSnapshot {
    AccountSnapshot(
        accountKey: accountKey,
        email: email,
        alias: nil,
        accountName: nil,
        plan: "Business",
        isActive: isActive,
        fiveHour: QuotaWindowState(
            usedPercent: hasUsage ? 1 : nil,
            resetAt: hasUsage ? weeklyResetAt : nil,
            isStale: false
        ),
        weekly: QuotaWindowState(
            usedPercent: hasUsage ? 1 : nil,
            resetAt: hasUsage ? weeklyResetAt : nil,
            isStale: false
        ),
        lastRefresh: nil
    )
}

private func makePrimerRegistrySnapshot(
    activeAccountKey: String? = nil,
    accounts: [RegistryAccount]
) -> RegistrySnapshot {
    RegistrySnapshot(
        activeAccountKey: activeAccountKey,
        autoSwitch: AutoSwitchConfig(enabled: true, threshold5hPercent: 10, thresholdWeeklyPercent: 5),
        api: APIConfig(usage: true),
        accounts: accounts
    )
}

private func makePrimerRegistryAccount(
    accountKey: String,
    email: String,
    weeklyResetAt: Date?
) -> RegistryAccount {
    RegistryAccount(
        accountKey: accountKey,
        email: email,
        alias: "",
        accountName: nil,
        plan: "business",
        lastUsage: UsageSnapshot(
            primary: UsageWindow(usedPercent: 1, windowMinutes: 300, resetsAt: nil),
            secondary: UsageWindow(usedPercent: 1, windowMinutes: 10_080, resetsAt: weeklyResetAt?.timeIntervalSince1970),
            planType: "business"
        ),
        lastUsageAt: Date.now.timeIntervalSince1970
    )
}

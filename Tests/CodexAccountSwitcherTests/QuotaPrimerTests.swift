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
    func scheduledQuotaPrimerCannotBeEnabled() async {
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

        #expect(!reloadedState.quotaPrimerEnabled)
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
    func legacyScheduledPrimerEntryPointPrimesOnlyActiveAccount() async {
        let now = Date(timeIntervalSince1970: 1_779_000_000)
        let authRunner = RecordingAuthRunner()
        let appState = AppState(
            authRunner: authRunner,
            registryStore: SnapshotRegistryStore(
                snapshot: makePrimerRegistrySnapshot(
                    activeAccountKey: "active",
                    accounts: [
                        makePrimerRegistryAccount(accountKey: "active", email: "active@example.com", weeklyResetAt: now.addingTimeInterval(5 * 24 * 60 * 60)),
                        makePrimerRegistryAccount(accountKey: "full-window", email: "full@example.com", weeklyResetAt: now.addingTimeInterval((6 * 24 * 60 * 60) + 60))
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
            .init(accountKey: "active", accountQuery: "active@example.com")
        ])
        #expect(await authRunner.refreshUsageCount == 2)
        #expect(appState.lastQuotaPrimerStatusMessage == "Sent a primer message from active@example.com; quota could not be verified.")
    }

    @Test
    func plannerAutoModeRequiresSevenDayWeeklyWindowAndFullFiveHourQuota() {
        let now = Date(timeIntervalSince1970: 1_779_000_000)
        let accounts = [
            makePrimerAccount(accountKey: "full", email: "full@example.com", fiveHourRemaining: 99, weeklyResetAt: now.addingTimeInterval((6 * 24 * 60 * 60) + 60)),
            makePrimerAccount(accountKey: "low-five", email: "low-five@example.com", fiveHourRemaining: 98, weeklyResetAt: now.addingTimeInterval((6 * 24 * 60 * 60) + 60)),
            makePrimerAccount(accountKey: "short-week", email: "short-week@example.com", fiveHourRemaining: 99, weeklyResetAt: now.addingTimeInterval((6 * 24 * 60 * 60) - 60)),
            makePrimerAccount(accountKey: "expired", email: "expired@example.com", fiveHourRemaining: 99, weeklyResetAt: now.addingTimeInterval(-60))
        ]

        let eligible = QuotaPrimerPlanner.eligibleAccounts(
            from: accounts,
            now: now,
            recentAttempts: [:],
            mode: .fullWindowOnly
        )

        #expect(eligible.map(\.accountKey) == ["full"])
    }

    @Test
    func manualPrimerPrimesAccountsWithActiveWindows() async {
        let now = Date(timeIntervalSince1970: 1_779_000_000)
        let authRunner = RecordingAuthRunner()
        let appState = AppState(
            authRunner: authRunner,
            registryStore: SnapshotRegistryStore(
                snapshot: makePrimerRegistrySnapshot(
                    activeAccountKey: "active",
                    accounts: [
                        makePrimerRegistryAccount(accountKey: "active", email: "active@example.com", weeklyResetAt: now.addingTimeInterval(86_400))
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
        await appState.runManualQuotaPrimerNow(now: now)

        #expect(await authRunner.primeRequests == [
            .init(accountKey: "active", accountQuery: "active@example.com")
        ])
        #expect(appState.lastQuotaPrimerStatusMessage == "Sent a primer message from active@example.com; quota could not be verified.")
    }

    @Test
    func primeAllAccountsUsesIsolatedAuthWithoutRestartOrSwitch() async {
        let now = Date(timeIntervalSince1970: 1_779_000_000)
        let authRunner = RecordingAuthRunner()
        let codexController = RecordingCodexController()
        let appState = AppState(
            authRunner: authRunner,
            registryStore: SnapshotRegistryStore(
                snapshot: makePrimerRegistrySnapshot(
                    activeAccountKey: "active",
                    accounts: [
                        makePrimerRegistryAccount(accountKey: "active", email: "active@example.com", weeklyResetAt: nil),
                        makePrimerRegistryAccount(accountKey: "work", email: "work@example.com", weeklyResetAt: nil),
                        makePrimerRegistryAccount(accountKey: "spare", email: "spare@example.com", weeklyResetAt: nil)
                    ]
                )
            ),
            codexController: codexController,
            notifications: RecordingNotifications(),
            startAutomatically: false,
            userDefaults: makePrimerDefaults()
        )

        await appState.refreshAll(showNotifications: false)
        let orderedAccounts = [appState.activeAccount!] + appState.accounts.filter { !$0.isActive }
        await appState.primeAllAccounts(now: now)

        #expect(await authRunner.primeRequests.map(\.accountKey) == orderedAccounts.map(\.accountKey))
        #expect(await authRunner.switchQueries.isEmpty)
        #expect(codexController.quitCount == 0)
        #expect(codexController.launchCount == 0)
        #expect(codexController.relaunchCount == 0)
        #expect(await authRunner.refreshUsageCount == 2)
        #expect(appState.lastQuotaPrimerStatusMessage?.hasPrefix("Sent 3/3 primer messages") == true)
    }

    @Test
    func primeAllContinuesAfterFailureAndPreservesRefreshWarning() async {
        let now = Date(timeIntervalSince1970: 1_779_000_000)
        let authRunner = RecordingAuthRunner(
            refreshResult: UsageRefreshResult(
                successfulAccountEmails: ["active@example.com", "spare@example.com"],
                failedAccounts: ["work@example.com": "401 Unauthorized"]
            ),
            failedPrimeAccountKeys: ["work"]
        )
        let codexController = RecordingCodexController()
        let appState = AppState(
            authRunner: authRunner,
            registryStore: SnapshotRegistryStore(
                snapshot: makePrimerRegistrySnapshot(
                    activeAccountKey: "active",
                    accounts: [
                        makePrimerRegistryAccount(accountKey: "active", email: "active@example.com", weeklyResetAt: nil),
                        makePrimerRegistryAccount(accountKey: "work", email: "work@example.com", weeklyResetAt: nil),
                        makePrimerRegistryAccount(accountKey: "spare", email: "spare@example.com", weeklyResetAt: nil)
                    ]
                )
            ),
            codexController: codexController,
            notifications: RecordingNotifications(),
            startAutomatically: false,
            userDefaults: makePrimerDefaults()
        )

        await appState.refreshAll(showNotifications: false)
        await appState.primeAllAccounts(now: now)

        #expect(await authRunner.primeRequests.map(\.accountKey) == ["active", "spare", "work"])
        #expect(await authRunner.switchQueries.isEmpty)
        #expect(codexController.quitCount == 0)
        #expect(codexController.launchCount == 0)
        #expect(codexController.relaunchCount == 0)
        #expect(appState.lastQuotaPrimerStatusMessage?.contains("Sent 2/3 primer messages") == true)
        #expect(appState.lastQuotaPrimerStatusMessage?.contains("work@example.com") == true)
        #expect(appState.refreshWarningMessage?.contains("2 refreshed, 1 cached") == true)
        #expect(appState.headerMessage == appState.refreshWarningMessage)
    }

    @Test
    func primerCommandPlacesGlobalApprovalOptionBeforeExecSubcommand() {
        let arguments = CodexPrimerCommand.arguments(
            outputURL: URL(fileURLWithPath: "/tmp/primer-response.txt")
        )

        #expect(arguments.firstIndex(of: "--ask-for-approval")! < arguments.firstIndex(of: "exec")!)
        #expect(arguments.contains("--ephemeral"))
        #expect(arguments.contains("--ignore-user-config"))
        #expect(arguments.contains("--output-last-message"))
        #expect(arguments.last == "Reply exactly: hi")
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
    fiveHourRemaining: Int = 99,
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
            usedPercent: hasUsage ? 100 - fiveHourRemaining : nil,
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
        lastUsageAt: Date.now.timeIntervalSince1970,
        chatGPTAccountID: "chatgpt-\(accountKey)"
    )
}

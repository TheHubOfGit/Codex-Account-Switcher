import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    private static let weeklyPaceDemoKey = "weeklyPaceDemoEnabled"

    @Published private(set) var accounts: [AccountSnapshot] = []
    @Published private(set) var authStatus = AuthStatus(
        autoSwitchEnabled: false,
        serviceStatus: nil,
        threshold5hPercent: nil,
        thresholdWeeklyPercent: nil,
        usageMode: .unknown,
        accountMode: nil
    )
    @Published private(set) var setupIssue: SetupIssue?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSwitching = false
    @Published private(set) var isSavingSettings = false
    @Published private(set) var weeklyPaceDemoEnabled: Bool

    private let authRunner: CodexAuthRunner
    private let registryStore: RegistryStore
    private let codexController: CodexAppController
    private let notifications: NotificationManager

    private var lastObservedActiveAccountKey: String?
    private var suppressNextExternalSwitchNotification = false
    private var reloadTask: Task<Void, Never>?
    private var pendingAutoMonitorPromptTargetKey: String?
    private var settingsOpener: (() -> Void)?

    init(
        authRunner: CodexAuthRunner = CodexAuthRunner(),
        registryStore: RegistryStore = RegistryStore(),
        codexController: CodexAppController = CodexAppController(),
        notifications: NotificationManager = NotificationManager()
    ) {
        self.authRunner = authRunner
        self.registryStore = registryStore
        self.codexController = codexController
        self.notifications = notifications
        weeklyPaceDemoEnabled = UserDefaults.standard.bool(forKey: Self.weeklyPaceDemoKey)

        registryStore.startWatching { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleRegistryReload()
            }
        }

        Task { @MainActor in
            await refreshAll(showNotifications: false)
        }
    }

    var activeAccount: AccountSnapshot? {
        accounts.first(where: \.isActive)
    }

    var bestAvailableAccount: AccountSnapshot? {
        AccountRanking.bestCandidate(
            from: accounts,
            fiveHourThreshold: quotaThresholds.fiveHour,
            weeklyThreshold: quotaThresholds.weekly
        )
    }

    var fleetQuotaSummary: FleetQuotaSummary {
        FleetQuotaSummary.make(
            from: accounts,
            fiveHourThreshold: quotaThresholds.fiveHour,
            weeklyThreshold: quotaThresholds.weekly
        )
    }

    var autoMonitorEnabled: Bool {
        authStatus.autoSwitchEnabled
    }

    var usageModeLabel: String {
        authStatus.usageMode.displayName
    }

    func requestNotificationAuthorization() {
        notifications.requestAuthorization()
    }

    func refreshAll(showNotifications: Bool = true) async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            guard await authRunner.executableExists() else {
                setupIssue = .missingCodexAuth
                accounts = []
                return
            }

            try await authRunner.refreshUsage()
            let status = try await authRunner.status()
            let snapshot = try registryStore.loadSnapshot()

            apply(snapshot: snapshot, status: status)
            setupIssue = nil
            lastErrorMessage = nil
        } catch let issue as SetupIssue {
            setupIssue = issue
            accounts = []
        } catch {
            lastErrorMessage = error.localizedDescription
            if showNotifications {
                notifications.notify(title: "Quota refresh failed", body: error.localizedDescription)
            }
            await reloadFromDisk(showNotifications: false)
        }
    }

    func restartCodex() async {
        do {
            try await codexController.relaunchCodex()
            lastErrorMessage = nil
            notifications.notify(title: "Codex restarted", body: "Codex was relaunched.")
        } catch {
            lastErrorMessage = error.localizedDescription
            notifications.notify(title: "Codex restart failed", body: error.localizedDescription)
        }
    }

    func switchToAccount(_ account: AccountSnapshot) async {
        guard !isSwitching else { return }

        isSwitching = true
        defer { isSwitching = false }

        do {
            try await authRunner.switchAccount(query: account.email)
            suppressNextExternalSwitchNotification = true
            let snapshot = try registryStore.loadSnapshot()
            let status = try await authRunner.status()
            apply(snapshot: snapshot, status: status)

            try await codexController.relaunchCodex()
            lastErrorMessage = nil
            notifications.notify(title: "Account switched", body: "Now using \(account.primaryLabel).")
        } catch {
            lastErrorMessage = error.localizedDescription
            notifications.notify(title: "Account switch failed", body: error.localizedDescription)
        }
    }

    func switchToBestAvailable() async {
        guard let candidate = bestAvailableAccount else {
            notifications.notify(
                title: "No eligible account",
                body: "All accounts are exhausted, missing quota data, or have stale usage information."
            )
            return
        }

        if candidate.accountKey == activeAccount?.accountKey {
            notifications.notify(title: "Already on target account", body: "\(candidate.primaryLabel) is already the lowest eligible account.")
            return
        }

        await switchToAccount(candidate)
    }

    func sendTestAutoSwitchNotification() {
        let currentAccount = AccountSnapshot(
            accountKey: "test-current",
            email: "current@example.com",
            alias: "Current Test Account",
            accountName: nil,
            plan: "Test",
            isActive: true,
            fiveHour: QuotaWindowState(usedPercent: 92, resetAt: nil, isStale: false),
            weekly: QuotaWindowState(usedPercent: 45, resetAt: nil, isStale: false),
            lastRefresh: .now
        )
        let candidate = AccountSnapshot(
            accountKey: "test-candidate",
            email: "next@example.com",
            alias: "Next Test Account",
            accountName: nil,
            plan: "Test",
            isActive: false,
            fiveHour: QuotaWindowState(usedPercent: 70, resetAt: nil, isStale: false),
            weekly: QuotaWindowState(usedPercent: 55, resetAt: nil, isStale: false),
            lastRefresh: .now
        )

        notifications.promptForAutoSwitch(from: currentAccount, to: candidate) { [weak self] in
            self?.notifications.notify(
                title: "Test auto-switch confirmed",
                body: "No account was switched and Codex was not restarted."
            )
        }
    }

    func setAutoMonitor(enabled: Bool) async {
        isSavingSettings = true
        defer { isSavingSettings = false }

        do {
            try await authRunner.setAutoSwitch(enabled: enabled)
            try await refreshStatusOnly()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            notifications.notify(title: "Auto monitor update failed", body: error.localizedDescription)
        }
    }

    func saveThresholds(fiveHour: Int, weekly: Int) async {
        isSavingSettings = true
        defer { isSavingSettings = false }

        do {
            try await authRunner.setThresholds(fiveHour: fiveHour, weekly: weekly)
            try await refreshStatusOnly()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            notifications.notify(title: "Threshold update failed", body: error.localizedDescription)
        }
    }

    func setWeeklyPaceDemo(enabled: Bool) {
        weeklyPaceDemoEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.weeklyPaceDemoKey)
    }

    func openSettings() {
        if let settingsOpener {
            settingsOpener()
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func setSettingsOpener(_ opener: @escaping () -> Void) {
        settingsOpener = opener
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func refreshStatusOnly() async throws {
        let status = try await authRunner.status()
        authStatus = status

        do {
            let snapshot = try registryStore.loadSnapshot()
            apply(snapshot: snapshot, status: status, notifyOnExternalSwitch: false)
            setupIssue = nil
        } catch let issue as SetupIssue {
            setupIssue = issue
        }
    }

    private func scheduleRegistryReload() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            await reloadFromDisk(showNotifications: true)
        }
    }

    private func reloadFromDisk(showNotifications: Bool) async {
        do {
            let snapshot = try registryStore.loadSnapshot()
            apply(snapshot: snapshot, status: authStatus, notifyOnExternalSwitch: showNotifications)
            setupIssue = nil
        } catch let issue as SetupIssue {
            setupIssue = issue
            accounts = []
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func apply(snapshot: RegistrySnapshot, status: AuthStatus, notifyOnExternalSwitch: Bool = true) {
        let previousActive = lastObservedActiveAccountKey
        let nextAccounts = snapshot.accountSnapshots()
        let nextActive = nextAccounts.first(where: \.isActive)?.accountKey

        accounts = nextAccounts
        authStatus = mergedStatus(status: status, snapshot: snapshot)
        lastObservedActiveAccountKey = nextActive
        evaluateAutoMonitor()

        guard notifyOnExternalSwitch,
              let previousActive,
              let nextActive,
              previousActive != nextActive else {
            if suppressNextExternalSwitchNotification {
                suppressNextExternalSwitchNotification = false
            }
            return
        }

        if suppressNextExternalSwitchNotification {
            suppressNextExternalSwitchNotification = false
            return
        }

        if let account = accounts.first(where: { $0.accountKey == nextActive }) {
            notifications.notify(title: "Auto-switched account", body: "Active account changed to \(account.primaryLabel).")
        }
    }

    private func mergedStatus(status: AuthStatus, snapshot: RegistrySnapshot) -> AuthStatus {
        AuthStatus(
            autoSwitchEnabled: snapshot.autoSwitch.enabled,
            serviceStatus: status.serviceStatus,
            threshold5hPercent: snapshot.autoSwitch.threshold5hPercent,
            thresholdWeeklyPercent: snapshot.autoSwitch.thresholdWeeklyPercent,
            usageMode: snapshot.api.usage ? .api : .local,
            accountMode: status.accountMode
        )
    }

    private var quotaThresholds: (fiveHour: Int, weekly: Int) {
        (
            fiveHour: authStatus.threshold5hPercent ?? 0,
            weekly: authStatus.thresholdWeeklyPercent ?? 0
        )
    }

    private func evaluateAutoMonitor() {
        guard authStatus.autoSwitchEnabled,
              !isSwitching,
              let activeAccount,
              activeAccount.isExhausted(
                fiveHourThreshold: quotaThresholds.fiveHour,
                weeklyThreshold: quotaThresholds.weekly
              ),
              let candidate = bestAvailableAccount,
              candidate.accountKey != activeAccount.accountKey,
              candidate.accountKey != pendingAutoMonitorPromptTargetKey else {
            return
        }

        pendingAutoMonitorPromptTargetKey = candidate.accountKey
        notifications.promptForAutoSwitch(from: activeAccount, to: candidate) { [weak self] in
            guard let self else { return }
            defer { pendingAutoMonitorPromptTargetKey = nil }
            await switchToAccount(candidate)
        }
    }
}

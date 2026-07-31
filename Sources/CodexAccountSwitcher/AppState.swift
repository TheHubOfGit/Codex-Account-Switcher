import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    private static let weeklyPaceDemoKey = "weeklyPaceDemoEnabled"
    private static let backgroundRefreshEnabledKey = "backgroundRefreshEnabled"
    private static let backgroundRefreshIntervalMinutesKey = "backgroundRefreshIntervalMinutes"
    private static let defaultBackgroundRefreshIntervalMinutes = 10
    private static let lastSuccessfulRefreshAtKey = "lastSuccessfulRefreshAt"
    private static let accountUsageFreshnessKey = "accountUsageFreshness.v1"
    private static let accountResetCreditsKey = "accountResetCredits.v1"
    private static let askBeforeSwitchingKey = "askBeforeSwitchingEnabled"
    private static let monitorFiveHourThresholdKey = "monitorFiveHourThreshold"
    private static let monitorWeeklyThresholdKey = "monitorWeeklyThreshold"
    private static let quotaPrimerEnabledKey = "quotaPrimerEnabled"
    private static let quotaPrimerIntervalMinutesKey = "quotaPrimerIntervalMinutes"
    private static let defaultQuotaPrimerIntervalMinutes = 30

    static let backgroundRefreshIntervalOptions = [5, 10, 15, 30]
    static let quotaPrimerIntervalOptions = [30, 60, 120, 360]

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
    @Published private(set) var refreshWarningMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSwitching = false
    @Published private(set) var isRestarting = false
    @Published private(set) var isSavingSettings = false
    @Published private(set) var weeklyPaceDemoEnabled: Bool
    @Published private(set) var backgroundRefreshEnabled: Bool
    @Published private(set) var backgroundRefreshIntervalMinutes: Int
    @Published private(set) var quotaPrimerEnabled: Bool
    @Published private(set) var quotaPrimerIntervalMinutes: Int
    @Published private(set) var isPrimingQuota = false
    @Published private(set) var lastQuotaPrimerStatusMessage: String?
    @Published private(set) var freshnessNow = Date.now
    @Published private(set) var lastSuccessfulRefreshAt: Date?
    @Published private(set) var askBeforeSwitchingEnabled: Bool
    @Published private(set) var monitorFiveHourThreshold: Int
    @Published private(set) var monitorWeeklyThreshold: Int
    @Published private(set) var codexAuthVersionLabel: String?
    @Published private(set) var isCodexAuthSupported = true

    private let authRunner: any CodexAuthRunning
    private let registryStore: any RegistryStoring
    private let codexController: any CodexAppControlling
    private let notifications: any NotificationManaging
    private let userDefaults: UserDefaults
    private let schedulesBackgroundRefresh: Bool

    private var lastObservedActiveAccountKey: String?
    private var suppressNextExternalSwitchNotification = false
    private var reloadTask: Task<Void, Never>?
    private var backgroundRefreshTask: Task<Void, Never>?
    private var quotaPrimerTask: Task<Void, Never>?
    private var freshnessTask: Task<Void, Never>?
    private var pendingAutoMonitorPromptTargetKey: String?
    private var pendingAutoMonitorPromptExpiresAt: Date?
    private var lastRefreshAttemptAt: Date?
    private var usageCheckedAtByAccountKey: [String: Date]
    private var resetCreditsByAccountKey: [String: RateLimitResetCreditsSnapshot]
    private var lastRefreshVerifiedAccountKeys: Set<String> = []
    private var settingsOpener: (() -> Void)?
    private var quotaPrimerAttempts: [String: Date] = [:]

    init(
        authRunner: any CodexAuthRunning = CodexAuthRunner(),
        registryStore: any RegistryStoring = RegistryStore(),
        codexController: any CodexAppControlling = CodexAppController(),
        notifications: any NotificationManaging = NotificationManager(),
        startAutomatically: Bool = true,
        userDefaults: UserDefaults = .standard
    ) {
        self.authRunner = authRunner
        self.registryStore = registryStore
        self.codexController = codexController
        self.notifications = notifications
        self.userDefaults = userDefaults
        schedulesBackgroundRefresh = startAutomatically
        weeklyPaceDemoEnabled = userDefaults.bool(forKey: Self.weeklyPaceDemoKey)
        backgroundRefreshEnabled = userDefaults.bool(forKey: Self.backgroundRefreshEnabledKey)
        backgroundRefreshIntervalMinutes = Self.normalizedBackgroundRefreshInterval(
            userDefaults.integer(forKey: Self.backgroundRefreshIntervalMinutesKey)
        )
        quotaPrimerEnabled = userDefaults.bool(forKey: Self.quotaPrimerEnabledKey)
        quotaPrimerIntervalMinutes = Self.normalizedQuotaPrimerInterval(
            userDefaults.integer(forKey: Self.quotaPrimerIntervalMinutesKey)
        )
        lastSuccessfulRefreshAt = userDefaults.object(forKey: Self.lastSuccessfulRefreshAtKey) as? Date
        usageCheckedAtByAccountKey = Self.loadUsageFreshness(from: userDefaults)
        resetCreditsByAccountKey = Self.loadResetCredits(from: userDefaults)
        refreshWarningMessage = nil
        askBeforeSwitchingEnabled = userDefaults.bool(forKey: Self.askBeforeSwitchingKey)
        monitorFiveHourThreshold = Self.normalizedThreshold(
            userDefaults.integer(forKey: Self.monitorFiveHourThresholdKey),
            fallback: 10
        )
        monitorWeeklyThreshold = Self.normalizedThreshold(
            userDefaults.integer(forKey: Self.monitorWeeklyThresholdKey),
            fallback: 5
        )
        codexAuthVersionLabel = nil

        if startAutomatically {
            registryStore.startWatching { [weak self] in
                Task { @MainActor [weak self] in
                    self?.scheduleRegistryReload()
                }
            }

            Task { @MainActor in
                await refreshAll(showNotifications: false)
            }

            rescheduleBackgroundRefresh()
            startFreshnessClock()
        }
    }

    deinit {
        reloadTask?.cancel()
        backgroundRefreshTask?.cancel()
        quotaPrimerTask?.cancel()
        freshnessTask?.cancel()
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
            now: freshnessNow,
            fiveHourThreshold: quotaThresholds.fiveHour,
            weeklyThreshold: quotaThresholds.weekly
        )
    }

    var autoMonitorEnabled: Bool {
        askBeforeSwitchingEnabled
    }

    var externalAutoSwitchEnabled: Bool {
        authStatus.autoSwitchEnabled
    }

    var usageModeLabel: String {
        authStatus.usageMode.displayName
    }

    var headerMessage: String? {
        lastErrorMessage ?? refreshWarningMessage
    }

    func requestNotificationAuthorization() {
        notifications.requestAuthorization()
    }

    func refreshAll(showNotifications: Bool = true) async {
        guard !isRefreshing else { return }

        lastRefreshAttemptAt = .now
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            guard await authRunner.executableExists() else {
                setupIssue = .missingCodexAuth
                accounts = []
                return
            }

            let versionOutput = try await authRunner.version()
            codexAuthVersionLabel = versionOutput
            let parsedVersion = CodexAuthVersion(output: versionOutput)
            isCodexAuthSupported = parsedVersion.map { $0 >= .minimumSupported } ?? false

            if !isCodexAuthSupported {
                let status = try await authRunner.status()
                let snapshot = try registryStore.loadSnapshot()
                apply(snapshot: snapshot, status: status)
                setupIssue = nil
                lastErrorMessage = "Update codex-auth to 0.2.10 or newer before refreshing or switching accounts."
                return
            }

            let refreshResult = try await authRunner.refreshUsage()
            let status = try await authRunner.status()
            let snapshot = try registryStore.loadSnapshot()
            var resetCreditFailures: [String] = []
            for registryAccount in snapshot.accounts {
                do {
                    let identity = try primerIdentity(for: registryAccount)
                    let fetched = try await authRunner
                        .readRateLimitResetCredits(account: identity)
                    resetCreditsByAccountKey[registryAccount.accountKey] = mergedResetCredits(
                        fetched,
                        cached: resetCreditsByAccountKey[registryAccount.accountKey]
                    )
                } catch {
                    let alias = registryAccount.alias.trimmingCharacters(in: .whitespacesAndNewlines)
                    resetCreditFailures.append(alias.isEmpty ? registryAccount.email : alias)
                }
            }

            let checkedAt = Date.now
            lastSuccessfulRefreshAt = checkedAt
            userDefaults.set(checkedAt, forKey: Self.lastSuccessfulRefreshAtKey)

            let successfulEmails = refreshResult.successfulAccountEmails
            let verifiedKeys = Set(snapshot.accounts.compactMap { account in
                successfulEmails.contains(account.email.lowercased()) ? account.accountKey : nil
            })
            lastRefreshVerifiedAccountKeys = verifiedKeys
            for accountKey in verifiedKeys {
                usageCheckedAtByAccountKey[accountKey] = checkedAt
            }
            let currentKeys = Set(snapshot.accounts.map(\.accountKey))
            usageCheckedAtByAccountKey = usageCheckedAtByAccountKey.filter {
                currentKeys.contains($0.key)
            }
            resetCreditsByAccountKey = resetCreditsByAccountKey.filter {
                currentKeys.contains($0.key)
            }
            persistUsageFreshness()
            persistResetCredits()

            apply(snapshot: snapshot, status: status)
            setupIssue = nil
            lastErrorMessage = nil
            let cachedCount = max(0, snapshot.accounts.count - verifiedKeys.count)
            var warnings: [String] = []
            if cachedCount > 0 {
                warnings.append(
                    "\(verifiedKeys.count) refreshed, \(cachedCount) cached. Cached quota remains for accounts that could not be verified."
                )
            }
            if !resetCreditFailures.isEmpty {
                warnings.append(
                    "Reset availability remains cached for \(resetCreditFailures.joined(separator: ", "))."
                )
            }
            refreshWarningMessage = warnings.isEmpty ? nil : warnings.joined(separator: " ")
            if !warnings.isEmpty, showNotifications {
                notifications.notify(
                    title: "Usage refresh partially failed",
                    body: refreshWarningMessage ?? "Some quota remains cached."
                )
            }
        } catch let issue as SetupIssue {
            setupIssue = issue
            if accounts.isEmpty {
                accounts = []
            } else {
                lastErrorMessage = issue.localizedDescription
            }
        } catch {
            lastRefreshVerifiedAccountKeys = []
            lastErrorMessage = error.localizedDescription
            if showNotifications {
                notifications.notify(title: "Quota refresh failed", body: error.localizedDescription)
            }
            await reloadFromDisk(showNotifications: false)
        }
    }

    func restartCodex() async {
        guard !isRestarting, !isSwitching else { return }
        isRestarting = true
        defer { isRestarting = false }

        do {
            try await codexController.relaunchCodex()
            lastErrorMessage = nil
            notifications.notify(title: "Codex restarted", body: "Codex was relaunched.")
        } catch {
            lastErrorMessage = error.localizedDescription
            notifications.notify(title: "Codex restart failed", body: error.localizedDescription)
        }
    }

    func switchToAccount(_ account: AccountSnapshot, notifyOnSuccess: Bool = true) async {
        guard isCodexAuthSupported else {
            lastErrorMessage = "Update codex-auth to 0.2.10 or newer before switching accounts."
            return
        }
        guard !isSwitching, !isRestarting else { return }
        guard account.accountKey != activeAccount?.accountKey else { return }

        isSwitching = true
        defer { isSwitching = false }

        do {
            try await authRunner.switchAccount(query: account.email)
            suppressNextExternalSwitchNotification = true
            let snapshot = try registryStore.loadSnapshot()
            guard snapshot.activeAccountKey == account.accountKey else {
                throw CodexAuthError.switchVerificationFailed
            }

            let status = (try? await authRunner.status()) ?? authStatus
            apply(snapshot: snapshot, status: status)
        } catch {
            lastErrorMessage = error.localizedDescription
            notifications.notify(title: "Account switch failed", body: error.localizedDescription)
            return
        }

        do {
            try await codexController.relaunchCodex()
            lastErrorMessage = nil
            if notifyOnSuccess {
                notifications.notify(title: "Account switched", body: "Now using \(account.primaryLabel).")
            }
        } catch {
            let message = "Switched to \(account.primaryLabel), but Codex could not restart: \(error.localizedDescription)"
            lastErrorMessage = message
            notifications.notify(title: "Account switched; restart needed", body: message)
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

        if enabled && externalAutoSwitchEnabled {
            lastErrorMessage = "Turn off codex-auth automatic switching before enabling Ask Before Switching."
            return
        }

        askBeforeSwitchingEnabled = enabled
        userDefaults.set(enabled, forKey: Self.askBeforeSwitchingKey)
        if enabled {
            requestNotificationAuthorization()
            if !backgroundRefreshEnabled {
                setBackgroundRefresh(enabled: true, intervalMinutes: 10)
            }
        } else {
            pendingAutoMonitorPromptTargetKey = nil
            pendingAutoMonitorPromptExpiresAt = nil
        }
        lastErrorMessage = nil
    }

    func saveThresholds(fiveHour: Int, weekly: Int) async {
        isSavingSettings = true
        defer { isSavingSettings = false }

        guard (1...100).contains(fiveHour), (1...100).contains(weekly) else {
            lastErrorMessage = CodexAuthError.invalidThresholds.localizedDescription
            return
        }

        monitorFiveHourThreshold = fiveHour
        monitorWeeklyThreshold = weekly
        userDefaults.set(fiveHour, forKey: Self.monitorFiveHourThresholdKey)
        userDefaults.set(weekly, forKey: Self.monitorWeeklyThresholdKey)
        lastErrorMessage = nil
        evaluateAutoMonitor()
    }

    func disableExternalAutoSwitch() async {
        isSavingSettings = true
        defer { isSavingSettings = false }

        do {
            try await authRunner.setAutoSwitch(enabled: false)
            try await refreshStatusOnly()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func setWeeklyPaceDemo(enabled: Bool) {
        weeklyPaceDemoEnabled = enabled
        userDefaults.set(enabled, forKey: Self.weeklyPaceDemoKey)
    }

    func setBackgroundRefresh(enabled: Bool, intervalMinutes: Int? = nil) {
        backgroundRefreshEnabled = enabled
        if let intervalMinutes {
            backgroundRefreshIntervalMinutes = Self.normalizedBackgroundRefreshInterval(intervalMinutes)
        }

        userDefaults.set(backgroundRefreshEnabled, forKey: Self.backgroundRefreshEnabledKey)
        userDefaults.set(backgroundRefreshIntervalMinutes, forKey: Self.backgroundRefreshIntervalMinutesKey)
        rescheduleBackgroundRefresh()
    }

    func setBackgroundRefreshInterval(minutes: Int) {
        setBackgroundRefresh(enabled: backgroundRefreshEnabled, intervalMinutes: minutes)
    }

    func setQuotaPrimer(enabled: Bool, intervalMinutes: Int? = nil) {
        quotaPrimerEnabled = false
        if let intervalMinutes {
            quotaPrimerIntervalMinutes = Self.normalizedQuotaPrimerInterval(intervalMinutes)
        }

        userDefaults.set(false, forKey: Self.quotaPrimerEnabledKey)
        userDefaults.set(quotaPrimerIntervalMinutes, forKey: Self.quotaPrimerIntervalMinutesKey)
        quotaPrimerTask?.cancel()
        quotaPrimerTask = nil
    }

    func setQuotaPrimerInterval(minutes: Int) {
        setQuotaPrimer(enabled: quotaPrimerEnabled, intervalMinutes: minutes)
    }

    func runQuotaPrimerNow(now: Date = .now) async {
        await runManualQuotaPrimerNow(now: now)
    }

    func runManualQuotaPrimerNow(now: Date = .now) async {
        guard isCodexAuthSupported else {
            lastQuotaPrimerStatusMessage = "Update codex-auth to 0.2.10 or newer before priming quota."
            return
        }
        guard !isPrimingQuota,
              !isRefreshing,
              !isSwitching,
              !isRestarting else {
            return
        }

        guard let account = activeAccount else {
            lastQuotaPrimerStatusMessage = "No active account is available to prime."
            return
        }

        if let lastAttempt = quotaPrimerAttempts[account.accountKey],
           now.timeIntervalSince(lastAttempt) < QuotaPrimerPlanner.attemptCooldown {
            lastQuotaPrimerStatusMessage = "This account was primed recently. Try again later."
            return
        }

        quotaPrimerAttempts[account.accountKey] = now
        lastQuotaPrimerStatusMessage = "Priming \(account.primaryLabel)..."
        isPrimingQuota = true
        defer { isPrimingQuota = false }

        do {
            let snapshot = try registryStore.loadSnapshot()
            let identity = try primerIdentity(for: account, in: snapshot)
            _ = try await authRunner.primeUsage(account: identity)
            await refreshAll(showNotifications: false)
            let verified = lastRefreshVerifiedAccountKeys.contains(account.accountKey)
            lastQuotaPrimerStatusMessage = verified
                ? "Sent a primer message from \(account.primaryLabel); quota verified."
                : "Sent a primer message from \(account.primaryLabel); quota could not be verified."
        } catch {
            lastErrorMessage = error.localizedDescription
            lastQuotaPrimerStatusMessage = "Quota primer failed: \(error.localizedDescription)"
            notifications.notify(title: "Quota primer failed", body: error.localizedDescription)
        }
    }

    func primeAllAccounts(now: Date = .now) async {
        guard isCodexAuthSupported else {
            lastQuotaPrimerStatusMessage = "Update codex-auth to 0.2.10 or newer before priming quota."
            return
        }
        guard !isPrimingQuota,
              !isRefreshing,
              !isSwitching,
              !isRestarting else {
            return
        }
        guard let originalAccount = activeAccount, !accounts.isEmpty else {
            lastQuotaPrimerStatusMessage = "No active account is available to prime."
            return
        }

        let orderedAccounts = [originalAccount] + accounts.filter { $0.accountKey != originalAccount.accountKey }
        isPrimingQuota = true
        defer { isPrimingQuota = false }

        let startingSnapshot: RegistrySnapshot
        do {
            startingSnapshot = try registryStore.loadSnapshot()
        } catch {
            lastErrorMessage = error.localizedDescription
            lastQuotaPrimerStatusMessage = "Could not read account state: \(error.localizedDescription)"
            return
        }

        var deliveredAccountKeys: Set<String> = []
        var failures: [(label: String, reason: String)] = []

        for (index, account) in orderedAccounts.enumerated() {
            do {
                lastQuotaPrimerStatusMessage = "Sending \(index + 1) of \(orderedAccounts.count): \(account.primaryLabel)…"
                let identity = try primerIdentity(for: account, in: startingSnapshot)
                _ = try await authRunner.primeUsage(account: identity)
                deliveredAccountKeys.insert(account.accountKey)
                quotaPrimerAttempts[account.accountKey] = now
            } catch {
                failures.append((account.primaryLabel, error.localizedDescription))
            }
        }

        var safetyIssue: String?
        do {
            let endingSnapshot = try registryStore.loadSnapshot()
            if endingSnapshot.activeAccountKey != startingSnapshot.activeAccountKey {
                safetyIssue = "The active account changed unexpectedly during priming."
            }
        } catch {
            safetyIssue = "The active account could not be verified after priming: \(error.localizedDescription)"
        }

        lastQuotaPrimerStatusMessage = "Refreshing quota after primer messages…"
        await refreshAll(showNotifications: false)

        let currentAccountKeys = Set(orderedAccounts.map(\.accountKey))
        let verifiedAccountCount = currentAccountKeys.intersection(lastRefreshVerifiedAccountKeys).count
        var summary = "Sent \(deliveredAccountKeys.count)/\(orderedAccounts.count) primer messages; quota verified for \(verifiedAccountCount)/\(orderedAccounts.count)."
        if !failures.isEmpty {
            summary += " Failed: " + failures.map { "\($0.label) (\($0.reason))" }.joined(separator: ", ") + "."
        }
        if let safetyIssue {
            summary += " \(safetyIssue)"
            lastErrorMessage = safetyIssue
        } else {
            lastErrorMessage = nil
        }
        lastQuotaPrimerStatusMessage = summary
        notifications.notify(
            title: failures.isEmpty && safetyIssue == nil ? "All primer messages sent" : "Account priming finished",
            body: summary
        )
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

    func popoverDidOpen() {
        freshnessNow = .now
        let reference = lastRefreshAttemptAt ?? lastSuccessfulRefreshAt
        let needsRefresh = reference.map { freshnessNow.timeIntervalSince($0) >= 5 * 60 } ?? true
        guard needsRefresh, !isRefreshing, !isSwitching else { return }

        Task { await refreshAll(showNotifications: false) }
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
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            await reloadFromDisk(showNotifications: true)
        }
    }

    private func startFreshnessClock() {
        freshnessTask?.cancel()
        freshnessTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                guard let self else { return }
                freshnessNow = .now
                if let expiresAt = pendingAutoMonitorPromptExpiresAt,
                   freshnessNow >= expiresAt {
                    pendingAutoMonitorPromptTargetKey = nil
                    pendingAutoMonitorPromptExpiresAt = nil
                }
                evaluateAutoMonitor()
            }
        }
    }

    private func rescheduleBackgroundRefresh() {
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = nil

        guard schedulesBackgroundRefresh, backgroundRefreshEnabled else {
            return
        }

        backgroundRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: .seconds(backgroundRefreshIntervalMinutes * 60))
                guard !Task.isCancelled else { return }
                await runBackgroundRefreshTick()
            }
        }
    }

    private func rescheduleQuotaPrimer() {
        quotaPrimerTask?.cancel()
        quotaPrimerTask = nil

        guard schedulesBackgroundRefresh, quotaPrimerEnabled else {
            return
        }

        quotaPrimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: .seconds(quotaPrimerIntervalMinutes * 60))
                guard !Task.isCancelled else { return }
                await runQuotaPrimerNow()
            }
        }
    }

    private func runBackgroundRefreshTick() async {
        guard !isRefreshing, !isSwitching else {
            return
        }

        await refreshAll(showNotifications: false)
    }

    private func reloadFromDisk(showNotifications: Bool) async {
        do {
            let snapshot = try registryStore.loadSnapshot()
            apply(snapshot: snapshot, status: authStatus, notifyOnExternalSwitch: showNotifications)
            setupIssue = nil
        } catch let issue as SetupIssue {
            setupIssue = issue
            if !accounts.isEmpty {
                lastErrorMessage = issue.localizedDescription
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func apply(snapshot: RegistrySnapshot, status: AuthStatus, notifyOnExternalSwitch: Bool = true) {
        let previousActive = lastObservedActiveAccountKey
        freshnessNow = .now
        let nextAccounts = snapshot.accountSnapshots(
            now: freshnessNow,
            usageCheckedAtByAccountKey: usageCheckedAtByAccountKey,
            resetCreditsByAccountKey: resetCreditsByAccountKey
        )
        let nextActive = nextAccounts.first(where: \.isActive)?.accountKey

        accounts = nextAccounts
        authStatus = mergedStatus(status: status, snapshot: snapshot)
        lastObservedActiveAccountKey = nextActive
        evaluateAutoMonitor()

        let decision = AccountSwitchNotificationPolicy.decision(
            previousActive: previousActive,
            nextActive: nextActive,
            notifyOnExternalSwitch: notifyOnExternalSwitch,
            suppressNextExternalSwitchNotification: &suppressNextExternalSwitchNotification,
            pendingAutoMonitorPromptTargetKey: &pendingAutoMonitorPromptTargetKey
        )

        if case .notifyExternalSwitch(let accountKey) = decision,
           let account = accounts.first(where: { $0.accountKey == accountKey }) {
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
            fiveHour: monitorFiveHourThreshold,
            weekly: monitorWeeklyThreshold
        )
    }

    private static func normalizedThreshold(_ value: Int, fallback: Int) -> Int {
        (1...100).contains(value) ? value : fallback
    }

    private static func normalizedBackgroundRefreshInterval(_ value: Int) -> Int {
        guard backgroundRefreshIntervalOptions.contains(value) else {
            return defaultBackgroundRefreshIntervalMinutes
        }

        return value
    }

    private static func normalizedQuotaPrimerInterval(_ value: Int) -> Int {
        guard quotaPrimerIntervalOptions.contains(value) else {
            return defaultQuotaPrimerIntervalMinutes
        }

        return value
    }

    private static func accountCountLabel(_ count: Int) -> String {
        count == 1 ? "1 account" : "\(count) accounts"
    }

    private func primerIdentity(
        for account: AccountSnapshot,
        in snapshot: RegistrySnapshot
    ) throws -> PrimerAccountIdentity {
        guard let registryAccount = snapshot.accounts.first(where: {
            $0.accountKey == account.accountKey
        }), let rawAccountID = registryAccount.chatGPTAccountID else {
            throw CodexAuthError.missingPrimerIdentity(accountKey: account.accountKey)
        }
        let chatGPTAccountID = rawAccountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chatGPTAccountID.isEmpty else {
            throw CodexAuthError.missingPrimerIdentity(accountKey: account.accountKey)
        }
        return PrimerAccountIdentity(
            accountKey: account.accountKey,
            email: account.email,
            chatGPTAccountID: chatGPTAccountID
        )
    }

    private func primerIdentity(for account: RegistryAccount) throws -> PrimerAccountIdentity {
        guard let rawAccountID = account.chatGPTAccountID else {
            throw CodexAuthError.missingPrimerIdentity(accountKey: account.accountKey)
        }
        let chatGPTAccountID = rawAccountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chatGPTAccountID.isEmpty else {
            throw CodexAuthError.missingPrimerIdentity(accountKey: account.accountKey)
        }
        return PrimerAccountIdentity(
            accountKey: account.accountKey,
            email: account.email,
            chatGPTAccountID: chatGPTAccountID
        )
    }

    private static func loadUsageFreshness(from defaults: UserDefaults) -> [String: Date] {
        guard let data = defaults.data(forKey: accountUsageFreshnessKey),
              let stored = try? JSONDecoder().decode([String: TimeInterval].self, from: data) else {
            return [:]
        }
        return stored.mapValues(Date.init(timeIntervalSince1970:))
    }

    private func persistUsageFreshness() {
        let stored = usageCheckedAtByAccountKey.mapValues(\.timeIntervalSince1970)
        if let data = try? JSONEncoder().encode(stored) {
            userDefaults.set(data, forKey: Self.accountUsageFreshnessKey)
        }
    }

    private static func loadResetCredits(
        from defaults: UserDefaults
    ) -> [String: RateLimitResetCreditsSnapshot] {
        guard let data = defaults.data(forKey: accountResetCreditsKey),
              let stored = try? JSONDecoder().decode(
                [String: RateLimitResetCreditsSnapshot].self,
                from: data
              ) else {
            return [:]
        }
        return stored
    }

    private func persistResetCredits() {
        if let data = try? JSONEncoder().encode(resetCreditsByAccountKey) {
            userDefaults.set(data, forKey: Self.accountResetCreditsKey)
        }
    }

    private func mergedResetCredits(
        _ fetched: RateLimitResetCreditsSnapshot,
        cached: RateLimitResetCreditsSnapshot?
    ) -> RateLimitResetCreditsSnapshot {
        guard fetched.availableCount > fetched.credits.count,
              let cached,
              cached.availableCount == fetched.availableCount,
              cached.credits.count > fetched.credits.count else {
            return fetched
        }
        let stillValid = cached.credits.filter {
            guard let expiresAt = $0.expiresAt else { return true }
            return expiresAt > Date.now.timeIntervalSince1970
        }
        guard stillValid.count > fetched.credits.count else { return fetched }
        return RateLimitResetCreditsSnapshot(
            availableCount: fetched.availableCount,
            credits: stillValid,
            checkedAt: fetched.checkedAt
        )
    }

    private func evaluateAutoMonitor() {
        guard askBeforeSwitchingEnabled,
              !externalAutoSwitchEnabled,
              !isSwitching,
              let activeAccount,
              !activeAccount.isUsageStale(at: freshnessNow),
              !activeAccount.hasResetPending(at: freshnessNow),
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
        pendingAutoMonitorPromptExpiresAt = freshnessNow.addingTimeInterval(10 * 60)
        notifications.promptForAutoSwitch(from: activeAccount, to: candidate) { [weak self] in
            guard let self else { return }
            defer {
                pendingAutoMonitorPromptTargetKey = nil
                pendingAutoMonitorPromptExpiresAt = nil
            }
            await refreshAll(showNotifications: false)
            guard let refreshedCandidate = accounts.first(where: { $0.accountKey == candidate.accountKey }),
                  !refreshedCandidate.isUsageStale,
                  !refreshedCandidate.hasResetPending() else {
                notifications.notify(title: "Switch cancelled", body: "Quota data changed or could not be verified.")
                return
            }
            await switchToAccount(refreshedCandidate, notifyOnSuccess: false)
        }
    }
}

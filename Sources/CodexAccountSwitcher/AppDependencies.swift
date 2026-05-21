import Foundation

protocol CodexAuthRunning: Sendable {
    func refreshUsage() async throws
    func status() async throws -> AuthStatus
    func switchAccount(query: String) async throws
    func primeUsage(accountKey: String, accountQuery: String) async throws
    func setAutoSwitch(enabled: Bool) async throws
    func setThresholds(fiveHour: Int, weekly: Int) async throws
    func setUsageAPI(enabled: Bool) async throws
    func executableExists() async -> Bool
}

protocol RegistryStoring: AnyObject {
    func loadSnapshot() throws -> RegistrySnapshot
    func startWatching(onChange: @escaping () -> Void)
}

@MainActor
protocol CodexAppControlling: AnyObject {
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

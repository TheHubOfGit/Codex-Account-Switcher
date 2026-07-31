import Foundation
import Testing
@testable import CodexAccountSwitcher

struct LivePrimerSmokeTests {
    @Test
    func readResetCreditsForEveryRealAccountWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["CODEX_ACCOUNT_SWITCHER_LIVE_RESET_CREDITS"] == "1" else {
            return
        }

        let snapshot = try RegistryStore().loadSnapshot()
        let runner = CodexAuthRunner()
        var results: [RateLimitResetCreditsSnapshot] = []

        for account in snapshot.accounts {
            let accountID = try #require(account.chatGPTAccountID)
            results.append(
                try await runner.readRateLimitResetCredits(
                    account: PrimerAccountIdentity(
                        accountKey: account.accountKey,
                        email: account.email,
                        chatGPTAccountID: accountID
                    )
                )
            )
        }

        #expect(results.count == snapshot.accounts.count)
        #expect(results.allSatisfy { $0.availableCount == $0.credits.count })
        #expect(results.flatMap(\.credits).allSatisfy { $0.expiresAt != nil })
    }

    @Test
    func primeEveryRealAccountWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["CODEX_ACCOUNT_SWITCHER_LIVE_PRIME"] == "1" else {
            return
        }

        let registry = RegistryStore()
        let startingSnapshot = try registry.loadSnapshot()
        let runner = CodexAuthRunner()
        var delivered: [String] = []
        var attempted: [String] = []
        var failures: [String] = []

        for account in startingSnapshot.accounts {
            attempted.append(account.accountKey)
            guard let chatGPTAccountID = account.chatGPTAccountID else {
                failures.append("\(account.email): missing account identity")
                continue
            }
            let identity = PrimerAccountIdentity(
                accountKey: account.accountKey,
                email: account.email,
                chatGPTAccountID: chatGPTAccountID
            )
            do {
                let result = try await runner.primeUsage(account: identity)
                if result.response.lowercased() == "hi" {
                    delivered.append(account.accountKey)
                } else {
                    failures.append("\(account.email): unexpected response")
                }
            } catch {
                failures.append("\(account.email): \(error.localizedDescription)")
            }
        }

        let refresh = try await runner.refreshUsage()
        let endingSnapshot = try registry.loadSnapshot()

        #expect(attempted.count == startingSnapshot.accounts.count)
        #expect(endingSnapshot.activeAccountKey == startingSnapshot.activeAccountKey)
        print(
            "Live primer attempted \(attempted.count)/\(startingSnapshot.accounts.count), "
                + "delivered \(delivered.count)/\(startingSnapshot.accounts.count), "
                + "quota verified for \(refresh.successfulAccountEmails.count)/\(startingSnapshot.accounts.count). "
                + (failures.isEmpty ? "" : "Failures: \(failures.joined(separator: " | "))")
        )
    }
}

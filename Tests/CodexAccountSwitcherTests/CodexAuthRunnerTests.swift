import Foundation
import Testing
@testable import CodexAccountSwitcher

struct CodexAuthRunnerTests {
    @Test
    func augmentedPathIncludesDefaultSearchPathsWhenPathIsMissing() {
        let environment = CodexAuthRunner.environmentWithAugmentedPath([:])
        let path = environment["PATH"] ?? ""

        #expect(path.split(separator: ":").contains("/opt/homebrew/bin"))
        #expect(path.split(separator: ":").contains("/usr/local/bin"))
        #expect(path.split(separator: ":").contains("/usr/bin"))
    }

    @Test
    func augmentedPathPreservesExistingEntriesAndAddsDefaults() {
        let environment = CodexAuthRunner.environmentWithAugmentedPath(["PATH": "/custom/bin:/usr/bin"])
        let components = environment["PATH"]?.split(separator: ":").map(String.init) ?? []

        #expect(components.first == "/custom/bin")
        #expect(components.contains("/usr/bin"))
        #expect(components.contains("/opt/homebrew/bin"))
        #expect(components.contains("/usr/local/bin"))
        #expect(components.filter { $0 == "/usr/bin" }.count == 1)
    }

    @Test
    func detectsPartialRefreshOutput() {
        #expect(CodexAuthRunner.containsRefreshFailure("account@example.com 401 Unauthorized"))
        #expect(CodexAuthRunner.containsRefreshFailure("API Error: token_invalidated"))
        #expect(CodexAuthRunner.containsRefreshFailure("account@example.com Business RequestFailed RequestFailed"))
        #expect(!CodexAuthRunner.containsRefreshFailure("4 accounts refreshed successfully"))
    }

    @Test
    func identifiesOnlyAccountsWhoseUsageRefreshFailed() {
        let result = CodexAuthRunner.refreshResult(
            from: """
              01 fresh@example.com Business 0% 0% Now
              02 stale@example.com Business 401 401 3d ago
            """
        )

        #expect(result.successfulAccountEmails == ["fresh@example.com"])
        #expect(result.failedAccounts["stale@example.com"] == "401 Unauthorized")
        #expect(!result.hadUnattributedFailure)
    }

    @Test
    func weeklyOnlyRowIsTreatedAsSuccessfullyRefreshed() {
        let result = CodexAuthRunner.refreshResult(
            from: "01 weekly@example.com Business 43% (12:35 on 31 Jul) Now"
        )

        #expect(result.successfulAccountEmails == ["weekly@example.com"])
        #expect(result.failedAccounts.isEmpty)
    }

    @Test
    func unknownAccountRowsAreNeverTreatedAsFresh() {
        let result = CodexAuthRunner.refreshResult(
            from: "01 unknown@example.com Business Pending Pending Now"
        )

        #expect(result.successfulAccountEmails.isEmpty)
        #expect(result.failedAccounts["unknown@example.com"] == "Unrecognized quota result")
    }

    @Test
    func parsesAndComparesCodexAuthVersions() {
        let old = CodexAuthVersion(output: "codex-auth 0.2.8")
        let supported = CodexAuthVersion(output: "codex-auth 0.2.10")

        #expect(old != nil)
        #expect(supported != nil)
        #expect(old! < .minimumSupported)
        #expect(supported! >= .minimumSupported)
    }

    @Test
    func parsesAvailableResetCreditsAndSortsByExpiry() throws {
        let checkedAt = Date(timeIntervalSince1970: 1_000)
        let result = try CodexAuthRunner.rateLimitResetCredits(
            fromAppServerOutput: """
            {"id":1,"result":{"userAgent":"test"}}
            {"id":2,"result":{"rateLimits":{},"rateLimitResetCredits":{"availableCount":3,"credits":[{"id":"later","resetType":"codexRateLimits","status":"available","expiresAt":2000,"title":"Full reset"},{"id":"used","status":"consumed","expiresAt":1500,"title":"Full reset"},{"id":"sooner","status":"available","expiresAt":1200,"title":"Full reset"}]}}}
            """,
            checkedAt: checkedAt
        )

        #expect(result.availableCount == 3)
        #expect(result.credits.map(\.id) == ["sooner", "later"])
        #expect(result.checkedAt == checkedAt)
    }

    @Test
    func rejectsMissingResetCreditSnapshot() {
        #expect(throws: CodexAuthError.invalidRateLimitResponse) {
            _ = try CodexAuthRunner.rateLimitResetCredits(
                fromAppServerOutput: #"{"id":2,"result":{"rateLimitResetCredits":null}}"#,
                checkedAt: .now
            )
        }
    }

    @Test
    func parsesBackendResetExpiryRowsWithISO8601Dates() throws {
        let result = try CodexAuthRunner.rateLimitResetCredits(
            fromBackendData: Data(
                """
                {
                  "available_count": 2,
                  "credits": [
                    {
                      "id": "reset-1",
                      "reset_type": "codex_rate_limits",
                      "status": "available",
                      "granted_at": "2026-07-01T12:00:00Z",
                      "expires_at": "2026-07-26T12:00:00Z"
                    },
                    {
                      "id": "reset-used",
                      "status": "redeemed",
                      "expires_at": "2026-07-20T12:00:00Z"
                    },
                    {
                      "id": "reset-2",
                      "status": "available",
                      "expires_at": "2026-07-31T12:00:00.000Z"
                    }
                  ]
                }
                """.utf8
            ),
            checkedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(result.availableCount == 2)
        #expect(result.credits.map(\.id) == ["reset-1", "reset-2"])
        #expect(result.credits.allSatisfy { $0.expiresAt != nil })
    }
}

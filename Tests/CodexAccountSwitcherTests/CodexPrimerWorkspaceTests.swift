import Foundation
import Testing
@testable import CodexAccountSwitcher

struct CodexPrimerWorkspaceTests {
    @Test
    func createsRestrictedWorkspaceForMatchingCredential() throws {
        let fixture = try PrimerFixture()
        defer { fixture.cleanup() }
        let account = fixture.account

        let workspace = try CodexPrimerWorkspace.make(
            account: account,
            accountsDirectory: fixture.accountsDirectory,
            temporaryDirectory: fixture.root,
            fileManager: .default
        )
        defer { try? FileManager.default.removeItem(at: workspace.codexHome) }

        #expect(workspace.environmentOverrides["CODEX_HOME"] == workspace.codexHome.path)
        #expect(FileManager.default.fileExists(
            atPath: workspace.codexHome.appendingPathComponent("auth.json").path
        ))
        let attributes = try FileManager.default.attributesOfItem(
            atPath: workspace.codexHome.appendingPathComponent("auth.json").path
        )
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test
    func rejectsCredentialForDifferentChatGPTAccount() throws {
        let fixture = try PrimerFixture()
        defer { fixture.cleanup() }

        #expect(throws: CodexAuthError.accountAuthMismatch(accountKey: fixture.account.accountKey)) {
            _ = try CodexPrimerWorkspace.make(
                account: PrimerAccountIdentity(
                    accountKey: fixture.account.accountKey,
                    email: fixture.account.email,
                    chatGPTAccountID: "different-account"
                ),
                accountsDirectory: fixture.accountsDirectory,
                temporaryDirectory: fixture.root,
                fileManager: .default
            )
        }
    }

    @Test
    func runnerValidatesResponseAndRemovesIsolatedCredentials() async throws {
        let fixture = try PrimerFixture()
        defer { fixture.cleanup() }
        let fakeCodex = fixture.root.appendingPathComponent("fake-codex")
        try """
        #!/bin/sh
        output=""
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--output-last-message" ]; then
            shift
            output="$1"
          fi
          shift
        done
        printf 'hi\\n' > "$output"
        """.write(to: fakeCodex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeCodex.path)

        let runner = CodexAuthRunner(
            accountsDirectory: fixture.accountsDirectory,
            temporaryDirectory: fixture.root,
            executableOverrides: ["codex": fakeCodex]
        )
        let result = try await runner.primeUsage(account: fixture.account)

        #expect(result == PrimerDeliveryResult(accountKey: fixture.account.accountKey, response: "hi"))
        let leftovers = try FileManager.default.contentsOfDirectory(
            at: fixture.root,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("codex-primer-") }
        #expect(leftovers.isEmpty)
    }

    @Test
    func runnerRemovesIsolatedCredentialsAfterTimeout() async throws {
        let fixture = try PrimerFixture()
        defer { fixture.cleanup() }
        let fakeCodex = fixture.root.appendingPathComponent("slow-codex")
        try """
        #!/bin/sh
        sleep 5
        """.write(to: fakeCodex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeCodex.path)

        let runner = CodexAuthRunner(
            accountsDirectory: fixture.accountsDirectory,
            temporaryDirectory: fixture.root,
            executableOverrides: ["codex": fakeCodex],
            primerTimeout: 1
        )

        var didTimeOut = false
        do {
            _ = try await runner.primeUsage(account: fixture.account)
        } catch CodexAuthError.commandTimedOut(_, let seconds) {
            didTimeOut = seconds == 1
        }
        #expect(didTimeOut)
        let leftovers = try FileManager.default.contentsOfDirectory(
            at: fixture.root,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("codex-primer-") }
        #expect(leftovers.isEmpty)
    }

    @Test
    func runnerReadsResetCreditsWithIsolatedCredentialsAndCleansUp() async throws {
        let fixture = try PrimerFixture()
        defer { fixture.cleanup() }
        let fakeCodex = fixture.root.appendingPathComponent("fake-app-server")
        try """
        #!/bin/sh
        IFS= read -r first
        IFS= read -r second
        IFS= read -r third
        input="$first$second$third"
        case "$input" in
          *'"method":"initialize"'*'"method":"account/rateLimits/read"'*) ;;
          *) exit 2 ;;
        esac
        printf '%s\\n' '{"id":1,"result":{"userAgent":"test"}}'
        printf '%s\\n' '{"id":2,"result":{"rateLimitResetCredits":{"availableCount":1,"credits":[{"id":"reset-1","status":"available","expiresAt":2000,"title":"Full reset"}]}}}'
        """.write(to: fakeCodex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeCodex.path)

        let runner = CodexAuthRunner(
            accountsDirectory: fixture.accountsDirectory,
            temporaryDirectory: fixture.root,
            executableOverrides: ["codex": fakeCodex]
        )
        let result = try await runner.readRateLimitResetCredits(account: fixture.account)

        #expect(result.availableCount == 1)
        #expect(result.credits.first?.id == "reset-1")
        let leftovers = try FileManager.default.contentsOfDirectory(
            at: fixture.root,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("codex-primer-") }
        #expect(leftovers.isEmpty)
    }
}

private struct PrimerFixture {
    let root: URL
    let accountsDirectory: URL
    let account = PrimerAccountIdentity(
        accountKey: "registry-key",
        email: "primer@example.com",
        chatGPTAccountID: "chatgpt-account"
    )

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("primer-tests-\(UUID().uuidString)", isDirectory: true)
        accountsDirectory = root.appendingPathComponent("accounts", isDirectory: true)
        try FileManager.default.createDirectory(at: accountsDirectory, withIntermediateDirectories: true)

        let encodedKey = Data(account.accountKey.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let authURL = accountsDirectory.appendingPathComponent("\(encodedKey).auth.json")
        let auth = """
        {"tokens":{"account_id":"\(account.chatGPTAccountID)","access_token":"test","id_token":"test","refresh_token":"test"}}
        """
        try auth.write(to: authURL, atomically: true, encoding: .utf8)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

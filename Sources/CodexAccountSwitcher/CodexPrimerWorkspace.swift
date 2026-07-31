import Foundation

struct CodexPrimerWorkspace {
    let codexHome: URL
    let outputURL: URL
    let environmentOverrides: [String: String]

    static func make(
        account: PrimerAccountIdentity,
        accountsDirectory: URL,
        temporaryDirectory: URL,
        fileManager: FileManager
    ) throws -> CodexPrimerWorkspace {
        let storedAuth = authFileURL(
            accountKey: account.accountKey,
            accountsDirectory: accountsDirectory,
            fileManager: fileManager
        )
        guard fileManager.fileExists(atPath: storedAuth.path) else {
            throw CodexAuthError.missingAccountAuth(accountKey: account.accountKey)
        }

        _ = try validatedAuth(
            account: account,
            accountsDirectory: accountsDirectory,
            fileManager: fileManager
        )

        let codexHome = temporaryDirectory
            .appendingPathComponent("codex-primer-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: codexHome,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )

        let isolatedAuth = codexHome.appendingPathComponent("auth.json", isDirectory: false)
        try fileManager.copyItem(at: storedAuth, to: isolatedAuth)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: isolatedAuth.path)

        return CodexPrimerWorkspace(
            codexHome: codexHome,
            outputURL: codexHome.appendingPathComponent("primer-response.txt", isDirectory: false),
            environmentOverrides: ["CODEX_HOME": codexHome.path]
        )
    }

    static func validatedAuth(
        account: PrimerAccountIdentity,
        accountsDirectory: URL,
        fileManager: FileManager
    ) throws -> StoredCodexAuth {
        let authURL = authFileURL(
            accountKey: account.accountKey,
            accountsDirectory: accountsDirectory,
            fileManager: fileManager
        )
        guard fileManager.fileExists(atPath: authURL.path) else {
            throw CodexAuthError.missingAccountAuth(accountKey: account.accountKey)
        }
        let auth = try JSONDecoder().decode(
            StoredCodexAuth.self,
            from: Data(contentsOf: authURL)
        )
        guard auth.tokens.accountID == account.chatGPTAccountID else {
            throw CodexAuthError.accountAuthMismatch(accountKey: account.accountKey)
        }
        return auth
    }

    private static func authFileURL(
        accountKey: String,
        accountsDirectory: URL,
        fileManager: FileManager
    ) -> URL {
        let encodedAccountKey = Data(accountKey.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let candidates = [
            accountsDirectory.appendingPathComponent("\(encodedAccountKey).auth.json", isDirectory: false),
            accountsDirectory.appendingPathComponent("\(accountKey).auth.json", isDirectory: false)
        ]
        return candidates.first { fileManager.fileExists(atPath: $0.path) } ?? candidates[0]
    }
}

struct StoredCodexAuth: Decodable {
    let tokens: Tokens

    struct Tokens: Decodable {
        let accountID: String
        let accessToken: String

        enum CodingKeys: String, CodingKey {
            case accountID = "account_id"
            case accessToken = "access_token"
        }
    }
}

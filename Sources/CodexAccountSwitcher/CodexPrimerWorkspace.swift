import Foundation

struct CodexPrimerWorkspace {
    let codexHome: URL
    let environmentOverrides: [String: String]

    static func make(
        accountKey: String,
        accountsDirectory: URL,
        temporaryDirectory: URL,
        fileManager: FileManager
    ) throws -> CodexPrimerWorkspace {
        let storedAuth = authFileURL(
            accountKey: accountKey,
            accountsDirectory: accountsDirectory,
            fileManager: fileManager
        )
        guard fileManager.fileExists(atPath: storedAuth.path) else {
            throw CodexAuthError.missingAccountAuth(accountKey: accountKey)
        }

        let codexHome = temporaryDirectory
            .appendingPathComponent("codex-primer-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try fileManager.copyItem(
            at: storedAuth,
            to: codexHome.appendingPathComponent("auth.json", isDirectory: false)
        )

        return CodexPrimerWorkspace(
            codexHome: codexHome,
            environmentOverrides: ["CODEX_HOME": codexHome.path]
        )
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

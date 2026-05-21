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
        let storedAuth = accountsDirectory.appendingPathComponent("\(accountKey).auth.json", isDirectory: false)
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
}

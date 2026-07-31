import Foundation

enum CodexPrimerCommand {
    static func arguments(outputURL: URL) -> [String] {
        [
        "--ask-for-approval",
        "never",
        "exec",
        "--ephemeral",
        "--ignore-user-config",
        "--skip-git-repo-check",
        "--ignore-rules",
        "--sandbox",
        "read-only",
        "--output-last-message",
        outputURL.path,
        "Reply exactly: hi"
        ]
    }
}

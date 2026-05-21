import Foundation

enum CodexAuthError: LocalizedError, Equatable {
    case executableNotFound(name: String)
    case commandFailed(command: String, code: Int32, stderr: String)
    case invalidThresholds
    case missingAccountAuth(accountKey: String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let name):
            return "\(name) is not installed or not available on PATH."
        case .commandFailed(let command, let code, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "\(command) failed with exit code \(code)."
            }
            return "\(command) failed with exit code \(code): \(detail)"
        case .invalidThresholds:
            return "Thresholds must be between 1 and 100."
        case .missingAccountAuth(let accountKey):
            return "No stored Codex auth file was found for account \(accountKey)."
        }
    }
}

actor CodexAuthRunner: CodexAuthRunning {
    private let fileManager: FileManager
    private let environment: [String: String]
    private let accountsDirectory: URL
    private let temporaryDirectory: URL

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        accountsDirectory: URL = CodexAuthRunner.defaultAccountsDirectory,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.accountsDirectory = accountsDirectory
        self.temporaryDirectory = temporaryDirectory
    }

    func refreshUsage() async throws {
        _ = try run(arguments: ["list"])
    }

    func status() async throws -> AuthStatus {
        let output = try run(arguments: ["status"])
        return AuthStatus.parse(output)
    }

    func switchAccount(query: String) async throws {
        _ = try run(arguments: ["switch", query])
    }

    func primeUsage(accountKey: String, accountQuery: String) async throws {
        let workspace = try CodexPrimerWorkspace.make(
            accountKey: accountKey,
            accountsDirectory: accountsDirectory,
            temporaryDirectory: temporaryDirectory,
            fileManager: fileManager
        )
        defer {
            try? fileManager.removeItem(at: workspace.codexHome)
        }

        _ = try runCodex(
            arguments: [
                "exec",
                "--ephemeral",
                "--skip-git-repo-check",
                "--ignore-rules",
                "--sandbox",
                "read-only",
                "--ask-for-approval",
                "never",
                "Reply exactly: hi"
            ],
            environmentOverrides: workspace.environmentOverrides
        )
    }

    func setAutoSwitch(enabled: Bool) async throws {
        _ = try run(arguments: ["config", "auto", enabled ? "enable" : "disable"])
    }

    func setThresholds(fiveHour: Int, weekly: Int) async throws {
        guard (1...100).contains(fiveHour), (1...100).contains(weekly) else {
            throw CodexAuthError.invalidThresholds
        }

        _ = try run(arguments: ["config", "auto", "--5h", "\(fiveHour)", "--weekly", "\(weekly)"])
    }

    func setUsageAPI(enabled: Bool) async throws {
        _ = try run(arguments: ["config", "api", enabled ? "enable" : "disable"])
    }

    func executableExists() async -> Bool {
        (try? executableURL(named: "codex-auth")) != nil
    }

    private func run(arguments: [String]) throws -> String {
        try run(executableName: "codex-auth", arguments: arguments)
    }

    private func runCodex(arguments: [String], environmentOverrides: [String: String] = [:]) throws -> String {
        try run(executableName: "codex", arguments: arguments, environmentOverrides: environmentOverrides)
    }

    private func run(
        executableName: String,
        arguments: [String],
        environmentOverrides: [String: String] = [:]
    ) throws -> String {
        let executable = try executableURL(named: executableName)
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment.merging(environmentOverrides) { _, new in new }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outputData, as: UTF8.self)
        let error = String(decoding: errorData, as: UTF8.self)

        guard process.terminationStatus == 0 else {
            throw CodexAuthError.commandFailed(
                command: "\(executableName) \(arguments.joined(separator: " "))",
                code: process.terminationStatus,
                stderr: error
            )
        }

        return output
    }

    private func executableURL(named executableName: String) throws -> URL {
        let directCandidates = [
            "/opt/homebrew/bin/\(executableName)",
            "/usr/local/bin/\(executableName)"
        ]

        for path in directCandidates where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let pathValue = environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for component in pathValue.split(separator: ":") {
            let candidate = String(component) + "/\(executableName)"
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        throw CodexAuthError.executableNotFound(name: executableName)
    }

    static var defaultAccountsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("accounts", isDirectory: true)
    }
}

import Foundation

enum CodexAuthError: LocalizedError, Equatable {
    case executableNotFound
    case commandFailed(command: String, code: Int32, stderr: String)
    case invalidThresholds

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "codex-auth is not installed or not available on PATH."
        case .commandFailed(let command, let code, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "\(command) failed with exit code \(code)."
            }
            return "\(command) failed with exit code \(code): \(detail)"
        case .invalidThresholds:
            return "Thresholds must be between 1 and 100."
        }
    }
}

actor CodexAuthRunner: CodexAuthRunning {
    private let fileManager: FileManager
    private let environment: [String: String]

    init(fileManager: FileManager = .default, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.fileManager = fileManager
        self.environment = environment
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
        (try? executableURL()) != nil
    }

    private func run(arguments: [String]) throws -> String {
        let executable = try executableURL()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment

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
                command: "codex-auth \(arguments.joined(separator: " "))",
                code: process.terminationStatus,
                stderr: error
            )
        }

        return output
    }

    private func executableURL() throws -> URL {
        let directCandidates = [
            "/opt/homebrew/bin/codex-auth",
            "/usr/local/bin/codex-auth"
        ]

        for path in directCandidates where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let pathValue = environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for component in pathValue.split(separator: ":") {
            let candidate = String(component) + "/codex-auth"
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        throw CodexAuthError.executableNotFound
    }
}

import Foundation

enum CodexAuthError: LocalizedError, Equatable {
    case executableNotFound(name: String)
    case commandFailed(command: String, code: Int32, stderr: String)
    case commandTimedOut(command: String, seconds: Int)
    case invalidThresholds
    case missingAccountAuth(accountKey: String)
    case missingPrimerIdentity(accountKey: String)
    case accountAuthMismatch(accountKey: String)
    case invalidPrimerResponse
    case invalidRateLimitResponse
    case resetCreditsRequestFailed(statusCode: Int)
    case partialRefresh(String)
    case switchVerificationFailed

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
        case .commandTimedOut(let command, let seconds):
            return "\(command) did not finish within \(seconds) seconds."
        case .invalidThresholds:
            return "Thresholds must be between 1 and 100."
        case .missingAccountAuth(let accountKey):
            return "No stored Codex auth file was found for account \(accountKey)."
        case .missingPrimerIdentity(let accountKey):
            return "No ChatGPT account identity was found for account \(accountKey)."
        case .accountAuthMismatch(let accountKey):
            return "The stored Codex auth file did not match account \(accountKey)."
        case .invalidPrimerResponse:
            return "Codex completed without the expected primer response."
        case .invalidRateLimitResponse:
            return "Codex returned an invalid usage-limit reset response."
        case .resetCreditsRequestFailed(let statusCode):
            return "Codex reset expiry lookup failed with HTTP \(statusCode)."
        case .partialRefresh(let detail):
            return detail
        case .switchVerificationFailed:
            return "codex-auth reported success, but the selected account was not made active."
        }
    }
}

actor CodexAuthRunner: CodexAuthRunning {
    private let fileManager: FileManager
    private let environment: [String: String]
    private let processEnvironment: [String: String]
    private let accountsDirectory: URL
    private let temporaryDirectory: URL
    private let executableOverrides: [String: URL]
    private let primerTimeout: Int

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        accountsDirectory: URL = CodexAuthRunner.defaultAccountsDirectory,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        executableOverrides: [String: URL] = [:],
        primerTimeout: Int = 120
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.processEnvironment = Self.environmentWithAugmentedPath(environment)
        self.accountsDirectory = accountsDirectory
        self.temporaryDirectory = temporaryDirectory
        self.executableOverrides = executableOverrides
        self.primerTimeout = primerTimeout
    }

    func version() async throws -> String {
        try run(executableName: "codex-auth", arguments: ["--version"], timeout: 5)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func refreshUsage() async throws -> UsageRefreshResult {
        let output = try run(arguments: ["list"], timeout: 60)
        return Self.refreshResult(from: output)
    }

    func readRateLimitResetCredits(
        account: PrimerAccountIdentity
    ) async throws -> RateLimitResetCreditsSnapshot {
        let workspace = try CodexPrimerWorkspace.make(
            account: account,
            accountsDirectory: accountsDirectory,
            temporaryDirectory: temporaryDirectory,
            fileManager: fileManager
        )
        defer { try? fileManager.removeItem(at: workspace.codexHome) }

        let requests = [
            #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"codex_account_switcher","title":"Codex Account Switcher","version":"1.0"}}}"#,
            #"{"method":"initialized","params":{}}"#,
            #"{"method":"account/rateLimits/read","id":2}"#
        ].joined(separator: "\n") + "\n"
        let output = try runAppServer(
            arguments: ["app-server", "--stdio"],
            environmentOverrides: workspace.environmentOverrides,
            requests: Data(requests.utf8),
            responseID: 2,
            timeout: 30
        )
        let appServerSnapshot = try Self.rateLimitResetCredits(
            fromAppServerOutput: output,
            checkedAt: .now
        )
        guard appServerSnapshot.availableCount > appServerSnapshot.credits.count else {
            return appServerSnapshot
        }

        // Older Codex app-server builds may expose only the authoritative count.
        // The desktop backend supplies the missing per-credit expiry rows.
        return (try? await readDetailedResetCredits(account: account)) ?? appServerSnapshot
    }

    func status() async throws -> AuthStatus {
        let output = try run(arguments: ["status"], timeout: 5)
        return AuthStatus.parse(output)
    }

    func switchAccount(query: String) async throws {
        _ = try run(arguments: ["switch", query], timeout: 15)
    }

    func primeUsage(account: PrimerAccountIdentity) async throws -> PrimerDeliveryResult {
        let workspace = try CodexPrimerWorkspace.make(
            account: account,
            accountsDirectory: accountsDirectory,
            temporaryDirectory: temporaryDirectory,
            fileManager: fileManager
        )
        defer { try? fileManager.removeItem(at: workspace.codexHome) }

        _ = try runCodex(
            arguments: CodexPrimerCommand.arguments(outputURL: workspace.outputURL),
            environmentOverrides: workspace.environmentOverrides,
            timeout: primerTimeout
        )

        let response = try String(contentsOf: workspace.outputURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard response.lowercased() == "hi" else {
            throw CodexAuthError.invalidPrimerResponse
        }
        return PrimerDeliveryResult(accountKey: account.accountKey, response: response)
    }

    func setAutoSwitch(enabled: Bool) async throws {
        _ = try run(arguments: ["config", "auto", enabled ? "enable" : "disable"], timeout: 15)
    }

    func setThresholds(fiveHour: Int, weekly: Int) async throws {
        guard (1...100).contains(fiveHour), (1...100).contains(weekly) else {
            throw CodexAuthError.invalidThresholds
        }

        _ = try run(arguments: ["config", "auto", "--5h", "\(fiveHour)", "--weekly", "\(weekly)"], timeout: 15)
    }

    func setUsageAPI(enabled: Bool) async throws {
        _ = try run(arguments: ["config", "api", enabled ? "enable" : "disable"], timeout: 15)
    }

    func executableExists() async -> Bool {
        (try? executableURL(named: "codex-auth")) != nil
    }

    private func run(arguments: [String], timeout: Int) throws -> String {
        try run(executableName: "codex-auth", arguments: arguments, timeout: timeout)
    }

    private func runCodex(
        arguments: [String],
        environmentOverrides: [String: String] = [:],
        timeout: Int
    ) throws -> String {
        try run(
            executableName: "codex",
            arguments: arguments,
            environmentOverrides: environmentOverrides,
            timeout: timeout
        )
    }

    private func readDetailedResetCredits(
        account: PrimerAccountIdentity
    ) async throws -> RateLimitResetCreditsSnapshot {
        let auth = try CodexPrimerWorkspace.validatedAuth(
            account: account,
            accountsDirectory: accountsDirectory,
            fileManager: fileManager
        )
        guard let url = URL(
            string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits"
        ) else {
            throw CodexAuthError.invalidRateLimitResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(
            "Bearer \(auth.tokens.accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(account.chatGPTAccountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw CodexAuthError.resetCreditsRequestFailed(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
            )
        }
        return try Self.rateLimitResetCredits(
            fromBackendData: data,
            checkedAt: .now
        )
    }

    private func runAppServer(
        arguments: [String],
        environmentOverrides: [String: String],
        requests: Data,
        responseID: Int,
        timeout: Int
    ) throws -> String {
        let executable = try executableURL(named: "codex")
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = processEnvironment.merging(environmentOverrides) { _, new in new }

        let captureDirectory = temporaryDirectory.appendingPathComponent(
            "codex-account-switcher-app-server-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: captureDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? fileManager.removeItem(at: captureDirectory) }

        let stdoutURL = captureDirectory.appendingPathComponent("stdout")
        let stderrURL = captureDirectory.appendingPathComponent("stderr")
        fileManager.createFile(atPath: stdoutURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        fileManager.createFile(atPath: stderrURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        let stdin = Pipe()
        defer {
            try? stdin.fileHandleForWriting.close()
            try? stdin.fileHandleForReading.close()
            try? stdout.close()
            try? stderr.close()
        }
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        try stdin.fileHandleForWriting.write(contentsOf: requests)

        let deadline = Date().addingTimeInterval(TimeInterval(timeout))
        var output = ""
        while process.isRunning, Date() < deadline {
            try? stdout.synchronize()
            output = String(decoding: try Data(contentsOf: stdoutURL), as: UTF8.self)
            if Self.containsJSONRPCResponse(id: responseID, in: output) {
                try? stdin.fileHandleForWriting.close()
                process.terminate()
                let terminationDeadline = Date().addingTimeInterval(1)
                while process.isRunning, Date() < terminationDeadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                return output
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(1)
            while process.isRunning, Date() < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            throw CodexAuthError.commandTimedOut(
                command: "codex \(arguments.joined(separator: " "))",
                seconds: timeout
            )
        }

        try? stdout.synchronize()
        output = String(decoding: try Data(contentsOf: stdoutURL), as: UTF8.self)
        if Self.containsJSONRPCResponse(id: responseID, in: output) {
            return output
        }

        let error = String(decoding: try Data(contentsOf: stderrURL).prefix(64 * 1024), as: UTF8.self)
        throw CodexAuthError.commandFailed(
            command: "codex \(arguments.joined(separator: " "))",
            code: process.terminationStatus,
            stderr: error
        )
    }

    private func run(
        executableName: String,
        arguments: [String],
        environmentOverrides: [String: String] = [:],
        standardInput: Data? = nil,
        timeout: Int
    ) throws -> String {
        let executable = try executableURL(named: executableName)
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = processEnvironment.merging(environmentOverrides) { _, new in new }

        let captureDirectory = temporaryDirectory.appendingPathComponent(
            "codex-account-switcher-process-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: captureDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? fileManager.removeItem(at: captureDirectory) }

        let stdoutURL = captureDirectory.appendingPathComponent("stdout")
        let stderrURL = captureDirectory.appendingPathComponent("stderr")
        let stdinURL = captureDirectory.appendingPathComponent("stdin")
        fileManager.createFile(atPath: stdoutURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        fileManager.createFile(atPath: stderrURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        if let standardInput {
            fileManager.createFile(
                atPath: stdinURL.path,
                contents: standardInput,
                attributes: [.posixPermissions: 0o600]
            )
        }
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        let stdin = try standardInput.map { _ in try FileHandle(forReadingFrom: stdinURL) }
        defer {
            try? stdout.close()
            try? stderr.close()
            try? stdin?.close()
        }
        process.standardInput = stdin ?? FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(1)
            while process.isRunning, Date() < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            throw CodexAuthError.commandTimedOut(
                command: "\(executableName) \(arguments.joined(separator: " "))",
                seconds: timeout
            )
        }

        let outputData = try Data(contentsOf: stdoutURL).prefix(64 * 1024)
        let errorData = try Data(contentsOf: stderrURL).prefix(64 * 1024)
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

    static func rateLimitResetCredits(
        fromAppServerOutput output: String,
        checkedAt: Date
    ) throws -> RateLimitResetCreditsSnapshot {
        for line in output.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let envelope = try? JSONDecoder().decode(AppServerRateLimitsEnvelope.self, from: data),
                  envelope.id == 2,
                  let resetCredits = envelope.result?.rateLimitResetCredits else {
                continue
            }

            let available = resetCredits.credits?
                .filter { $0.status?.lowercased() == "available" || $0.status == nil } ?? []
            return RateLimitResetCreditsSnapshot(
                availableCount: max(0, resetCredits.availableCount),
                credits: available.sorted {
                    ($0.expiresAt ?? .greatestFiniteMagnitude)
                        < ($1.expiresAt ?? .greatestFiniteMagnitude)
                },
                checkedAt: checkedAt
            )
        }
        throw CodexAuthError.invalidRateLimitResponse
    }

    static func rateLimitResetCredits(
        fromBackendData data: Data,
        checkedAt: Date
    ) throws -> RateLimitResetCreditsSnapshot {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let availableCount = integerValue(
                payload["available_count"] ?? payload["availableCount"]
              ) else {
            throw CodexAuthError.invalidRateLimitResponse
        }
        let rawCredits = payload["credits"] as? [[String: Any]] ?? []
        let credits = rawCredits.compactMap { raw -> RateLimitResetCredit? in
            let status = raw["status"] as? String
            guard status?.lowercased() == "available" || status == nil else {
                return nil
            }
            guard let id = raw["id"] as? String else { return nil }
            return RateLimitResetCredit(
                id: id,
                resetType: raw["reset_type"] as? String ?? raw["resetType"] as? String,
                status: status,
                grantedAt: timestampValue(raw["granted_at"] ?? raw["grantedAt"]),
                expiresAt: timestampValue(raw["expires_at"] ?? raw["expiresAt"]),
                title: raw["title"] as? String,
                description: raw["description"] as? String
            )
        }
        .sorted {
            ($0.expiresAt ?? .greatestFiniteMagnitude)
                < ($1.expiresAt ?? .greatestFiniteMagnitude)
        }
        return RateLimitResetCreditsSnapshot(
            availableCount: max(0, availableCount),
            credits: credits,
            checkedAt: checkedAt
        )
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func timestampValue(_ value: Any?) -> TimeInterval? {
        if let number = value as? NSNumber { return number.doubleValue }
        guard let string = value as? String else { return nil }
        if let numeric = TimeInterval(string) { return numeric }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date.timeIntervalSince1970
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)?.timeIntervalSince1970
    }

    private static func containsJSONRPCResponse(id: Int, in output: String) -> Bool {
        output.split(separator: "\n").contains { line in
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseID = object["id"] as? NSNumber else {
                return false
            }
            return responseID.intValue == id
        }
    }

    static func containsRefreshFailure(_ output: String) -> Bool {
        refreshResult(from: output).hasFailures
    }

    static func refreshResult(from output: String) -> UsageRefreshResult {
        let markers = [" 401", "unauthorized", "refresh failed", "api error", "token_invalidated", "requestfailed"]
        var successfulAccountEmails: Set<String> = []
        var failedAccounts: [String: String] = [:]
        var foundUnattributedFailure = false

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let normalized = line.lowercased()
            guard let email = line
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
                .first(where: { $0.contains("@") })?
                .lowercased() else {
                if markers.contains(where: { normalized.contains($0) }) {
                    foundUnattributedFailure = true
                }
                continue
            }

            // Codex currently exposes a weekly-only row. Older versions exposed
            // both 5-hour and weekly percentages, so one or two valid quota
            // values are both positive evidence of a successful refresh.
            if percentageCount(in: line) >= 1 {
                successfulAccountEmails.insert(email)
            } else {
                failedAccounts[email] = failureReason(in: normalized)
            }
        }

        return UsageRefreshResult(
            successfulAccountEmails: successfulAccountEmails,
            failedAccounts: failedAccounts,
            hadUnattributedFailure: foundUnattributedFailure
        )
    }

    private static func percentageCount(in line: String) -> Int {
        let regex = try? NSRegularExpression(pattern: #"(?<!\S)\d{1,3}%"#)
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex?.numberOfMatches(in: line, range: range) ?? 0
    }

    private static func failureReason(in normalizedLine: String) -> String {
        if normalizedLine.contains("401") { return "401 Unauthorized" }
        if normalizedLine.contains("requestfailed") { return "Request failed" }
        if normalizedLine.contains("token_invalidated") { return "Token invalidated" }
        if normalizedLine.contains("api error") { return "API error" }
        return "Unrecognized quota result"
    }

    private func executableURL(named executableName: String) throws -> URL {
        if let override = executableOverrides[executableName],
           fileManager.isExecutableFile(atPath: override.path) {
            return override
        }

        let directCandidates = [
            "/opt/homebrew/bin/\(executableName)",
            "/usr/local/bin/\(executableName)"
        ]

        for path in directCandidates where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let pathValue = processEnvironment["PATH"] ?? Self.defaultPathValue
        for component in pathValue.split(separator: ":") {
            let candidate = String(component) + "/\(executableName)"
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        throw CodexAuthError.executableNotFound(name: executableName)
    }

    static func environmentWithAugmentedPath(_ environment: [String: String]) -> [String: String] {
        var result = environment
        result["PATH"] = augmentedPath(from: environment["PATH"])
        return result
    }

    static func augmentedPath(from pathValue: String?) -> String {
        var components = (pathValue ?? defaultPathValue)
            .split(separator: ":")
            .map(String.init)

        for component in defaultPathValue.split(separator: ":").map(String.init) where !components.contains(component) {
            components.append(component)
        }

        for component in nodeManagerPathCandidates() where !components.contains(component) {
            components.append(component)
        }

        return components.joined(separator: ":")
    }

    private static var defaultPathValue: String {
        "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    }

    private static func nodeManagerPathCandidates() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.npm-global/bin",
            "\(home)/.local/bin",
            "\(home)/.volta/bin",
            "\(home)/.fnm/current/bin",
            "\(home)/.nvm/current/bin"
        ]
    }

    static var defaultAccountsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("accounts", isDirectory: true)
    }
}

private struct AppServerRateLimitsEnvelope: Decodable {
    let id: Int?
    let result: Result?

    struct Result: Decodable {
        let rateLimitResetCredits: ResetCredits?
    }

    struct ResetCredits: Decodable {
        let availableCount: Int
        let credits: [RateLimitResetCredit]?
    }
}

import AppKit
import Foundation

enum CodexAppError: LocalizedError {
    case applicationNotFound
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .applicationNotFound:
            return "Codex.app could not be found."
        case .launchFailed(let detail):
            return detail
        }
    }
}

@MainActor
final class CodexAppController: CodexAppControlling {
    let bundleIdentifier = "com.openai.codex"

    func quitCodex() async throws -> Bool {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)

        guard !runningApps.isEmpty else { return false }

        for app in runningApps {
            app.terminate()
        }

        let terminated = await waitUntilCodexExits(timeout: 5)
        if !terminated {
            throw CodexAppError.launchFailed(
                "Codex did not close after 5 seconds. Close it manually, then try again."
            )
        }

        return true
    }

    func launchCodex() async throws {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw CodexAppError.applicationNotFound
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: CodexAppError.launchFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func relaunchCodex() async throws {
        _ = try await quitCodex()
        try await launchCodex()
    }

    private func waitUntilCodexExits(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
                return true
            }

            try? await Task.sleep(for: .milliseconds(100))
        }

        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}

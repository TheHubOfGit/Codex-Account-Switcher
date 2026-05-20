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

    func relaunchCodex() async throws {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)

        for app in runningApps {
            app.terminate()
        }

        if !runningApps.isEmpty {
            let terminated = await waitUntilCodexExits(timeout: 1.2)

            if !terminated {
                for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
                    app.forceTerminate()
                }

                _ = await waitUntilCodexExits(timeout: 0.8)
            }
        }

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

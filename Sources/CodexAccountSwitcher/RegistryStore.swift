import Foundation

final class RegistryStore: RegistryStoring, @unchecked Sendable {
    private let registryURL: URL
    private var directorySource: DispatchSourceFileSystemObject?
    private var directoryFileDescriptor: CInt = -1
    private var changeHandler: (() -> Void)?

    init(registryURL: URL = RegistryStore.defaultRegistryURL) {
        self.registryURL = registryURL
    }

    deinit {
        stopWatching()
    }

    func loadSnapshot() throws -> RegistrySnapshot {
        let retryDelays: [useconds_t] = [0, 50_000, 150_000, 300_000]
        var lastError: Error?

        for delay in retryDelays {
            if delay > 0 { usleep(delay) }
            guard FileManager.default.fileExists(atPath: registryURL.path) else {
                lastError = SetupIssue.missingRegistry
                continue
            }

            do {
                let data = try Data(contentsOf: registryURL)
                return try RegistrySnapshot.decode(from: data)
            } catch {
                lastError = error
            }
        }

        if let issue = lastError as? SetupIssue {
            throw issue
        }
        throw SetupIssue.unreadableRegistry(lastError?.localizedDescription ?? "Unknown registry error")
    }

    func startWatching(onChange: @escaping () -> Void) {
        changeHandler = onChange
        stopWatching()

        let directoryURL = registryURL.deletingLastPathComponent()
        directoryFileDescriptor = open(directoryURL.path, O_EVTONLY)
        guard directoryFileDescriptor >= 0 else {
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self, weak source] in
            onChange()
            guard let self, let source else { return }
            let flags = source.data
            if flags.contains(.rename) || flags.contains(.delete) {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard let self, let handler = self.changeHandler else { return }
                    self.startWatching(onChange: handler)
                }
            }
        }
        source.setCancelHandler { [directoryFileDescriptor] in
            if directoryFileDescriptor >= 0 {
                close(directoryFileDescriptor)
            }
        }
        source.resume()

        self.directorySource = source
    }

    func stopWatching() {
        directorySource?.cancel()
        directorySource = nil
        directoryFileDescriptor = -1
    }

    static var defaultRegistryURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent("registry.json", isDirectory: false)
    }
}

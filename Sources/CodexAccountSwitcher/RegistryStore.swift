import Foundation

final class RegistryStore: RegistryStoring {
    private let registryURL: URL
    private var directorySource: DispatchSourceFileSystemObject?
    private var directoryFileDescriptor: CInt = -1

    init(registryURL: URL = RegistryStore.defaultRegistryURL) {
        self.registryURL = registryURL
    }

    deinit {
        stopWatching()
    }

    func loadSnapshot() throws -> RegistrySnapshot {
        guard FileManager.default.fileExists(atPath: registryURL.path) else {
            throw SetupIssue.missingRegistry
        }

        do {
            let data = try Data(contentsOf: registryURL)
            return try RegistrySnapshot.decode(from: data)
        } catch let issue as SetupIssue {
            throw issue
        } catch {
            throw SetupIssue.unreadableRegistry(error.localizedDescription)
        }
    }

    func startWatching(onChange: @escaping () -> Void) {
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

        source.setEventHandler(handler: onChange)
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

import Foundation

struct PluginLibrarySnapshot: Codable {
    let rootPath: String
    let plugins: [PluginRecord]
    let lastScannedAt: Date?
    let lastScanDuration: TimeInterval?
}

final class PluginSnapshotStore {
    private let fileManager: FileManager
    private let storageURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.storageURL = Self.defaultStorageURL(fileManager: fileManager)
    }

    func load(rootURL: URL) -> PluginLibrarySnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = try? Data(contentsOf: storageURL),
              let snapshot = try? decoder.decode(PluginLibrarySnapshot.self, from: data),
              snapshot.rootPath == rootURL.standardizedFileURL.path else {
            return nil
        }

        return snapshot
    }

    func save(_ snapshot: PluginLibrarySnapshot) {
        do {
            try fileManager.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Snapshot persistence is best-effort. Startup still works without it.
        }
    }

    private static func defaultStorageURL(fileManager: FileManager) -> URL {
        let applicationSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)

        return applicationSupportDirectory
            .appendingPathComponent("PluginSpector", isDirectory: true)
            .appendingPathComponent("plugin-library-snapshot.json")
    }
}

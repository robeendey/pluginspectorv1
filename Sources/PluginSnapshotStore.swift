import Foundation

struct PluginLibrarySnapshot: Codable {
    let rootPaths: [String]
    let plugins: [PluginRecord]
    let lastScannedAt: Date?
    let lastScanDuration: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case rootPaths
        case rootPath
        case plugins
        case lastScannedAt
        case lastScanDuration
    }

    init(rootPaths: [String], plugins: [PluginRecord], lastScannedAt: Date?, lastScanDuration: TimeInterval?) {
        self.rootPaths = rootPaths
        self.plugins = plugins
        self.lastScannedAt = lastScannedAt
        self.lastScanDuration = lastScanDuration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyRootPath = try container.decodeIfPresent(String.self, forKey: .rootPath)
        self.rootPaths = try container.decodeIfPresent([String].self, forKey: .rootPaths)
            ?? legacyRootPath.map { [$0] }
            ?? []
        self.plugins = try container.decode([PluginRecord].self, forKey: .plugins)
        self.lastScannedAt = try container.decodeIfPresent(Date.self, forKey: .lastScannedAt)
        self.lastScanDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .lastScanDuration)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rootPaths, forKey: .rootPaths)
        try container.encode(plugins, forKey: .plugins)
        try container.encodeIfPresent(lastScannedAt, forKey: .lastScannedAt)
        try container.encodeIfPresent(lastScanDuration, forKey: .lastScanDuration)
    }
}

final class PluginSnapshotStore {
    private let fileManager: FileManager
    private let storageURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.storageURL = Self.defaultStorageURL(fileManager: fileManager)
    }

    func load(rootURLs: [URL]) -> PluginLibrarySnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let expectedRootPaths = rootURLs.map { $0.standardizedFileURL.path }.sorted()

        let startedAt = CFAbsoluteTimeGetCurrent()
        guard let data = try? Data(contentsOf: storageURL),
              let snapshot = try? decoder.decode(PluginLibrarySnapshot.self, from: data) else {
            PerformanceTrace.log("Snapshot load: miss")
            return nil
        }

        let snapshotRootPaths = snapshot.rootPaths.sorted()
        let matchesCurrentRoots = snapshotRootPaths == expectedRootPaths
        let matchesLegacySingleRoot = snapshotRootPaths.count == 1 && snapshotRootPaths.allSatisfy(expectedRootPaths.contains)

        guard matchesCurrentRoots || matchesLegacySingleRoot else {
            PerformanceTrace.log("Snapshot load: schema/root mismatch (\(snapshotRootPaths))")
            return nil
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        PerformanceTrace.log("Snapshot load: \(snapshot.plugins.count) plugins in \(String(format: "%.1f", elapsed))ms")
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

import Foundation

final class PackageSizeCache {
    private struct Entry: Codable {
        let modificationTimestamp: Double?
        let byteCount: Int64
    }

    private let fileManager: FileManager
    private let storageURL: URL
    private let saveQueue = DispatchQueue(label: "PluginSpector.PackageSizeCache.save", qos: .utility)
    private let lock = NSLock()
    private var entries: [String: Entry]
    private var hasPendingChanges = false
    private var changeToken = 0
    private var saveWorkItem: DispatchWorkItem?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.storageURL = Self.defaultStorageURL(fileManager: fileManager)
        self.entries = Self.loadEntries(from: storageURL)
    }

    func byteCount(for url: URL, modificationDate: Date?) -> Int64 {
        let key = url.standardizedFileURL.path
        let timestamp = modificationDate?.timeIntervalSinceReferenceDate

        lock.lock()
        if let cached = entries[key], cached.modificationTimestamp == timestamp {
            let byteCount = cached.byteCount
            lock.unlock()
            return byteCount
        }
        lock.unlock()

        let byteCount = Self.measurePackageSize(at: url)
        let entry = Entry(modificationTimestamp: timestamp, byteCount: byteCount)
        lock.lock()
        entries[key] = entry
        hasPendingChanges = true
        changeToken += 1
        lock.unlock()
        return byteCount
    }

    func saveIfNeeded() {
        lock.lock()
        guard hasPendingChanges else {
            lock.unlock()
            return
        }
        if saveWorkItem != nil {
            lock.unlock()
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.performSave()
        }
        saveWorkItem = workItem
        lock.unlock()

        saveQueue.asyncAfter(deadline: .now() + 0.75, execute: workItem)
    }

    private func performSave() {
        let snapshot: [String: Entry]
        let token: Int

        lock.lock()
        snapshot = entries
        token = changeToken
        lock.unlock()

        do {
            try fileManager.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )

            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
            lock.lock()
            if changeToken == token {
                hasPendingChanges = false
            }
            saveWorkItem = nil
            let shouldReschedule = hasPendingChanges
            lock.unlock()
            if shouldReschedule {
                saveIfNeeded()
            }
        } catch {
            // Cache persistence is a best-effort optimization.
            lock.lock()
            saveWorkItem = nil
            lock.unlock()
        }
    }

    private static func defaultStorageURL(fileManager: FileManager) -> URL {
        let applicationSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)

        return applicationSupportDirectory
            .appendingPathComponent("PluginSpector", isDirectory: true)
            .appendingPathComponent("package-size-cache.json")
    }

    private static func loadEntries(from url: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url) else {
            return [:]
        }

        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    private static func measurePackageSize(at url: URL) -> Int64 {
        var totalBytes: Int64 = 0

        if let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .totalFileAllocatedSizeKey,
            ],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .fileSizeKey,
                    .totalFileAllocatedSizeKey,
                ])

                guard values?.isRegularFile == true else { continue }
                totalBytes += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            }
        }

        return totalBytes
    }
}

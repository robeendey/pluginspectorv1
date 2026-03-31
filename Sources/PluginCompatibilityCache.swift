import Foundation

final class PluginCompatibilityCache {
    private struct Entry: Codable {
        let modificationTimestamp: Double?
        let compatibility: PluginCompatibility
    }

    private let fileManager: FileManager
    private let storageURL: URL
    private let saveQueue = DispatchQueue(label: "PluginSpector.PluginCompatibilityCache.save", qos: .utility)
    private let lock = NSLock()
    private var entries: [String: Entry]
    private var hasPendingChanges = false
    private var saveWorkItem: DispatchWorkItem?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.storageURL = Self.defaultStorageURL(fileManager: fileManager)
        self.entries = Self.loadEntries(from: storageURL)
    }

    func compatibility(for url: URL, modificationDate: Date?) -> PluginCompatibility? {
        let key = url.standardizedFileURL.path
        let timestamp = modificationDate?.timeIntervalSinceReferenceDate

        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key], entry.modificationTimestamp == timestamp else { return nil }
        return entry.compatibility
    }

    func store(_ compatibility: PluginCompatibility, for url: URL, modificationDate: Date?) {
        let key = url.standardizedFileURL.path
        let timestamp = modificationDate?.timeIntervalSinceReferenceDate

        lock.lock()
        entries[key] = Entry(modificationTimestamp: timestamp, compatibility: compatibility)
        hasPendingChanges = true
        let shouldSchedule = saveWorkItem == nil
        lock.unlock()

        if shouldSchedule {
            scheduleSave()
        }
    }

    func saveIfNeeded() {
        lock.lock()
        let shouldSchedule = hasPendingChanges && saveWorkItem == nil
        lock.unlock()

        if shouldSchedule {
            scheduleSave()
        }
    }

    private func scheduleSave() {
        let workItem = DispatchWorkItem { [weak self] in
            self?.performSave()
        }

        lock.lock()
        saveWorkItem = workItem
        lock.unlock()

        saveQueue.asyncAfter(deadline: .now() + 0.75, execute: workItem)
    }

    private func performSave() {
        let snapshot: [String: Entry]

        lock.lock()
        snapshot = entries
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
            hasPendingChanges = false
            saveWorkItem = nil
            lock.unlock()
        } catch {
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
            .appendingPathComponent("compatibility-cache.json")
    }

    private static func loadEntries(from url: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }
}

import Foundation

enum PluginFileOperation: Sendable {
    case delete(quarantineRoot: URL)
    case move(destinationRoot: URL)
    case backup(destinationRoot: URL)

    var actionName: String {
        switch self {
        case .delete:
            "delete"
        case .move:
            "move"
        case .backup:
            "backup"
        }
    }

    var destinationRoot: URL {
        switch self {
        case .delete(let quarantineRoot):
            quarantineRoot
        case .move(let destinationRoot), .backup(let destinationRoot):
            destinationRoot
        }
    }
}

enum PluginFileActionStatus: String, Sendable {
    case success
    case dryRun
    case failed
}

enum PluginCopyVerification: Sendable {
    case matched(bytes: Int64)
    case sourceMissing
    case destinationMissing
    case sizeMismatch(sourceBytes: Int64, destinationBytes: Int64)
    case failed(reason: String)
}

struct PluginFileActionItemResult: Sendable {
    let sourceURL: URL
    let destinationURL: URL
    let status: PluginFileActionStatus
    let verification: PluginCopyVerification?
    let removedSource: Bool
    let message: String?
}

struct PluginFileActionBatchResult: Sendable {
    let operation: PluginFileOperation
    let dryRun: Bool
    let startedAt: Date
    let finishedAt: Date
    let itemResults: [PluginFileActionItemResult]

    var successCount: Int {
        itemResults.filter { $0.status == .success }.count
    }

    var dryRunCount: Int {
        itemResults.filter { $0.status == .dryRun }.count
    }

    var failureCount: Int {
        itemResults.filter { $0.status == .failed }.count
    }
}

enum PluginFileActions {
    static func execute(
        sources: [URL],
        operation: PluginFileOperation,
        dryRun: Bool,
        fileManager: FileManager = .default
    ) -> PluginFileActionBatchResult {
        let startedAt = Date()
        var itemResults: [PluginFileActionItemResult] = []
        itemResults.reserveCapacity(sources.count)

        for sourceURL in sources {
            let destinationURL = uniqueDestinationURL(
                for: sourceURL,
                root: operation.destinationRoot,
                fileManager: fileManager
            )

            if dryRun {
                itemResults.append(
                    PluginFileActionItemResult(
                        sourceURL: sourceURL,
                        destinationURL: destinationURL,
                        status: .dryRun,
                        verification: nil,
                        removedSource: false,
                        message: "Dry run: no file operations performed."
                    )
                )
                continue
            }

            let itemResult = executeOne(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                operation: operation,
                fileManager: fileManager
            )
            itemResults.append(itemResult)
        }

        return PluginFileActionBatchResult(
            operation: operation,
            dryRun: dryRun,
            startedAt: startedAt,
            finishedAt: Date(),
            itemResults: itemResults
        )
    }

    private static func executeOne(
        sourceURL: URL,
        destinationURL: URL,
        operation: PluginFileOperation,
        fileManager: FileManager
    ) -> PluginFileActionItemResult {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
            return PluginFileActionItemResult(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                status: .failed,
                verification: .sourceMissing,
                removedSource: false,
                message: "Source does not exist."
            )
        }

        do {
            try ensureDirectoryExists(at: operation.destinationRoot, fileManager: fileManager)

            let parentDirectory = destinationURL.deletingLastPathComponent()
            try ensureDirectoryExists(at: parentDirectory, fileManager: fileManager)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)

            let verification = verifyCopy(sourceURL: sourceURL, destinationURL: destinationURL, fileManager: fileManager)

            switch verification {
            case .matched:
                let removeSource: Bool
                switch operation {
                case .backup:
                    removeSource = false
                case .delete, .move:
                    removeSource = true
                }

                if removeSource {
                    try fileManager.removeItem(at: sourceURL)
                }

                return PluginFileActionItemResult(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    status: .success,
                    verification: verification,
                    removedSource: removeSource,
                    message: nil
                )
            default:
                try? fileManager.removeItem(at: destinationURL)
                return PluginFileActionItemResult(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    status: .failed,
                    verification: verification,
                    removedSource: false,
                    message: "Copy verification failed."
                )
            }
        } catch {
            return PluginFileActionItemResult(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                status: .failed,
                verification: .failed(reason: error.localizedDescription),
                removedSource: false,
                message: error.localizedDescription
            )
        }
    }

    private static func verifyCopy(
        sourceURL: URL,
        destinationURL: URL,
        fileManager: FileManager
    ) -> PluginCopyVerification {
        guard fileManager.fileExists(atPath: sourceURL.path) else { return .sourceMissing }
        guard fileManager.fileExists(atPath: destinationURL.path) else { return .destinationMissing }

        do {
            let sourceBytes = try totalAllocatedBytes(for: sourceURL, fileManager: fileManager)
            let destinationBytes = try totalAllocatedBytes(for: destinationURL, fileManager: fileManager)

            if sourceBytes == destinationBytes {
                return .matched(bytes: sourceBytes)
            }

            return .sizeMismatch(sourceBytes: sourceBytes, destinationBytes: destinationBytes)
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }

    private static func totalAllocatedBytes(for url: URL, fileManager: FileManager) throws -> Int64 {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
        ]

        let topValues = try url.resourceValues(forKeys: keys)
        if topValues.isRegularFile == true {
            return Int64(topValues.totalFileAllocatedSize ?? topValues.fileSize ?? 0)
        }

        guard topValues.isDirectory == true else {
            return Int64(topValues.totalFileAllocatedSize ?? topValues.fileSize ?? 0)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let childURL as URL in enumerator {
            let values = try childURL.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }

    private static func ensureDirectoryExists(at directoryURL: URL, fileManager: FileManager) throws {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory)
        if exists && isDirectory.boolValue {
            return
        }
        if exists && !isDirectory.boolValue {
            throw NSError(
                domain: "PluginFileActions",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Expected directory but found file at \(directoryURL.path)"]
            )
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private static func uniqueDestinationURL(for sourceURL: URL, root: URL, fileManager: FileManager) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        var candidate = root.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)
        var suffix = 1

        while fileManager.fileExists(atPath: candidate.path) {
            let stampedName = "\(baseName)-\(suffix)"
            let filename = ext.isEmpty ? stampedName : "\(stampedName).\(ext)"
            candidate = root.appendingPathComponent(filename, isDirectory: true)
            suffix += 1
        }

        return candidate
    }
}

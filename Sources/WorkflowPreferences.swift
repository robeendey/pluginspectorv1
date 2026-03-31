import Foundation

enum StartupWorkflowChoice: String, Codable, CaseIterable, Identifiable {
    case delete
    case backup
    case move

    var id: String { rawValue }
}

struct WorkflowPreferences: Codable, Equatable {
    var startupChoice: StartupWorkflowChoice
    var updatedAt: Date

    static let `default` = WorkflowPreferences(
        startupChoice: .backup,
        updatedAt: Date.distantPast
    )
}

enum WorkflowPreferencesStoreError: LocalizedError {
    case unableToResolveApplicationSupport

    var errorDescription: String? {
        switch self {
        case .unableToResolveApplicationSupport:
            "Unable to resolve Application Support directory."
        }
    }
}

final class WorkflowPreferencesStore {
    private static let containerFolderName = "PluginSpector"
    private static let filename = "workflow-preferences.json"

    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func load() throws -> WorkflowPreferences {
        let url = try fileURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return .default
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(WorkflowPreferences.self, from: data)
        } catch {
            return .default
        }
    }

    func save(_ preferences: WorkflowPreferences) throws {
        let url = try fileURL()
        try ensureContainerDirectoryExists()

        let normalized = WorkflowPreferences(
            startupChoice: preferences.startupChoice,
            updatedAt: Date()
        )
        let data = try encoder.encode(normalized)
        try data.write(to: url, options: .atomic)
    }

    func loadChoice() throws -> StartupWorkflowChoice {
        try load().startupChoice
    }

    func saveChoice(_ choice: StartupWorkflowChoice) throws {
        try save(
            WorkflowPreferences(
                startupChoice: choice,
                updatedAt: Date()
            )
        )
    }

    private func fileURL() throws -> URL {
        let appSupportDirectory = try applicationSupportDirectory()
            .appendingPathComponent(Self.containerFolderName, isDirectory: true)
        return appSupportDirectory.appendingPathComponent(Self.filename)
    }

    private func ensureContainerDirectoryExists() throws {
        let directory = try applicationSupportDirectory()
            .appendingPathComponent(Self.containerFolderName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func applicationSupportDirectory() throws -> URL {
        guard let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw WorkflowPreferencesStoreError.unableToResolveApplicationSupport
        }
        return directory
    }
}

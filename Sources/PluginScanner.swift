import Foundation

let defaultPluginRoot = URL(fileURLWithPath: "/Library/Audio/Plug-Ins", isDirectory: true)

enum PluginFormat: String, CaseIterable, Identifiable {
    case audioUnit = "Audio Unit"
    case vst2 = "VST2"
    case vst3 = "VST3"
    case aax = "AAX"
    case other = "Other"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .audioUnit:
            "AU"
        case .vst2:
            "VST2"
        case .vst3:
            "VST3"
        case .aax:
            "AAX"
        case .other:
            "Other"
        }
    }

    static func detect(from url: URL) -> PluginFormat {
        switch url.pathExtension.lowercased() {
        case "component":
            .audioUnit
        case "vst":
            .vst2
        case "vst3":
            .vst3
        case "aaxplugin":
            .aax
        default:
            .other
        }
    }
}

enum SidebarFilter: Hashable {
    case all
    case format(PluginFormat)

    var title: String {
        switch self {
        case .all:
            "All Plugins"
        case .format(let format):
            format.rawValue
        }
    }
}

struct PluginRecord: Identifiable, Hashable {
    let bundleURL: URL
    let name: String
    let format: PluginFormat
    let vendor: String?
    let version: String?
    let bundleIdentifier: String?
    let executableName: String?
    let minimumSystemVersion: String?
    let rootFolderName: String
    let relativeLocation: String
    let modifiedAt: Date?
    let componentNames: [String]
    let packageExtension: String

    var id: String { bundleURL.path }
    var path: String { bundleURL.path }
    var displayVendor: String { vendor ?? "Unknown vendor" }
    var displayVersion: String { version ?? "Unknown" }
    var componentSummary: String {
        guard !componentNames.isEmpty else { return "None reported" }
        return componentNames.joined(separator: ", ")
    }
}

enum PluginScannerError: LocalizedError {
    case missingRoot(URL)

    var errorDescription: String? {
        switch self {
        case .missingRoot(let url):
            "Scan root does not exist: \(url.path)"
        }
    }
}

enum PluginLibraryScanner {
    private static let supportedExtensions: Set<String> = [
        "component",
        "vst",
        "vst3",
        "aaxplugin",
    ]

    static func scan(root: URL) throws -> [PluginRecord] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PluginScannerError.missingRoot(root)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
            ],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in
                true
            }
        ) else {
            return []
        }

        var records: [PluginRecord] = []

        for case let bundleURL as URL in enumerator {
            let fileExtension = bundleURL.pathExtension.lowercased()
            guard supportedExtensions.contains(fileExtension) else { continue }

            records.append(loadPluginRecord(at: bundleURL, root: root))
            enumerator.skipDescendants()
        }

        return records.sorted {
            if $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedSame {
                return $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
            }

            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func formattedPackageSize(for url: URL) -> String {
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

        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    private static func loadPluginRecord(at url: URL, root: URL) -> PluginRecord {
        let infoDictionary = bundleInfoDictionary(for: url)
        let name = pluginName(for: url, info: infoDictionary)
        let bundleIdentifier = infoDictionary["CFBundleIdentifier"] as? String
        let version = (infoDictionary["CFBundleShortVersionString"] as? String) ?? (infoDictionary["CFBundleVersion"] as? String)
        let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let componentNames = componentNames(from: infoDictionary)

        return PluginRecord(
            bundleURL: url,
            name: name,
            format: PluginFormat.detect(from: url),
            vendor: inferVendor(for: url, bundleIdentifier: bundleIdentifier, info: infoDictionary),
            version: version,
            bundleIdentifier: bundleIdentifier,
            executableName: infoDictionary["CFBundleExecutable"] as? String,
            minimumSystemVersion: infoDictionary["LSMinimumSystemVersion"] as? String,
            rootFolderName: rootFolderName(for: url, root: root),
            relativeLocation: relativeLocation(for: url, root: root),
            modifiedAt: modifiedAt,
            componentNames: componentNames,
            packageExtension: url.pathExtension.lowercased()
        )
    }

    private static func bundleInfoDictionary(for url: URL) -> [String: Any] {
        if let bundle = Bundle(url: url), let info = bundle.infoDictionary {
            return info
        }

        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        return (NSDictionary(contentsOf: infoURL) as? [String: Any]) ?? [:]
    }

    private static func pluginName(for url: URL, info: [String: Any]) -> String {
        if let displayName = info["CFBundleDisplayName"] as? String, !displayName.isEmpty {
            return displayName
        }

        if let name = info["CFBundleName"] as? String, !name.isEmpty {
            return name
        }

        return url.deletingPathExtension().lastPathComponent
    }

    private static func componentNames(from info: [String: Any]) -> [String] {
        guard let components = info["AudioComponents"] as? [[String: Any]] else { return [] }

        return components.compactMap { component in
            (component["name"] as? String) ?? (component["description"] as? String)
        }
    }

    private static func inferVendor(for url: URL, bundleIdentifier: String?, info: [String: Any]) -> String? {
        let parent = url.deletingLastPathComponent().lastPathComponent
        let rootNames: Set<String> = [
            "Audio",
            "Components",
            "MAS",
            "Plug-Ins",
            "VST",
            "VST2",
            "VST2 Custom",
            "VST3",
        ]

        if !rootNames.contains(parent) {
            return parent
        }

        if let copyright = info["NSHumanReadableCopyright"] as? String,
           let owner = copyright
            .components(separatedBy: "Copyright")
            .last?
            .components(separatedBy: ".")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !owner.isEmpty {
            return owner
        }

        if let bundleIdentifier {
            let parts = bundleIdentifier.split(separator: ".").map(String.init)
            if parts.count >= 2 {
                return parts[1]
            }
        }

        return nil
    }

    private static func rootFolderName(for url: URL, root: URL) -> String {
        let relativeComponents = url.path.replacingOccurrences(of: root.path + "/", with: "").split(separator: "/")
        return relativeComponents.first.map(String.init) ?? root.lastPathComponent
    }

    private static func relativeLocation(for url: URL, root: URL) -> String {
        let relativePath = url.path.replacingOccurrences(of: root.path + "/", with: "")
        return relativePath
    }
}

@MainActor
final class PluginLibraryViewModel: ObservableObject {
    static let defaultRoot = defaultPluginRoot

    @Published private(set) var plugins: [PluginRecord] = []
    @Published private(set) var lastScanDuration: TimeInterval?
    @Published private(set) var lastScannedAt: Date?
    @Published var isScanning = false
    @Published var scanError: String?
    @Published var selectedFilter: SidebarFilter = .all
    @Published var selectedPluginID: PluginRecord.ID?

    let rootURL: URL

    init(rootURL: URL = defaultPluginRoot) {
        self.rootURL = rootURL
    }

    func scan() {
        guard !isScanning else { return }

        let rootURL = rootURL
        isScanning = true
        scanError = nil

        Task {
            let startDate = Date()

            do {
                let records = try await Task.detached(priority: .userInitiated) {
                    try PluginLibraryScanner.scan(root: rootURL)
                }.value

                plugins = records
                lastScannedAt = Date()
                lastScanDuration = Date().timeIntervalSince(startDate)

                if !records.contains(where: { $0.id == selectedPluginID }) {
                    selectedPluginID = nil
                }
            } catch {
                scanError = error.localizedDescription
            }

            isScanning = false
        }
    }

    func selectedPlugin(in plugins: [PluginRecord]) -> PluginRecord? {
        guard let selectedPluginID else { return nil }
        return plugins.first(where: { $0.id == selectedPluginID })
    }

    func totalCount(for filter: SidebarFilter) -> Int {
        switch filter {
        case .all:
            plugins.count
        case .format(let format):
            plugins.filter { $0.format == format }.count
        }
    }
}

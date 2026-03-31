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
    case vendor(String)
    case folder(String)

    var title: String {
        switch self {
        case .all:
            "All Plugins"
        case .format(let format):
            format.rawValue
        case .vendor(let vendor):
            vendor
        case .folder(let folder):
            folder
        }
    }
}

struct PluginRecord: Identifiable, Hashable, Sendable {
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
    let packageSizeBytes: Int64
    let searchIndex: String

    var id: String { bundleURL.path }
    var path: String { bundleURL.path }
    var displayVendor: String { vendor ?? "Unknown vendor" }
    var displayVersion: String { version ?? "Unknown" }
    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: packageSizeBytes, countStyle: .file)
    }
    var componentSummary: String {
        guard !componentNames.isEmpty else { return "None reported" }
        return componentNames.joined(separator: ", ")
    }

    static func buildSearchIndex(
        name: String,
        displayVendor: String,
        displayVersion: String,
        rootFolderName: String,
        relativeLocation: String,
        bundleIdentifier: String?,
        componentSummary: String
    ) -> String {
        [
            name,
            displayVendor,
            displayVersion,
            rootFolderName,
            relativeLocation,
            bundleIdentifier ?? "",
            componentSummary,
        ]
        .joined(separator: "\n")
        .lowercased()
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
    private static let packageSizeCache = PackageSizeCache()

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

        packageSizeCache.saveIfNeeded()
        return records
    }

    static func formattedPackageSize(for url: URL) -> String {
        let modificationDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return ByteCountFormatter.string(
            fromByteCount: packageSizeCache.byteCount(for: url, modificationDate: modificationDate),
            countStyle: .file
        )
    }

    private static func loadPluginRecord(at url: URL, root: URL) -> PluginRecord {
        let infoDictionary = bundleInfoDictionary(for: url)
        let name = pluginName(for: url, info: infoDictionary)
        let bundleIdentifier = infoDictionary["CFBundleIdentifier"] as? String
        let version = (infoDictionary["CFBundleShortVersionString"] as? String) ?? (infoDictionary["CFBundleVersion"] as? String)
        let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let componentNames = componentNames(from: infoDictionary)
        let rootFolder = rootFolderName(for: url, root: root)
        let relativePath = relativeLocation(for: url, root: root)
        let rawVendor = inferVendor(for: url, bundleIdentifier: bundleIdentifier, info: infoDictionary)
        let vendor = rawVendor.map { PluginLibraryScanner.sanitizedManufacturer($0) }
        let displayVendor = vendor ?? "Unknown vendor"
        let displayVersion = version ?? "Unknown"
        let componentSummary = componentNames.isEmpty ? "None reported" : componentNames.joined(separator: ", ")
        let searchIndex = PluginRecord.buildSearchIndex(
            name: name,
            displayVendor: displayVendor,
            displayVersion: displayVersion,
            rootFolderName: rootFolder,
            relativeLocation: relativePath,
            bundleIdentifier: bundleIdentifier,
            componentSummary: componentSummary
        )

        return PluginRecord(
            bundleURL: url,
            name: name,
            format: PluginFormat.detect(from: url),
            vendor: vendor,
            version: version,
            bundleIdentifier: bundleIdentifier,
            executableName: infoDictionary["CFBundleExecutable"] as? String,
            minimumSystemVersion: infoDictionary["LSMinimumSystemVersion"] as? String,
            rootFolderName: rootFolder,
            relativeLocation: relativePath,
            modifiedAt: modifiedAt,
            componentNames: componentNames,
            packageExtension: url.pathExtension.lowercased(),
            packageSizeBytes: packageSizeCache.byteCount(for: url, modificationDate: modifiedAt),
            searchIndex: searchIndex
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

    // MARK: - Manufacturer sanitization

    /// Strips copyright noise, normalises 4-digit years, and maps known brand
    /// aliases to a single canonical name.
    static func sanitizedManufacturer(_ raw: String) -> String {
        var s = raw

        // Strip © symbol
        s = s.replacingOccurrences(of: "©", with: "")
        // Strip "Copyright" word (case-insensitive)
        s = s.replacingOccurrences(of: #"(?i)\bcopyright\b"#, with: "", options: .regularExpression)
        // Strip standalone 4-digit years, e.g. 2022 or 2018-2024
        s = s.replacingOccurrences(
            of: #"\b[12][0-9]{3}(?:-[12][0-9]{3})?\b"#,
            with: "",
            options: .regularExpression
        )
        s = s.trimmingCharacters(in: .whitespaces)

        // Brand grouping on the cleaned value
        let key = s.lowercased()
        switch key {
        case "uad", "universal audio", "uad mono",
             _ where key.hasPrefix("uad "):
            return "Universal Audio"
        case "plugin-alliance", "plugin alliance":
            return "Plugin Alliance"
        default:
            break
        }

        return s.isEmpty ? raw.trimmingCharacters(in: .whitespaces).capitalized : s.capitalized
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
        case .vendor(let vendor):
            plugins.filter { $0.displayVendor == vendor }.count
        case .folder(let folder):
            plugins.filter { $0.rootFolderName == folder }.count
        }
    }
}

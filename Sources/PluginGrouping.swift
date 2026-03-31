import Foundation

struct CollapsedPlugin: Identifiable, Hashable {
    struct Variant: Identifiable, Hashable {
        let record: PluginRecord

        var id: String { record.id }
        var format: PluginFormat { record.format }
        var version: String { record.displayVersion }
        var path: String { record.path }
        var relativeLocation: String { record.relativeLocation }
        var modifiedAt: Date? { record.modifiedAt }
        var sizeBytes: Int64 { record.packageSizeBytes }
        var displaySize: String { record.displaySize }
    }

    let canonicalKey: String
    let displayName: String
    let displayVendor: String
    let bundleIdentifierPrefix: String?
    let formats: [PluginFormat]
    let versions: [String]
    let variants: [Variant]
    let totalSizeBytes: Int64
    let latestModifiedAt: Date?
    let primaryRecord: PluginRecord

    var id: String { canonicalKey }

    var isMultiFormat: Bool { formats.count > 1 }

    var formatSummary: String {
        formats.map(\.shortLabel).joined(separator: " / ")
    }

    var versionSummary: String {
        guard !versions.isEmpty else { return "Unknown" }
        if versions.count == 1 {
            return versions[0]
        }
        return "\(versions.count) versions"
    }

    var variantSummary: String {
        "\(variants.count) variant\(variants.count == 1 ? "" : "s")"
    }

    var displayTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }

    var detailSummary: String {
        "\(formatSummary) | \(versionSummary) | \(variantSummary)"
    }
}

enum PluginGrouping {
    static func collapse(_ plugins: [PluginRecord]) -> [CollapsedPlugin] {
        let grouped = Dictionary(grouping: plugins, by: canonicalKey(for:))
        let collapsed = grouped.map { key, records in
            buildCollapsedPlugin(canonicalKey: key, records: records)
        }

        return collapsed.sorted { lhs, rhs in
            let nameComparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }

            let vendorComparison = lhs.displayVendor.localizedCaseInsensitiveCompare(rhs.displayVendor)
            if vendorComparison != .orderedSame {
                return vendorComparison == .orderedAscending
            }

            return lhs.canonicalKey.localizedCaseInsensitiveCompare(rhs.canonicalKey) == .orderedAscending
        }
    }

    static func collapseByFormat(_ plugins: [PluginRecord]) -> [CollapsedPlugin] {
        let grouped = Dictionary(grouping: plugins) { record in
            canonicalKey(for: record) + "|" + record.format.rawValue.lowercased()
        }

        let collapsed = grouped.map { key, records in
            buildCollapsedPlugin(canonicalKey: key, records: records)
        }

        return collapsed.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func buildCollapsedPlugin(canonicalKey: String, records: [PluginRecord]) -> CollapsedPlugin {
        let sortedRecords = records.sorted(by: compareRecordsForVariantOrder)
        let variants = sortedRecords.map(CollapsedPlugin.Variant.init)
        let primaryRecord = choosePrimaryRecord(from: sortedRecords)
        let formats = Array(Set(sortedRecords.map(\.format))).sorted(by: formatOrder)
        let versions = uniqueValues(sortedRecords.map(\.displayVersion))
        let latestModifiedAt = sortedRecords.compactMap(\.modifiedAt).max()
        let totalSizeBytes = sortedRecords.reduce(0) { $0 + $1.packageSizeBytes }

        return CollapsedPlugin(
            canonicalKey: canonicalKey,
            displayName: primaryRecord.name,
            displayVendor: primaryRecord.displayVendor,
            bundleIdentifierPrefix: bundleIdentifierPrefix(primaryRecord.bundleIdentifier),
            formats: formats,
            versions: versions,
            variants: variants,
            totalSizeBytes: totalSizeBytes,
            latestModifiedAt: latestModifiedAt,
            primaryRecord: primaryRecord
        )
    }

    private static func canonicalKey(for plugin: PluginRecord) -> String {
        let normalizedName = normalizeName(plugin.name)
        let normalizedVendor = normalizeName(plugin.displayVendor)
        let bundlePrefix = bundleIdentifierPrefix(plugin.bundleIdentifier) ?? "no-bundle-id"

        return "\(normalizedVendor)|\(normalizedName)|\(bundlePrefix)"
    }

    private static func bundleIdentifierPrefix(_ bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier else { return nil }
        let parts = bundleIdentifier
            .split(separator: ".")
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return nil }
        return parts.prefix(3).joined(separator: ".").lowercased()
    }

    private static func normalizeName(_ raw: String) -> String {
        let lowered = raw
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let separators = CharacterSet.alphanumerics.inverted
        let pieces = lowered.components(separatedBy: separators).filter { !$0.isEmpty }
        return pieces.joined(separator: " ")
    }

    private static func choosePrimaryRecord(from sortedRecords: [PluginRecord]) -> PluginRecord {
        guard let first = sortedRecords.first else {
            fatalError("choosePrimaryRecord requires a non-empty record set")
        }

        return first
    }

    private static func compareRecordsForVariantOrder(lhs: PluginRecord, rhs: PluginRecord) -> Bool {
        if lhs.format != rhs.format {
            return formatOrder(lhs.format, rhs.format)
        }

        let versionComparison = lhs.displayVersion.localizedCaseInsensitiveCompare(rhs.displayVersion)
        if versionComparison != .orderedSame {
            return versionComparison == .orderedDescending
        }

        switch (lhs.modifiedAt, rhs.modifiedAt) {
        case let (left?, right?) where left != right:
            return left > right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }

        return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
    }

    private static func formatOrder(_ lhs: PluginFormat, _ rhs: PluginFormat) -> Bool {
        formatRank(lhs) < formatRank(rhs)
    }

    private static func formatRank(_ format: PluginFormat) -> Int {
        switch format {
        case .audioUnit:
            0
        case .vst3:
            1
        case .vst2:
            2
        case .aax:
            3
        case .other:
            4
        }
    }

    private static func uniqueValues(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []

        for value in values where seen.insert(value).inserted {
            ordered.append(value)
        }

        return ordered
    }
}

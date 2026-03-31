import Foundation

struct DashboardSnapshot {
    let filteredPlugins: [PluginRecord]
    let filteredManufacturerCounts: [(String, Int)]
    let filteredFormatCounts: [(PluginFormat, Int)]
    let filteredFolderCounts: [(String, Int)]
    let hasSidebarMatches: Bool
    let totalCount: Int
    let visibleCount: Int
    let manufacturerCounts: [(String, Int)]
    let folderCounts: [(String, Int)]
    let formatCounts: [(PluginFormat, Int)]
    let totalPackageSizeDescription: String
    let selectedPlugin: PluginRecord?
    let selectedCount: Int
    let visibleFormatCount: Int
    let visibleVendorCount: Int
    let multiFormatPluginIDs: Set<PluginRecord.ID>

    static let empty = DashboardSnapshot(
        filteredPlugins: [],
        filteredManufacturerCounts: [],
        filteredFormatCounts: [],
        filteredFolderCounts: [],
        hasSidebarMatches: false,
        totalCount: 0,
        visibleCount: 0,
        manufacturerCounts: [],
        folderCounts: [],
        formatCounts: [],
        totalPackageSizeDescription: ByteCountFormatter.string(fromByteCount: 0, countStyle: .file),
        selectedPlugin: nil,
        selectedCount: 0,
        visibleFormatCount: 0,
        visibleVendorCount: 0,
        multiFormatPluginIDs: []
    )
}

@MainActor
final class DashboardSnapshotModel: ObservableObject {
    @Published private(set) var snapshot: DashboardSnapshot = .empty

    func rebuild(
        plugins: [PluginRecord],
        selectedFilter: SidebarFilter,
        searchText: String,
        sidebarSearchText: String,
        sortOption: PluginSortOption,
        selectedPluginID: PluginRecord.ID?
    ) {
        let scopedPlugins: [PluginRecord]
        switch selectedFilter {
        case .all:
            scopedPlugins = plugins
        case .format(let format):
            scopedPlugins = plugins.filter { $0.format == format }
        case .vendor(let vendor):
            scopedPlugins = plugins.filter { $0.displayVendor == vendor }
        case .folder(let folder):
            scopedPlugins = plugins.filter { $0.rootFolderName == folder }
        }

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingPlugins: [PluginRecord]
        if trimmedSearch.isEmpty {
            matchingPlugins = scopedPlugins
        } else {
            let normalizedSearch = trimmedSearch.normalizedSearchKey
            matchingPlugins = scopedPlugins.filter { plugin in
                plugin.searchIndex.contains(normalizedSearch)
            }
        }

        let filteredPlugins = sortOption.sorted(matchingPlugins)
        let visibleCount = filteredPlugins.count

        var visibleFormats = Set<PluginFormat>()
        var visibleVendors = Set<String>()
        for plugin in filteredPlugins {
            visibleFormats.insert(plugin.format)
            visibleVendors.insert(plugin.displayVendor)
        }

        let selectedPlugin = selectedPluginID.flatMap { id in
            filteredPlugins.first(where: { $0.id == id })
        }
        let selectedCount = selectedPlugin == nil ? 0 : 1

        let aggregates = buildAggregates(for: plugins)
        let sidebarQuery = sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines).normalizedSearchKey
        let filteredManufacturerCounts = filterSidebarCounts(aggregates.manufacturerCounts, query: sidebarQuery)
        let filteredFormatCounts = filterSidebarCounts(aggregates.formatCounts, query: sidebarQuery)
        let filteredFolderCounts = filterSidebarCounts(aggregates.folderCounts, query: sidebarQuery)
        let hasSidebarMatches = !filteredManufacturerCounts.isEmpty || !filteredFormatCounts.isEmpty || !filteredFolderCounts.isEmpty

        let multiFormatPluginIDs: Set<PluginRecord.ID> = Set(
            PluginGrouping.collapse(filteredPlugins)
                .filter(\.isMultiFormat)
                .flatMap { $0.variants.map(\.id) }
        )

        snapshot = DashboardSnapshot(
            filteredPlugins: filteredPlugins,
            filteredManufacturerCounts: filteredManufacturerCounts,
            filteredFormatCounts: filteredFormatCounts,
            filteredFolderCounts: filteredFolderCounts,
            hasSidebarMatches: hasSidebarMatches,
            totalCount: plugins.count,
            visibleCount: visibleCount,
            manufacturerCounts: aggregates.manufacturerCounts,
            folderCounts: aggregates.folderCounts,
            formatCounts: aggregates.formatCounts,
            totalPackageSizeDescription: aggregates.totalPackageSizeDescription,
            selectedPlugin: selectedPlugin,
            selectedCount: selectedCount,
            visibleFormatCount: visibleFormats.count,
            visibleVendorCount: visibleVendors.count,
            multiFormatPluginIDs: multiFormatPluginIDs
        )
    }

    private struct Aggregates {
        let manufacturerCounts: [(String, Int)]
        let folderCounts: [(String, Int)]
        let formatCounts: [(PluginFormat, Int)]
        let totalPackageSizeDescription: String
    }

    private func buildAggregates(for plugins: [PluginRecord]) -> Aggregates {
        var vendorCounts: [String: Int] = [:]
        var folderCounts: [String: Int] = [:]
        var formatCounts: [PluginFormat: Int] = [:]
        var totalBytes: Int64 = 0

        for plugin in plugins {
            vendorCounts[plugin.displayVendor, default: 0] += 1
            folderCounts[plugin.rootFolderName, default: 0] += 1
            formatCounts[plugin.format, default: 0] += 1
            totalBytes += plugin.packageSizeBytes
        }

        let manufacturerCounts = sortedAlphabetically(vendorCounts)
        let folderCountsSorted = sortedCounts(folderCounts)
        let formatCountsSorted = PluginFormat.allCases
            .filter { $0 != .other }
            .compactMap { format -> (PluginFormat, Int)? in
                let count = formatCounts[format, default: 0]
                return count > 0 ? (format, count) : nil
            }

        let totalPackageSizeDescription = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)

        return Aggregates(
            manufacturerCounts: manufacturerCounts,
            folderCounts: folderCountsSorted,
            formatCounts: formatCountsSorted,
            totalPackageSizeDescription: totalPackageSizeDescription
        )
    }

    private func sortedCounts(_ counts: [String: Int]) -> [(String, Int)] {
        counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
                }
                return lhs.value > rhs.value
            }
            .map { ($0.key, $0.value) }
    }

    private func sortedAlphabetically(_ counts: [String: Int]) -> [(String, Int)] {
        counts
            .sorted { lhs, rhs in
                lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            .map { ($0.key, $0.value) }
    }

    private func filterSidebarCounts<T>(_ counts: [(T, Int)], query: String) -> [(T, Int)] {
        guard !query.isEmpty else { return counts }

        return counts.filter { item, _ in
            sidebarTitle(for: item).normalizedSearchKey.contains(query)
        }
    }

    private func sidebarTitle<T>(for item: T) -> String {
        switch item {
        case let format as PluginFormat:
            format.rawValue
        case let string as String:
            string
        default:
            ""
        }
    }
}

import Foundation

struct DashboardSnapshot {
    let filteredPlugins: [PluginRecord]
    let filteredManufacturerCounts: [(String, Int)]
    let filteredFormatCounts: [(PluginFormat, Int)]
    let filteredFolderCounts: [(String, Int)]
    let filteredCompatibilityCounts: [(PluginCompatibility.Verdict, Int)]
    let hasSidebarMatches: Bool
    let totalCount: Int
    let visibleCount: Int
    let manufacturerCounts: [(String, Int)]
    let folderCounts: [(String, Int)]
    let formatCounts: [(PluginFormat, Int)]
    let compatibilityCounts: [(PluginCompatibility.Verdict, Int)]
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
        filteredCompatibilityCounts: [],
        hasSidebarMatches: false,
        totalCount: 0,
        visibleCount: 0,
        manufacturerCounts: [],
        folderCounts: [],
        formatCounts: [],
        compatibilityCounts: [],
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
    private var cachedAggregates: Aggregates?
    private var cachedPluginStorageID: UInt?
    private var multiFormatTask: Task<Void, Never>?
    private var multiFormatRequestID: UInt = 0

    func rebuild(
        plugins: [PluginRecord],
        selectedFilter: SidebarFilter,
        searchText: String,
        sidebarSearchText: String,
        sortOption: PluginSortOption,
        selectedPluginIDs: Set<PluginRecord.ID>
    ) {
        let rebuildStartedAt = CFAbsoluteTimeGetCurrent()
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
        case .compatibility(let verdict):
            scopedPlugins = plugins.filter { $0.compatibility.verdict == verdict }
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

        let selectedPlugin = selectedPluginIDs.first.flatMap { id in
            filteredPlugins.first(where: { $0.id == id })
        }
        let selectedCount = filteredPlugins.filter { selectedPluginIDs.contains($0.id) }.count

        let aggregates = aggregates(for: plugins)
        let sidebarQuery = sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines).normalizedSearchKey
        let filteredManufacturerCounts = filterSidebarCounts(aggregates.manufacturerCounts, query: sidebarQuery)
        let filteredFormatCounts = filterSidebarCounts(aggregates.formatCounts, query: sidebarQuery)
        let filteredFolderCounts = filterSidebarCounts(aggregates.folderCounts, query: sidebarQuery)
        let filteredCompatibilityCounts = filterSidebarCounts(aggregates.compatibilityCounts, query: sidebarQuery)
        let hasSidebarMatches = !filteredManufacturerCounts.isEmpty || !filteredFormatCounts.isEmpty || !filteredFolderCounts.isEmpty || !filteredCompatibilityCounts.isEmpty

        snapshot = DashboardSnapshot(
            filteredPlugins: filteredPlugins,
            filteredManufacturerCounts: filteredManufacturerCounts,
            filteredFormatCounts: filteredFormatCounts,
            filteredFolderCounts: filteredFolderCounts,
            filteredCompatibilityCounts: filteredCompatibilityCounts,
            hasSidebarMatches: hasSidebarMatches,
            totalCount: plugins.count,
            visibleCount: visibleCount,
            manufacturerCounts: aggregates.manufacturerCounts,
            folderCounts: aggregates.folderCounts,
            formatCounts: aggregates.formatCounts,
            compatibilityCounts: aggregates.compatibilityCounts,
            totalPackageSizeDescription: aggregates.totalPackageSizeDescription,
            selectedPlugin: selectedPlugin,
            selectedCount: selectedCount,
            visibleFormatCount: visibleFormats.count,
            visibleVendorCount: visibleVendors.count,
            multiFormatPluginIDs: []
        )
        let elapsed = (CFAbsoluteTimeGetCurrent() - rebuildStartedAt) * 1000
        PerformanceTrace.log("Dashboard rebuild: \(plugins.count) plugins -> \(visibleCount) visible in \(String(format: "%.1f", elapsed))ms")

        scheduleMultiFormatComputation(for: filteredPlugins)
    }

    func updateSelection(selectedPluginIDs: Set<PluginRecord.ID>) {
        let selectedPlugin = selectedPluginIDs.first.flatMap { id in
            snapshot.filteredPlugins.first(where: { $0.id == id })
        }
        let selectedCount = snapshot.filteredPlugins.filter { selectedPluginIDs.contains($0.id) }.count

        snapshot = DashboardSnapshot(
            filteredPlugins: snapshot.filteredPlugins,
            filteredManufacturerCounts: snapshot.filteredManufacturerCounts,
            filteredFormatCounts: snapshot.filteredFormatCounts,
            filteredFolderCounts: snapshot.filteredFolderCounts,
            filteredCompatibilityCounts: snapshot.filteredCompatibilityCounts,
            hasSidebarMatches: snapshot.hasSidebarMatches,
            totalCount: snapshot.totalCount,
            visibleCount: snapshot.visibleCount,
            manufacturerCounts: snapshot.manufacturerCounts,
            folderCounts: snapshot.folderCounts,
            formatCounts: snapshot.formatCounts,
            compatibilityCounts: snapshot.compatibilityCounts,
            totalPackageSizeDescription: snapshot.totalPackageSizeDescription,
            selectedPlugin: selectedPlugin,
            selectedCount: selectedCount,
            visibleFormatCount: snapshot.visibleFormatCount,
            visibleVendorCount: snapshot.visibleVendorCount,
            multiFormatPluginIDs: snapshot.multiFormatPluginIDs
        )
    }

    private struct Aggregates {
        let manufacturerCounts: [(String, Int)]
        let folderCounts: [(String, Int)]
        let formatCounts: [(PluginFormat, Int)]
        let compatibilityCounts: [(PluginCompatibility.Verdict, Int)]
        let totalPackageSizeDescription: String
    }

    private func aggregates(for plugins: [PluginRecord]) -> Aggregates {
        let storageID = pluginStorageID(for: plugins)
        if cachedPluginStorageID == storageID, let cachedAggregates {
            return cachedAggregates
        }

        let startedAt = CFAbsoluteTimeGetCurrent()
        let rebuilt = buildAggregates(for: plugins)
        cachedPluginStorageID = storageID
        cachedAggregates = rebuilt
        let elapsed = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        PerformanceTrace.log("Dashboard aggregates: \(plugins.count) plugins in \(String(format: "%.1f", elapsed))ms")
        return rebuilt
    }

    private func buildAggregates(for plugins: [PluginRecord]) -> Aggregates {
        var vendorCounts: [String: Int] = [:]
        var folderCounts: [String: Int] = [:]
        var formatCounts: [PluginFormat: Int] = [:]
        var compatibilityCounts: [PluginCompatibility.Verdict: Int] = [:]
        var totalBytes: Int64 = 0

        for plugin in plugins {
            vendorCounts[plugin.displayVendor, default: 0] += 1
            folderCounts[plugin.rootFolderName, default: 0] += 1
            formatCounts[plugin.format, default: 0] += 1
            compatibilityCounts[plugin.compatibility.verdict, default: 0] += 1
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
        let compatibilityCountsSorted = [
            PluginCompatibility.Verdict.legacy32Bit,
            .rosetta,
            .unknown,
            .native,
        ].compactMap { verdict -> (PluginCompatibility.Verdict, Int)? in
            let count = compatibilityCounts[verdict, default: 0]
            return count > 0 ? (verdict, count) : nil
        }

        let totalPackageSizeDescription = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)

        return Aggregates(
            manufacturerCounts: manufacturerCounts,
            folderCounts: folderCountsSorted,
            formatCounts: formatCountsSorted,
            compatibilityCounts: compatibilityCountsSorted,
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
        case let verdict as PluginCompatibility.Verdict:
            verdict.title
        case let string as String:
            string
        default:
            ""
        }
    }

    private func pluginStorageID(for plugins: [PluginRecord]) -> UInt {
        plugins.withUnsafeBufferPointer { buffer in
            UInt(bitPattern: buffer.baseAddress)
        } ^ UInt(plugins.count)
    }

    private func scheduleMultiFormatComputation(for filteredPlugins: [PluginRecord]) {
        multiFormatTask?.cancel()
        guard !filteredPlugins.isEmpty else { return }

        multiFormatRequestID &+= 1
        let requestID = multiFormatRequestID
        let collapseInput = filteredPlugins

        multiFormatTask = Task {
            let collapseStartedAt = CFAbsoluteTimeGetCurrent()
            let multiFormatPluginIDs: Set<PluginRecord.ID> = await Task.detached(priority: .utility) {
                Set(
                    PluginGrouping.collapse(collapseInput)
                        .filter(\.isMultiFormat)
                        .flatMap { $0.variants.map(\.id) }
                )
            }.value
            let collapseElapsed = (CFAbsoluteTimeGetCurrent() - collapseStartedAt) * 1000
            PerformanceTrace.log("Dashboard multi-format collapse: \(collapseInput.count) plugins in \(String(format: "%.1f", collapseElapsed))ms")

            guard !Task.isCancelled, requestID == multiFormatRequestID else { return }

            snapshot = DashboardSnapshot(
                filteredPlugins: snapshot.filteredPlugins,
                filteredManufacturerCounts: snapshot.filteredManufacturerCounts,
                filteredFormatCounts: snapshot.filteredFormatCounts,
                filteredFolderCounts: snapshot.filteredFolderCounts,
                filteredCompatibilityCounts: snapshot.filteredCompatibilityCounts,
                hasSidebarMatches: snapshot.hasSidebarMatches,
                totalCount: snapshot.totalCount,
                visibleCount: snapshot.visibleCount,
                manufacturerCounts: snapshot.manufacturerCounts,
                folderCounts: snapshot.folderCounts,
                formatCounts: snapshot.formatCounts,
                compatibilityCounts: snapshot.compatibilityCounts,
                totalPackageSizeDescription: snapshot.totalPackageSizeDescription,
                selectedPlugin: snapshot.selectedPlugin,
                selectedCount: snapshot.selectedCount,
                visibleFormatCount: snapshot.visibleFormatCount,
                visibleVendorCount: snapshot.visibleVendorCount,
                multiFormatPluginIDs: multiFormatPluginIDs
            )
        }
    }
}

import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: PluginLibraryViewModel
    @AppStorage("pluginspector.theme") private var themeKey = PrototypeTheme.mint.rawValue
    @AppStorage("pluginspector.sidebarWidth") private var storedSidebarWidth = 250.0

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var sidebarSearchText = ""
    @State private var debouncedSidebarSearchText = ""
    @State private var sortOption = PluginSortOption.nameAscending
    @State private var sidebarWidth: CGFloat = 250
    @State private var detailPlugin: PluginRecord?
    @State private var expandedGroups: Set<SidebarGroup> = [.compatibility, .manufacturer, .format, .folder]
    @State private var dragStartWidth: CGFloat?
    @State private var toast: ToastMessage?
    @StateObject private var dashboard = DashboardSnapshotModel()

    private var theme: PrototypeTheme {
        PrototypeTheme(rawValue: themeKey) ?? .mint
    }

    private var machineSubtitle: String {
        let host = Host.current().localizedName ?? "This Mac"
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(host) · macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private var topbarTitle: String {
        library.selectedFilter.title
    }

    private var topbarSubtitle: String {
        let scanText: String
        if let lastScannedAt = library.lastScannedAt {
            scanText = "Last scanned: \(lastScannedAt.formatted(date: .abbreviated, time: .shortened))"
        } else {
            scanText = library.isRefreshingInBackground ? "Loading cached library while the background scan runs" : "Ready to scan your installed plugins"
        }

        let visibleCount = dashboard.snapshot.visibleCount
        let statusSuffix: String
        if library.isRefreshingInBackground {
            statusSuffix = " · Refreshing in background"
        } else if library.isForegroundScanning {
            statusSuffix = " · Scanning now"
        } else {
            statusSuffix = ""
        }

        return "\(scanText) · \(visibleCount) plugin\(visibleCount == 1 ? "" : "s")\(statusSuffix)"
    }

    var body: some View {
        ZStack {
            theme.background
                .ignoresSafeArea()

            HStack(spacing: 0) {
                SidebarPanel(
                    theme: theme,
                    machineSubtitle: machineSubtitle,
                    selectedTheme: theme,
                    onSelectTheme: { nextTheme in
                        themeKey = nextTheme.rawValue
                    },
                    selectedFilter: library.selectedFilter,
                    sidebarSearchText: $sidebarSearchText,
                    expandedGroups: expandedGroups,
                    manufacturerCounts: dashboard.snapshot.manufacturerCounts,
                    folderCounts: dashboard.snapshot.folderCounts,
                    compatibilityCounts: dashboard.snapshot.compatibilityCounts,
                    filteredFormatCounts: dashboard.snapshot.filteredFormatCounts,
                    filteredManufacturerCounts: dashboard.snapshot.filteredManufacturerCounts,
                    filteredFolderCounts: dashboard.snapshot.filteredFolderCounts,
                    filteredCompatibilityCounts: dashboard.snapshot.filteredCompatibilityCounts,
                    hasSidebarMatches: dashboard.snapshot.hasSidebarMatches,
                    totalCount: dashboard.snapshot.totalCount,
                    visibleCount: dashboard.snapshot.visibleCount,
                    selectedCount: dashboard.snapshot.selectedCount,
                    totalPackageSizeDescription: dashboard.snapshot.totalPackageSizeDescription,
                    onToggleGroup: toggleGroup(_:),
                    onSelectFilter: { filter in
                        library.selectedFilter = filter
                    },
                    onScan: {
                        library.scan(presentation: .foreground)
                    }
                )
                .frame(width: sidebarWidth)
                .background(theme.surface)

                SidebarResizeHandle(theme: theme)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                let startWidth = dragStartWidth ?? sidebarWidth
                                if dragStartWidth == nil {
                                    dragStartWidth = sidebarWidth
                                }

                                sidebarWidth = clampedSidebarWidth(startWidth + gesture.translation.width)
                            }
                            .onEnded { _ in
                                dragStartWidth = nil
                            }
                    )

                MainPanel(
                    theme: theme,
                    title: topbarTitle,
                    subtitle: topbarSubtitle,
                    searchText: $searchText,
                    sortOption: $sortOption,
                    plugins: dashboard.snapshot.filteredPlugins,
                    multiFormatPluginIDs: dashboard.snapshot.multiFormatPluginIDs,
                    visibleFormatCount: dashboard.snapshot.visibleFormatCount,
                    visibleVendorCount: dashboard.snapshot.visibleVendorCount,
                    isRefreshingInBackground: library.isRefreshingInBackground,
                    selectedPlugin: dashboard.snapshot.selectedPlugin,
                    selectedPluginIDs: library.selectedPluginIDs,
                    onSelectOnly: { plugin in
                        library.selectOnly(plugin.id)
                    },
                    onToggleSelection: { plugin in
                        library.toggleSelection(for: plugin.id)
                    },
                    onSelectAllFiltered: {
                        library.replaceSelection(with: Set(dashboard.snapshot.filteredPlugins.map(\.id)))
                    },
                    onClearSelection: {
                        library.clearSelection()
                    },
                    onExport: exportReport,
                    onRevealSelected: revealSelectedPlugin,
                    onOpenSelected: openSelectedPlugin,
                    onOpenDetails: openDetailForSelectedPlugin,
                    onOpenPluginDetails: { plugin in
                        detailPlugin = plugin
                    },
                    onRevealPlugin: { plugin in
                        revealPlugin(plugin)
                    },
                    onRescan: {
                        library.scan(presentation: .foreground)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(14)

            if library.isForegroundScanning {
                ScanningOverlay(theme: theme, rootPath: library.scanScopeDescription)
            }

            if let detailPlugin {
                DetailOverlay(
                    theme: theme,
                    plugin: detailPlugin,
                    scanScopeDescription: library.scanScopeDescription,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            self.detailPlugin = nil
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            VStack {
                Spacer()

                if let toast {
                    ToastView(theme: theme, toast: toast)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .task {
            sidebarWidth = clampedSidebarWidth(CGFloat(storedSidebarWidth))
            debouncedSearchText = searchText
            debouncedSidebarSearchText = sidebarSearchText
            rebuildSnapshot()
            library.startInitialRefreshIfNeeded()
        }
        .onAppear {
            sidebarWidth = clampedSidebarWidth(CGFloat(storedSidebarWidth))
        }
        .onChange(of: sidebarWidth) { newValue in
            storedSidebarWidth = Double(newValue)
        }
        .onChange(of: library.plugins) { _ in
            rebuildSnapshot()
        }
        .onChange(of: library.selectedFilter) { _ in
            rebuildSnapshot()
        }
        .onChange(of: library.selectedPluginIDs) { _ in
            dashboard.updateSelection(selectedPluginIDs: library.selectedPluginIDs)
        }
        .onChange(of: sidebarSearchText) { _ in
            scheduleSidebarSearchRebuild()
        }
        .onChange(of: sortOption) { _ in
            rebuildSnapshot()
        }
        .onChange(of: searchText) { _ in
            scheduleSearchRebuild()
        }
        .animation(.easeInOut(duration: 0.18), value: themeKey)
        .animation(.easeInOut(duration: 0.15), value: library.selectedFilter)
        .animation(.easeInOut(duration: 0.15), value: library.selectedPluginIDs)
    }

    private func rebuildSnapshot() {
        dashboard.rebuild(
            plugins: library.plugins,
            selectedFilter: library.selectedFilter,
            searchText: debouncedSearchText,
            sidebarSearchText: debouncedSidebarSearchText,
            sortOption: sortOption,
            selectedPluginIDs: library.selectedPluginIDs
        )
    }

    private func scheduleSearchRebuild() {
        let pendingValue = searchText
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard pendingValue == searchText else { return }
            debouncedSearchText = pendingValue
            rebuildSnapshot()
        }
    }

    private func scheduleSidebarSearchRebuild() {
        let pendingValue = sidebarSearchText
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard pendingValue == sidebarSearchText else { return }
            debouncedSidebarSearchText = pendingValue
            rebuildSnapshot()
        }
    }

    private func clampedSidebarWidth(_ proposed: CGFloat) -> CGFloat {
        min(max(proposed, 220), 420)
    }

    private func toggleGroup(_ group: SidebarGroup) {
        if expandedGroups.contains(group) {
            expandedGroups.remove(group)
        } else {
            expandedGroups.insert(group)
        }
    }

    private func showToast(_ message: String, color: Color) {
        let nextToast = ToastMessage(text: message, accent: color)

        withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
            toast = nextToast
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            guard toast?.id == nextToast.id else { return }

            withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                toast = nil
            }
        }
    }

    private func exportReport() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let filename = "PluginSpector-Report-\(formatter.string(from: Date())).csv"
        let destination = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent(filename)

        let plugins = library.selectedPluginIDs.isEmpty
            ? dashboard.snapshot.filteredPlugins
            : dashboard.snapshot.filteredPlugins.filter { library.selectedPluginIDs.contains($0.id) }

        Task.detached(priority: .userInitiated) {
            let rows = plugins.map { plugin in
                [
                    plugin.name,
                    plugin.format.rawValue,
                    plugin.displayVendor,
                    plugin.displayVersion,
                    "\(plugin.packageSizeBytes)",
                    plugin.rootFolderName,
                    plugin.modifiedAt?.formatted(date: .numeric, time: .shortened) ?? "Unknown",
                    plugin.bundleIdentifier ?? "",
                    plugin.relativeLocation,
                ]
                .map(ContentView.csvEscaped)
                .joined(separator: ",")
            }

            let csv = ([
                "Name,Format,Vendor,Version,SizeBytes,Folder,Modified,BundleIdentifier,Path",
            ] + rows).joined(separator: "\n")

            do {
                try csv.write(to: destination, atomically: true, encoding: .utf8)
                await MainActor.run {
                    NSWorkspace.shared.activateFileViewerSelecting([destination])
                    let targetLabel = library.selectedPluginIDs.isEmpty ? "report" : "selected plugins report"
                    showToast("Exported \(targetLabel) to Downloads.", color: theme.accent)
                }
            } catch {
                await MainActor.run {
                    showToast("Could not export report: \(error.localizedDescription)", color: ThemeTone.red.textColor(in: theme))
                }
            }
        }
    }

    private nonisolated static func csvEscaped(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func revealSelectedPlugin() {
        guard let selectedPlugin = dashboard.snapshot.selectedPlugin else {
            showToast("Select one or more plugins first.", color: ThemeTone.orange.textColor(in: theme))
            return
        }

        revealPlugin(selectedPlugin)
    }

    private func revealPlugin(_ plugin: PluginRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([plugin.bundleURL])
        showToast("Revealed \(plugin.name) in Finder.", color: theme.accent)
    }

    private func openSelectedPlugin() {
        guard let selectedPlugin = dashboard.snapshot.selectedPlugin else {
            showToast("Select one or more plugins first.", color: ThemeTone.orange.textColor(in: theme))
            return
        }

        NSWorkspace.shared.open(selectedPlugin.bundleURL)
        showToast("Opened \(selectedPlugin.name).", color: ThemeTone.teal.textColor(in: theme))
    }

    private func openDetailForSelectedPlugin() {
        guard let selectedPlugin = dashboard.snapshot.selectedPlugin else {
            showToast("Select one or more plugins first.", color: ThemeTone.orange.textColor(in: theme))
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            detailPlugin = selectedPlugin
        }
    }
}

private enum SidebarGroup: Hashable {
    case compatibility
    case manufacturer
    case format
    case folder

    var title: String {
        switch self {
        case .compatibility:
            "Compatibility"
        case .manufacturer:
            "Manufacturer"
        case .format:
            "Format"
        case .folder:
            "Folder"
        }
    }

    var icon: String {
        switch self {
        case .compatibility:
            "exclamationmark.shield"
        case .manufacturer:
            "building.2.crop.circle"
        case .format:
            "square.grid.2x2"
        case .folder:
            "folder"
        }
    }
}

private struct SidebarPanel: View {
    let theme: PrototypeTheme
    let machineSubtitle: String
    let selectedTheme: PrototypeTheme
    let onSelectTheme: (PrototypeTheme) -> Void
    let selectedFilter: SidebarFilter
    @Binding var sidebarSearchText: String
    @State private var manufacturerFilter: String = ""
    let expandedGroups: Set<SidebarGroup>
    let manufacturerCounts: [(String, Int)]
    let folderCounts: [(String, Int)]
    let compatibilityCounts: [(PluginCompatibility.Verdict, Int)]
    let filteredFormatCounts: [(PluginFormat, Int)]
    let filteredManufacturerCounts: [(String, Int)]
    let filteredFolderCounts: [(String, Int)]
    let filteredCompatibilityCounts: [(PluginCompatibility.Verdict, Int)]
    let hasSidebarMatches: Bool
    let totalCount: Int
    let visibleCount: Int
    let selectedCount: Int
    let totalPackageSizeDescription: String
    let onToggleGroup: (SidebarGroup) -> Void
    let onSelectFilter: (SidebarFilter) -> Void
    let onScan: () -> Void

    private var babyFilteredManufacturers: [(String, Int)] {
        let trimmed = manufacturerFilter.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return filteredManufacturerCounts }
        return filteredManufacturerCounts.filter {
            $0.0.normalizedSearchKey.contains(trimmed.normalizedSearchKey)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SidebarSection(theme: theme, title: "Library") {
                        SidebarFilterButton(
                            theme: theme,
                            title: "All Plugins",
                            subtitle: "Every bundle in the scan root",
                            count: totalCount,
                            icon: "bolt.fill",
                            isSelected: selectedFilter == .all
                        ) {
                            onSelectFilter(.all)
                        }
                    }

                    SidebarSection(theme: theme, title: "Browse By") {
                        VStack(spacing: 10) {
                            SearchField(
                                theme: theme,
                                placeholder: "Filter sidebar sections",
                                text: $sidebarSearchText,
                                compact: true
                            )

                            if sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasSidebarMatches {
                                SidebarGroupView(
                                    theme: theme,
                                    group: .compatibility,
                                    isExpanded: expandedGroups.contains(.compatibility),
                                    onToggle: { onToggleGroup(.compatibility) }
                                ) {
                                    VStack(spacing: 6) {
                                        ForEach(filteredCompatibilityCounts, id: \.0.rawValue) { verdict, count in
                                            SidebarFilterButton(
                                                theme: theme,
                                                title: verdict.title,
                                                subtitle: verdict.subtitle,
                                                count: count,
                                                icon: compatibilityIcon(for: verdict),
                                                isSelected: selectedFilter == .compatibility(verdict),
                                                compact: true
                                            ) {
                                                onSelectFilter(.compatibility(verdict))
                                            }
                                        }
                                    }
                                }

                                SidebarGroupView(
                                    theme: theme,
                                    group: .manufacturer,
                                    isExpanded: expandedGroups.contains(.manufacturer),
                                    onToggle: { onToggleGroup(.manufacturer) }
                                ) {
                                    VStack(spacing: 6) {
                                        // Baby Search — filters manufacturer names live
                                        SearchField(
                                            theme: theme,
                                            placeholder: "Filter manufacturers…",
                                            text: $manufacturerFilter,
                                            compact: true
                                        )
                                        ForEach(babyFilteredManufacturers, id: \.0) { vendor, count in
                                            SidebarFilterButton(
                                                theme: theme,
                                                title: vendor,
                                                subtitle: "Manufacturer",
                                                count: count,
                                                icon: "building.2",
                                                isSelected: selectedFilter == .vendor(vendor),
                                                compact: true
                                            ) {
                                                onSelectFilter(.vendor(vendor))
                                            }
                                        }
                                    }
                                }

                                SidebarGroupView(
                                    theme: theme,
                                    group: .format,
                                    isExpanded: expandedGroups.contains(.format),
                                    onToggle: { onToggleGroup(.format) }
                                ) {
                                    VStack(spacing: 6) {
                                        ForEach(filteredFormatCounts, id: \.0.id) { format, count in
                                            SidebarFilterButton(
                                                theme: theme,
                                                title: format.rawValue,
                                                subtitle: "Plugin format",
                                                count: count,
                                                icon: format.systemIcon,
                                                isSelected: selectedFilter == .format(format),
                                                compact: true
                                            ) {
                                                onSelectFilter(.format(format))
                                            }
                                        }
                                    }
                                }

                                SidebarGroupView(
                                    theme: theme,
                                    group: .folder,
                                    isExpanded: expandedGroups.contains(.folder),
                                    onToggle: { onToggleGroup(.folder) }
                                ) {
                                    VStack(spacing: 6) {
                                        ForEach(filteredFolderCounts, id: \.0) { folder, count in
                                            SidebarFilterButton(
                                                theme: theme,
                                                title: folder,
                                                subtitle: "Scan folder",
                                                count: count,
                                                icon: "folder",
                                                isSelected: selectedFilter == .folder(folder),
                                                compact: true
                                            ) {
                                                onSelectFilter(.folder(folder))
                                            }
                                        }
                                    }
                                }
                            } else {
                                Text("No sidebar matches.")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(theme.textDim)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(theme.surface2.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }

                    SidebarSection(theme: theme, title: "Summary") {
                        summaryCard
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }

            Button(action: onScan) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                    Text("Scan Plugins")
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(theme.scanGradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(theme.border)
                .frame(width: 1)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.scanGradient)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Plugin Inspector")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.text)

                    Text(machineSubtitle)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textDim)
                        .lineLimit(1)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Skin")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(theme.textDim)

                HStack(spacing: 8) {
                    ForEach(PrototypeTheme.allCases) { themeChoice in
                        Button {
                            onSelectTheme(themeChoice)
                        } label: {
                            Circle()
                                .fill(themeChoice.dotGradient)
                                .overlay {
                                    Circle()
                                        .stroke(selectedTheme == themeChoice ? theme.text : .clear, lineWidth: 2)
                                }
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.border)
                .frame(height: 1)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryRow(title: "Total", value: "\(totalCount)", accent: theme.text)
            summaryRow(title: "Visible", value: "\(visibleCount)", accent: theme.accent)
            summaryRow(title: "Manufacturers", value: "\(manufacturerCounts.count)", accent: ThemeTone.teal.textColor(in: theme))
            summaryRow(title: "Folders", value: "\(folderCounts.count)", accent: ThemeTone.orange.textColor(in: theme))
            summaryRow(title: "Needs review", value: compatibilitySummaryCount, accent: ThemeTone.red.textColor(in: theme))
            summaryRow(title: "Disk usage", value: totalPackageSizeDescription, accent: ThemeTone.green.textColor(in: theme))
            summaryRow(title: "Selected", value: "\(selectedCount)", accent: ThemeTone.purple.textColor(in: theme))
        }
        .padding(14)
        .background(theme.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        }
    }

    private func summaryRow(title: String, value: String, accent: Color) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(theme.textDim)

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(accent)
        }
    }

    private var compatibilitySummaryCount: String {
        let flagged = compatibilityCounts
            .filter { $0.0 == .legacy32Bit || $0.0 == .rosetta || $0.0 == .unknown }
            .reduce(0) { $0 + $1.1 }
        return "\(flagged)"
    }

    private func compatibilityIcon(for verdict: PluginCompatibility.Verdict) -> String {
        switch verdict {
        case .native:
            "checkmark.circle"
        case .rosetta:
            "exclamationmark.triangle"
        case .legacy32Bit:
            "xmark.octagon"
        case .unknown:
            "questionmark.circle"
        }
    }
}

private struct SidebarSection<Content: View>: View {
    let theme: PrototypeTheme
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(theme.textDim)
                .textCase(.uppercase)

            content
        }
    }
}

private struct SidebarGroupView<Content: View>: View {
    let theme: PrototypeTheme
    let group: SidebarGroup
    let isExpanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 6) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: group.icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.textDim)
                        .frame(width: 14)

                    Text(group.title)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.text)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.textDim)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(theme.surface2.opacity(0.55), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
                    .padding(.leading, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct SidebarFilterButton: View {
    let theme: PrototypeTheme
    let title: String
    let subtitle: String
    let count: Int
    let icon: String
    let isSelected: Bool
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(isSelected ? theme.accent : theme.textDim.opacity(0.6))
                    .frame(width: compact ? 7 : 8, height: compact ? 7 : 8)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.clear)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: compact ? 11 : 12, weight: isSelected ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(isSelected ? theme.text : theme.textDim)

                    if !compact {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textDim.opacity(0.8))
                    }
                }

                Spacer()

                Text("\(count)")
                    .font(.system(size: compact ? 9 : 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? theme.accent : theme.textDim)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(isSelected ? theme.accentBackground : theme.surface2, in: Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, compact ? 5 : 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? theme.accentBackground : Color.clear)
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(isSelected ? theme.accent : .clear)
                    .frame(width: compact ? 2 : 3)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarResizeHandle: View {
    let theme: PrototypeTheme

    var body: some View {
        ZStack {
            theme.background
            Rectangle()
                .fill(theme.borderStrong)
                .frame(width: 1)
        }
        .frame(width: 10)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

private struct MainPanel: View {
    let theme: PrototypeTheme
    let title: String
    let subtitle: String
    @Binding var searchText: String
    @Binding var sortOption: PluginSortOption
    let plugins: [PluginRecord]
    let multiFormatPluginIDs: Set<PluginRecord.ID>
    let visibleFormatCount: Int
    let visibleVendorCount: Int
    let isRefreshingInBackground: Bool
    let selectedPlugin: PluginRecord?
    let selectedPluginIDs: Set<PluginRecord.ID>
    let onSelectOnly: (PluginRecord) -> Void
    let onToggleSelection: (PluginRecord) -> Void
    let onSelectAllFiltered: () -> Void
    let onClearSelection: () -> Void
    let onExport: () -> Void
    let onRevealSelected: () -> Void
    let onOpenSelected: () -> Void
    let onOpenDetails: () -> Void
    let onOpenPluginDetails: (PluginRecord) -> Void
    let onRevealPlugin: (PluginRecord) -> Void
    let onRescan: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topbar
            toolbarRow
            pluginList
            bottombar
        }
        .background(theme.background)
    }

    private var topbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.text)

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textDim)
            }

            Spacer()

            HStack(spacing: 8) {
                ChromeButton(theme: theme, title: selectedPluginIDs.isEmpty ? "Export report" : "Export selected", tone: .neutral, action: onExport)
                ChromeButton(theme: theme, title: "Select filtered", tone: .neutral, isDisabled: plugins.isEmpty, action: onSelectAllFiltered)
                ChromeButton(theme: theme, title: "Clear selection", tone: .neutral, isDisabled: selectedPluginIDs.isEmpty, action: onClearSelection)
                ChromeButton(theme: theme, title: "Rescan", tone: .neutral, action: onRescan)
                ChromeButton(theme: theme, title: "Reveal selected", tone: .accent, isDisabled: selectedPlugin == nil, action: onRevealSelected)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.border)
                .frame(height: 1)
        }
    }

    private var toolbarRow: some View {
        HStack(spacing: 12) {
            SearchField(
                theme: theme,
                placeholder: "Search plugins, vendors, paths, or component names",
                text: $searchText
            )
            .frame(maxWidth: .infinity)

            SortPicker(theme: theme, selection: $sortOption)
                .frame(width: 200)

            CompactMetric(theme: theme, title: "Visible", value: "\(plugins.count)")
            CompactMetric(theme: theme, title: "Formats", value: "\(visibleFormatCount)")
            CompactMetric(theme: theme, title: "Vendors", value: "\(visibleVendorCount)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var pluginList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if plugins.isEmpty {
                    EmptyState(theme: theme, searchText: searchText, isRefreshingInBackground: isRefreshingInBackground)
                        .padding(.top, 80)
                } else {
                    ForEach(plugins) { plugin in
                        PluginCard(
                            theme: theme,
                            plugin: plugin,
                            isMultiFormat: multiFormatPluginIDs.contains(plugin.id),
                            isSelected: selectedPluginIDs.contains(plugin.id),
                            onSelect: {
                                onSelectOnly(plugin)
                            },
                            onToggleSelection: {
                                onToggleSelection(plugin)
                            },
                            onDetails: {
                                onSelectOnly(plugin)
                                onOpenPluginDetails(plugin)
                            },
                            onReveal: {
                                onSelectOnly(plugin)
                                onRevealPlugin(plugin)
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }

    private var bottombar: some View {
        HStack(spacing: 8) {
            ChromeButton(theme: theme, title: "Open details", tone: .neutral, isDisabled: selectedPlugin == nil, action: onOpenDetails)
            ChromeButton(theme: theme, title: "Open bundle", tone: .neutral, isDisabled: selectedPlugin == nil, action: onOpenSelected)

            Spacer()

            Text("\(selectedPluginIDs.count) of \(plugins.count) selected")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.textDim)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(theme.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.border)
                .frame(height: 1)
        }
    }
}

private struct SearchField: View {
    let theme: PrototypeTheme
    let placeholder: String
    @Binding var text: String
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: compact ? 11 : 12, weight: .medium))
                .foregroundStyle(theme.textDim)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: compact ? 11 : 12, weight: .medium, design: .rounded))
                .foregroundStyle(theme.text)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: compact ? 11 : 12, weight: .medium))
                        .foregroundStyle(theme.textDim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 8 : 10)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        }
        .onExitCommand {
            guard !text.isEmpty else { return }
            text = ""
        }
    }
}

private struct SortPicker: View {
    let theme: PrototypeTheme
    @Binding var selection: PluginSortOption

    var body: some View {
        Picker(selection: $selection) {
            ForEach(PluginSortOption.allCases) { option in
                Text(option.title).tag(option)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textDim)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Sort")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(theme.textDim)

                    Text(selection.title)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.textDim)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            }
        }
        .pickerStyle(.menu)
    }
}

enum PluginSortOption: String, CaseIterable, Identifiable {
    case nameAscending
    case nameDescending
    case dateNewest
    case dateOldest
    case sizeLargest
    case sizeSmallest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nameAscending:
            "Name A-Z"
        case .nameDescending:
            "Name Z-A"
        case .dateNewest:
            "Newest First"
        case .dateOldest:
            "Oldest First"
        case .sizeLargest:
            "Largest First"
        case .sizeSmallest:
            "Smallest First"
        }
    }

    func sorted(_ plugins: [PluginRecord]) -> [PluginRecord] {
        plugins.sorted { lhs, rhs in
            switch self {
            case .nameAscending:
                return comparePluginNames(lhs, rhs, ascending: true)
            case .nameDescending:
                return comparePluginNames(lhs, rhs, ascending: false)
            case .dateNewest:
                return comparePluginDates(lhs, rhs, newestFirst: true)
            case .dateOldest:
                return comparePluginDates(lhs, rhs, newestFirst: false)
            case .sizeLargest:
                return comparePluginSizes(lhs, rhs, largestFirst: true)
            case .sizeSmallest:
                return comparePluginSizes(lhs, rhs, largestFirst: false)
            }
        }
    }
}

private func comparePluginNames(_ lhs: PluginRecord, _ rhs: PluginRecord, ascending: Bool) -> Bool {
    let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
    if nameComparison != .orderedSame {
        return ascending ? nameComparison == .orderedAscending : nameComparison == .orderedDescending
    }

    let vendorComparison = lhs.displayVendor.localizedCaseInsensitiveCompare(rhs.displayVendor)
    if vendorComparison != .orderedSame {
        return vendorComparison == .orderedAscending
    }

    return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
}

private func comparePluginDates(_ lhs: PluginRecord, _ rhs: PluginRecord, newestFirst: Bool) -> Bool {
    switch (lhs.modifiedAt, rhs.modifiedAt) {
    case let (left?, right?) where left != right:
        return newestFirst ? left > right : left < right
    case (_?, nil):
        return true
    case (nil, _?):
        return false
    default:
        return comparePluginNames(lhs, rhs, ascending: true)
    }
}

private func comparePluginSizes(_ lhs: PluginRecord, _ rhs: PluginRecord, largestFirst: Bool) -> Bool {
    if lhs.packageSizeBytes != rhs.packageSizeBytes {
        return largestFirst ? lhs.packageSizeBytes > rhs.packageSizeBytes : lhs.packageSizeBytes < rhs.packageSizeBytes
    }

    return comparePluginNames(lhs, rhs, ascending: true)
}

private struct CompactMetric: View {
    let theme: PrototypeTheme
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(theme.textDim)

            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        }
    }
}

private struct PluginCard: View {
    let theme: PrototypeTheme
    let plugin: PluginRecord
    let isMultiFormat: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleSelection: () -> Void
    let onDetails: () -> Void
    let onReveal: () -> Void

    private var tone: ThemeTone {
        switch plugin.format {
        case .audioUnit:
            .orange
        case .vst2:
            .teal
        case .vst3:
            .blue
        case .aax:
            .pink
        case .other:
            .gray
        }
    }

    var body: some View {
        HStack(spacing: 11) {
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.accent : theme.textDim)
            }
            .buttonStyle(.plain)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(tone.textColor(in: theme))
                .frame(width: 3)

            Circle()
                .fill(tone.textColor(in: theme))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(plugin.name)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                Text(metaLine)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textDim)
                    .lineLimit(1)

                if isSelected {
                    Text(expandedLine)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textDim.opacity(0.92))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 4) {
                    SmallTag(theme: theme, title: plugin.compatibility.verdict.title, tone: compatibilityTone)
                    if isMultiFormat {
                        SmallTag(theme: theme, title: "Multi-Format", tone: .purple)
                    }
                    SmallTag(theme: theme, title: plugin.format.shortLabel, tone: .blue)
                    SmallTag(theme: theme, title: plugin.rootFolderName, tone: .gray)
                    SmallTag(theme: theme, title: plugin.displaySize, tone: .green)
                    if let version = plugin.version {
                        SmallTag(theme: theme, title: "v\(version)", tone: .orange)
                    }
                }

                HStack(spacing: 5) {
                    SmallActionButton(theme: theme, title: "Details", action: onDetails)
                    SmallActionButton(theme: theme, title: "Reveal", accent: true, action: onReveal)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(isSelected ? theme.accentBackground : theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? theme.accent : theme.border, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(perform: onSelect)
    }

    private var metaLine: String {
        let dateText = plugin.modifiedAt?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown date"
        return "\(plugin.relativeLocation) · \(plugin.displayVendor) · \(dateText)"
    }

    private var expandedLine: String {
        let bundleID = plugin.bundleIdentifier ?? "Bundle ID not reported"
        return "\(bundleID) · \(plugin.displaySize) · \(plugin.path)"
    }

    private var compatibilityTone: ThemeTone {
        switch plugin.compatibility.verdict {
        case .native:
            .green
        case .rosetta:
            .orange
        case .legacy32Bit:
            .red
        case .unknown:
            .gray
        }
    }
}

private struct SmallTag: View {
    let theme: PrototypeTheme
    let title: String
    let tone: ThemeTone

    var body: some View {
        Text(title)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(tone.textColor(in: theme))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tone.backgroundColor(in: theme), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(tone.borderColor(in: theme), lineWidth: 1)
            }
    }
}

private struct SmallActionButton: View {
    let theme: PrototypeTheme
    let title: String
    var accent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(accent ? theme.text : theme.textDim)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background((accent ? theme.accentBackground : theme.surface2), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(accent ? theme.accent : theme.borderStrong, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct ChromeButton: View {
    let theme: PrototypeTheme
    let title: String
    let tone: ChromeButtonTone
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(textColor)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(fillColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
    }

    private var textColor: Color {
        switch tone {
        case .neutral:
            theme.textDim
        case .accent:
            theme.accent
        }
    }

    private var fillColor: Color {
        switch tone {
        case .neutral:
            theme.buttonBackground
        case .accent:
            theme.accentBackground
        }
    }

    private var borderColor: Color {
        switch tone {
        case .neutral:
            theme.buttonBorder
        case .accent:
            theme.accent.opacity(0.42)
        }
    }
}

private enum ChromeButtonTone {
    case neutral
    case accent
}

private struct EmptyState: View {
    let theme: PrototypeTheme
    let searchText: String
    let isRefreshingInBackground: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(theme.textDim)

            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.text)

            Text(message)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.textDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var title: String {
        if isRefreshingInBackground && searchText.isEmpty {
            return "Loading Plugin Library"
        }
        return searchText.isEmpty ? "No Plugins Found" : "No Matching Plugins"
    }

    private var message: String {
        if isRefreshingInBackground && searchText.isEmpty {
            return "The app opened immediately from startup state and is scanning your plugin folders in the background."
        }
        return searchText.isEmpty ? "Run a scan or check the scan root in the sidebar." : "Try a different search term or clear the current filter."
    }
}

private struct ScanningOverlay: View {
    let theme: PrototypeTheme
    let rootPath: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.66)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text("Scanning plugins...")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.text)

                    Text(rootPath)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textDim)
                        .multilineTextAlignment(.center)
                }

                ProgressView()
                    .controlSize(.large)
                    .tint(theme.accent)

                Text("Reading bundle metadata and rebuilding the browser.")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textDim)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(theme.borderStrong, lineWidth: 1)
            }
        }
    }
}

private struct DetailOverlay: View {
    let theme: PrototypeTheme
    let plugin: PluginRecord
    let scanScopeDescription: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plugin.name)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.text)

                        Text("\(plugin.format.rawValue) · \(plugin.displayVendor)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textDim)

                        SmallTag(theme: theme, title: plugin.compatibility.verdict.title, tone: compatibilityTone)
                    }

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.textDim)
                            .frame(width: 26, height: 26)
                            .background(theme.surface2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(theme.border, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 0) {
                    detailRow("Version", plugin.displayVersion)
                    detailRow("Package Size", plugin.displaySize)
                    detailRow("Bundle ID", plugin.bundleIdentifier ?? "Not reported")
                    detailRow("Executable", plugin.executableName ?? "Not reported")
                    detailRow("Minimum macOS", plugin.minimumSystemVersion ?? "Not reported")
                    detailRow("Compatibility", plugin.compatibility.verdict.title)
                    detailRow("Review guidance", compatibilityGuidance, multiline: true)
                    detailRow("Compatibility reason", plugin.compatibility.reason, multiline: true)
                    detailRow("Folder", plugin.rootFolderName)
                    detailRow("Scan location", plugin.scanRootLabel)
                    detailRow("Extension", plugin.packageExtension)
                    detailRow("Modified", plugin.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown")
                    detailRow("Audio Components", plugin.componentSummary)
                    detailRow("Active scan scope", scanScopeDescription, multiline: true)
                    detailRow("Path", plugin.path, multiline: true, isLast: true)
                }

                HStack(spacing: 8) {
                    ChromeButton(theme: theme, title: "Reveal in Finder", tone: .neutral) {
                        NSWorkspace.shared.activateFileViewerSelecting([plugin.bundleURL])
                    }

                    ChromeButton(theme: theme, title: "Open Bundle", tone: .accent) {
                        NSWorkspace.shared.open(plugin.bundleURL)
                    }
                }
            }
            .padding(26)
            .frame(width: 520)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(theme.borderStrong, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.22), radius: 30, x: 0, y: 16)
        }
    }

    private func detailRow(_ title: String, _ value: String, multiline: Bool = false, isLast: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(theme.textDim)

            Spacer(minLength: 16)

            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: multiline)
                .textSelection(.enabled)
                .frame(maxWidth: 260, alignment: .trailing)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(theme.border)
                    .frame(height: 1)
            }
        }
    }

    private var compatibilityTone: ThemeTone {
        switch plugin.compatibility.verdict {
        case .native:
            .green
        case .rosetta:
            .orange
        case .legacy32Bit:
            .red
        case .unknown:
            .gray
        }
    }

    private var compatibilityGuidance: String {
        switch plugin.compatibility.verdict {
        case .native:
            return "This plugin should work on this Mac without Rosetta."
        case .rosetta:
            return "This plugin may still work, but only through Rosetta. Treat it as cautionary, not dead."
        case .legacy32Bit:
            return "This plugin will never work on this machine because current macOS cannot run legacy 32-bit binaries."
        case .unknown:
            return "The app cannot classify this plugin confidently yet. Review it manually before cleanup."
        }
    }
}

private struct ToastView: View {
    let theme: PrototypeTheme
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(toast.accent)
                .frame(width: 7, height: 7)

            Text(toast.text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(theme.text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.borderStrong, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 8)
    }
}

private struct ToastMessage: Identifiable {
    let id = UUID()
    let text: String
    let accent: Color
}

private enum PrototypeTheme: String, CaseIterable, Identifiable {
    case electric
    case aurora
    case neon
    case mint

    var id: String { rawValue }

    var background: Color {
        switch self {
        case .electric:
            Color(hex: 0x0D1B3E)
        case .aurora:
            Color(hex: 0x120824)
        case .neon:
            Color(hex: 0x06060F)
        case .mint:
            Color(hex: 0xEEF8F3)
        }
    }

    var surface: Color {
        switch self {
        case .electric:
            Color(hex: 0x0A1530)
        case .aurora:
            Color.white.opacity(0.05)
        case .neon:
            Color(hex: 0x09091A)
        case .mint:
            Color.white
        }
    }

    var surface2: Color {
        switch self {
        case .electric:
            Color(hex: 0x111F45)
        case .aurora:
            Color.white.opacity(0.08)
        case .neon:
            Color(red: 100 / 255, green: 200 / 255, blue: 1, opacity: 0.07)
        case .mint:
            Color(hex: 0xF4FAF7)
        }
    }

    var border: Color {
        switch self {
        case .electric:
            Color(red: 77 / 255, green: 143 / 255, blue: 1, opacity: 0.12)
        case .aurora:
            Color.white.opacity(0.08)
        case .neon:
            Color(red: 100 / 255, green: 200 / 255, blue: 1, opacity: 0.1)
        case .mint:
            Color(hex: 0xCCE8D8)
        }
    }

    var borderStrong: Color {
        switch self {
        case .electric:
            Color(red: 77 / 255, green: 143 / 255, blue: 1, opacity: 0.22)
        case .aurora:
            Color.white.opacity(0.14)
        case .neon:
            Color(red: 100 / 255, green: 200 / 255, blue: 1, opacity: 0.18)
        case .mint:
            Color(hex: 0xB8DDC8)
        }
    }

    var text: Color {
        switch self {
        case .electric:
            Color(hex: 0xC8D8F8)
        case .aurora:
            Color.white.opacity(0.86)
        case .neon:
            Color.white.opacity(0.74)
        case .mint:
            Color(hex: 0x0E3D26)
        }
    }

    var textDim: Color {
        switch self {
        case .electric:
            Color(red: 184 / 255, green: 204 / 255, blue: 240 / 255, opacity: 0.55)
        case .aurora:
            Color.white.opacity(0.42)
        case .neon:
            Color(red: 100 / 255, green: 200 / 255, blue: 1, opacity: 0.42)
        case .mint:
            Color(hex: 0x7AA898)
        }
    }

    var accent: Color {
        switch self {
        case .electric:
            Color(hex: 0x4D8FFF)
        case .aurora:
            Color(hex: 0xA78BFF)
        case .neon:
            Color(hex: 0x64C8FF)
        case .mint:
            Color(hex: 0x155C38)
        }
    }

    var accentBackground: Color {
        switch self {
        case .electric:
            Color(red: 77 / 255, green: 143 / 255, blue: 1, opacity: 0.15)
        case .aurora:
            Color(red: 167 / 255, green: 139 / 255, blue: 1, opacity: 0.18)
        case .neon:
            Color(red: 100 / 255, green: 200 / 255, blue: 1, opacity: 0.12)
        case .mint:
            Color(red: 21 / 255, green: 92 / 255, blue: 56 / 255, opacity: 0.10)
        }
    }

    var buttonBackground: Color {
        switch self {
        case .electric:
            Color(red: 77 / 255, green: 143 / 255, blue: 1, opacity: 0.08)
        case .aurora:
            Color.white.opacity(0.05)
        case .neon:
            Color.clear
        case .mint:
            Color.clear
        }
    }

    var buttonBorder: Color {
        switch self {
        case .electric:
            Color(red: 77 / 255, green: 143 / 255, blue: 1, opacity: 0.25)
        case .aurora:
            Color.white.opacity(0.12)
        case .neon:
            Color(red: 100 / 255, green: 200 / 255, blue: 1, opacity: 0.18)
        case .mint:
            Color(hex: 0xC0DECE)
        }
    }

    var scanGradient: LinearGradient {
        switch self {
        case .electric:
            LinearGradient(colors: [Color(hex: 0x2A5FD4), Color(hex: 0x4D8FFF)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .aurora:
            LinearGradient(colors: [Color(hex: 0x6E3FFF), Color(hex: 0xA78BFF)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .neon:
            LinearGradient(colors: [Color(hex: 0x0090CC), Color(hex: 0x64C8FF)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .mint:
            LinearGradient(colors: [Color(hex: 0x0E4A2C), Color(hex: 0x1A8C4A)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var dotGradient: LinearGradient {
        switch self {
        case .electric:
            LinearGradient(colors: [Color(hex: 0x0D1B3E), Color(hex: 0x4D8FFF)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .aurora:
            LinearGradient(colors: [Color(hex: 0x120824), Color(hex: 0xA78BFF)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .neon:
            LinearGradient(colors: [Color(hex: 0x06060F), Color(hex: 0x64C8FF)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .mint:
            LinearGradient(colors: [Color(hex: 0x155C38), Color(hex: 0x4DD9AC)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private enum ThemeTone {
    case blue
    case orange
    case teal
    case purple
    case green
    case pink
    case red
    case gray

    func textColor(in theme: PrototypeTheme) -> Color {
        switch (self, theme) {
        case (.blue, .mint):
            Color(hex: 0x2A6AB8)
        case (.orange, .mint):
            Color(hex: 0xC07820)
        case (.teal, .mint):
            Color(hex: 0x0E7A5A)
        case (.purple, .mint):
            Color(hex: 0x5A3A9A)
        case (.green, .mint):
            Color(hex: 0x1A7A42)
        case (.red, .mint):
            Color(hex: 0xC03C28)
        case (.gray, .mint):
            Color(hex: 0x7AA898)
        case (.pink, _):
            Color(hex: 0xE040FB)
        case (.blue, _):
            Color(hex: 0x4D8FFF)
        case (.orange, _):
            Color(hex: 0xFF8C42)
        case (.teal, _):
            Color(hex: 0x00D4AA)
        case (.purple, _):
            Color(hex: 0x9D7EFF)
        case (.green, _):
            Color(hex: 0x00E5A0)
        case (.red, _):
            Color(hex: 0xFF4D6D)
        case (.gray, _):
            theme.textDim
        }
    }

    func backgroundColor(in theme: PrototypeTheme) -> Color {
        switch (self, theme) {
        case (.gray, .mint):
            Color(hex: 0xF0F7F4)
        case (.gray, _):
            Color.white.opacity(0.05)
        case (.blue, .mint):
            Color(hex: 0xE8F0FC)
        case (.orange, .mint):
            Color(hex: 0xFFF3E0)
        case (.teal, .mint):
            Color(hex: 0xE0F5EE)
        case (.purple, .mint):
            Color(hex: 0xECE8FF)
        case (.green, .mint):
            Color(hex: 0xE0F5EC)
        case (.red, .mint):
            Color(hex: 0xFFE8E4)
        case (.pink, _):
            Color(red: 224 / 255, green: 64 / 255, blue: 251 / 255, opacity: 0.12)
        case (.blue, _):
            Color(red: 77 / 255, green: 143 / 255, blue: 1, opacity: 0.12)
        case (.orange, _):
            Color(red: 1, green: 140 / 255, blue: 66 / 255, opacity: 0.12)
        case (.teal, _):
            Color(red: 0, green: 212 / 255, blue: 170 / 255, opacity: 0.1)
        case (.purple, _):
            Color(red: 157 / 255, green: 126 / 255, blue: 1, opacity: 0.12)
        case (.green, _):
            Color(red: 0, green: 229 / 255, blue: 160 / 255, opacity: 0.1)
        case (.red, _):
            Color(red: 1, green: 77 / 255, blue: 109 / 255, opacity: 0.12)
        }
    }

    func borderColor(in theme: PrototypeTheme) -> Color {
        switch self {
        case .gray:
            theme.border
        default:
            textColor(in: theme).opacity(0.22)
        }
    }
}

private extension PluginFormat {
    var systemIcon: String {
        switch self {
        case .audioUnit:
            "dial.medium.fill"
        case .vst2:
            "waveform.path.ecg"
        case .vst3:
            "music.note.list"
        case .aax:
            "slider.horizontal.3"
        case .other:
            "questionmark.circle"
        }
    }
}

private extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

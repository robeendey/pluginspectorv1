import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: PluginLibraryViewModel
    @State private var searchText = ""

    private var filteredPlugins: [PluginRecord] {
        let pluginScope: [PluginRecord]

        switch library.selectedFilter {
        case .all:
            pluginScope = library.plugins
        case .format(let format):
            pluginScope = library.plugins.filter { $0.format == format }
        }

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return pluginScope }

        return pluginScope.filter { plugin in
            let haystacks = [
                plugin.name,
                plugin.displayVendor,
                plugin.displayVersion,
                plugin.bundleIdentifier ?? "",
                plugin.relativeLocation,
                plugin.componentSummary,
            ]

            return haystacks.contains { value in
                value.localizedCaseInsensitiveContains(trimmedSearch)
            }
        }
    }

    private var selectedPlugin: PluginRecord? {
        library.selectedPlugin(in: filteredPlugins)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(plugins: library.plugins)
        } content: {
            BrowserView(
                plugins: filteredPlugins,
                selectedPluginID: $library.selectedPluginID,
                searchText: $searchText
            )
        } detail: {
            PluginDetailView(plugin: selectedPlugin, isScanning: library.isScanning, rootURL: library.rootURL)
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            guard library.plugins.isEmpty else { return }
            library.scan()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if library.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    library.scan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var library: PluginLibraryViewModel
    let plugins: [PluginRecord]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SidebarSection(title: "Library") {
                    VStack(spacing: 6) {
                        SidebarSelectionButton(
                            title: "All Plugins",
                            count: library.totalCount(for: .all),
                            systemImage: "square.stack.3d.up.fill",
                            isSelected: library.selectedFilter == .all
                        ) {
                            library.selectedFilter = .all
                        }

                        ForEach(PluginFormat.allCases.filter { $0 != .other }) { format in
                            SidebarSelectionButton(
                                title: format.rawValue,
                                count: library.totalCount(for: .format(format)),
                                systemImage: sidebarIcon(for: format),
                                isSelected: library.selectedFilter == .format(format)
                            ) {
                                library.selectedFilter = .format(format)
                            }
                        }
                    }
                }

                SidebarSection(title: "Scan") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Root Folder", systemImage: "folder")
                                .font(.headline)

                            Text(library.rootURL.path)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        if let lastScannedAt = library.lastScannedAt {
                            Label(lastScannedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                                .foregroundStyle(.secondary)
                        }

                        if let lastScanDuration = library.lastScanDuration {
                            Label("\(lastScanDuration, format: .number.precision(.fractionLength(2)))s scan", systemImage: "speedometer")
                                .foregroundStyle(.secondary)
                        }

                        if let scanError = library.scanError {
                            Text(scanError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                SidebarSection(title: "Notes") {
                    Text("Prototype focuses on browsing, search, and bundle metadata from your installed plugins.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
        .background(.background)
        .navigationTitle("PluginSpector")
    }

    private func sidebarIcon(for format: PluginFormat) -> String {
        switch format {
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

private struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            content
        }
    }
}

private struct SidebarSelectionButton: View {
    let title: String
    let count: Int
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SidebarRow(title: title, count: count, systemImage: systemImage)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(isSelected ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarRow: View {
    let title: String
    let count: Int
    let systemImage: String

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private struct BrowserView: View {
    let plugins: [PluginRecord]
    @Binding var selectedPluginID: PluginRecord.ID?
    @Binding var searchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Search by plugin, vendor, version, path, or component name", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                StatsStrip(plugins: plugins)
            }

            VStack(spacing: 0) {
                PluginHeaderRow()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(plugins) { plugin in
                            Button {
                                selectedPluginID = plugin.id
                            } label: {
                                PluginRow(
                                    plugin: plugin,
                                    isSelected: selectedPluginID == plugin.id
                                )
                            }
                            .buttonStyle(.plain)

                            Divider()
                        }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(20)
    }
}

private struct PluginHeaderRow: View {
    var body: some View {
        HStack(spacing: 16) {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Format")
                .frame(width: 80, alignment: .leading)

            Text("Vendor")
                .frame(width: 150, alignment: .leading)

            Text("Version")
                .frame(width: 90, alignment: .leading)

            Text("Folder")
                .frame(width: 130, alignment: .leading)

            Text("Modified")
                .frame(width: 130, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

private struct PluginRow: View {
    let plugin: PluginRecord
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(plugin.name)
                    .lineLimit(1)

                Text(plugin.relativeLocation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            FormatBadge(format: plugin.format)
                .frame(width: 80, alignment: .leading)

            Text(plugin.displayVendor)
                .frame(width: 150, alignment: .leading)
                .lineLimit(1)

            Text(plugin.displayVersion)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
                .lineLimit(1)

            Text(plugin.rootFolderName)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
                .lineLimit(1)

            Text(formattedDate(plugin.modifiedAt))
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
        .contentShape(Rectangle())
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct StatsStrip: View {
    let plugins: [PluginRecord]

    private var countsByFormat: [(PluginFormat, Int)] {
        PluginFormat.allCases
            .filter { $0 != .other }
            .map { format in
                (format, plugins.filter { $0.format == format }.count)
            }
    }

    var body: some View {
        HStack(spacing: 12) {
            SummaryCard(title: "Visible Plugins", value: "\(plugins.count)", systemImage: "square.stack.3d.up")

            ForEach(countsByFormat, id: \.0.id) { format, count in
                SummaryCard(title: format.shortLabel, value: "\(count)", systemImage: icon(for: format))
            }
        }
    }

    private func icon(for format: PluginFormat) -> String {
        switch format {
        case .audioUnit:
            "dial.medium"
        case .vst2:
            "waveform.path"
        case .vst3:
            "music.note"
        case .aax:
            "slider.horizontal.3"
        case .other:
            "questionmark.circle"
        }
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quinary.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct FormatBadge: View {
    let format: PluginFormat

    var body: some View {
        Text(format.shortLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch format {
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
}

private struct PluginDetailView: View {
    let plugin: PluginRecord?
    let isScanning: Bool
    let rootURL: URL

    var body: some View {
        Group {
            if let plugin {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(for: plugin)
                        detailGrid(for: plugin)
                        actions(for: plugin)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if isScanning {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Scanning installed plugins…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)

                    Text("Choose a Plugin")
                        .font(.title3.weight(.semibold))

                    Text("Select a plugin on the left to inspect its bundle metadata and location.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(plugin?.name ?? "Details")
    }

    @ViewBuilder
    private func header(for plugin: PluginRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(plugin.name)
                        .font(.largeTitle.weight(.semibold))

                    HStack(spacing: 8) {
                        FormatBadge(format: plugin.format)

                        Text(plugin.displayVendor)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let version = plugin.version {
                            Text("Version \(version)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()
            }

            Text(plugin.relativeLocation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func detailGrid(for plugin: PluginRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Bundle Details")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible(minimum: 160), alignment: .leading),
                GridItem(.flexible(minimum: 240), alignment: .leading),
            ], alignment: .leading, spacing: 14) {
                DetailCell(label: "Format", value: plugin.format.rawValue)
                DetailCell(label: "Vendor", value: plugin.displayVendor)
                DetailCell(label: "Version", value: plugin.displayVersion)
                DetailCell(label: "Package Size", value: PluginLibraryScanner.formattedPackageSize(for: plugin.bundleURL))
                DetailCell(label: "Bundle ID", value: plugin.bundleIdentifier ?? "Not reported")
                DetailCell(label: "Executable", value: plugin.executableName ?? "Not reported")
                DetailCell(label: "Minimum macOS", value: plugin.minimumSystemVersion ?? "Not reported")
                DetailCell(label: "Detected Folder", value: plugin.rootFolderName)
                DetailCell(label: "Extension", value: plugin.packageExtension)
                DetailCell(label: "Modified", value: formattedDate(plugin.modifiedAt))
                DetailCell(label: "Audio Components", value: plugin.componentSummary)
                DetailCell(label: "Root Scan Path", value: rootURL.path)
            }
        }
    }

    @ViewBuilder
    private func actions(for plugin: PluginRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Actions")
                .font(.headline)

            HStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([plugin.bundleURL])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }

                Button {
                    NSWorkspace.shared.open(plugin.bundleURL)
                } label: {
                    Label("Open Bundle", systemImage: "arrow.up.right.square")
                }
            }
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct DetailCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quinary.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
    }
}

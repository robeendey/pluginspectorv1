import SwiftUI

@main
struct PluginSpectorApp: App {
    @StateObject private var library = PluginLibraryViewModel()

    var body: some Scene {
        WindowGroup("PluginSpector") {
            ContentView()
                .environmentObject(library)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowResizability(.contentSize)

        Settings {
            VStack(alignment: .leading, spacing: 12) {
                Text("PluginSpector")
                    .font(.title2.bold())

                Text("This prototype scans your installed macOS plugin bundles and gives you a searchable browser for formats, versions, vendors, and bundle details.")
                    .foregroundStyle(.secondary)

                Divider()

                Text("Current root")
                    .font(.headline)

                Text(PluginLibraryViewModel.defaultRoot.path)
                    .textSelection(.enabled)
            }
            .padding(24)
            .frame(width: 460)
        }
    }
}

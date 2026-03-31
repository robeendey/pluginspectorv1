import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first?.makeKeyAndOrderFront(nil)
        }

        sender.activate(ignoringOtherApps: true)
        return true
    }
}

@main
struct PluginSpectorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = PluginLibraryViewModel()

    var body: some Scene {
        WindowGroup("PluginSpector") {
            ContentView()
                .environmentObject(library)
                .frame(minWidth: 1180, minHeight: 760)
        }

        Settings {
            VStack(alignment: .leading, spacing: 12) {
                Text("PluginSpector")
                    .font(.title2.bold())

                Text("This prototype scans your installed macOS plugin bundles and gives you a searchable browser for formats, versions, vendors, and bundle details.")
                    .foregroundStyle(.secondary)

                Divider()

                Text("Active scan locations")
                    .font(.headline)

                Text(PluginLibraryViewModel.defaultRoots.map(\.path).joined(separator: "\n"))
                    .textSelection(.enabled)
            }
            .padding(24)
            .frame(width: 460)
        }
    }
}

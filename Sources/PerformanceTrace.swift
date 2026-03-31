import Foundation

enum PerformanceTrace {
    private static let isEnabled = ProcessInfo.processInfo.environment["PLUGINSPECTOR_PERF"] == "1"

    static func log(_ message: String) {
        guard isEnabled else { return }
        print("[PluginSpectorPerf] \(message)")
    }

    static func measure<T>(_ label: String, _ work: () throws -> T) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let value = try work()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        log("\(label): \(String(format: "%.1f", elapsed))ms")
        return value
    }
}

import AppKit
import Foundation

enum TabFaviconStore {
    private static let manualOverridesLock = NSLock()
    private static var manualOverrides: [String: NSImage] = [:]

    static func getCachedImage(for key: String) -> NSImage? {
        if let manual = withManualOverrides({ $0[key] }) {
            return manual
        }
        return withManager { $0.image(forLookupKey: key) }
    }

    static func clearCache() {
        withManualOverrides { overrides in
            overrides.removeAll()
        }
        NotificationCenter.default.post(name: .faviconCacheUpdated, object: nil)
    }

    static func getFaviconCacheStats() -> (count: Int, domains: [String]) {
        let managerStats = withManager { $0.cacheStats() }
        let manualKeys = withManualOverrides { Array($0.keys) }
        let merged = Array(Set(managerStats.domains).union(manualKeys)).sorted()
        return (merged.count, merged)
    }

    private static func withManualOverrides<T>(_ body: (inout [String: NSImage]) -> T) -> T {
        manualOverridesLock.lock()
        defer { manualOverridesLock.unlock() }
        return body(&manualOverrides)
    }

    private static func withManager<T>(_ body: @MainActor (FaviconManager) -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                body(SumiFaviconSystem.shared.manager)
            }
        }

        var result: T!
        DispatchQueue.main.sync {
            result = body(SumiFaviconSystem.shared.manager)
        }
        return result
    }
}

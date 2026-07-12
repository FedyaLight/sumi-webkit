import Foundation
import WebKit

/// Reads the browser content visible to the extension runtime from one
/// captured runtime value. It owns no lifecycle state and retains no manager.
@available(macOS 15.5, *)
@MainActor
struct ExtensionBrowserContentInventory {
    func tabs(in runtime: ExtensionManagerRuntime) -> [Tab] {
        runtime.allTabs()
            + runtime.allWindowStates().flatMap(\.ephemeralTabs)
    }

    func liveWebViews(
        for tab: Tab,
        in runtime: ExtensionManagerRuntime
    ) -> [WKWebView] {
        guard runtime.browserRuntimeAvailable() else { return [] }

        var candidates: [WKWebView] = []
        if let primaryWindowID = runtime.primaryTrackedWindowId(tab.id),
           let primary = runtime.windowOwnedWebView(tab, primaryWindowID) {
            candidates.append(primary)
        }
        if let untracked = runtime.untrackedOwnedWebView(tab) {
            candidates.append(untracked)
        }
        candidates.append(contentsOf: runtime.trackedWebViews(tab.id))

        var seen = Set<ObjectIdentifier>()
        return candidates.filter { webView in
            seen.insert(ObjectIdentifier(webView)).inserted
        }
    }
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    /// Stateless read capability. Accessing it must never materialize the
    /// runtime publication lifecycle.
    var browserContentInventory: ExtensionBrowserContentInventory { .init() }
}

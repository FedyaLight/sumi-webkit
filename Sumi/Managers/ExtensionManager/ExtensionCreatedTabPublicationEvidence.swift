import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionCreatedTabPublicationBaseEvidence {
    let tab: Tab
    let webView: WKWebView
    let dataStore: WKWebsiteDataStore
    let profileID: UUID
    let controller: WKWebExtensionController
    let generation: UInt64
    let extensionLoadGeneration: UInt64
    let contextBindingGeneration: UInt64
}

@available(macOS 15.5, *)
@MainActor
struct ExtensionCreatedTabPublicationEvidence {
    let base: ExtensionCreatedTabPublicationBaseEvidence
    let adapter: ExtensionTabAdapter
    let stateToken: TabExtensionPrepublicationToken
    let reason: String

    var tab: Tab { base.tab }
    var generation: UInt64 { base.generation }
}

/// Exact adapter materialization/removal for one requested-Tab transaction.
@available(macOS 15.5, *)
@MainActor
final class ExtensionCreatedTabAdapterPublication {
    struct PreparedAdapter {
        let adapter: ExtensionTabAdapter
        let created: Bool
    }

    private let store: ExtensionBrowserAdapterStore
    private let resolution: ExtensionAdapterCatalog

    init(
        store: ExtensionBrowserAdapterStore,
        resolution: ExtensionAdapterCatalog
    ) {
        self.store = store
        self.resolution = resolution
    }

    func prepare(for tab: Tab) -> PreparedAdapter? {
        let previous = store.tabAdapters[tab.id]
        guard let adapter = resolution.stableAdapter(for: tab),
              store.tabAdapters[tab.id] === adapter
        else {
            return nil
        }
        return PreparedAdapter(adapter: adapter, created: previous !== adapter)
    }

    func isCurrent(
        _ adapter: ExtensionTabAdapter,
        for tab: Tab
    ) -> Bool {
        store.tabAdapters[tab.id] === adapter
    }

    func retireExactAdapter(for evidence: ExtensionCreatedTabPublicationEvidence) {
        _ = store.removeTabAdapter(
            for: evidence.tab.id,
            ifIdenticalTo: evidence.adapter
        )
    }

    func retireExactAdapter(
        _ adapter: ExtensionTabAdapter,
        for tab: Tab
    ) {
        _ = store.removeTabAdapter(
            for: tab.id,
            ifIdenticalTo: adapter
        )
    }

    func removeCreatedAdapter(
        _ prepared: PreparedAdapter,
        for tab: Tab
    ) {
        guard prepared.created else { return }
        _ = store.removeTabAdapter(
            for: tab.id,
            ifIdenticalTo: prepared.adapter
        )
    }

    func removeCreatedAdapter(
        _ adapter: ExtensionTabAdapter,
        for tab: Tab,
        ifCreated created: Bool
    ) {
        guard created else { return }
        _ = store.removeTabAdapter(
            for: tab.id,
            ifIdenticalTo: adapter
        )
    }
}

//
//  WindowWebViewRegistry.swift
//  Sumi
//
//  Tracks window-specific WebViews and their reverse owner index.
//

import Foundation
import WebKit

struct TrackedWebViewOwner: Equatable {
    let tabID: UUID
    let windowID: UUID
}

@MainActor
final class WindowWebViewRegistry {
    private var webViewsByTabAndWindow: [UUID: [UUID: WKWebView]] = [:]
    private var webViewOwnersByIdentifier: [ObjectIdentifier: TrackedWebViewOwner] = [:]
    private var recentlyVisibleTabIDsByWindow: [UUID: [UUID]] = [:]

    var isEmpty: Bool {
        webViewsByTabAndWindow.isEmpty
    }

    var totalTrackedWebViewCount: Int {
        webViewsByTabAndWindow.values.reduce(0) { count, windowWebViews in
            count + windowWebViews.count
        }
    }

    func webView(for tabId: UUID, in windowId: UUID) -> WKWebView? {
        webViewsByTabAndWindow[tabId]?[windowId]
    }

    func webView(for owner: TrackedWebViewOwner) -> WKWebView? {
        webView(for: owner.tabID, in: owner.windowID)
    }

    func webViews(for tabId: UUID) -> [WKWebView] {
        guard let windowWebViews = webViewsByTabAndWindow[tabId] else { return [] }
        return Array(windowWebViews.values)
    }

    func windowWebViews(for tabId: UUID) -> [UUID: WKWebView] {
        webViewsByTabAndWindow[tabId] ?? [:]
    }

    func windowIDs(for tabId: UUID) -> [UUID] {
        guard let windowWebViews = webViewsByTabAndWindow[tabId] else { return [] }
        return Array(windowWebViews.keys)
    }

    func trackedWebViews() -> [(TrackedWebViewOwner, WKWebView)] {
        webViewsByTabAndWindow.flatMap { tabId, windowWebViews in
            windowWebViews.map { windowId, webView in
                (TrackedWebViewOwner(tabID: tabId, windowID: windowId), webView)
            }
        }
    }

    func trackedWebViews(for tabId: UUID) -> [(TrackedWebViewOwner, WKWebView)] {
        windowWebViews(for: tabId).map { windowId, webView in
            (TrackedWebViewOwner(tabID: tabId, windowID: windowId), webView)
        }
    }

    func trackedWebViews(in windowId: UUID) -> [(TrackedWebViewOwner, WKWebView)] {
        webViewsByTabAndWindow.compactMap { tabId, windowWebViews in
            guard let webView = windowWebViews[windowId] else { return nil }
            return (TrackedWebViewOwner(tabID: tabId, windowID: windowId), webView)
        }
    }

    func trackedWebView(with identifier: ObjectIdentifier) -> WKWebView? {
        guard let owner = webViewOwnersByIdentifier[identifier],
              let webView = webViewsByTabAndWindow[owner.tabID]?[owner.windowID],
              ObjectIdentifier(webView) == identifier
        else {
            return nil
        }
        return webView
    }

    func indexedOwner(containing webView: WKWebView) -> TrackedWebViewOwner? {
        webViewOwnersByIdentifier[ObjectIdentifier(webView)]
    }

    func isIndexed(_ webView: WKWebView) -> Bool {
        webViewOwnersByIdentifier[ObjectIdentifier(webView)] != nil
    }

    func trackedOwner(containing webView: WKWebView) -> TrackedWebViewOwner? {
        let webViewID = ObjectIdentifier(webView)
        guard let owner = webViewOwnersByIdentifier[webViewID] else { return nil }
        guard let trackedWebView = webViewsByTabAndWindow[owner.tabID]?[owner.windowID],
              trackedWebView === webView
        else {
            webViewOwnersByIdentifier.removeValue(forKey: webViewID)
            assertTrackingConsistency("trackedOwner.stale")
            return nil
        }
        return owner
    }

    func setWebView(_ webView: WKWebView, for owner: TrackedWebViewOwner) {
        if webViewsByTabAndWindow[owner.tabID] == nil {
            webViewsByTabAndWindow[owner.tabID] = [:]
        }
        webViewsByTabAndWindow[owner.tabID]?[owner.windowID] = webView
        webViewOwnersByIdentifier[ObjectIdentifier(webView)] = owner
    }

    func removeWebView(
        owner: TrackedWebViewOwner,
        resolvedWebView: WKWebView?,
        removeRecentVisibility: Bool
    ) {
        webViewsByTabAndWindow[owner.tabID]?[owner.windowID] = nil
        if let resolvedIdentifier = resolvedWebView.map(ObjectIdentifier.init),
           webViewOwnersByIdentifier[resolvedIdentifier] == owner
        {
            webViewOwnersByIdentifier.removeValue(forKey: resolvedIdentifier)
        }
        if removeRecentVisibility {
            removeTabFromVisibilityHistory(owner.tabID, in: owner.windowID)
        }
        cleanupEmptyTrackingBuckets(for: owner.tabID)
    }

    func removeReverseIndex(for webView: WKWebView, ifOwnedBy owner: TrackedWebViewOwner) {
        let identifier = ObjectIdentifier(webView)
        if webViewOwnersByIdentifier[identifier] == owner {
            webViewOwnersByIdentifier.removeValue(forKey: identifier)
        }
    }

    func removeAll() {
        webViewsByTabAndWindow.removeAll()
        webViewOwnersByIdentifier.removeAll()
        recentlyVisibleTabIDsByWindow.removeAll()
    }

    func noteVisibleTabs(_ tabIDs: [UUID], in windowId: UUID) {
        guard tabIDs.isEmpty == false else { return }
        var mru = recentlyVisibleTabIDsByWindow[windowId] ?? []
        for tabId in tabIDs.reversed() {
            mru.removeAll { $0 == tabId }
            mru.insert(tabId, at: 0)
        }
        if mru.count > 32 {
            mru = Array(mru.prefix(32))
        }
        recentlyVisibleTabIDsByWindow[windowId] = mru
    }

    func removeTabFromVisibilityHistory(_ tabId: UUID, in windowId: UUID) {
        guard var mru = recentlyVisibleTabIDsByWindow[windowId] else { return }
        mru.removeAll { $0 == tabId }
        if mru.isEmpty {
            recentlyVisibleTabIDsByWindow.removeValue(forKey: windowId)
        } else {
            recentlyVisibleTabIDsByWindow[windowId] = mru
        }
    }

    func removeVisibilityHistory(for windowId: UUID) {
        recentlyVisibleTabIDsByWindow.removeValue(forKey: windowId)
    }

    func recentVisibilityRank(for owner: TrackedWebViewOwner) -> Int {
        recentlyVisibleTabIDsByWindow[owner.windowID]?
            .firstIndex(of: owner.tabID) ?? Int.max
    }

    private func cleanupEmptyTrackingBuckets(for tabId: UUID) {
        if webViewsByTabAndWindow[tabId]?.isEmpty == true {
            webViewsByTabAndWindow.removeValue(forKey: tabId)
        }
    }

    func assertTrackingConsistency(_ context: StaticString) {
#if DEBUG
        var indexedWebViewIDs: Set<ObjectIdentifier> = []

        for (tabId, windowWebViews) in webViewsByTabAndWindow {
            for (windowId, webView) in windowWebViews {
                let identifier = ObjectIdentifier(webView)
                assert(
                    indexedWebViewIDs.insert(identifier).inserted,
                    "Duplicate tracked WKWebView \(identifier) during \(context)"
                )
                assert(
                    webViewOwnersByIdentifier[identifier] == TrackedWebViewOwner(
                        tabID: tabId,
                        windowID: windowId
                    ),
                    "Missing reverse index for WKWebView \(identifier) during \(context)"
                )
            }
        }

        for (identifier, owner) in webViewOwnersByIdentifier {
            guard let webView = webViewsByTabAndWindow[owner.tabID]?[owner.windowID] else {
                assertionFailure("Stale reverse index \(identifier) during \(context)")
                continue
            }
            assert(
                ObjectIdentifier(webView) == identifier,
                "Reverse index mismatch for WKWebView \(identifier) during \(context)"
            )
        }
#else
        _ = context
#endif
    }
}

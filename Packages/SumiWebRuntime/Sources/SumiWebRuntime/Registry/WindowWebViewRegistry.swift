//
//  WindowWebViewRegistry.swift
//  Sumi
//
//  Tracks window-specific WebViews and their reverse owner index.
//

import Foundation
import WebKit

public struct TrackedWebViewOwner: Equatable {
    public let tabID: UUID
    public let windowID: UUID

    public init(tabID: UUID, windowID: UUID) {
        self.tabID = tabID
        self.windowID = windowID
    }
}

@MainActor
public final class WindowWebViewRegistry {
    public init() {}

    private var webViewsByTabAndWindow: [UUID: [UUID: WKWebView]] = [:]
    private var webViewOwnersByIdentifier: [ObjectIdentifier: TrackedWebViewOwner] = [:]
    private var recentlyVisibleTabIDsByWindow: [UUID: [UUID]] = [:]

    public var isEmpty: Bool {
        webViewsByTabAndWindow.isEmpty
    }

    public var totalTrackedWebViewCount: Int {
        webViewsByTabAndWindow.values.reduce(0) { count, windowWebViews in
            count + windowWebViews.count
        }
    }

    public func webView(for tabId: UUID, in windowId: UUID) -> WKWebView? {
        webViewsByTabAndWindow[tabId]?[windowId]
    }

    public func webView(for owner: TrackedWebViewOwner) -> WKWebView? {
        webView(for: owner.tabID, in: owner.windowID)
    }

    public func webViews(for tabId: UUID) -> [WKWebView] {
        guard let windowWebViews = webViewsByTabAndWindow[tabId] else { return [] }
        return Array(windowWebViews.values)
    }

    public func windowWebViews(for tabId: UUID) -> [UUID: WKWebView] {
        webViewsByTabAndWindow[tabId] ?? [:]
    }

    public func windowIDs(for tabId: UUID) -> [UUID] {
        guard let windowWebViews = webViewsByTabAndWindow[tabId] else { return [] }
        return Array(windowWebViews.keys)
    }

    public func trackedWebViews() -> [(TrackedWebViewOwner, WKWebView)] {
        webViewsByTabAndWindow.flatMap { tabId, windowWebViews in
            windowWebViews.map { windowId, webView in
                (TrackedWebViewOwner(tabID: tabId, windowID: windowId), webView)
            }
        }
    }

    public func trackedWebViews(for tabId: UUID) -> [(TrackedWebViewOwner, WKWebView)] {
        windowWebViews(for: tabId).map { windowId, webView in
            (TrackedWebViewOwner(tabID: tabId, windowID: windowId), webView)
        }
    }

    public func trackedWebViews(in windowId: UUID) -> [(TrackedWebViewOwner, WKWebView)] {
        webViewsByTabAndWindow.compactMap { tabId, windowWebViews in
            guard let webView = windowWebViews[windowId] else { return nil }
            return (TrackedWebViewOwner(tabID: tabId, windowID: windowId), webView)
        }
    }

    public func trackedOwner(with identifier: ObjectIdentifier) -> TrackedWebViewOwner? {
        guard let owner = webViewOwnersByIdentifier[identifier] else { return nil }
        guard let webView = webViewsByTabAndWindow[owner.tabID]?[owner.windowID],
              ObjectIdentifier(webView) == identifier
        else {
            webViewOwnersByIdentifier.removeValue(forKey: identifier)
            assertTrackingConsistency("trackedOwner.identifier.stale")
            return nil
        }
        return owner
    }

    public func trackedWebView(with identifier: ObjectIdentifier) -> WKWebView? {
        guard let owner = trackedOwner(with: identifier),
              let webView = webViewsByTabAndWindow[owner.tabID]?[owner.windowID]
        else {
            return nil
        }
        return webView
    }

    public func indexedOwner(containing webView: WKWebView) -> TrackedWebViewOwner? {
        webViewOwnersByIdentifier[ObjectIdentifier(webView)]
    }

    public func isIndexed(_ webView: WKWebView) -> Bool {
        webViewOwnersByIdentifier[ObjectIdentifier(webView)] != nil
    }

    public func trackedOwner(containing webView: WKWebView) -> TrackedWebViewOwner? {
        trackedOwner(with: ObjectIdentifier(webView))
    }

    public func setWebView(_ webView: WKWebView, for owner: TrackedWebViewOwner) {
        if webViewsByTabAndWindow[owner.tabID] == nil {
            webViewsByTabAndWindow[owner.tabID] = [:]
        }
        webViewsByTabAndWindow[owner.tabID]?[owner.windowID] = webView
        webViewOwnersByIdentifier[ObjectIdentifier(webView)] = owner
    }

    public func removeWebView(
        owner: TrackedWebViewOwner,
        resolvedWebView: WKWebView?,
        removeRecentVisibility: Bool
    ) {
        webViewsByTabAndWindow[owner.tabID]?[owner.windowID] = nil
        if let resolvedIdentifier = resolvedWebView.map(ObjectIdentifier.init),
           webViewOwnersByIdentifier[resolvedIdentifier] == owner {
            webViewOwnersByIdentifier.removeValue(forKey: resolvedIdentifier)
        }
        if removeRecentVisibility {
            removeTabFromVisibilityHistory(owner.tabID, in: owner.windowID)
        }
        cleanupEmptyTrackingBuckets(for: owner.tabID)
    }

    public func removeReverseIndex(for webView: WKWebView, ifOwnedBy owner: TrackedWebViewOwner) {
        let identifier = ObjectIdentifier(webView)
        if webViewOwnersByIdentifier[identifier] == owner {
            webViewOwnersByIdentifier.removeValue(forKey: identifier)
        }
    }

    public func removeAll() {
        webViewsByTabAndWindow.removeAll()
        webViewOwnersByIdentifier.removeAll()
        recentlyVisibleTabIDsByWindow.removeAll()
    }

    public func noteVisibleTabs(_ tabIDs: [UUID], in windowId: UUID) {
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

    public func removeTabFromVisibilityHistory(_ tabId: UUID, in windowId: UUID) {
        guard var mru = recentlyVisibleTabIDsByWindow[windowId] else { return }
        mru.removeAll { $0 == tabId }
        if mru.isEmpty {
            recentlyVisibleTabIDsByWindow.removeValue(forKey: windowId)
        } else {
            recentlyVisibleTabIDsByWindow[windowId] = mru
        }
    }

    public func removeVisibilityHistory(for windowId: UUID) {
        recentlyVisibleTabIDsByWindow.removeValue(forKey: windowId)
    }

    public func recentVisibilityRank(for owner: TrackedWebViewOwner) -> Int {
        recentlyVisibleTabIDsByWindow[owner.windowID]?
            .firstIndex(of: owner.tabID) ?? Int.max
    }

    private func cleanupEmptyTrackingBuckets(for tabId: UUID) {
        if webViewsByTabAndWindow[tabId]?.isEmpty == true {
            webViewsByTabAndWindow.removeValue(forKey: tabId)
        }
    }

    public func assertTrackingConsistency(_ context: StaticString) {
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

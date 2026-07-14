//
//  WebViewTabTeardownOwner.swift
//  SumiWebRuntime
//
//  Owns whole-tab WebView teardown: removing every tracked and tab-owned
//  WebView for a tab, and releasing WebViews when a tab is suspended.
//  Protected WebViews are deferred instead of mutated.
//

import Foundation
import WebKit

public struct WebViewTabTeardownResult: Equatable, Sendable {
    public let discoveredWebViewCount: Int
    public let cleanedWebViewCount: Int
    public let deferredWebViewCount: Int
    public let unscheduledProtectedWebViewCount: Int
    public let blockedWebViewCount: Int

    public init(
        discoveredWebViewCount: Int,
        cleanedWebViewCount: Int,
        deferredWebViewCount: Int,
        unscheduledProtectedWebViewCount: Int,
        blockedWebViewCount: Int = 0
    ) {
        self.discoveredWebViewCount = discoveredWebViewCount
        self.cleanedWebViewCount = cleanedWebViewCount
        self.deferredWebViewCount = deferredWebViewCount
        self.unscheduledProtectedWebViewCount = unscheduledProtectedWebViewCount
        self.blockedWebViewCount = blockedWebViewCount
    }

    public static let none = Self(
        discoveredWebViewCount: 0,
        cleanedWebViewCount: 0,
        deferredWebViewCount: 0,
        unscheduledProtectedWebViewCount: 0,
        blockedWebViewCount: 0
    )

    public var foundWebViews: Bool { discoveredWebViewCount > 0 }
    public var isComplete: Bool {
        deferredWebViewCount == 0
            && unscheduledProtectedWebViewCount == 0
            && blockedWebViewCount == 0
    }
}

@MainActor
public final class WebViewTabTeardownOwner {
    private let webViewSessions: WebViewSessionRepository
    private let mediaProtectionOwner: WebViewMediaProtectionOwner
    private let isWebViewProtectedFromCompositorMutation: @MainActor (WKWebView) -> Bool
    private let enqueueDeferredProtectedCommand:
        @MainActor (DeferredWebViewCommand, WKWebView, String) -> Bool
    private let cleanupUnprotectedTrackedWebView:
        @MainActor (WKWebView, TrackedWebViewOwner, (any WebRuntimeTabHandle)?) -> Bool
    private let cleanupUnprotectedDetachedWebView:
        @MainActor (WKWebView, UUID, (any WebRuntimeTabHandle)?) -> Void
    private let refreshPrimaryTrackedWebView: @MainActor (any WebRuntimeTabHandle) -> Void
    private let removeWebViewFromContainers: @MainActor (WKWebView) -> Void
    private let unregisterTrackedWebViewSlot:
        @MainActor (TrackedWebViewOwner, WKWebView) -> WKWebView?

    public init(
        webViewSessions: WebViewSessionRepository,
        mediaProtectionOwner: WebViewMediaProtectionOwner,
        isWebViewProtectedFromCompositorMutation: @escaping @MainActor (WKWebView) -> Bool,
        enqueueDeferredProtectedCommand:
            @escaping @MainActor (DeferredWebViewCommand, WKWebView, String) -> Bool,
        cleanupUnprotectedTrackedWebView:
            @escaping @MainActor (WKWebView, TrackedWebViewOwner, (any WebRuntimeTabHandle)?) -> Bool,
        cleanupUnprotectedDetachedWebView:
            @escaping @MainActor (WKWebView, UUID, (any WebRuntimeTabHandle)?) -> Void,
        refreshPrimaryTrackedWebView: @escaping @MainActor (any WebRuntimeTabHandle) -> Void,
        removeWebViewFromContainers: @escaping @MainActor (WKWebView) -> Void,
        unregisterTrackedWebViewSlot:
            @escaping @MainActor (TrackedWebViewOwner, WKWebView) -> WKWebView?
    ) {
        self.webViewSessions = webViewSessions
        self.mediaProtectionOwner = mediaProtectionOwner
        self.isWebViewProtectedFromCompositorMutation = isWebViewProtectedFromCompositorMutation
        self.enqueueDeferredProtectedCommand = enqueueDeferredProtectedCommand
        self.cleanupUnprotectedTrackedWebView = cleanupUnprotectedTrackedWebView
        self.cleanupUnprotectedDetachedWebView = cleanupUnprotectedDetachedWebView
        self.refreshPrimaryTrackedWebView = refreshPrimaryTrackedWebView
        self.removeWebViewFromContainers = removeWebViewFromContainers
        self.unregisterTrackedWebViewSlot = unregisterTrackedWebViewSlot
    }

    public func allKnownWebViews(for tab: any WebRuntimeTabHandle) -> [WKWebView] {
        tab.webViewSession.requireBacking(by: webViewSessions)
        return webViewSessions.queries.allKnownWebViews(for: tab.id)
    }

    public func removeAllWebViews(
        for tab: any WebRuntimeTabHandle,
        closeActiveFullscreenMedia: Bool
    ) -> WebViewTabTeardownResult {
        let tabID = tab.id
        tab.webViewSession.requireBacking(by: webViewSessions)
        let snapshot = webViewSessions.queries.snapshot(for: tabID)
        let allWebViews = uniqueWebViews(snapshot.allKnownWebViews)
        guard allWebViews.isEmpty == false else { return .none }

        let trackedEntries = snapshot.windowWebViews.map { windowId, webView in
            (TrackedWebViewOwner(tabID: tabID, windowID: windowId), webView)
        }
        let trackedIDs = Set(trackedEntries.map { ObjectIdentifier($0.1) })
        let detachedWebViews = allWebViews.filter {
            trackedIDs.contains(ObjectIdentifier($0)) == false
        }
        var cleanedWebViewCount = 0
        var deferredWebViewCount = 0
        var unscheduledProtectedWebViewCount = 0
        var blockedWebViewCount = 0
        var closedMediaWebViewIDs: Set<ObjectIdentifier> = []

        func deferCleanup(
            of webView: WKWebView,
            command: DeferredWebViewCommand,
            reason: String
        ) -> Bool {
            guard enqueueDeferredProtectedCommand(command, webView, reason) else {
                return false
            }
            if closeActiveFullscreenMedia,
               closedMediaWebViewIDs.insert(ObjectIdentifier(webView)).inserted {
                mediaProtectionOwner.closeFullscreenMediaIfNeeded(on: webView)
            }
            deferredWebViewCount += 1
            return true
        }

        for (owner, webView) in trackedEntries {
            if isWebViewProtectedFromCompositorMutation(webView) {
                if deferCleanup(
                    of: webView,
                    command: .removeTrackedWebView(
                        webViewID: ObjectIdentifier(webView),
                        tabID: tabID,
                        windowID: owner.windowID
                    ),
                    reason: "removeAllWebViews.tracked"
                ) == false {
                    if isWebViewProtectedFromCompositorMutation(webView) {
                        unscheduledProtectedWebViewCount += 1
                    } else {
                        if cleanupUnprotectedTrackedWebView(webView, owner, tab) {
                            cleanedWebViewCount += 1
                        } else {
                            blockedWebViewCount += 1
                        }
                    }
                }
            } else {
                if cleanupUnprotectedTrackedWebView(webView, owner, tab) {
                    cleanedWebViewCount += 1
                } else {
                    blockedWebViewCount += 1
                }
            }
        }

        for webView in detachedWebViews {
            if isWebViewProtectedFromCompositorMutation(webView) {
                if deferCleanup(
                    of: webView,
                    command: .cleanupTabWebView(
                        webViewID: ObjectIdentifier(webView),
                        tabID: tabID
                    ),
                    reason: "removeAllWebViews.detached"
                ) == false {
                    if isWebViewProtectedFromCompositorMutation(webView) {
                        unscheduledProtectedWebViewCount += 1
                    } else if webViewSessions.placement
                        .removeDetachedWebView(webView, for: tabID) {
                        cleanupUnprotectedDetachedWebView(webView, tabID, tab)
                        cleanedWebViewCount += 1
                    } else {
                        blockedWebViewCount += 1
                    }
                }
            } else if webViewSessions.placement.removeDetachedWebView(
                webView,
                for: tabID
            ) {
                cleanupUnprotectedDetachedWebView(webView, tabID, tab)
                cleanedWebViewCount += 1
            } else {
                blockedWebViewCount += 1
            }
        }

        (tab as? any WebRuntimeTabTeardownLifecycle)?.cancelPendingMainFrameNavigation()
        refreshPrimaryTrackedWebView(tab)
        webViewSessions.assertConsistency("removeAllWebViews")
        assert(
            allWebViews.count
                == cleanedWebViewCount
                    + deferredWebViewCount
                    + unscheduledProtectedWebViewCount
                    + blockedWebViewCount,
            "Every discovered WebView must reach a teardown outcome"
        )
        return WebViewTabTeardownResult(
            discoveredWebViewCount: allWebViews.count,
            cleanedWebViewCount: cleanedWebViewCount,
            deferredWebViewCount: deferredWebViewCount,
            unscheduledProtectedWebViewCount: unscheduledProtectedWebViewCount,
            blockedWebViewCount: blockedWebViewCount
        )
    }

    @discardableResult
    public func suspendWebViews(for tab: any WebRuntimeTabHandle, reason: String) -> Bool {
        let tabID = tab.id
        let liveWebViews = allKnownWebViews(for: tab)
        guard !liveWebViews.isEmpty else { return false }
        guard !liveWebViews
            .contains(where: isWebViewProtectedFromCompositorMutation) else {
            SumiWebRuntimeDiagnostics.protectedWebViewTrace(
                "Skipping suspension cleanup for protected tab=\(tabID.uuidString.prefix(8)) reason=\(reason)."
            )
            return false
        }

        let trackedEntries = webViewSessions.queries.trackedWebViews(for: tabID)
        var cleanedIdentifiers: Set<ObjectIdentifier> = []
        let teardownLifecycle = tab as? any WebRuntimeTabTeardownLifecycle

        func cleanup(_ webView: WKWebView) {
            let identifier = ObjectIdentifier(webView)
            guard cleanedIdentifiers.insert(identifier).inserted else { return }
            teardownLifecycle?.cleanupCloneWebView(webView)
        }

        for (owner, webView) in trackedEntries {
            removeWebViewFromContainers(webView)
            _ = unregisterTrackedWebViewSlot(owner, webView)
            cleanup(webView)
        }

        for webView in liveWebViews {
            cleanup(webView)
        }

        teardownLifecycle?.cancelPendingMainFrameNavigation()
        webViewSessions.placement.clearAll(for: tabID)

        SumiWebRuntimeDiagnostics.protectedWebViewTrace(
            "Suspension released \(cleanedIdentifiers.count) WebView(s) for tab=\(tabID.uuidString.prefix(8)) reason=\(reason)."
        )

        return !cleanedIdentifiers.isEmpty
    }

    private func uniqueWebViews(_ webViews: [WKWebView]) -> [WKWebView] {
        var seen: Set<ObjectIdentifier> = []
        var unique: [WKWebView] = []
        for webView in webViews {
            let identifier = ObjectIdentifier(webView)
            if seen.insert(identifier).inserted {
                unique.append(webView)
            }
        }
        return unique
    }
}

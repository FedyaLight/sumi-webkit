//
//  WebViewTrackingLifecycleOwner.swift
//  Sumi
//
//  Owns tracked WebView slot attachment and detachment mechanics.
//

import Foundation
import WebKit

@MainActor
public final class WebViewTrackingLifecycleOwner {
    public init() {}

    public typealias ContainerRemoval = (WKWebView) -> Void
    public typealias RuntimeObservationInstaller = (WKWebView) -> Void
    public typealias RuntimeObservationUninstaller = (WKWebView) -> Void
    public typealias DeferredCommandPruner = (String) -> Void
    public typealias DisplacedWebViewCleanup = (WKWebView, UUID) -> Void
    public typealias DisplacementValidator = (WKWebView) -> Bool
    public typealias RecentVisibilityRemover = (TrackedWebViewOwner) -> Void

    public func registerTrackedWebView(
        _ webView: WKWebView,
        for owner: TrackedWebViewOwner,
        in webViewSessions: WebViewSessionRepository,
        removeFromContainers: ContainerRemoval,
        installRuntimeObservations: RuntimeObservationInstaller,
        uninstallRuntimeObservationsIfUntracked: RuntimeObservationUninstaller,
        pruneInvalidDeferredCommands: DeferredCommandPruner,
        canDisplaceWebView: DisplacementValidator,
        removeRecentVisibility: RecentVisibilityRemover,
        cleanupDisplacedWebView: DisplacedWebViewCleanup
    ) {
        let result = webViewSessions.placement.registerWindowWebView(
            webView,
            for: owner,
            canDisplaceWebView: canDisplaceWebView
        )

        switch result {
        case .unchanged:
            installRuntimeObservations(webView)
            return
        case .rejected(let rejection):
            preconditionFailure(registrationFailureMessage(for: rejection))
        case .committed(let commit):
            if let vacatedOwner = commit.vacatedOwner {
                removeFromContainers(webView)
                removeRecentVisibility(vacatedOwner)
            }

            if let displacedWebView = commit.displacedTrackedWebView {
                uninstallRuntimeObservationsIfUntracked(displacedWebView)
                cleanupDisplacedWebView(displacedWebView, owner.tabID)
            }
            if let displacedWebView = commit.displacedUntrackedWebView {
                uninstallRuntimeObservationsIfUntracked(displacedWebView)
                cleanupDisplacedWebView(displacedWebView, owner.tabID)
            }
        }

        installRuntimeObservations(webView)
        pruneInvalidDeferredCommands("registerTrackedWebView")
        webViewSessions.assertConsistency("registerTrackedWebView")
    }

    @discardableResult
    public func unregisterTrackedWebViewSlot(
        owner: TrackedWebViewOwner,
        expectedWebView: WKWebView? = nil,
        removeFromSuperview: Bool = false,
        removeRecentVisibility: Bool = true,
        in webViewSessions: WebViewSessionRepository,
        removeFromContainers: ContainerRemoval,
        uninstallRuntimeObservationsIfUntracked: RuntimeObservationUninstaller,
        pruneInvalidDeferredCommands: DeferredCommandPruner,
        forgetRecentVisibility: RecentVisibilityRemover
    ) -> WKWebView? {
        guard let resolvedWebView = webViewSessions.placement
            .removeWindowWebView(
            owner: owner,
            expectedWebView: expectedWebView
            ) else { return nil }

        if removeFromSuperview {
            removeFromContainers(resolvedWebView)
        }

        if removeRecentVisibility {
            forgetRecentVisibility(owner)
        }
        uninstallRuntimeObservationsIfUntracked(resolvedWebView)
        pruneInvalidDeferredCommands("unregisterTrackedWebViewSlot")
        webViewSessions.assertConsistency("unregisterTrackedWebViewSlot")
        return resolvedWebView
    }

    public func replaceTrackedWebViewSet(
        for tabID: UUID,
        expectedGeneration: UInt64,
        webViewsByWindowID: [UUID: WKWebView],
        primaryWindowID: UUID,
        validateCommit: () -> Bool = { true },
        didCommitPlacement: () -> Void = {},
        in webViewSessions: WebViewSessionRepository,
        installRuntimeObservations: RuntimeObservationInstaller,
        uninstallRuntimeObservationsIfUntracked: RuntimeObservationUninstaller,
        pruneInvalidDeferredCommands: DeferredCommandPruner,
        forgetRecentVisibility: RecentVisibilityRemover
    ) -> WebViewWindowSetReplacementResult {
        guard validateCommit() else {
            return .stale(
                currentGeneration: webViewSessions.queries.generation(for: tabID)
            )
        }
        let result = webViewSessions.placement.replaceWindowSet(
            for: tabID,
            expectedGeneration: expectedGeneration,
            webViewsByWindowID: webViewsByWindowID,
            primaryWindowID: primaryWindowID
        )
        guard case .committed(let previous) = result else { return result }
        // No app-owned callback runs between the repository CAS and this model
        // commit. Observation/container side effects happen only afterwards.
        didCommitPlacement()

        previous.windowWebViews.values.forEach(uninstallRuntimeObservationsIfUntracked)
        webViewsByWindowID.values.forEach(installRuntimeObservations)
        let removedWindowIDs = Set(previous.windowWebViews.keys)
            .subtracting(webViewsByWindowID.keys)
        for windowID in removedWindowIDs {
            forgetRecentVisibility(.init(tabID: tabID, windowID: windowID))
        }
        pruneInvalidDeferredCommands("replaceTrackedWebViewSet")
        return result
    }

    @discardableResult
    public func promoteTrackedWebViewToPrimary(
        owner: TrackedWebViewOwner,
        expectedWebView: WKWebView,
        in webViewSessions: WebViewSessionRepository
    ) -> Bool {
        webViewSessions.placement.promoteTrackedWebViewToPrimary(
            owner: owner,
            expectedWebView: expectedWebView
        )
    }

    private func registrationFailureMessage(
        for rejection: WebViewWindowSlotRegistrationRejection
    ) -> String {
        switch rejection {
        case .crossTabCandidate:
            return "A tracked WebView cannot move between tab sessions"
        case .inconsistentIdentity:
            return "Tracked WebView registration encountered inconsistent repository identity"
        case .pendingCleanupCandidate:
            return "A WebView leased for cleanup cannot enter a tracked slot"
        case .protectedCandidate:
            return "A protected WebView cannot move to another tracked slot"
        case .protectedTrackedOccupant:
            return "A protected tracked WebView cannot be displaced by registration"
        case .protectedUntrackedOccupant:
            return "A protected untracked WebView cannot be displaced by registration"
        case .changedDuringPreflight:
            return "Tracked WebView registration state changed during displacement preflight"
        }
    }
}

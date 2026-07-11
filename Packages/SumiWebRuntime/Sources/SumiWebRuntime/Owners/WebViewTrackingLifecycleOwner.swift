//
//  WebViewTrackingLifecycleOwner.swift
//  Sumi
//
//  Owns tracked WebView slot attachment and detachment mechanics.
//

import Foundation
import WebKit

public enum WebViewTrackedRegistrationRejection: Equatable {
    case crossTabCandidate
    case inconsistentIdentity
    case pendingCleanupCandidate
    case protectedCandidate
    case protectedTrackedOccupant
    case protectedUntrackedOccupant
    case changedDuringPreflight
}

public enum WebViewTrackedRegistrationResult: Equatable {
    case unchanged
    case committed
    case rejected(WebViewTrackedRegistrationRejection)
}

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
    public typealias PlacementCommit = @MainActor () -> Void

    @discardableResult
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
        didCommitPlacement: PlacementCommit = {},
        cleanupDisplacedWebView: DisplacedWebViewCleanup
    ) -> WebViewTrackedRegistrationResult {
        let result = webViewSessions.placement.registerWindowWebView(
            webView,
            for: owner,
            canDisplaceWebView: canDisplaceWebView
        )

        switch result {
        case .unchanged:
            installRuntimeObservations(webView)
            return .unchanged
        case .rejected(let rejection):
            return .rejected(Self.registrationRejection(from: rejection))
        case .committed(let commit):
            // The repository CAS is now canonical. Settle app-level evidence
            // before observation and cleanup callbacks can run.
            didCommitPlacement()
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
        return .committed
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

    private static func registrationRejection(
        from rejection: WebViewWindowSlotRegistrationRejection
    ) -> WebViewTrackedRegistrationRejection {
        switch rejection {
        case .crossTabCandidate:
            return .crossTabCandidate
        case .inconsistentIdentity:
            return .inconsistentIdentity
        case .pendingCleanupCandidate:
            return .pendingCleanupCandidate
        case .protectedCandidate:
            return .protectedCandidate
        case .protectedTrackedOccupant:
            return .protectedTrackedOccupant
        case .protectedUntrackedOccupant:
            return .protectedUntrackedOccupant
        case .changedDuringPreflight:
            return .changedDuringPreflight
        }
    }
}

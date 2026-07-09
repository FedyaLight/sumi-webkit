//
//  WebRuntimeBoundaryProtocols.swift
//  SumiWebRuntime
//
//  Boundary protocols so coordinator contexts can talk about tabs/windows
//  without type-edging concrete app-target Tab / BrowserWindowState.
//

import Foundation
import WebKit

/// Tab surface visible to WebRuntime owners (teardown, broadcast, planning).
///
/// App-target `Tab` conforms; package code should depend only on this handle
/// plus `TabWebViewSession` / registry types already in SumiWebRuntime.
@MainActor
public protocol WebRuntimeTabHandle: AnyObject {
    var id: UUID { get }

    /// Pre-runtime / tab-local session notes used by session-store promote paths.
    var localSession: TabWebViewSession { get }

    /// Whether visible preparation should materialize a primary WebView for this tab.
    var requiresPrimaryWebView: Bool { get }

    /// Current navigation URL (warmup gating, reload target fallback, rebuild write-back).
    var url: URL { get set }

    /// Incognito / ephemeral tabs skip initial-document warmup.
    var isEphemeral: Bool { get }

    /// Profile used for initial-document extension-context warmup
    /// (`resolveProfile()?.id ?? stored profileId` on the app Tab).
    var resolvedProfileId: UUID? { get }
}

/// Window surface visible to WebRuntime owners (compositor refresh is UUID-keyed outside).
@MainActor
public protocol WebRuntimeWindowHandle: AnyObject {
    var id: UUID { get }

    /// Incognito ephemeral tabs hosted by this window (empty for normal windows).
    var ephemeralTabHandles: [any WebRuntimeTabHandle] { get }
}

/// Resolves a tab handle by id (regular / pinned / ephemeral as wired by the host).
@MainActor
public protocol WebRuntimeTabResolving {
    func resolveWebRuntimeTab(_ id: UUID) -> (any WebRuntimeTabHandle)?
}

/// Promoted WebView host surface (Glance / compositor handoff).
///
/// App-target `SumiWebViewContainerView` conforms; the container stays in the
/// app target. `WebViewCompositorHandoffState` stores hosts only as this protocol.
@MainActor
public protocol WebRuntimePromotedHost: AnyObject {
    var tabID: UUID { get }
    var webView: WKWebView { get }
    func prepareForSuperviewTransferPreservingDisplayedContent()
}

/// Normal-tab WebView construction surface used by assignment/rebuild.
///
/// App-target `Tab` conforms. Kept separate from `WebRuntimeTabHandle` so
/// handle consumers are not forced into materialization / profile resolution.
@MainActor
public protocol WebRuntimeTabMaterializing: AnyObject {
    /// Creates a fully configured normal-tab WebView (primary or clone).
    /// Matches app `Tab.makeNormalTabWebView(reason:prepareConfiguration:)`.
    func makeNormalTabWebView(
        reason: String,
        prepareConfiguration: ((WKWebViewConfiguration) -> Void)?
    ) -> WKWebView?
}

extension WebRuntimeTabMaterializing {
    /// Convenience matching the app Tab default (`prepareConfiguration: nil`).
    public func makeNormalTabWebView(reason: String) -> WKWebView? {
        makeNormalTabWebView(reason: reason, prepareConfiguration: nil)
    }
}

/// Ownership-mirror mutations used by assignment/rebuild (assign / clear / identity).
///
/// App-target `Tab` conforms. Only the AssignmentRebuild ownership-mirror
/// surface — not full session teardown or clone cleanup.
@MainActor
public protocol WebRuntimeTabOwnershipMutating: AnyObject {
    func assignWebViewToWindow(_ webView: WKWebView, windowId: UUID)
    func clearCurrentWebViewOwnership()
    func clearAllWebViewOwnership()
    func currentWebViewIsIdentical(to webView: WKWebView) -> Bool
}

/// Tab-owned WebView teardown surface used by tab/window cleanup owners.
///
/// App-target `Tab` conforms. Kept separate from `WebRuntimeTabHandle` and
/// from assignment/rebuild materializing / ownership-mirror protocols.
@MainActor
public protocol WebRuntimeTabTeardownLifecycle: AnyObject {
    func cleanupCloneWebView(_ webView: WKWebView)
    func cancelPendingMainFrameNavigation()
    func clearAllWebViewOwnership()
}

/// Site reload-policy flag refresh used after live WebView rebuild.
///
/// App-target `Tab` conforms. Kept separate from `WebRuntimeTabHandle` so
/// handle consumers are not forced into reload-policy bookkeeping.
@MainActor
public protocol WebRuntimeTabSiteReloadPolicyNotifying: AnyObject {
    func updateSafariContentBlockerReloadRequirementForCurrentSite()
    func updateProtectionReloadRequirementForCurrentSite()
    func updateAutoplayReloadRequirementForCurrentSite()
}

/// Main-frame load / extension-registration surface used by assignment/rebuild.
///
/// App-target `Tab` conforms. Initial-document handoff orchestration stays an
/// app Runtime callback; this protocol covers the Tab-owned load primitives.
@MainActor
public protocol WebRuntimeTabMainFrameLoading: AnyObject {
    func performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
        on webView: WKWebView,
        waitForContentBlockingAssets: Bool,
        performLoad: @escaping @MainActor @Sendable (WKWebView) -> Void
    )

    func loadURL(
        _ url: URL,
        resolvedWebView: @escaping @MainActor @Sendable () -> WKWebView?,
        reason: String
    )

    func registerTabWithExtensionRuntimeIfNeeded(reason: String)
}

/// Mute snapshot used when applying audio state to newly created clone WebViews.
///
/// App-target `Tab` conforms (`audioState.isMuted`). Kept separate from
/// `WebRuntimeTabHandle` so handle consumers are not forced into media state.
@MainActor
public protocol WebRuntimeTabAudioMuteSnapshotting: AnyObject {
    var isAudioMuted: Bool { get }
}

/// Visible-preparation bookkeeping used by window cleanup.
///
/// Package `VisibleWebViewRuntimeOwner` conforms. Window cleanup depends on
/// this surface only — not the full visible-preparation owner.
@MainActor
public protocol WebRuntimeVisiblePreparationControlling: AnyObject {
    func cancelScheduledPreparation(for windowId: UUID)
    func resetWindowRegistrations()
}

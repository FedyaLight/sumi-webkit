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
/// plus the WebView session handle already in SumiWebRuntime.
@MainActor
public protocol WebRuntimeTabHandle: AnyObject {
    var id: UUID { get }

    /// Stable ownership handle backed by the process WebView repository once
    /// browser runtime composition is attached.
    var webViewSession: WebViewSessionHandle { get }

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
    func makeNormalTabWebView(reason: String) -> WKWebView?
}

/// Tab-owned WebView teardown surface used by tab/window cleanup owners.
///
/// App-target `Tab` conforms. Kept separate from `WebRuntimeTabHandle` and
/// from assignment/rebuild materializing / ownership-mirror protocols.
@MainActor
public protocol WebRuntimeTabTeardownLifecycle: AnyObject {
    func cleanupCloneWebView(_ webView: WKWebView)
    func cancelPendingMainFrameNavigation()
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

/// Mute snapshot used when applying audio state to newly created clone WebViews.
///
/// App-target `Tab` conforms (`audioState.isMuted`). Kept separate from
/// `WebRuntimeTabHandle` so handle consumers are not forced into media state.
@MainActor
public protocol WebRuntimeTabAudioMuteSnapshotting: AnyObject {
    var isAudioMuted: Bool { get }
}

/// Complete tab capability required by assignment/rebuild orchestration.
/// Ownership mutations themselves go through `webViewSession`; this composite
/// keeps concrete app-target `Tab` out of SumiWebRuntime.
@MainActor
public protocol WebRuntimeRebuildableTab:
    WebRuntimeTabHandle,
    WebRuntimeTabMaterializing,
    WebRuntimeTabTeardownLifecycle,
    WebRuntimeTabSiteReloadPolicyNotifying,
    WebRuntimeTabAudioMuteSnapshotting
{}

/// Visible-preparation bookkeeping used by window cleanup.
///
/// Package `VisibleWebViewRuntimeOwner` conforms. Window cleanup depends on
/// this surface only — not the full visible-preparation owner.
@MainActor
public protocol WebRuntimeVisiblePreparationControlling: AnyObject {
    func cancelScheduledPreparation(for windowId: UUID)
    func resetWindowRegistrations()
}

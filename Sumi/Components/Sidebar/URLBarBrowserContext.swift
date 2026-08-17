import AppKit
import Combine
import SumiDomain
import SwiftUI
import WebKit

@MainActor
struct URLBarExtensionActionContext {
    let moduleEnabledChanges: AnyPublisher<Bool, Never>
    let toolbarPresentationSnapshot:
        (UUID?) -> BrowserExtensionToolbarPresentationSnapshot
    let toolbarPresentationSnapshots:
        (UUID?) -> AnyPublisher<BrowserExtensionToolbarPresentationSnapshot, Never>
    /// `(records, orderedIDs, windowState, profileID)`. The ordered ids come
    /// from the observed presentation snapshot so a pin, unpin, or reorder is a
    /// SwiftUI input change rather than an invisible read inside the surface.
    let compactStrip:
        ([BrowserExtensionToolbarDisplayRecord], [String], BrowserWindowState, UUID?) -> AnyView
    let hubTiles:
        ([BrowserExtensionToolbarDisplayRecord], [String], BrowserWindowState, UUID?) -> AnyView
    let ensureActionMetadataLoadedIfNeeded: () -> Void
}

@MainActor
struct URLBarZoomContext {
    let manager: ZoomManager
    let stateRevision: Int
    let resetCurrentTab: (BrowserWindowState) -> Void
    let zoomOutCurrentTab: (BrowserWindowState) -> Void
    let zoomInCurrentTab: (BrowserWindowState) -> Void
}

@MainActor
struct URLBarPermissionContext {
    let coordinator: any SumiPermissionCoordinating
    let runtimeController: any SumiRuntimePermissionControlling
    let popupStore: SumiBlockedPopupStore
    let externalSchemeStore: SumiExternalSchemeSessionStore
    let indicatorEventStore: SumiPermissionIndicatorEventStore
    let systemPermissionService: any SumiSystemPermissionService
    let externalAppResolver: any SumiExternalAppResolving
    let siteActivityRevision: () -> Int
    let updateIndicator: (SumiPermissionIndicatorViewModel, Tab, BrowserWindowState) -> Void
    let updatePrompt: (SumiPermissionPromptPresenter, Tab, BrowserWindowState) -> Void
}

@MainActor
struct URLBarHubBrowserContext {
    let pageActionOwner: URLBarHubPageActionOwner
    let bookmarkManager: SumiBookmarkManager
    let bookmarkPresentationRequest: SumiBookmarkEditorPresentationRequest?
    let extensionActions: URLBarExtensionActionContext
    let permission: URLBarPermissionContext
    let permissionDependencies: SumiCurrentSitePermissionsViewModel.LoadDependencies
    let protectionCoordinator: SumiProtectionCoordinator
    let adblockZapperStore: SumiAdblockZapperStore
    let cleanupService: any SumiWebsiteDataCleanupServicing
    let profileWebsiteDataMutationService: any SumiProfileWebsiteDataMutating
    let siteDataPolicyStore: any BrowserSiteDataPolicyStoring
    let siteDataPolicyEnforcementService: any BrowserSiteDataPolicyEnforcing
    let faviconService: any BrowserFaviconServicing
    let faviconImageReader: any BrowserFaviconImageReading
    let protectionSettingsChanges: AnyPublisher<Void, Never>
    let protectionSitePolicyChanges: AnyPublisher<Void, Never>
    let blockedPopupChanges: AnyPublisher<Void, Never>
    let externalSchemeChanges: AnyPublisher<Void, Never>
    let indicatorEventChanges: AnyPublisher<Void, Never>
    let permissionSiteActivityChanges: AnyPublisher<Void, Never>
    let boostChanges: AnyPublisher<Void, Never>
    let profiles: () -> [Profile]
    let currentProfile: () -> Profile?
    let webView: (Tab, BrowserWindowState) -> WKWebView?
    let siteControlsSnapshot: (URL?, Profile?, Bool, Bool) -> SiteControlsSnapshot
    let openExtensionSettings: (BrowserWindowState) -> Void
    let openSiteSettings: (Tab?, BrowserWindowState) -> Void
    let reloadAfterProtectionPolicyChange: (Tab, BrowserWindowState) -> Bool
    let setSafariContentBlockerSiteOverride: (SumiSafariContentBlockerSiteOverride, URL) -> Void
    let canBoost: (URL?) -> Bool
    let changedBoosts: (URL?, UUID?) -> [SumiBoost]
    let activeBoostId: (URL?, UUID?) -> UUID?
    let createBoostAndOpenEditor: (Tab, Profile?, BrowserWindowState) throws -> Void
    let toggleActiveBoost: (SumiBoost, Bool) -> Void
    let presentBoostEditor: (SumiBoost, Tab, Profile?, BrowserWindowState) -> Void
    let presentSharingServicePicker: ([Any], SidebarTransientPresentationSource) -> Void
    let clearBookmarkEditorPresentationRequest: (SumiBookmarkEditorPresentationRequest) -> Void
}

@MainActor
struct URLBarBrowserContext {
    let zoom: URLBarZoomContext
    let permission: URLBarPermissionContext
    let hub: URLBarHubBrowserContext
    let hubPopoverPresenter: URLBarHubPopoverPresenter
    let bookmarkEditorPresentationRequest: SumiBookmarkEditorPresentationRequest?
    let activePage: (BrowserWindowState) -> ActivePageResolution?
    let webView: (Tab, BrowserWindowState) -> WKWebView?
    let profiles: () -> [Profile]
    let currentProfile: () -> Profile?
    let siteControlsSnapshot: (URL?, Profile?, Bool, Bool) -> SiteControlsSnapshot
    let focusCommandPalette: (BrowserWindowState, String, Bool) -> Void
    let reloadPage: (ActivePageResolution, String) -> Bool
    let closeURLBarHubPopover: (BrowserWindowState) -> Void
    let presentURLBarHubPopover: (BrowserWindowState) -> Void
    let toggleURLBarHubPopover: (BrowserWindowState) -> Void
    let isURLBarHubPopoverPresented: (BrowserWindowState) -> Bool
    let copyURLToClipboard: (String, BrowserWindowState) -> Void
    let extensionActions: URLBarExtensionActionContext
}

import AppKit
import Combine
import SwiftUI
import WebKit

@MainActor
struct URLBarExtensionActionContext {
    let orderedPinnedToolbarSlotCount: ([InstalledExtension]) -> Int
    let compactStrip: ([InstalledExtension], BrowserWindowState) -> AnyView
    let hubTiles: ([InstalledExtension], BrowserWindowState) -> AnyView
    let ensureActionSurfaceMetadataLoadedIfNeeded: () -> Void
    let isPinnedToToolbar: (String) -> Bool
    let sumiScriptsManagerEnabled: () -> Bool
}

@MainActor
struct URLBarZoomContext {
    let manager: ZoomManager
    let stateRevision: Int
    let popoverRequest: ZoomPopoverRequest?
    let resetCurrentTab: (BrowserWindowState) -> Void
    let zoomOutCurrentTab: (BrowserWindowState) -> Void
    let zoomInCurrentTab: (BrowserWindowState) -> Void
    let requestPopover: (Tab, BrowserWindowState, ZoomPopoverSource) -> Void
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
    let bookmarkManager: SumiBookmarkManager
    let bookmarkPresentationRequest: SumiBookmarkEditorPresentationRequest?
    let extensionSurfaceStore: BrowserExtensionSurfaceStore
    let extensionActions: URLBarExtensionActionContext
    let permission: URLBarPermissionContext
    let permissionDependencies: SumiCurrentSitePermissionsViewModel.LoadDependencies
    let protectionCoordinator: SumiProtectionCoordinator
    let cleanupService: any SumiWebsiteDataCleanupServicing
    let siteDataPolicyStore: any BrowserSiteDataPolicyStoring
    let siteDataPolicyEnforcementService: any BrowserSiteDataPolicyEnforcing
    let faviconService: any BrowserFaviconServicing
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
    let currentTab: (BrowserWindowState) -> Tab?
    let tabForID: (UUID) -> Tab?
    let webView: (Tab, BrowserWindowState) -> WKWebView?
    let profiles: () -> [Profile]
    let currentProfile: () -> Profile?
    let siteControlsSnapshot: (URL?, Profile?, Bool, Bool) -> SiteControlsSnapshot
    let focusFloatingBar: (BrowserWindowState, String, Bool) -> Void
    let closeURLBarHubPopover: (BrowserWindowState) -> Void
    let presentURLBarHubPopover: (BrowserWindowState) -> Void
    let toggleURLBarHubPopover: (BrowserWindowState) -> Void
    let isURLBarHubPopoverPresented: (BrowserWindowState) -> Bool
    let presentToast: (BrowserToast, BrowserWindowState) -> Void
    let extensionActions: URLBarExtensionActionContext
}

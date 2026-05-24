//
//  ChromeMV3WebViewSurfaceInventory.swift
//  Sumi
//
//  Static mapping from real Sumi WebView construction sites to Chrome MV3
//  surface classifications. This table is diagnostic data only.
//

import Foundation

struct ChromeMV3WebViewSurfaceMapping: Codable, Equatable, Sendable {
    var siteID: String
    var sourcePath: String
    var surface: ChromeMV3WebViewSurface
    var futureEligibility: ChromeMV3WebViewEligibilityStatus
    var controllerAttachmentAllowedNow: Bool
    var futureAttachmentRequiresEnabledModule: Bool
    var futureAttachmentRequiresNormalBrowsingPromotion: Bool
    var futureAttachmentRequiresExtensionUIHost: Bool
    var risksAndNotes: [String]
}

struct ChromeMV3WebViewSurfaceMappingDiagnostic: Codable, Equatable, Sendable {
    var siteID: String
    var sourcePath: String
    var surface: ChromeMV3WebViewSurface
    var futureEligibility: ChromeMV3WebViewEligibilityStatus
    var currentEligibility: ChromeMV3WebViewEligibility
    var controllerAttachmentAllowedNow: Bool
    var futureAttachmentRequiresEnabledModule: Bool
    var futureAttachmentRequiresNormalBrowsingPromotion: Bool
    var futureAttachmentRequiresExtensionUIHost: Bool
    var risksAndNotes: [String]
    var warnings: [String]
}

enum ChromeMV3WebViewSurfaceInventory {
    static let currentSumiMappings: [ChromeMV3WebViewSurfaceMapping] = [
        ChromeMV3WebViewSurfaceMapping(
            siteID: "tab.normal.primary",
            sourcePath: "Sumi/Models/Tab/Tab+WebViewRuntime.swift:makeNormalTabWebView",
            surface: .normalTab,
            futureEligibility: .futureEligible,
            controllerAttachmentAllowedNow: false,
            futureAttachmentRequiresEnabledModule: true,
            futureAttachmentRequiresNormalBrowsingPromotion: false,
            futureAttachmentRequiresExtensionUIHost: false,
            risksAndNotes: [
                "Primary normal-tab construction uses BrowserConfiguration.normalTabWebViewConfiguration.",
                "Future attachment must remain profile-scoped and pass runtime preflight first.",
            ]
        ),
        ChromeMV3WebViewSurfaceMapping(
            siteID: "tab.normal.clone",
            sourcePath: "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift:createCloneWebView",
            surface: .normalTab,
            futureEligibility: .futureEligible,
            controllerAttachmentAllowedNow: false,
            futureAttachmentRequiresEnabledModule: true,
            futureAttachmentRequiresNormalBrowsingPromotion: false,
            futureAttachmentRequiresExtensionUIHost: false,
            risksAndNotes: [
                "Clone WebViews are constructed through Tab.makeNormalTabWebView.",
                "Future attachment must match the profile controller used by the primary normal tab.",
            ]
        ),
        ChromeMV3WebViewSurfaceMapping(
            siteID: "shortcut.live.normalBrowsing",
            sourcePath: "Sumi/Managers/TabManager/TabManager+LauncherOwnership.swift:activateShortcutPin",
            surface: .pinnedEssentialsLiveNormalBrowsing,
            futureEligibility: .futureEligible,
            controllerAttachmentAllowedNow: false,
            futureAttachmentRequiresEnabledModule: true,
            futureAttachmentRequiresNormalBrowsingPromotion: false,
            futureAttachmentRequiresExtensionUIHost: false,
            risksAndNotes: [
                "Pinned and Essentials live instances are Tabs and materialize through the normal Tab WebView path.",
                "Launcher identity alone is not a browsing surface; only the live Tab runtime maps here.",
            ]
        ),
        ChromeMV3WebViewSurfaceMapping(
            siteID: "shortcut.launcher.metadata",
            sourcePath: "Sumi/Models/Tab/ShortcutPin.swift and Navigation/Sidebar/SpacesSideBarView.swift",
            surface: .pinnedEssentialsLauncherMetadata,
            futureEligibility: .neverEligible,
            controllerAttachmentAllowedNow: false,
            futureAttachmentRequiresEnabledModule: false,
            futureAttachmentRequiresNormalBrowsingPromotion: false,
            futureAttachmentRequiresExtensionUIHost: false,
            risksAndNotes: [
                "ShortcutPin and sidebar snapshots are launcher metadata, not WebViews.",
                "No runtime object should be associated with launcher-only state.",
            ]
        ),
        ChromeMV3WebViewSurfaceMapping(
            siteID: "glance.preview.tab",
            sourcePath: "Sumi/Managers/GlanceManager/GlanceManager.swift:beginSession",
            surface: .peekGlancePreview,
            futureEligibility: .notEligible,
            controllerAttachmentAllowedNow: false,
            futureAttachmentRequiresEnabledModule: true,
            futureAttachmentRequiresNormalBrowsingPromotion: true,
            futureAttachmentRequiresExtensionUIHost: false,
            risksAndNotes: [
                "Glance preview creates a transient Tab and calls ensureWebView.",
                "Preview semantics must be promoted or reclassified before future extension attachment.",
            ]
        ),
        ChromeMV3WebViewSurfaceMapping(
            siteID: "miniWindow.oauth.webView",
            sourcePath: "Sumi/Components/MiniWindow/MiniWindowWebView.swift:makeNSView",
            surface: .miniWindow,
            futureEligibility: .notEligible,
            controllerAttachmentAllowedNow: false,
            futureAttachmentRequiresEnabledModule: true,
            futureAttachmentRequiresNormalBrowsingPromotion: true,
            futureAttachmentRequiresExtensionUIHost: false,
            risksAndNotes: [
                "Mini windows use BrowserConfiguration.auxiliaryWebViewConfiguration with the miniWindow surface.",
                "OAuth/auth auxiliary semantics are separate from normal-tab browsing.",
            ]
        ),
        ChromeMV3WebViewSurfaceMapping(
            siteID: "miniWindow.popup.inlineLoad",
            sourcePath: "Sumi/Components/MiniWindow/MiniWindowWebView.swift:createWebViewWith",
            surface: .helperWebView,
            futureEligibility: .neverEligible,
            controllerAttachmentAllowedNow: false,
            futureAttachmentRequiresEnabledModule: false,
            futureAttachmentRequiresNormalBrowsingPromotion: false,
            futureAttachmentRequiresExtensionUIHost: false,
            risksAndNotes: [
                "Mini-window popup requests are loaded into the existing auxiliary WebView.",
                "This helper path should not become an extension host.",
            ]
        ),
        ChromeMV3WebViewSurfaceMapping(
            siteID: "favicon.temporaryDownload",
            sourcePath: "Sumi/Favicons/DDG/Model/FaviconDownloader.swift:createTemporaryWebView",
            surface: .faviconDownload,
            futureEligibility: .neverEligible,
            controllerAttachmentAllowedNow: false,
            futureAttachmentRequiresEnabledModule: false,
            futureAttachmentRequiresNormalBrowsingPromotion: false,
            futureAttachmentRequiresExtensionUIHost: false,
            risksAndNotes: [
                "Temporary favicon downloads use the faviconDownload auxiliary surface.",
                "JavaScript is disabled for this helper configuration.",
            ]
        ),
        ChromeMV3WebViewSurfaceMapping(
            siteID: "download.retry.currentTab",
            sourcePath: "Sumi/Managers/DownloadManager/DownloadManager.swift:retryWebView",
            surface: .downloadHelper,
            futureEligibility: .neverEligible,
            controllerAttachmentAllowedNow: false,
            futureAttachmentRequiresEnabledModule: false,
            futureAttachmentRequiresNormalBrowsingPromotion: false,
            futureAttachmentRequiresExtensionUIHost: false,
            risksAndNotes: [
                "Download retry borrows the current page WebView to restart a download.",
                "Download helper behavior must not create a separate extension host.",
            ]
        ),
        ChromeMV3WebViewSurfaceMapping(
            siteID: "contextMenu.download",
            sourcePath: "Sumi/Utils/WebKit/SumiWebPageMenuController.swift:startDownload",
            surface: .downloadHelper,
            futureEligibility: .neverEligible,
            controllerAttachmentAllowedNow: false,
            futureAttachmentRequiresEnabledModule: false,
            futureAttachmentRequiresNormalBrowsingPromotion: false,
            futureAttachmentRequiresExtensionUIHost: false,
            risksAndNotes: [
                "Context-menu downloads use the owning page WebView only to start the transfer.",
                "This is not a page-hosting surface for extension runtime.",
            ]
        ),
        ChromeMV3WebViewSurfaceMapping(
            siteID: "extension.options.window",
            sourcePath: "Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift:presentOptionsPageWindow",
            surface: .extensionOwnedOptionsPage,
            futureEligibility: .futureEligibleThroughExtensionUIHostOnly,
            controllerAttachmentAllowedNow: false,
            futureAttachmentRequiresEnabledModule: true,
            futureAttachmentRequiresNormalBrowsingPromotion: false,
            futureAttachmentRequiresExtensionUIHost: true,
            risksAndNotes: [
                "Existing reusable engine code has an options-page auxiliary host.",
                "Chrome MV3 inventory does not create or display options pages.",
            ]
        ),
        ChromeMV3WebViewSurfaceMapping(
            siteID: "extension.action.popup",
            sourcePath: "Sumi/Managers/ExtensionManager/ExtensionManager+ControllerDelegate.swift:presentActionPopup",
            surface: .extensionOwnedPopup,
            futureEligibility: .futureEligibleThroughExtensionUIHostOnly,
            controllerAttachmentAllowedNow: false,
            futureAttachmentRequiresEnabledModule: true,
            futureAttachmentRequiresNormalBrowsingPromotion: false,
            futureAttachmentRequiresExtensionUIHost: true,
            risksAndNotes: [
                "Action popups are extension-owned UI, not normal browsing tabs.",
                "Chrome MV3 inventory only records future eligibility.",
            ]
        ),
        ChromeMV3WebViewSurfaceMapping(
            siteID: "tab.webKitPopup.delegate",
            sourcePath: "Sumi/Models/Tab/Tab+UIDelegate.swift:createWebViewWith and Sumi/Models/Tab/Navigation/SumiPopupHandlingNavigationResponder.swift:createChildWebView",
            surface: .webKitCreatedPopupOrNewWindow,
            futureEligibility: .eligibleAfterPromotionAndReevaluation,
            controllerAttachmentAllowedNow: false,
            futureAttachmentRequiresEnabledModule: true,
            futureAttachmentRequiresNormalBrowsingPromotion: true,
            futureAttachmentRequiresExtensionUIHost: false,
            risksAndNotes: [
                "WebKit-created popup configurations are converted to child popup tabs.",
                "Future extension attachment must wait until Sumi promotes or reclassifies the surface.",
            ]
        ),
        ChromeMV3WebViewSurfaceMapping(
            siteID: "browserConfig.auxiliary.glance",
            sourcePath: "Sumi/Models/BrowserConfig/BrowserConfig.swift:BrowserConfigurationAuxiliarySurface.glance",
            surface: .peekGlancePreview,
            futureEligibility: .notEligible,
            controllerAttachmentAllowedNow: false,
            futureAttachmentRequiresEnabledModule: true,
            futureAttachmentRequiresNormalBrowsingPromotion: true,
            futureAttachmentRequiresExtensionUIHost: false,
            risksAndNotes: [
                "The auxiliary enum still contains a glance case for lightweight preview configuration.",
                "Current Glance preview tabs use the normal Tab path and remain ineligible by default.",
            ]
        ),
        ChromeMV3WebViewSurfaceMapping(
            siteID: "browserConfig.auxiliary.extensionOptions",
            sourcePath: "Sumi/Models/BrowserConfig/BrowserConfig.swift:BrowserConfigurationAuxiliarySurface.extensionOptions",
            surface: .extensionOwnedOptionsPage,
            futureEligibility: .futureEligibleThroughExtensionUIHostOnly,
            controllerAttachmentAllowedNow: false,
            futureAttachmentRequiresEnabledModule: true,
            futureAttachmentRequiresNormalBrowsingPromotion: false,
            futureAttachmentRequiresExtensionUIHost: true,
            risksAndNotes: [
                "The auxiliary enum has a dedicated extension options case.",
                "Inventory diagnostics do not request or construct an options host.",
            ]
        ),
        ChromeMV3WebViewSurfaceMapping(
            siteID: "browserConfig.auxiliary.faviconDownload",
            sourcePath: "Sumi/Models/BrowserConfig/BrowserConfig.swift:BrowserConfigurationAuxiliarySurface.faviconDownload",
            surface: .faviconDownload,
            futureEligibility: .neverEligible,
            controllerAttachmentAllowedNow: false,
            futureAttachmentRequiresEnabledModule: false,
            futureAttachmentRequiresNormalBrowsingPromotion: false,
            futureAttachmentRequiresExtensionUIHost: false,
            risksAndNotes: [
                "The auxiliary enum has a favicon download case with JavaScript disabled.",
            ]
        ),
        ChromeMV3WebViewSurfaceMapping(
            siteID: "browserConfig.auxiliary.miniWindow",
            sourcePath: "Sumi/Models/BrowserConfig/BrowserConfig.swift:BrowserConfigurationAuxiliarySurface.miniWindow",
            surface: .miniWindow,
            futureEligibility: .notEligible,
            controllerAttachmentAllowedNow: false,
            futureAttachmentRequiresEnabledModule: true,
            futureAttachmentRequiresNormalBrowsingPromotion: true,
            futureAttachmentRequiresExtensionUIHost: false,
            risksAndNotes: [
                "The auxiliary enum has a mini-window case for OAuth/auth helper flows.",
            ]
        ),
    ].sorted { $0.siteID < $1.siteID }

    static func diagnostics(
        extensionModuleEnabled: Bool,
        profileHostActive: Bool,
        mappings: [ChromeMV3WebViewSurfaceMapping] = currentSumiMappings
    ) -> [ChromeMV3WebViewSurfaceMappingDiagnostic] {
        mappings.map { mapping in
            let eligibility = ChromeMV3WebViewEligibilityPolicy.evaluate(
                surface: mapping.surface,
                extensionModuleEnabled: extensionModuleEnabled,
                profileHostActive: profileHostActive
            )
            let warnings = mapping.controllerAttachmentAllowedNow
                ? ["Surface mapping unexpectedly permits controller attachment now: \(mapping.siteID)"]
                : []
            return ChromeMV3WebViewSurfaceMappingDiagnostic(
                siteID: mapping.siteID,
                sourcePath: mapping.sourcePath,
                surface: mapping.surface,
                futureEligibility: mapping.futureEligibility,
                currentEligibility: eligibility,
                controllerAttachmentAllowedNow: false,
                futureAttachmentRequiresEnabledModule: mapping
                    .futureAttachmentRequiresEnabledModule,
                futureAttachmentRequiresNormalBrowsingPromotion: mapping
                    .futureAttachmentRequiresNormalBrowsingPromotion,
                futureAttachmentRequiresExtensionUIHost: mapping
                    .futureAttachmentRequiresExtensionUIHost,
                risksAndNotes: mapping.risksAndNotes.sorted(),
                warnings: warnings
            )
        }
        .sorted { $0.siteID < $1.siteID }
    }
}

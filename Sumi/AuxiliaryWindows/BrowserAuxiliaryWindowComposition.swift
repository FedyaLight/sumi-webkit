import AppKit
import Foundation
import WebKit

@MainActor
private final class BrowserAuxiliaryWindowContext:
    AuxiliaryWindowContextResolving
{
    private let windowRegistry: @MainActor () -> WindowRegistry?
    private let currentProfile: @MainActor () -> UUID?
    private let spaces: TabSpaceCollectionStateOwner
    private let tabs: BrowserWindowTabContext

    init(
        windowRegistry: @escaping @MainActor () -> WindowRegistry?,
        currentProfile: @escaping @MainActor () -> UUID?,
        spaces: TabSpaceCollectionStateOwner,
        tabs: BrowserWindowTabContext
    ) {
        self.windowRegistry = windowRegistry
        self.currentProfile = currentProfile
        self.spaces = spaces
        self.tabs = tabs
    }

    var activeWindow: BrowserWindowState? {
        windowRegistry()?.activeWindow
    }

    var currentProfileID: UUID? {
        currentProfile()
    }

    var currentSpace: Space? {
        spaces.currentSpace
    }

    func currentTab(in windowState: BrowserWindowState) -> Tab? {
        tabs.currentTab(for: windowState)
    }

    func parentWindow(for tab: Tab) -> NSWindow? {
        guard let windowRegistry = windowRegistry() else { return nil }
        if let windowState = tabs.windowState(containing: tab) {
            return windowRegistry.appKitWindow(for: windowState)
        }
        return windowRegistry.activeWindow.flatMap {
            windowRegistry.appKitWindow(for: $0)
        }
    }
}

@MainActor
private final class BrowserAuxiliaryWindowTabs:
    AuxiliaryWindowTabLifecycle
{
    private let transientTabs: TabTransientWebKitTabLifecycleOwner
    private let webViewOwnership: @MainActor () -> WebViewOwnershipService?
    private let extensions: SumiExtensionsModule
    private let context: any AuxiliaryWindowContextResolving

    init(
        transientTabs: TabTransientWebKitTabLifecycleOwner,
        webViewOwnership: @escaping @MainActor () -> WebViewOwnershipService?,
        extensions: SumiExtensionsModule,
        context: any AuxiliaryWindowContextResolving
    ) {
        self.transientTabs = transientTabs
        self.webViewOwnership = webViewOwnership
        self.extensions = extensions
        self.context = context
    }

    var canInstallMiniWindowWebView: Bool {
        webViewOwnership() != nil
    }

    func createMiniWindowTab(
        openerTab: Tab?,
        profileID: UUID?,
        urlString: String?,
        extensionContext: WKWebExtensionContext?
    ) -> Tab? {
        let openerProfileID = openerTab?.profileId
            ?? openerTab?.resolveProfile()?.id
        let currentSpace = context.currentSpace
        let identity = AuxiliaryWindowTabIdentityPolicy.resolve(
            explicitProfileID: profileID,
            openerProfileID: openerProfileID,
            openerSpaceID: openerTab?.spaceId,
            currentProfileID: context.currentProfileID,
            currentSpaceID: currentSpace?.id,
            currentSpaceProfileID: currentSpace?.profileId
        )
        let tab = transientTabs.createAuxiliaryMiniWindowTab(
            openerTab: openerTab,
            profileId: identity.profileID,
            urlString: urlString,
            webExtensionContextOverride: extensionContext
        )
        tab.profileId = identity.profileID
        tab.spaceId = identity.spaceID
        return tab
    }

    func install(_ webView: WKWebView, for tab: Tab) {
        guard let webViewOwnership = webViewOwnership() else {
            preconditionFailure(
                "Auxiliary WebView ownership disappeared after admission"
            )
        }
        webViewOwnership.installUntracked(webView, for: tab)
    }

    func registerExtensionCreatedTab(_ tab: Tab, reason: String) {
        extensions.registerExtensionCreatedTabWithExtensionRuntimeIfLoaded(
            tab,
            reason: reason
        )
    }

    func notifyTabClosed(_ tab: Tab) {
        extensions.notifyTabClosedIfLoaded(tab)
    }

    func removeMiniWindowTab(_ tab: Tab) {
        transientTabs.removeAuxiliaryMiniWindowTab(tab)
    }
}

@MainActor
private final class BrowserAuxiliaryWindowPermissions:
    AuxiliaryWindowPermissionHandling
{
    private let popup: SumiPopupPermissionBridge
    private let filePicker: SumiFilePickerPermissionBridge

    init(
        popup: SumiPopupPermissionBridge,
        filePicker: SumiFilePickerPermissionBridge
    ) {
        self.popup = popup
        self.filePicker = filePicker
    }

    func evaluatePopupPermission(
        _ request: SumiPopupPermissionRequest,
        tabContext: SumiPopupPermissionTabContext
    ) -> SumiPopupPermissionResult? {
        popup.evaluateSynchronouslyForWebKitFallback(
            request,
            tabContext: tabContext
        )
    }

    func handleFilePickerOpenPanel(
        _ request: SumiFilePickerPermissionRequest,
        tabContext: SumiFilePickerPermissionTabContext,
        webView: WKWebView?,
        currentPageID: @escaping @MainActor () -> String?,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) -> Bool {
        filePicker.handleOpenPanel(
            request,
            tabContext: tabContext,
            webView: webView,
            currentPageId: currentPageID,
            completionHandler: { urls in
                Task { @MainActor in
                    completionHandler(urls)
                }
            }
        )
        return true
    }
}

@MainActor
private final class BrowserAuxiliaryWindowMutationAdmission:
    AuxiliaryWindowMutationAdmitting
{
    private let cleanup: @MainActor () -> WebsiteDataCleanupService?

    init(
        cleanup: @escaping @MainActor () -> WebsiteDataCleanupService?
    ) {
        self.cleanup = cleanup
    }

    func admissionIsBlocked(profileID: UUID) -> Bool {
        cleanup()?.admissionIsBlocked(profileID: profileID) ?? false
    }

    func waitForAdmission(profileID: UUID) async -> Bool {
        guard let cleanup = cleanup() else {
            return true
        }
        return await cleanup.waitForAdmission(profileID: profileID)
    }
}

extension ExtensionManager: AuxiliaryWindowExtensionEventHandling {
    func auxiliaryWindowIntegration() -> AuxiliaryWindowExtensionIntegration {
        AuxiliaryWindowExtensionIntegration(
            installedExtensions: installedExtensionCollection.records,
            events: self,
            resolveExtensionID: { [weak self] context, openerTab, sourceURL in
                self?.ownerExtensionID(
                    extensionContext: context,
                    openerTab: openerTab,
                    extensionOwnedSourceURL: sourceURL
                )
            },
            makeMiniWindowAdapter: {
                [weak self] sessionID, tab, window, isPrivate, shouldActivate in
                self?.adapterResolutionOwner.miniWindowAdapter(
                    for: sessionID,
                    tab: tab,
                    window: window,
                    isPrivate: isPrivate,
                    shouldActivateApp: shouldActivate
                )
            }
        )
    }
}

extension SumiExtensionsModule: AuxiliaryWindowExtensionRuntimeResolving {
    func loadedEnabledAuxiliaryWindowIntegration()
        -> AuxiliaryWindowExtensionIntegration? {
        managerIfLoadedAndEnabled()?.auxiliaryWindowIntegration()
    }
}

/// Composition root only. Callers use the exact registry or service and this
/// type intentionally provides no forwarding methods.
@MainActor
final class BrowserAuxiliaryWindowComposition {
    let nestingPolicy: AuxiliaryWindowNestingPolicy
    let sessions: AuxiliaryWindowSessionRegistry
    let focus: AuxiliaryWindowFocusService
    let teardown: AuxiliaryWindowTeardownService
    let popups: AuxiliaryPopupOpeningService
    let extensionWindows: ExtensionAuxiliaryWindowOpeningService

    init(
        windowRegistry: @escaping @MainActor () -> WindowRegistry?,
        currentProfile: @escaping @MainActor () -> UUID?,
        spaces: TabSpaceCollectionStateOwner,
        tabContext: BrowserWindowTabContext,
        transientTabs: TabTransientWebKitTabLifecycleOwner,
        webViewOwnership: @escaping @MainActor () -> WebViewOwnershipService?,
        extensions: SumiExtensionsModule,
        popupPermissions: SumiPopupPermissionBridge,
        filePickerPermissions: SumiFilePickerPermissionBridge,
        mutationAdmission: @escaping @MainActor () -> WebsiteDataCleanupService?
    ) {
        let context = BrowserAuxiliaryWindowContext(
            windowRegistry: windowRegistry,
            currentProfile: currentProfile,
            spaces: spaces,
            tabs: tabContext
        )
        let tabs = BrowserAuxiliaryWindowTabs(
            transientTabs: transientTabs,
            webViewOwnership: webViewOwnership,
            extensions: extensions,
            context: context
        )
        let permissions = BrowserAuxiliaryWindowPermissions(
            popup: popupPermissions,
            filePicker: filePickerPermissions
        )
        let admission = BrowserAuxiliaryWindowMutationAdmission(
            cleanup: mutationAdmission
        )
        let nestingPolicy = AuxiliaryWindowNestingPolicy()
        let sessions = AuxiliaryWindowSessionRegistry()
        let focus = AuxiliaryWindowFocusService(sessions: sessions)
        let teardown = AuxiliaryWindowTeardownService(
            sessions: sessions,
            tabs: tabs,
            focus: focus
        )
        let presentation = AuxiliaryWindowPresentationService(
            sessions: sessions,
            context: context,
            permissions: permissions,
            nestingPolicy: nestingPolicy,
            teardown: teardown,
            focus: focus
        )
        let popups = AuxiliaryPopupOpeningService(
            context: context,
            tabs: tabs,
            admission: admission,
            extensionRuntime: extensions,
            nestingPolicy: nestingPolicy,
            presentation: presentation
        )

        self.nestingPolicy = nestingPolicy
        self.sessions = sessions
        self.focus = focus
        self.teardown = teardown
        self.popups = popups
        self.extensionWindows = ExtensionAuxiliaryWindowOpeningService(
            context: context,
            tabs: tabs,
            admission: admission,
            presentation: presentation,
            popups: popups,
            teardown: teardown
        )
    }
}

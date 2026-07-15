import AppKit
import Foundation
import WebKit

@MainActor
private final class BrowserAuxiliaryWindowContext:
    AuxiliaryWindowContextResolving {
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
    AuxiliaryWindowTabLifecycle {
    private let transientTabs: TabTransientWebKitTabLifecycleOwner
    private let webViewInstaller: any UntrackedWebViewInstalling
    private let context: any AuxiliaryWindowContextResolving

    init(
        transientTabs: TabTransientWebKitTabLifecycleOwner,
        untrackedWebViewInstallation: any UntrackedWebViewInstalling,
        context: any AuxiliaryWindowContextResolving
    ) {
        self.transientTabs = transientTabs
        self.webViewInstaller = untrackedWebViewInstallation
        self.context = context
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

    func install(
        _ webView: WKWebView,
        for tab: Tab
    ) -> UntrackedWebViewInstallationOutcome {
        webViewInstaller.installUntracked(webView, for: tab)
    }

    func discardCreatedMiniWindowTab(
        _ tab: Tab,
        unplacedWebView: WKWebView?
    ) {
        unplacedWebView.map(tab.cleanupCloneWebView)
        transientTabs.removeAuxiliaryMiniWindowTab(tab)
    }

    func removeMiniWindowTab(_ tab: Tab) {
        transientTabs.removeAuxiliaryMiniWindowTab(tab)
    }
}

@MainActor
private final class BrowserAuxiliaryWindowPermissions:
    AuxiliaryWindowPermissionHandling {
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
    AuxiliaryWindowMutationAdmitting {
    private let cleanup: WebsiteDataCleanupService

    init(cleanup: WebsiteDataCleanupService) {
        self.cleanup = cleanup
    }

    func admissionIsBlocked(profileID: UUID) -> Bool {
        cleanup.admissionIsBlocked(profileID: profileID)
    }

    func waitForAdmission(profileID: UUID) async -> Bool {
        await cleanup.waitForAdmission(profileID: profileID)
    }
}

extension SumiExtensionsModule: AuxiliaryWindowExtensionRuntimeResolving {
    func loadedEnabledAuxiliaryWindowIntegration()
        -> AuxiliaryWindowExtensionIntegration? {
        runtimeSurface.loadedAuxiliaryWindowIntegration()
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
        untrackedWebViewInstallation: any UntrackedWebViewInstalling,
        extensions: SumiExtensionsModule,
        popupPermissions: SumiPopupPermissionBridge,
        filePickerPermissions: SumiFilePickerPermissionBridge,
        mutationAdmission: WebsiteDataCleanupService
    ) {
        let context = BrowserAuxiliaryWindowContext(
            windowRegistry: windowRegistry,
            currentProfile: currentProfile,
            spaces: spaces,
            tabs: tabContext
        )
        let tabs = BrowserAuxiliaryWindowTabs(
            transientTabs: transientTabs,
            untrackedWebViewInstallation: untrackedWebViewInstallation,
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
            presentation: presentation,
            teardown: teardown
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

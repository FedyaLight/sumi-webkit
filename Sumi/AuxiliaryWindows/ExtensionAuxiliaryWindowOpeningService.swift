import Foundation
import SumiDomain
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionAuxiliaryWindowOpeningService {
    private let context: any AuxiliaryWindowContextResolving
    private let tabs: any AuxiliaryWindowTabLifecycle
    private let admission: any AuxiliaryWindowMutationAdmitting
    private let presentation: AuxiliaryWindowPresentationService
    private let popups: AuxiliaryPopupOpeningService
    private let teardown: AuxiliaryWindowTeardownService

    init(
        context: any AuxiliaryWindowContextResolving,
        tabs: any AuxiliaryWindowTabLifecycle,
        admission: any AuxiliaryWindowMutationAdmitting,
        presentation: AuxiliaryWindowPresentationService,
        popups: AuxiliaryPopupOpeningService,
        teardown: AuxiliaryWindowTeardownService
    ) {
        self.context = context
        self.tabs = tabs
        self.admission = admission
        self.presentation = presentation
        self.popups = popups
        self.teardown = teardown
    }

    func present(
        configuration: WKWebExtension.WindowConfiguration,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext,
        extensionManager: ExtensionManager,
        parentWindow: NSWindow?
    ) async -> ExtensionMiniWindowAdapter? {
        let isPrivate = configuration.shouldBePrivate
            || context.activeWindow?.isIncognito == true
        guard isPrivate == false else {
            return nil
        }

        let geometry = AuxiliaryWindowGeometryResolver.resolve(
            extensionFrame: configuration.frame,
            parentWindow: parentWindow
        )
        let activeWindow = context.activeWindow
        let openerTab = activeWindow.flatMap(context.currentTab(in:))
        let profileID = extensionManager.profileId(for: extensionContext)
            ?? openerTab?.profileId
            ?? context.currentProfileID

        if let profileID {
            guard await admission.waitForAdmission(profileID: profileID) else {
                return nil
            }
            await extensionManager.ensureInitialExtensionContextsLoaded(
                for: profileID
            )
        }

        let firstURL = configuration.tabURLs.first
        let resolvedLoad = extensionManager.requestedTabLoadResolver.resolve(
            firstURL,
            controller: controller
        )
        let loadURL = resolvedLoad.url ?? firstURL
        let isExtensionOwnedLoad = ExtensionUtils.isExtensionOwnedURL(loadURL)
        let tabExtensionContext = resolvedLoad.extensionContext
            ?? (isExtensionOwnedLoad ? extensionContext : nil)

        if let loadURL {
            await extensionManager.requestedTabContextPreloader.prepare(
                load: ExtensionRequestedTabLoad(
                    url: loadURL,
                    extensionContext: tabExtensionContext
                ),
                targetWindow: activeWindow,
                targetSpace: context.currentSpace,
                controller: controller
            )
            extensionManager.recentExtensionTabRequests.record(loadURL)
        }

        if let profileID,
           await admission.waitForAdmission(profileID: profileID) == false {
            return nil
        }

        let loadURLString = loadURL?.absoluteString
            ?? SumiSurface.emptyTabURL.absoluteString
        guard let tab = tabs.createMiniWindowTab(
            openerTab: openerTab,
            profileID: profileID,
            urlString: loadURLString,
            extensionContext: tabExtensionContext
        ) else {
            return nil
        }

        let webViewConfiguration = (tabExtensionContext ?? extensionContext)
            .webViewConfiguration ?? WKWebViewConfiguration()
        extensionManager.prepareWebViewConfigForExtensionRuntime(
            webViewConfiguration,
            profileId: profileID,
            reason: "ExtensionAuxiliaryWindowOpeningService.webView"
        )
        let webView = tab.createAuxiliaryMiniWindowWebViewFromWebKitConfiguration(
            webViewConfiguration,
            currentURL: loadURL,
            isExtensionOriginated: true,
            reason: "ExtensionAuxiliaryWindowOpeningService.present"
        )
        tabs.install(webView, for: tab)

        let extensionIntegration = extensionManager
            .auxiliaryWindowIntegration()
        let extensionID = AuxiliaryWindowExtensionIdentityResolver.resolve(
            extensionIntegration: extensionIntegration,
            extensionContext: extensionContext,
            openerTab: openerTab,
            extensionOwnedSourceURL: firstURL,
            explicitExtensionID: nil
        )
        let session = presentation.present(
            AuxiliaryWindowPresentationRequest(
                tab: tab,
                webView: webView,
                geometry: geometry,
                openerTab: openerTab,
                explicitOpenerWindow: parentWindow,
                titleURL: firstURL,
                shouldActivateApp: configuration.shouldBeFocused,
                isPrivate: false,
                nestedDepth: 0,
                extensionIntegration: extensionIntegration,
                extensionID: extensionID
            ),
            nestedPopups: popups
        )

        guard let adapter = session.miniWindowAdapter else {
            teardown.teardown(
                for: session.webView,
                reason: .presentationFailure
            )
            return nil
        }

        extensionManager.extensionCreatedTabRegistrar.register(
            tab,
            reason: "ExtensionAuxiliaryWindowOpeningService.present"
        )
        session.extensionEvents?.notifyAuxiliaryWindowOpened(session)
        if let loadURL {
            tab.loadURL(loadURL)
        }
        return adapter
    }
}

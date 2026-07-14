import Foundation
import SumiDomain
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionAuxiliaryWindowCallbackRuntime {
    let contextLoading: any ExtensionInitialDocumentContextReadiness
    let loadResolver: ExtensionRequestedTabLoadResolver
    let contextPreloader: ExtensionRequestedTabContextPreloader
    let recentRequests: ExtensionRecentTabRequestHistory
    let configurationPreparation: ExtensionWebViewConfigurationPreparation
    let integration: AuxiliaryWindowExtensionIntegration
}

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
        evidence: ExtensionControllerCallbackEvidence,
        callbackAdmission: ExtensionControllerCallbackAdmission,
        runtime: ExtensionAuxiliaryWindowCallbackRuntime,
        parentWindow: NSWindow?
    ) async -> ExtensionPopupWindowPresentationReceipt? {
        guard callbackAdmission.isCurrent(evidence) else { return nil }
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
        let profileID = evidence.profileID
        guard openerTab?.profileId.map({ $0 == profileID }) ?? true else {
            return nil
        }

        let firstURL = configuration.tabURLs.first
        let resolvedLoad = runtime.loadResolver.resolve(
            firstURL,
            controller: evidence.controller
        )
        guard resolvedLoad.hasUnresolvedExtensionOwnership == false else {
            return nil
        }
        if case .extensionOwned(let loadContext) = resolvedLoad.ownership {
            guard loadContext === evidence.context else { return nil }
        }
        let loadURL = resolvedLoad.url ?? firstURL
        let tabExtensionContext = resolvedLoad.extensionContext

        guard callbackAdmission.isCurrent(evidence),
              await admission.waitForAdmission(profileID: profileID),
              callbackAdmission.isCurrent(evidence)
        else {
            return nil
        }
        if runtime.contextLoading
            .profileNeedsInitialDocumentExtensionContextLoad(
                profileId: profileID
            ) {
            await runtime.contextLoading.ensureInitialExtensionContextsLoaded(
                for: profileID
            )
            guard callbackAdmission.isCurrent(evidence) else { return nil }
        }

        if let loadURL {
            await runtime.contextPreloader.prepare(
                load: ExtensionRequestedTabLoad(
                    url: loadURL,
                    ownership: resolvedLoad.ownership
                ),
                targetWindow: activeWindow,
                targetSpace: context.currentSpace,
                controller: evidence.controller
            )
            guard callbackAdmission.isCurrent(evidence) else { return nil }
            runtime.recentRequests.record(loadURL)
        }

        guard callbackAdmission.isCurrent(evidence),
              await admission.waitForAdmission(profileID: profileID),
              callbackAdmission.isCurrent(evidence)
        else {
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
        guard callbackAdmission.isCurrent(evidence) else {
            tabs.discardCreatedMiniWindowTab(tab, unplacedWebView: nil)
            return nil
        }

        let webViewConfiguration = (tabExtensionContext ?? evidence.context)
            .webViewConfiguration ?? WKWebViewConfiguration()
        guard callbackAdmission.isCurrent(evidence) else {
            tabs.discardCreatedMiniWindowTab(tab, unplacedWebView: nil)
            return nil
        }
        runtime.configurationPreparation.prepareWebViewConfigForExtensionRuntime(
            webViewConfiguration,
            profileId: profileID,
            reason: "ExtensionAuxiliaryWindowOpeningService.webView"
        )
        guard callbackAdmission.isCurrent(evidence) else {
            tabs.discardCreatedMiniWindowTab(tab, unplacedWebView: nil)
            return nil
        }
        let webView = tab.createAuxiliaryMiniWindowWebViewFromWebKitConfiguration(
            webViewConfiguration,
            currentURL: loadURL,
            isExtensionOriginated: true,
            reason: "ExtensionAuxiliaryWindowOpeningService.present"
        )
        guard callbackAdmission.isCurrent(evidence) else {
            tabs.discardCreatedMiniWindowTab(tab, unplacedWebView: webView)
            return nil
        }
        let installation = tabs.install(webView, for: tab)
        guard installation.isAccepted else {
            tabs.discardCreatedMiniWindowTab(
                tab,
                unplacedWebView: installation.callerRetainsWebView
                    ? webView
                    : nil
            )
            return nil
        }
        guard callbackAdmission.isCurrent(evidence) else {
            tab.performComprehensiveWebViewCleanup()
            tabs.removeMiniWindowTab(tab)
            return nil
        }

        let extensionID = AuxiliaryWindowExtensionIdentityResolver.resolve(
            extensionIntegration: runtime.integration,
            extensionContext: evidence.context,
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
                extensionIntegration: runtime.integration,
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

        guard callbackAdmission.isCurrent(evidence),
              session.extensionEvents?
            .notifyAuxiliaryWindowOpened(session) == true else {
            teardown.teardown(
                for: session.webView,
                reason: .presentationFailure
            )
            return nil
        }
        if let loadURL {
            guard callbackAdmission.isCurrent(evidence) else {
                teardown.teardown(
                    for: session.webView,
                    reason: .presentationFailure
                )
                return nil
            }
            tab.loadURL(loadURL)
        }
        let sessionReceipt = AuxiliaryWindowSessionReceipt(session: session)
        return ExtensionPopupWindowPresentationReceipt(
            sessionReceipt: sessionReceipt,
            adapter: adapter,
            retireExactSession: {
                [weak teardown = self.teardown] in
                guard let teardown else { return }
                teardown.teardown(
                    sessionReceipt,
                    reason: .presentationFailure
                )
            }
        )
    }
}

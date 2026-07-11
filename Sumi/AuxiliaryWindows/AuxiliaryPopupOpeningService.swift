import AppKit
import Foundation
import WebKit

@MainActor
final class AuxiliaryPopupOpeningService {
    private let context: any AuxiliaryWindowContextResolving
    private let tabs: any AuxiliaryWindowTabLifecycle
    private let admission: any AuxiliaryWindowMutationAdmitting
    private let extensionRuntime: any AuxiliaryWindowExtensionRuntimeResolving
    private let nestingPolicy: AuxiliaryWindowNestingPolicy
    private let presentation: AuxiliaryWindowPresentationService
    private let teardown: AuxiliaryWindowTeardownService

    init(
        context: any AuxiliaryWindowContextResolving,
        tabs: any AuxiliaryWindowTabLifecycle,
        admission: any AuxiliaryWindowMutationAdmitting,
        extensionRuntime: any AuxiliaryWindowExtensionRuntimeResolving,
        nestingPolicy: AuxiliaryWindowNestingPolicy,
        presentation: AuxiliaryWindowPresentationService,
        teardown: AuxiliaryWindowTeardownService
    ) {
        self.context = context
        self.tabs = tabs
        self.admission = admission
        self.extensionRuntime = extensionRuntime
        self.nestingPolicy = nestingPolicy
        self.presentation = presentation
        self.teardown = teardown
    }

    @discardableResult
    func presentWebPopup(
        configuration: WKWebViewConfiguration,
        request: URLRequest?,
        windowFeatures: WKWindowFeatures,
        openerTab: Tab,
        explicitOpenerWindow: NSWindow? = nil,
        explicitOpenerProfileID: UUID? = nil,
        isExtensionOriginated: Bool = false,
        shouldActivateApp: Bool = true,
        nestedDepth: Int = 0,
        ownerExtensionID: String? = nil,
        extensionOwnedSourceURL: URL? = nil
    ) -> WKWebView? {
        if isExtensionOriginated {
            return presentExtensionExternalWebPopup(
                configuration: configuration,
                request: request,
                windowFeatures: windowFeatures,
                openerTab: openerTab,
                explicitOpenerWindow: explicitOpenerWindow,
                explicitOpenerProfileID: explicitOpenerProfileID,
                shouldActivateApp: shouldActivateApp,
                nestedDepth: nestedDepth,
                extensionOwnedSourceURL: extensionOwnedSourceURL,
                ownerExtensionID: ownerExtensionID
            )
        }

        guard nestingPolicy.allowsPresentation(at: nestedDepth),
              admissionIsOpen(
                  for: openerTab,
                  explicitProfileID: explicitOpenerProfileID
              ) else {
            return nil
        }

        let parentWindow = explicitOpenerWindow
            ?? context.parentWindow(for: openerTab)
        let geometry = AuxiliaryWindowGeometryResolver.resolve(
            windowFeatures: windowFeatures,
            parentWindow: parentWindow
        )
        guard let tab = tabs.createMiniWindowTab(
            openerTab: openerTab,
            profileID: explicitOpenerProfileID,
            urlString: request?.url?.absoluteString,
            extensionContext: nil
        ) else {
            return nil
        }
        guard configurationMatchesResolvedProfile(
            configuration,
            tab: tab,
            explicitProfileID: explicitOpenerProfileID
        ) else {
            tabs.removeMiniWindowTab(tab)
            return nil
        }

        let webView = tab.createAuxiliaryMiniWindowWebViewFromWebKitConfiguration(
            configuration,
            currentURL: request?.url,
            isExtensionOriginated: false,
            reason: "AuxiliaryPopupOpeningService.presentWebPopup"
        )
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
        _ = presentation.present(
            AuxiliaryWindowPresentationRequest(
                tab: tab,
                webView: webView,
                geometry: geometry,
                openerTab: openerTab,
                explicitOpenerWindow: parentWindow,
                titleURL: request?.url,
                shouldActivateApp: shouldActivateApp,
                isPrivate: openerTab.isEphemeral,
                nestedDepth: nestedDepth,
                extensionIntegration: nil,
                extensionID: ownerExtensionID
            ),
            nestedPopups: self
        )
        return webView
    }

    @discardableResult
    func presentExtensionExternalWebPopup(
        configuration: WKWebViewConfiguration,
        request: URLRequest?,
        windowFeatures: WKWindowFeatures,
        openerTab: Tab,
        explicitOpenerWindow: NSWindow? = nil,
        explicitOpenerProfileID: UUID? = nil,
        shouldActivateApp: Bool = true,
        nestedDepth: Int = 0,
        extensionOwnedSourceURL: URL? = nil,
        ownerExtensionID: String? = nil
    ) -> WKWebView? {
        guard nestingPolicy.allowsPresentation(at: nestedDepth),
              admissionIsOpen(
                  for: openerTab,
                  explicitProfileID: explicitOpenerProfileID
              ) else {
            return nil
        }

        let extensionIntegration = extensionRuntime
            .loadedEnabledAuxiliaryWindowIntegration()
        let extensionID = AuxiliaryWindowExtensionIdentityResolver.resolve(
            extensionIntegration: extensionIntegration,
            extensionContext: nil,
            openerTab: openerTab,
            extensionOwnedSourceURL: extensionOwnedSourceURL,
            explicitExtensionID: ownerExtensionID
        )
        let parentWindow = explicitOpenerWindow
            ?? context.parentWindow(for: openerTab)
        let hasExplicitGeometry = windowFeatures.width != nil
            || windowFeatures.height != nil
            || windowFeatures.sumiOrigin != nil
        let geometry = hasExplicitGeometry
            ? AuxiliaryWindowGeometryResolver.resolve(
                windowFeatures: windowFeatures,
                parentWindow: parentWindow
            )
            : AuxiliaryWindowGeometryResolver.resolveDefault(
                parentWindow: parentWindow
            )

        guard let tab = tabs.createMiniWindowTab(
            openerTab: openerTab,
            profileID: explicitOpenerProfileID,
            urlString: request?.url?.absoluteString,
            extensionContext: nil
        ) else {
            return nil
        }
        guard configurationMatchesResolvedProfile(
            configuration,
            tab: tab,
            explicitProfileID: explicitOpenerProfileID
        ) else {
            tabs.removeMiniWindowTab(tab)
            return nil
        }
        let webView = tab.createAuxiliaryMiniWindowWebViewFromWebKitConfiguration(
            configuration,
            currentURL: request?.url,
            isExtensionOriginated: true,
            reason: "AuxiliaryPopupOpeningService.presentExtensionExternalWebPopup"
        )
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

        let session = presentation.present(
            AuxiliaryWindowPresentationRequest(
                tab: tab,
                webView: webView,
                geometry: geometry,
                openerTab: openerTab,
                explicitOpenerWindow: parentWindow,
                titleURL: request?.url,
                shouldActivateApp: shouldActivateApp,
                isPrivate: openerTab.isEphemeral,
                nestedDepth: nestedDepth,
                extensionIntegration: extensionIntegration,
                extensionID: extensionID
            ),
            nestedPopups: self
        )
        if session.miniWindowAdapter != nil || session.extensionEvents != nil {
            guard session.extensionEvents?
                .notifyAuxiliaryWindowOpened(session) == true else {
                teardown.teardown(
                    for: session.webView,
                    reason: .presentationFailure
                )
                return nil
            }
        }
        return webView
    }

    private func admissionIsOpen(
        for openerTab: Tab,
        explicitProfileID: UUID?
    ) -> Bool {
        guard let profileID = explicitProfileID
            ?? openerTab.profileId
            ?? openerTab.resolveProfile()?.id else {
            return true
        }
        return admission.admissionIsBlocked(profileID: profileID) == false
    }

    private func configurationMatchesResolvedProfile(
        _ configuration: WKWebViewConfiguration,
        tab: Tab,
        explicitProfileID: UUID?
    ) -> Bool {
        guard let explicitProfileID else { return true }
        guard tab.profileId == explicitProfileID,
              let profile = tab.resolveProfile(),
              profile.id == explicitProfileID
        else {
            return false
        }
        return configuration.websiteDataStore === profile.dataStore
    }
}

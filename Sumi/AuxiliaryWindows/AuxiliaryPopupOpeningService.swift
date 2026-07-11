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

    init(
        context: any AuxiliaryWindowContextResolving,
        tabs: any AuxiliaryWindowTabLifecycle,
        admission: any AuxiliaryWindowMutationAdmitting,
        extensionRuntime: any AuxiliaryWindowExtensionRuntimeResolving,
        nestingPolicy: AuxiliaryWindowNestingPolicy,
        presentation: AuxiliaryWindowPresentationService
    ) {
        self.context = context
        self.tabs = tabs
        self.admission = admission
        self.extensionRuntime = extensionRuntime
        self.nestingPolicy = nestingPolicy
        self.presentation = presentation
    }

    @discardableResult
    func presentWebPopup(
        configuration: WKWebViewConfiguration,
        request: URLRequest?,
        windowFeatures: WKWindowFeatures,
        openerTab: Tab,
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
                shouldActivateApp: shouldActivateApp,
                nestedDepth: nestedDepth,
                extensionOwnedSourceURL: extensionOwnedSourceURL,
                ownerExtensionID: ownerExtensionID
            )
        }

        guard nestingPolicy.allowsPresentation(at: nestedDepth),
              admissionIsOpen(for: openerTab) else {
            return nil
        }

        let parentWindow = context.parentWindow(for: openerTab)
        let geometry = AuxiliaryWindowGeometryResolver.resolve(
            windowFeatures: windowFeatures,
            parentWindow: parentWindow
        )
        guard let tab = tabs.createMiniWindowTab(
            openerTab: openerTab,
            profileID: nil,
            urlString: request?.url?.absoluteString,
            extensionContext: nil
        ) else {
            return nil
        }

        let webView = tab.createAuxiliaryMiniWindowWebViewFromWebKitConfiguration(
            configuration,
            currentURL: request?.url,
            isExtensionOriginated: false,
            reason: "AuxiliaryPopupOpeningService.presentWebPopup"
        )
        tabs.install(webView, for: tab)
        _ = presentation.present(
            AuxiliaryWindowPresentationRequest(
                tab: tab,
                webView: webView,
                geometry: geometry,
                openerTab: openerTab,
                explicitOpenerWindow: nil,
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
        shouldActivateApp: Bool = true,
        nestedDepth: Int = 0,
        extensionOwnedSourceURL: URL? = nil,
        ownerExtensionID: String? = nil
    ) -> WKWebView? {
        guard nestingPolicy.allowsPresentation(at: nestedDepth),
              admissionIsOpen(for: openerTab) else {
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
        let parentWindow = context.parentWindow(for: openerTab)
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
            profileID: nil,
            urlString: request?.url?.absoluteString,
            extensionContext: nil
        ) else {
            return nil
        }
        let webView = tab.createAuxiliaryMiniWindowWebViewFromWebKitConfiguration(
            configuration,
            currentURL: request?.url,
            isExtensionOriginated: true,
            reason: "AuxiliaryPopupOpeningService.presentExtensionExternalWebPopup"
        )
        tabs.install(webView, for: tab)

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
        tabs.registerExtensionCreatedTab(
            tab,
            reason: "AuxiliaryPopupOpeningService.presentExtensionExternalWebPopup"
        )
        session.extensionEvents?.notifyAuxiliaryWindowOpened(session)
        return webView
    }

    private func admissionIsOpen(for openerTab: Tab) -> Bool {
        guard let profileID = openerTab.profileId
            ?? openerTab.resolveProfile()?.id else {
            return true
        }
        return admission.admissionIsBlocked(profileID: profileID) == false
    }
}

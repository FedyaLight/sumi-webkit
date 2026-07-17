import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionPageNavigationPreparationOwner {
    private let webViewReplacement = TabWebViewReplacementService()
    private let tabProfiles: any ExtensionTabProfileResolving
    private let webViews: ExtensionExactTabWebViewQuery
    private let controllerProvisioning: ExtensionControllerProvisioningOwner

    init(
        tabProfiles: any ExtensionTabProfileResolving,
        webViews: ExtensionExactTabWebViewQuery,
        controllerProvisioning: ExtensionControllerProvisioningOwner
    ) {
        self.tabProfiles = tabProfiles
        self.webViews = webViews
        self.controllerProvisioning = controllerProvisioning
    }

    @discardableResult
    func prepareNavigation(
        _ tab: Tab,
        targetURL: URL,
        reason: String
    ) -> TabWebViewReplacementOutcome {
        if ExtensionURLIdentity.isOwned(targetURL) {
            return prepareExtensionOwnedNavigation(
                tab,
                targetURL: targetURL,
                reason: reason
            )
        }
        return clearExtensionPageOverrideIfNeeded(
            tab,
            targetURL: targetURL,
            reason: reason
        )
    }

    private func prepareExtensionOwnedNavigation(
        _ tab: Tab,
        targetURL: URL,
        reason: String
    ) -> TabWebViewReplacementOutcome {
        guard let extensionContext = extensionContext(
            for: targetURL,
            tab: tab
        ) else {
            return .notNeeded
        }

        let previousExtensionContext = tab.webExtensionContextOverride
        tab.webExtensionContextOverride = extensionContext
        guard let configuration = extensionContext.webViewConfiguration,
              needsExtensionPageWebViewReplacement(
                  tab,
                  configuration: configuration
              )
        else {
            return .notNeeded
        }

        let outcome = webViewReplacement.replaceCurrentWebView(
            in: tab,
            targetURL: targetURL,
            reason: "\(reason).extensionPageConfiguration",
            configuration: .currentExtensionPage,
            makeReplacementWebView: { replacementReason in
                tab.makeAuxiliaryOverrideTabWebView(
                    configuration: configuration,
                    reason: replacementReason
                )
            }
        )
        if outcome == .failed {
            tab.webExtensionContextOverride = previousExtensionContext
        }
        return outcome
    }

    private func clearExtensionPageOverrideIfNeeded(
        _ tab: Tab,
        targetURL: URL,
        reason: String
    ) -> TabWebViewReplacementOutcome {
        guard tab.webExtensionContextOverride != nil else {
            return .notNeeded
        }
        let previousExtensionContext = tab.webExtensionContextOverride
        tab.webExtensionContextOverride = nil

        guard let currentWebView = webViews.liveWebView(for: tab),
              currentWebView.configuration.sumiIsNormalTabWebViewConfiguration == false
        else {
            return .notNeeded
        }

        let outcome = webViewReplacement.replaceNormalWebView(
            in: tab,
            targetURL: targetURL,
            reason: "\(reason).normalPageConfiguration"
        )
        if outcome == .failed {
            tab.webExtensionContextOverride = previousExtensionContext
        }
        return outcome
    }

    private func extensionContext(
        for targetURL: URL,
        tab: Tab
    ) -> WKWebExtensionContext? {
        if let currentOverride = tab.webExtensionContextOverride,
           targetURL.scheme?.lowercased() == currentOverride.baseURL.scheme?.lowercased(),
           targetURL.host?.lowercased() == currentOverride.baseURL.host?.lowercased() {
            return currentOverride
        }

        guard let profileId = tabProfiles.profileID(for: tab) else {
            return nil
        }
        guard let controller = controllerProvisioning.controllerIfAdmitted(
            for: profileId
        ) else { return nil }
        return controller.extensionContext(for: targetURL)
    }

    private func needsExtensionPageWebViewReplacement(
        _ tab: Tab,
        configuration: WKWebViewConfiguration
    ) -> Bool {
        guard let currentWebView = webViews.liveWebView(for: tab) else {
            return false
        }
        return currentWebView.configuration !== configuration
    }
}

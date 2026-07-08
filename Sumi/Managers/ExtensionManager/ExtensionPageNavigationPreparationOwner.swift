import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionPageNavigationPreparationOwner {
    private let webViewReplacementOwner = TabWebViewReplacementOwner()

    @discardableResult
    func prepareNavigation(
        _ tab: Tab,
        targetURL: URL,
        reason: String,
        manager: ExtensionManager
    ) -> Bool {
        if ExtensionUtils.isExtensionOwnedURL(targetURL) {
            return prepareExtensionOwnedNavigation(
                tab,
                targetURL: targetURL,
                reason: reason,
                manager: manager
            )
        }
        return clearExtensionPageOverrideIfNeeded(
            tab,
            reason: reason,
            manager: manager
        )
    }

    private func prepareExtensionOwnedNavigation(
        _ tab: Tab,
        targetURL: URL,
        reason: String,
        manager: ExtensionManager
    ) -> Bool {
        guard let extensionContext = extensionContext(
            for: targetURL,
            tab: tab,
            manager: manager
        ) else {
            return false
        }

        tab.webExtensionContextOverride = extensionContext
        guard let configuration = extensionContext.webViewConfiguration,
              needsExtensionPageWebViewReplacement(
                  tab,
                  configuration: configuration,
                  manager: manager
              )
        else {
            return false
        }

        return webViewReplacementOwner.replaceCurrentWebView(
            reason: "\(reason).extensionPageConfiguration",
            context: tab.webViewReplacementContextOwner.makeContext(for: tab),
            makeReplacementWebView: { replacementReason in
                tab.makeAuxiliaryOverrideTabWebView(
                    configuration: configuration,
                    reason: replacementReason
                )
            }
        )
    }

    private func clearExtensionPageOverrideIfNeeded(
        _ tab: Tab,
        reason: String,
        manager: ExtensionManager
    ) -> Bool {
        guard tab.webExtensionContextOverride != nil else {
            return false
        }
        tab.webExtensionContextOverride = nil

        guard let currentWebView = manager.resolvedLiveWebView(for: tab),
              currentWebView.configuration.sumiIsNormalTabWebViewConfiguration == false
        else {
            return false
        }

        return webViewReplacementOwner.replaceNormalWebView(
            reason: "\(reason).normalPageConfiguration",
            context: tab.webViewReplacementContextOwner.makeContext(for: tab)
        )
    }

    private func extensionContext(
        for targetURL: URL,
        tab: Tab,
        manager: ExtensionManager
    ) -> WKWebExtensionContext? {
        if let currentOverride = tab.webExtensionContextOverride,
           targetURL.scheme?.lowercased() == currentOverride.baseURL.scheme?.lowercased(),
           targetURL.host?.lowercased() == currentOverride.baseURL.host?.lowercased() {
            return currentOverride
        }

        guard let profileId = manager.resolvedProfileId(for: tab) else {
            return nil
        }
        let controller = manager.ensureExtensionController(for: profileId)
        return controller.extensionContext(for: targetURL)
    }

    private func needsExtensionPageWebViewReplacement(
        _ tab: Tab,
        configuration: WKWebViewConfiguration,
        manager: ExtensionManager
    ) -> Bool {
        guard let currentWebView = manager.resolvedLiveWebView(for: tab) else {
            return false
        }
        return currentWebView.configuration !== configuration
    }
}

// MARK: - ExtensionManager facade

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func prepareExtensionPageNavigation(
        _ tab: Tab,
        targetURL: URL,
        reason: String
    ) -> Bool {
        pageNavigationPreparationOwner.prepareNavigation(
            tab,
            targetURL: targetURL,
            reason: reason,
            manager: self
        )
    }
}

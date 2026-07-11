import Foundation
import SumiDomain
import WebKit

@MainActor
final class AutoplayReloadState {
    private(set) var requirement: SumiAutoplayReloadRequirement?

    var isReloadRequired: Bool { requirement != nil }

    @discardableResult
    func markRequiredIfNeeded(
        afterChangingPolicyFor changedURL: URL?,
        currentURL: URL,
        existingWebView: WKWebView?,
        profile: Profile?,
        policy: any AutoplayPolicyReading
    ) -> Bool {
        let changedOrigin = SumiPermissionOrigin(url: changedURL)
        let currentOrigin = SumiPermissionOrigin(url: currentURL)
        guard changedOrigin.isWebOrigin,
              changedOrigin.identity == currentOrigin.identity else {
            return false
        }
        return updateRequirement(
            currentURL: currentURL,
            existingWebView: existingWebView,
            profile: profile,
            policy: policy
        )
    }

    @discardableResult
    func updateRequirement(
        currentURL: URL,
        existingWebView: WKWebView?,
        profile: Profile?,
        policy: any AutoplayPolicyReading
    ) -> Bool {
        guard let webView = existingWebView else {
            return clearRequirement()
        }

        let desiredPolicy = policy.policy(for: currentURL, profile: profile)
        let result = policy.evaluateChange(
            desiredPolicy.runtimeState,
            for: webView
        )
        guard case .requiresReload(let runtimeRequirement) = result else {
            return clearRequirement()
        }

        return setRequirement(
            SumiAutoplayReloadRequirement(
                desiredPolicy: desiredPolicy,
                runtimeRequirement: runtimeRequirement
            )
        )
    }

    @discardableResult
    func clearIfResolved(
        currentURL: URL,
        existingWebView: WKWebView?,
        profile: Profile?,
        policy: any AutoplayPolicyReading
    ) -> Bool {
        updateRequirement(
            currentURL: currentURL,
            existingWebView: existingWebView,
            profile: profile,
            policy: policy
        )
    }

    func requiresNormalWebViewRebuild(
        for targetURL: URL?,
        existingWebView: WKWebView?,
        webViewConfigurationOverride: WKWebViewConfiguration?,
        isPopupHost: Bool,
        profile: Profile?,
        policy: any AutoplayPolicyReading
    ) -> Bool {
        guard let webView = existingWebView,
              webViewConfigurationOverride == nil,
              isPopupHost == false else {
            return false
        }

        let desiredPolicy = policy.policy(for: targetURL, profile: profile)
        let currentState = SumiRuntimePermissionController.autoplayState(
            from: webView.configuration
                .mediaTypesRequiringUserActionForPlayback
        )
        return currentState != desiredPolicy.runtimeState
    }

    private func setRequirement(
        _ newValue: SumiAutoplayReloadRequirement
    ) -> Bool {
        guard requirement != newValue else { return false }
        requirement = newValue
        return true
    }

    private func clearRequirement() -> Bool {
        guard requirement != nil else { return false }
        requirement = nil
        return true
    }
}

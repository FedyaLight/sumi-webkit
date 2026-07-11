import Foundation
import WebKit

@MainActor
final class SafariContentBlockerReloadState {
    private let policyLedger: TabConfigurationPolicyLedger
    private(set) var requirement:
        SumiSafariContentBlockerReloadRequirement?

    init(policyLedger: TabConfigurationPolicyLedger) {
        self.policyLedger = policyLedger
    }

    var isReloadRequired: Bool { requirement != nil }

    var appliedAttachmentState:
        SumiSafariContentBlockerAttachmentState? {
        policyLedger.safariContentBlockerAttachment
    }

    func desiredAttachmentState(
        for targetURL: URL?,
        policy: any SafariContentBlockerPolicyReading
    ) -> SumiSafariContentBlockerAttachmentState {
        policy.attachmentState(for: targetURL)
    }

    @discardableResult
    func markRequiredIfNeeded(
        afterChangingPolicyFor changedURL: URL?,
        currentURL: URL,
        existingWebView: WKWebView?,
        policy: any SafariContentBlockerPolicyReading
    ) -> Bool {
        let changedState = desiredAttachmentState(
            for: changedURL,
            policy: policy
        )
        let currentState = desiredAttachmentState(
            for: currentURL,
            policy: policy
        )
        guard changedState.siteHost != nil,
              changedState.siteHost == currentState.siteHost else {
            return false
        }

        return updateRequirement(
            currentURL: currentURL,
            existingWebView: existingWebView,
            policy: policy
        )
    }

    @discardableResult
    func updateRequirement(
        currentURL: URL,
        existingWebView: WKWebView?,
        policy: any SafariContentBlockerPolicyReading
    ) -> Bool {
        guard existingWebView != nil else { return clearRequirement() }

        let desiredState = desiredAttachmentState(
            for: currentURL,
            policy: policy
        )
        guard desiredState.siteHost != nil else {
            return clearRequirement()
        }

        if attachmentIsApplied(desiredState) {
            return clearRequirement()
        }

        guard appliedAttachmentState != nil || desiredState.isEnabled else {
            return clearRequirement()
        }

        return setRequirement(
            SumiSafariContentBlockerReloadRequirement(
                siteHost: desiredState.siteHost,
                desiredAttachmentState: desiredState
            )
        )
    }

    @discardableResult
    func clearIfResolved(
        for committedURL: URL,
        policy: any SafariContentBlockerPolicyReading
    ) -> Bool {
        guard let requirement else { return false }
        let committedState = desiredAttachmentState(
            for: committedURL,
            policy: policy
        )
        if committedState.siteHost != requirement.siteHost
            || attachmentIsApplied(committedState) {
            return clearRequirement()
        }
        return false
    }

    func requiresNormalWebViewRebuild(
        for targetURL: URL?,
        existingWebView: WKWebView?,
        webViewConfigurationOverride: WKWebViewConfiguration?,
        isPopupHost: Bool,
        policy: any SafariContentBlockerPolicyReading
    ) -> Bool {
        guard existingWebView != nil,
              webViewConfigurationOverride == nil,
              isPopupHost == false else {
            return false
        }

        let desiredState = desiredAttachmentState(
            for: targetURL,
            policy: policy
        )
        guard let appliedState = appliedAttachmentState else {
            return desiredState.isEnabled
        }
        return !appliedState.hasSameEffectiveWebViewAttachment(
            as: desiredState
        )
    }

    private func attachmentIsApplied(
        _ desiredState: SumiSafariContentBlockerAttachmentState
    ) -> Bool {
        if let appliedState = appliedAttachmentState {
            return appliedState.hasSameEffectiveWebViewAttachment(
                as: desiredState
            )
        }
        return desiredState.isEnabled == false
    }

    private func setRequirement(
        _ newValue: SumiSafariContentBlockerReloadRequirement
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

import Foundation
import SumiDomain
import WebKit

@MainActor
final class ProtectionReloadState {
    private let policyLedger: TabConfigurationPolicyLedger
    private(set) var requirement: SumiProtectionReloadRequirement?
    private(set) var didManualReloadRebuildWebView = false
    private(set) var appliedAfterManualReload = false

    init(policyLedger: TabConfigurationPolicyLedger) {
        self.policyLedger = policyLedger
    }

    var isReloadRequired: Bool { requirement != nil }

    var appliedAttachmentState: SumiProtectionAttachmentState? {
        policyLedger.protectionAttachment
    }

    func desiredAttachmentState(
        for targetURL: URL?,
        policy: any ProtectionPolicyReading
    ) -> SumiProtectionAttachmentState {
        policy.attachmentState(for: targetURL)
    }

    @discardableResult
    func markRequiredIfNeeded(
        afterChangingPolicyFor changedURL: URL?,
        currentURL: URL,
        existingWebView: WKWebView?,
        policy: any ProtectionPolicyReading
    ) -> Bool {
        guard let changedHost = policy.surfaceHost(for: changedURL),
              changedHost == policy.surfaceHost(for: currentURL) else {
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
        policy: any ProtectionPolicyReading
    ) -> Bool {
        guard existingWebView != nil else { return clearRequirement() }

        let desiredState = desiredAttachmentState(
            for: currentURL,
            policy: policy
        )
        guard desiredState.siteHost != nil,
              let appliedState = appliedAttachmentState,
              appliedState.hasSameEffectiveWebViewAttachment(
                  as: desiredState
              ) == false else {
            return clearRequirement()
        }

        return setRequirement(
            SumiProtectionReloadRequirement(
                siteHost: desiredState.siteHost,
                desiredAttachmentState: desiredState
            )
        )
    }

    @discardableResult
    func clearIfResolved(
        for committedURL: URL,
        policy: any ProtectionPolicyReading
    ) -> Bool {
        guard let requirement else { return false }
        let committedState = desiredAttachmentState(
            for: committedURL,
            policy: policy
        )
        if committedState.siteHost != requirement.siteHost
            || appliedAttachmentState?.hasSameEffectiveWebViewAttachment(
                as: committedState
            ) == true {
            return clearRequirement()
        }
        return false
    }

    func requiresNormalWebViewRebuild(
        for targetURL: URL?,
        existingWebView: WKWebView?,
        webViewConfigurationOverride: WKWebViewConfiguration?,
        isPopupHost: Bool,
        policy: any ProtectionPolicyReading
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

    func recordManualReloadResult(
        rebuiltForConfigurationPolicy: Bool,
        targetURL: URL?,
        policy: any ProtectionPolicyReading
    ) {
        didManualReloadRebuildWebView = rebuiltForConfigurationPolicy
        appliedAfterManualReload = appliedAttachmentState?
            .hasSameEffectiveWebViewAttachment(
                as: desiredAttachmentState(for: targetURL, policy: policy)
            ) == true
    }

    private func setRequirement(
        _ newValue: SumiProtectionReloadRequirement
    ) -> Bool {
        guard requirement != newValue else { return false }
        didManualReloadRebuildWebView = false
        appliedAfterManualReload = false
        requirement = newValue
        return true
    }

    private func clearRequirement() -> Bool {
        guard requirement != nil else { return false }
        requirement = nil
        return true
    }
}

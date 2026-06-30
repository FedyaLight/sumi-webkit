import Foundation
import WebKit

@MainActor
struct TabReloadPolicyWebViewRebuildContext {
    let currentURL: URL
    let existingWebView: () -> WKWebView?
    let webViewConfigurationOverride: WKWebViewConfiguration?
    let isPopupHost: Bool
    let profile: Profile?
    let replacementContext: TabConfigurationPolicyWebViewReplacementContext
    let publishNavigationStateChangeIfNeeded: (Bool) -> Void
}

@MainActor
struct TabReloadPolicyProtectionDiagnosticsContext {
    let currentURL: URL
    let appliedState: SumiProtectionAttachmentState?
    let reloadRequired: Bool
    let reloadRequiredReason: String?
    let didManualReloadRebuildWebView: Bool
    let appliedAfterManualReload: Bool
    let actualAttachedRuleListIdentifiers: [String]?
    let contentBlockingAssetSummary: SumiNormalTabContentBlockingAssetSummary?
    let webViewRebuildDuration: TimeInterval?
    let urlHubSummaryDuration: TimeInterval?
}

@MainActor
struct TabReloadPolicyRuntime {
    let safariContentBlockerAttachmentState: (URL?) -> SumiSafariContentBlockerAttachmentState
    let protectionAttachmentState: (URL?) -> SumiProtectionAttachmentState
    let protectionSurfaceHost: (URL?) -> String?
    let protectionCurrentTabDiagnostics: (TabReloadPolicyProtectionDiagnosticsContext) -> SumiProtectionCurrentTabDiagnostics?
    let evaluateAutoplayPolicyChange: (SumiRuntimeAutoplayState, WKWebView) -> SumiRuntimePermissionOperationResult
}

extension TabReloadPolicyRuntime {
    static let empty = Self(
        safariContentBlockerAttachmentState: { _ in .disabled(siteHost: nil) },
        protectionAttachmentState: { _ in .disabled(siteHost: nil) },
        protectionSurfaceHost: { _ in nil },
        protectionCurrentTabDiagnostics: { _ in nil },
        evaluateAutoplayPolicyChange: { _, _ in .noOp }
    )
}

@MainActor
final class TabReloadPolicyStateOwner {
    private let webViewReplacementOwner: TabConfigurationPolicyWebViewReplacementOwner

    var safariContentBlockerAppliedAttachmentState: SumiSafariContentBlockerAttachmentState?
    var protectionAppliedAttachmentState: SumiProtectionAttachmentState?
    var safariContentBlockerReloadRequirement: SumiSafariContentBlockerReloadRequirement?
    var protectionReloadRequirement: SumiProtectionReloadRequirement?
    var autoplayReloadRequirement: SumiAutoplayReloadRequirement?
    var didManualReloadRebuildProtectionWebView: Bool = false
    var appliedProtectionAfterManualReload: Bool = false
    var lastProtectionWebViewRebuildDuration: TimeInterval?
    var lastProtectionURLHubSummaryDuration: TimeInterval?

    init(
        webViewReplacementOwner: TabConfigurationPolicyWebViewReplacementOwner = TabConfigurationPolicyWebViewReplacementOwner()
    ) {
        self.webViewReplacementOwner = webViewReplacementOwner
    }

    var isSafariContentBlockerReloadRequired: Bool {
        safariContentBlockerReloadRequirement != nil
    }

    var isProtectionReloadRequired: Bool {
        protectionReloadRequirement != nil
    }

    var isAutoplayReloadRequired: Bool {
        autoplayReloadRequirement != nil
    }

    func safariContentBlockerDesiredAttachmentState(
        for targetURL: URL?,
        runtime: TabReloadPolicyRuntime
    ) -> SumiSafariContentBlockerAttachmentState {
        runtime.safariContentBlockerAttachmentState(targetURL)
    }

    func noteSafariContentBlockerAttachmentApplied(
        _ state: SumiSafariContentBlockerAttachmentState
    ) {
        safariContentBlockerAppliedAttachmentState = state
    }

    func protectionDesiredAttachmentState(
        for targetURL: URL?,
        runtime: TabReloadPolicyRuntime
    ) -> SumiProtectionAttachmentState {
        runtime.protectionAttachmentState(targetURL)
    }

    func noteProtectionAttachmentApplied(
        _ state: SumiProtectionAttachmentState
    ) {
        protectionAppliedAttachmentState = state
    }

    @discardableResult
    func markProtectionReloadRequiredIfNeeded(
        afterChangingPolicyFor changedURL: URL?,
        currentURL: URL,
        existingWebView: WKWebView?,
        runtime: TabReloadPolicyRuntime
    ) -> Bool {
        guard let changedHost = runtime.protectionSurfaceHost(changedURL),
              changedHost == runtime.protectionSurfaceHost(currentURL)
        else { return false }

        return updateProtectionReloadRequirementForCurrentSite(
            currentURL: currentURL,
            existingWebView: existingWebView,
            runtime: runtime
        )
    }

    @discardableResult
    func markSafariContentBlockerReloadRequiredIfNeeded(
        afterChangingPolicyFor changedURL: URL?,
        currentURL: URL,
        existingWebView: WKWebView?,
        runtime: TabReloadPolicyRuntime
    ) -> Bool {
        let changedState = safariContentBlockerDesiredAttachmentState(
            for: changedURL,
            runtime: runtime
        )
        let currentState = safariContentBlockerDesiredAttachmentState(
            for: currentURL,
            runtime: runtime
        )
        guard changedState.siteHost != nil,
              changedState.siteHost == currentState.siteHost
        else { return false }

        return updateSafariContentBlockerReloadRequirementForCurrentSite(
            currentURL: currentURL,
            existingWebView: existingWebView,
            runtime: runtime
        )
    }

    @discardableResult
    func updateSafariContentBlockerReloadRequirementForCurrentSite(
        currentURL: URL,
        existingWebView: WKWebView?,
        runtime: TabReloadPolicyRuntime
    ) -> Bool {
        guard existingWebView != nil else {
            return clearSafariContentBlockerReloadRequirement()
        }

        let desiredState = safariContentBlockerDesiredAttachmentState(
            for: currentURL,
            runtime: runtime
        )
        guard desiredState.siteHost != nil
        else {
            return clearSafariContentBlockerReloadRequirement()
        }

        if safariContentBlockerAttachmentIsApplied(desiredState) {
            let updatedAppliedState = noteSafariContentBlockerAttachmentAppliedIfEquivalent(
                to: desiredState
            )
            return clearSafariContentBlockerReloadRequirement() || updatedAppliedState
        }

        guard safariContentBlockerAppliedAttachmentState != nil || desiredState.isEnabled else {
            return clearSafariContentBlockerReloadRequirement()
        }

        return setSafariContentBlockerReloadRequirement(
            SumiSafariContentBlockerReloadRequirement(
                siteHost: desiredState.siteHost,
                desiredAttachmentState: desiredState
            )
        )
    }

    @discardableResult
    func clearSafariContentBlockerReloadRequirementIfResolved(
        for committedURL: URL,
        runtime: TabReloadPolicyRuntime
    ) -> Bool {
        guard let requirement = safariContentBlockerReloadRequirement else { return false }

        let committedState = safariContentBlockerDesiredAttachmentState(
            for: committedURL,
            runtime: runtime
        )
        if committedState.siteHost != requirement.siteHost
            || safariContentBlockerAttachmentIsApplied(committedState) {
            _ = noteSafariContentBlockerAttachmentAppliedIfEquivalent(to: committedState)
            return clearSafariContentBlockerReloadRequirement()
        }

        return false
    }

    @discardableResult
    func updateProtectionReloadRequirementForCurrentSite(
        currentURL: URL,
        existingWebView: WKWebView?,
        runtime: TabReloadPolicyRuntime
    ) -> Bool {
        guard existingWebView != nil else {
            return clearProtectionReloadRequirement()
        }

        let desiredState = protectionDesiredAttachmentState(
            for: currentURL,
            runtime: runtime
        )
        guard desiredState.siteHost != nil,
              let appliedState = protectionAppliedAttachmentState,
              appliedState != desiredState
        else {
            return clearProtectionReloadRequirement()
        }

        return setProtectionReloadRequirement(
            SumiProtectionReloadRequirement(
                siteHost: desiredState.siteHost,
                desiredAttachmentState: desiredState
            )
        )
    }

    @discardableResult
    func clearProtectionReloadRequirementIfResolved(
        for committedURL: URL,
        runtime: TabReloadPolicyRuntime
    ) -> Bool {
        guard let requirement = protectionReloadRequirement else { return false }

        let committedState = protectionDesiredAttachmentState(
            for: committedURL,
            runtime: runtime
        )
        if committedState.siteHost != requirement.siteHost
            || protectionAppliedAttachmentState == committedState {
            return clearProtectionReloadRequirement()
        }

        return false
    }

    func protectionCurrentTabDiagnostics(
        for currentURL: URL,
        existingWebView: WKWebView?,
        runtime: TabReloadPolicyRuntime
    ) -> SumiProtectionCurrentTabDiagnostics? {
        let contentBlockingSummary = existingWebView?
            .configuration
            .userContentController
            .sumiNormalTabUserContentController?
            .contentBlockingAssetSummary
        return runtime.protectionCurrentTabDiagnostics(
            TabReloadPolicyProtectionDiagnosticsContext(
                currentURL: currentURL,
                appliedState: protectionAppliedAttachmentState,
                reloadRequired: isProtectionReloadRequired,
                reloadRequiredReason: protectionReloadRequirement.map { requirement in
                    "desired=\(requirement.desiredAttachmentState.effectiveLevel.rawValue)"
                },
                didManualReloadRebuildWebView: didManualReloadRebuildProtectionWebView,
                appliedAfterManualReload: appliedProtectionAfterManualReload,
                actualAttachedRuleListIdentifiers: contentBlockingSummary?.globalRuleListIdentifiers,
                contentBlockingAssetSummary: contentBlockingSummary,
                webViewRebuildDuration: lastProtectionWebViewRebuildDuration,
                urlHubSummaryDuration: lastProtectionURLHubSummaryDuration
            )
        )
    }

    func protectionAttachmentRequiresNormalWebViewRebuild(
        for targetURL: URL?,
        existingWebView: WKWebView?,
        webViewConfigurationOverride: WKWebViewConfiguration?,
        isPopupHost: Bool,
        runtime: TabReloadPolicyRuntime
    ) -> Bool {
        guard existingWebView != nil,
              webViewConfigurationOverride == nil,
              !isPopupHost
        else { return false }

        let desiredState = protectionDesiredAttachmentState(
            for: targetURL,
            runtime: runtime
        )
        guard let appliedState = protectionAppliedAttachmentState else {
            return desiredState.isEnabled
        }
        return appliedState != desiredState
    }

    func safariContentBlockerAttachmentRequiresNormalWebViewRebuild(
        for targetURL: URL?,
        existingWebView: WKWebView?,
        webViewConfigurationOverride: WKWebViewConfiguration?,
        isPopupHost: Bool,
        runtime: TabReloadPolicyRuntime
    ) -> Bool {
        guard existingWebView != nil,
              webViewConfigurationOverride == nil,
              !isPopupHost
        else { return false }

        let desiredState = safariContentBlockerDesiredAttachmentState(
            for: targetURL,
            runtime: runtime
        )
        guard let appliedState = safariContentBlockerAppliedAttachmentState else {
            return desiredState.isEnabled
        }
        return !appliedState.hasSameEffectiveWebViewAttachment(as: desiredState)
    }

    func noteProtectionManualReloadResult(
        rebuiltForConfigurationPolicy: Bool,
        targetURL: URL?,
        runtime: TabReloadPolicyRuntime
    ) {
        didManualReloadRebuildProtectionWebView = rebuiltForConfigurationPolicy
        appliedProtectionAfterManualReload =
            protectionAppliedAttachmentState == protectionDesiredAttachmentState(
                for: targetURL,
                runtime: runtime
            )
    }

    @discardableResult
    func rebuildNormalWebViewForContentBlockingPolicyIfNeeded(
        targetURL: URL?,
        reason: String,
        runtime: TabReloadPolicyRuntime,
        context: TabReloadPolicyWebViewRebuildContext
    ) -> Bool {
        let requiresProtectionRebuild = protectionAttachmentRequiresNormalWebViewRebuild(
            for: targetURL,
            existingWebView: context.existingWebView(),
            webViewConfigurationOverride: context.webViewConfigurationOverride,
            isPopupHost: context.isPopupHost,
            runtime: runtime
        )
        let requiresSafariContentBlockerRebuild = safariContentBlockerAttachmentRequiresNormalWebViewRebuild(
            for: targetURL,
            existingWebView: context.existingWebView(),
            webViewConfigurationOverride: context.webViewConfigurationOverride,
            isPopupHost: context.isPopupHost,
            runtime: runtime
        )
        guard (requiresProtectionRebuild || requiresSafariContentBlockerRebuild),
              context.existingWebView() != nil
        else { return false }

        let rebuildStart = Date()
        let previousProtectionState = protectionAppliedAttachmentState
        let previousSafariContentBlockerState = safariContentBlockerAppliedAttachmentState

        guard rebuildNormalWebViewForConfigurationPolicy(
            reason: reason,
            context: context,
            onTrackedWebViewRemovalFailure: {
                noteContentBlockingWebViewRebuildFailed(
                    restoringProtectionState: previousProtectionState,
                    restoringSafariContentBlockerState: previousSafariContentBlockerState
                )
            }
        ) else { return false }

        context.publishNavigationStateChangeIfNeeded(
            updateSafariContentBlockerReloadRequirementForCurrentSite(
                currentURL: context.currentURL,
                existingWebView: context.existingWebView(),
                runtime: runtime
            )
        )
        context.publishNavigationStateChangeIfNeeded(
            updateProtectionReloadRequirementForCurrentSite(
                currentURL: context.currentURL,
                existingWebView: context.existingWebView(),
                runtime: runtime
            )
        )
        if requiresProtectionRebuild {
            noteProtectionWebViewRebuildSucceeded(startedAt: rebuildStart)
        }
        context.publishNavigationStateChangeIfNeeded(
            updateAutoplayReloadRequirementForCurrentSite(
                currentURL: context.currentURL,
                existingWebView: context.existingWebView(),
                profile: context.profile,
                runtime: runtime
            )
        )
        return true
    }

    @discardableResult
    func rebuildNormalWebViewForAutoplayIfNeeded(
        targetURL: URL?,
        reason: String,
        runtime: TabReloadPolicyRuntime,
        context: TabReloadPolicyWebViewRebuildContext
    ) -> Bool {
        guard autoplayPolicyRequiresNormalWebViewRebuild(
            for: targetURL,
            existingWebView: context.existingWebView(),
            webViewConfigurationOverride: context.webViewConfigurationOverride,
            isPopupHost: context.isPopupHost,
            profile: context.profile
        ), context.existingWebView() != nil
        else { return false }

        guard rebuildNormalWebViewForConfigurationPolicy(
            reason: reason,
            context: context
        ) else { return false }

        context.publishNavigationStateChangeIfNeeded(
            updateAutoplayReloadRequirementForCurrentSite(
                currentURL: context.currentURL,
                existingWebView: context.existingWebView(),
                profile: context.profile,
                runtime: runtime
            )
        )
        return true
    }

    @discardableResult
    func markAutoplayReloadRequiredIfNeeded(
        afterChangingPolicyFor changedURL: URL?,
        currentURL: URL,
        existingWebView: WKWebView?,
        profile: Profile?,
        runtime: TabReloadPolicyRuntime
    ) -> Bool {
        let changedOrigin = SumiPermissionOrigin(url: changedURL)
        let currentOrigin = SumiPermissionOrigin(url: currentURL)
        guard changedOrigin.isWebOrigin,
              changedOrigin.identity == currentOrigin.identity
        else { return false }

        return updateAutoplayReloadRequirementForCurrentSite(
            currentURL: currentURL,
            existingWebView: existingWebView,
            profile: profile,
            runtime: runtime
        )
    }

    @discardableResult
    func updateAutoplayReloadRequirementForCurrentSite(
        currentURL: URL,
        existingWebView: WKWebView?,
        profile: Profile?,
        runtime: TabReloadPolicyRuntime
    ) -> Bool {
        guard let webView = existingWebView else {
            return clearAutoplayReloadRequirement()
        }

        let desiredPolicy = desiredAutoplayPolicy(for: currentURL, profile: profile)
        let result = runtime.evaluateAutoplayPolicyChange(
            desiredPolicy.runtimeState,
            webView
        )

        guard case .requiresReload(let requirement) = result else {
            return clearAutoplayReloadRequirement()
        }

        return setAutoplayReloadRequirement(
            SumiAutoplayReloadRequirement(
                desiredPolicy: desiredPolicy,
                runtimeRequirement: requirement
            )
        )
    }

    @discardableResult
    func clearAutoplayReloadRequirementIfResolved(
        for committedURL: URL,
        currentURL: URL,
        existingWebView: WKWebView?,
        profile: Profile?,
        runtime: TabReloadPolicyRuntime
    ) -> Bool {
        _ = committedURL
        return updateAutoplayReloadRequirementForCurrentSite(
            currentURL: currentURL,
            existingWebView: existingWebView,
            profile: profile,
            runtime: runtime
        )
    }

    func autoplayPolicyRequiresNormalWebViewRebuild(
        for targetURL: URL?,
        existingWebView: WKWebView?,
        webViewConfigurationOverride: WKWebViewConfiguration?,
        isPopupHost: Bool,
        profile: Profile?
    ) -> Bool {
        guard let webView = existingWebView,
              webViewConfigurationOverride == nil,
              !isPopupHost
        else { return false }

        let desiredPolicy = desiredAutoplayPolicy(for: targetURL, profile: profile)
        let currentState = SumiRuntimePermissionController.autoplayState(
            from: webView.configuration.mediaTypesRequiringUserActionForPlayback
        )
        return currentState != desiredPolicy.runtimeState
    }

    func noteContentBlockingWebViewRebuildFailed(
        restoringProtectionState previousProtectionState: SumiProtectionAttachmentState?,
        restoringSafariContentBlockerState previousSafariContentBlockerState: SumiSafariContentBlockerAttachmentState?
    ) {
        protectionAppliedAttachmentState = previousProtectionState
        safariContentBlockerAppliedAttachmentState = previousSafariContentBlockerState
    }

    func noteProtectionWebViewRebuildSucceeded(startedAt rebuildStart: Date) {
        lastProtectionWebViewRebuildDuration = Date().timeIntervalSince(rebuildStart)
    }

    @discardableResult
    private func rebuildNormalWebViewForConfigurationPolicy(
        reason: String,
        context: TabReloadPolicyWebViewRebuildContext,
        onTrackedWebViewRemovalFailure: () -> Void = {}
    ) -> Bool {
        webViewReplacementOwner.replaceNormalWebView(
            reason: reason,
            context: context.replacementContext,
            onTrackedWebViewRemovalFailure: onTrackedWebViewRemovalFailure
        )
    }

    private func desiredAutoplayPolicy(for targetURL: URL?, profile: Profile?) -> SumiAutoplayPolicy {
        SumiAutoplayPolicyStoreAdapter.shared.effectivePolicy(
            for: targetURL,
            profile: profile
        )
    }

    private func setSafariContentBlockerReloadRequirement(
        _ requirement: SumiSafariContentBlockerReloadRequirement
    ) -> Bool {
        guard safariContentBlockerReloadRequirement != requirement else { return false }
        safariContentBlockerReloadRequirement = requirement
        return true
    }

    private func clearSafariContentBlockerReloadRequirement() -> Bool {
        guard safariContentBlockerReloadRequirement != nil else { return false }
        safariContentBlockerReloadRequirement = nil
        return true
    }

    private func safariContentBlockerAttachmentIsApplied(
        _ desiredState: SumiSafariContentBlockerAttachmentState
    ) -> Bool {
        if let appliedState = safariContentBlockerAppliedAttachmentState {
            return appliedState.hasSameEffectiveWebViewAttachment(as: desiredState)
        }
        return !desiredState.isEnabled
    }

    private func noteSafariContentBlockerAttachmentAppliedIfEquivalent(
        to desiredState: SumiSafariContentBlockerAttachmentState
    ) -> Bool {
        guard safariContentBlockerAttachmentIsApplied(desiredState),
              safariContentBlockerAppliedAttachmentState != desiredState
        else { return false }

        safariContentBlockerAppliedAttachmentState = desiredState
        return true
    }

    private func setProtectionReloadRequirement(
        _ requirement: SumiProtectionReloadRequirement
    ) -> Bool {
        guard protectionReloadRequirement != requirement else { return false }
        didManualReloadRebuildProtectionWebView = false
        appliedProtectionAfterManualReload = false
        lastProtectionWebViewRebuildDuration = nil
        protectionReloadRequirement = requirement
        return true
    }

    private func clearProtectionReloadRequirement() -> Bool {
        guard protectionReloadRequirement != nil else { return false }
        protectionReloadRequirement = nil
        return true
    }

    private func setAutoplayReloadRequirement(
        _ requirement: SumiAutoplayReloadRequirement
    ) -> Bool {
        guard autoplayReloadRequirement != requirement else { return false }
        autoplayReloadRequirement = requirement
        return true
    }

    private func clearAutoplayReloadRequirement() -> Bool {
        guard autoplayReloadRequirement != nil else { return false }
        autoplayReloadRequirement = nil
        return true
    }
}

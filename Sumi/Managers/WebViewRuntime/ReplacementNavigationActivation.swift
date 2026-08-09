import Foundation
import WebKit
import SumiWebRuntime

/// Activates an admitted replacement generation. The settlement receipt is
/// the only authority allowed to report exact navigation submission.
@MainActor
final class ReplacementNavigationActivation {
    struct Runtime {
        let webViewSessions: WebViewSessionRepository
        let pipeline: WebViewReplacementPipeline
        let installTrackedObservations: (WKWebView) -> Void
        let restorePresentation: (UUID, WebViewSessionSnapshot) -> Void
        let pruneDeferredCommands: (String) -> Void
    }

    private let runtime: Runtime

    init(runtime: Runtime) {
        self.runtime = runtime
    }

    func activate(
        _ replacements: [PreparedWebViewReplacement],
        receipt: WebViewReplacementSettlementReceipt,
        reason: String
    ) {
        for replacement in replacements {
            replacement.trackedReplacements.forEach(
                runtime.installTrackedObservations
            )
            prepareExtensionRuntime(replacement, reason: reason)
            scheduleBindings(replacement, receipt: receipt, reason: reason)
        }
        runtime.pruneDeferredCommands("\(reason).replacement-admitted")
        replacements.forEach {
            runtime.restorePresentation($0.tab.id, $0.snapshot)
        }
    }

    func activateWithoutNavigation(
        _ replacements: [PreparedWebViewReplacement],
        reason: String
    ) {
        replacements.forEach {
            prepareExtensionRuntime($0, reason: reason)
        }
    }

    func finishCommitted(
        _ replacements: [PreparedWebViewReplacement],
        reason: String
    ) {
        for replacement in replacements {
            let tab = replacement.tab
            tab.invalidatePermissionPageForReplacement(reason: reason)
            tab.updateSafariContentBlockerReloadRequirementForCurrentSite()
            tab.updateProtectionReloadRequirementForCurrentSite()
            tab.updateAutoplayReloadRequirementForCurrentSite()
        }
    }

    private func prepareExtensionRuntime(
        _ replacement: PreparedWebViewReplacement,
        reason: String
    ) {
        guard replacement.requiresExtensionRuntimePreparation else { return }
        for webView in replacement.replacements {
            replacement.tab.prepareNormalWebViewExtensionRuntime(
                webView,
                targetURL: replacement.targetURL,
                reason: "\(reason).admitted"
            )
        }
    }

    private func scheduleBindings(
        _ replacement: PreparedWebViewReplacement,
        receipt: WebViewReplacementSettlementReceipt,
        reason: String
    ) {
        for webView in replacement.bindingReplacements {
            guard let token = receipt.bindingToken(for: webView) else {
                preconditionFailure("Replacement receipt lost a required binding")
            }
            let binding = NormalTabInitialDocumentRuntimeHandoff
                .ReplacementBinding(
                    token: token,
                    markBound: { [weak self] token, binding in
                        self?.runtime.pipeline.markBound(
                            token,
                            binding: binding
                        ) ?? .ignored
                    },
                    fail: { [weak self] token, failure in
                        self?.runtime.pipeline.fail(token, reason: failure)
                    }
                )
            schedule(
                webView,
                replacement: replacement,
                binding: binding,
                reason: reason
            )
        }
    }

    private func schedule(
        _ webView: WKWebView,
        replacement: PreparedWebViewReplacement,
        binding: NormalTabInitialDocumentRuntimeHandoff.ReplacementBinding,
        reason: String
    ) {
        if case .window(let owner) = runtime.webViewSessions.residence(
            of: webView
        ) {
            NormalTabInitialDocumentRuntimeHandoff.scheduleTrackedInitialLoad(
                tab: replacement.tab,
                webView: webView,
                targetURL: replacement.targetURL,
                expectedOwner: owner,
                profileId: replacement.profileID,
                registrationReason: "\(reason).beforeInitialLoad",
                updatesTabPresentation:
                    owner.windowID == replacement.snapshot.primaryWindowID,
                replacementBinding: binding,
                nativeSessionData: replacement.nativeSessionDataByWebViewID[
                    ObjectIdentifier(webView)
                ]
            )
            return
        }
        NormalTabInitialDocumentRuntimeHandoff.scheduleTabSetupInitialLoad(
            tab: replacement.tab,
            webView: webView,
            targetURL: replacement.targetURL,
            profileId: replacement.profileID,
            registrationReason: "\(reason).beforeInitialLoad",
            replacementBinding: binding,
            nativeSessionData: replacement.nativeSessionDataByWebViewID[
                ObjectIdentifier(webView)
            ]
        )
    }
}

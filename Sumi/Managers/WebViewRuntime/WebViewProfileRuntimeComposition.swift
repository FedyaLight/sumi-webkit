import Foundation
import SumiWebRuntime
import WebKit

@MainActor
enum WebViewProfileRuntimeComposition {
    static func make(
        webViewSessions: WebViewSessionRepository,
        runtimeTabs: WebViewRuntimeTabRegistry,
        resolveRuntimeTab: @escaping WebViewRuntimeTabRegistry.RuntimeTabResolver,
        replacementPipeline: WebViewReplacementPipeline,
        replacementActivation: ReplacementNavigationActivation,
        admissionIsBlocked: @escaping (UUID) -> Bool,
        deferAdmission: @escaping (
            UUID,
            WebsiteDataMutationGate.DeferredAdmissionKey,
            @escaping @MainActor () -> Void
        ) -> Bool,
        isProtected: @escaping (WKWebView) -> Bool,
        preparedIsProtected: @escaping (WKWebView) -> Bool,
        deferProtectedCommand: @escaping (
            DeferredWebViewCommand,
            WKWebView,
            String
        ) -> DeferredProtectedCommandSchedulingOutcome
    ) -> WebViewProfileAssignmentService {
        let transitions = ProfileTransitionService(runtime: .init(
            webViewSessions: webViewSessions,
            admissionIsBlocked: admissionIsBlocked,
            deferAdmission: deferAdmission,
            isProtected: isProtected,
            deferProtectedCommand: deferProtectedCommand,
            provisioning: ProfileReplacementProvisioning(),
            pipeline: replacementPipeline,
            activation: replacementActivation
        ))
        let preparedTransitions = PreparedProfileAssignmentBatchTransitionService(
            runtime: .init(
                webViewSessions: webViewSessions,
                admissionIsBlocked: admissionIsBlocked,
                isProtected: preparedIsProtected,
                provisioning: ProfileReplacementProvisioning(),
                pipeline: replacementPipeline,
                activation: replacementActivation
            )
        )
        return WebViewProfileAssignmentService(
            runtimeTabs: runtimeTabs,
            resolveRuntimeTab: resolveRuntimeTab,
            transitions: transitions,
            preparedTransitions: preparedTransitions,
            replacementPipeline: replacementPipeline
        )
    }
}

import Foundation
import SumiWebRuntime

extension TabWebViewMaterializationService {
    @MainActor
    static func live(
        webViewSessions: WebViewSessionRepository,
        initialDocumentContext: InitialDocumentWebViewRuntimeContext,
        placement: CanonicalWebViewPlacementService,
        visibleRuntime: VisibleWebViewRuntimeProvider,
        windowServices: WebViewWindowServices,
        planner: WebViewCreationPlanner
    ) -> TabWebViewMaterializationService {
        TabWebViewMaterializationService(
            runtime: .init(
                webViewSessions: webViewSessions,
                initialDocumentWarmup: {
                    InitialDocumentWarmupRuntime(
                        needsInitialDocumentExtensionContextLoad:
                            initialDocumentContext
                                .needsInitialDocumentExtensionContextLoad,
                        ensureInitialExtensionContextsLoaded:
                            initialDocumentContext
                                .ensureInitialExtensionContextsLoaded,
                        refreshCompositorForWindow:
                            initialDocumentContext.refreshCompositorForWindow
                    )
                },
                placement: placement,
                primaryCandidate: visibleRuntime.preferredPrimaryCandidate,
                notifyActivatedIfCurrent:
                    windowServices.notifyTabActivatedIfCurrent
            ),
            planner: planner
        )
    }
}

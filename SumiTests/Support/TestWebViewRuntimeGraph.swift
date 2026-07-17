import Foundation
import SumiWebRuntime

@testable import Sumi

/// Composes an isolated WebView runtime for tests from the same exact
/// capabilities as production. Defaults are deliberately inert and fail
/// closed; tests opt into browser behavior by overriding only the capability
/// they exercise.
@MainActor
func makeTestWebViewRuntimeGraph(
    webViewSessions: WebViewSessionRepository = WebViewSessionRepository(),
    resolveRuntimeTab: @escaping @MainActor @Sendable (UUID) -> Tab? = { _ in nil },
    resolveCollectionTab: (@MainActor (UUID) -> Tab?)? = nil,
    windowServices: WebViewWindowServices? = nil,
    deferredServices: DeferredWebViewServices? = nil,
    visibleContext: WebViewVisibleRuntimeContext? = nil,
    initialDocumentContext: InitialDocumentWebViewRuntimeContext? = nil,
    profileReferenceAdmission: ProfileReferenceAdmissionLedger = .failClosed()
) -> WebViewRuntimeGraph {
    WebViewRuntimeGraph(
        webViewSessions: webViewSessions,
        resolveRuntimeTab: resolveRuntimeTab,
        resolveCollectionTab: resolveCollectionTab ?? resolveRuntimeTab,
        windowServices: windowServices ?? WebViewWindowServices(
            liveWindowIDs: { [] },
            containsWindow: { _ in false },
            currentTabID: { _ in nil },
            selectTab: { _, _ in },
            refreshCompositor: { _ in },
            notifyTabActivatedIfCurrent: { _, _ in }
        ),
        deferredServices: deferredServices ?? DeferredWebViewServices(
            handleWebKitClose: { _ in false },
            executeProfileAssignment: { _, _, _ in false },
            validateSpaceProfileAssignment: { _ in false },
            executeSpaceProfileAssignment: { _ in false }
        ),
        visibleContext: visibleContext ?? WebViewVisibleRuntimeContext(
            windowState: { _ in nil },
            currentTabId: { _ in nil },
            splitVisibleTabIds: { _ in [] },
            resolveTab: { _, _ in nil },
            canMaterializeWebViewDuringStartup: { _, _ in false },
            markTabAccessed: { _ in },
            globallyVisibleTabIDs: { [] },
            scheduleTabSuspensionReconcile: { _ in },
            scheduleBackgroundMediaReconcile: { _ in },
            refreshCompositor: { _ in }
        ),
        initialDocumentContext: initialDocumentContext
            ?? InitialDocumentWebViewRuntimeContext(
                needsInitialDocumentExtensionContextLoad: { _ in false },
                ensureInitialExtensionContextsLoaded: { _ in },
                refreshCompositorForWindow: { _ in }
            ),
        profileReferenceAdmission: profileReferenceAdmission
    )
}

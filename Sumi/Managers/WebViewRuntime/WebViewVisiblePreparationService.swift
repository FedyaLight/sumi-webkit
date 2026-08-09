import Foundation
import SumiWebRuntime

/// Joins visibility planning to the two narrow ownership capabilities.
/// Materialization occurs only for tabs selected by the native visibility plan.
@MainActor
final class WebViewVisiblePreparationService {
    typealias RegularTabResolver = @MainActor (UUID) -> Tab?
    typealias RecoveryActivation = @MainActor (UUID, UUID) -> Void

    private let visibility: WebViewVisibilityRuntime
    private let webViewSessions: WebViewSessionRepository
    private let ownershipQuery: WebViewOwnershipQuery
    private let trackedAdmission: TrackedWebViewAdmissionService
    private let regularTab: RegularTabResolver
    private let activateRecovery: RecoveryActivation

    init(
        visibility: WebViewVisibilityRuntime,
        webViewSessions: WebViewSessionRepository,
        ownershipQuery: WebViewOwnershipQuery,
        trackedAdmission: TrackedWebViewAdmissionService,
        regularTab: @escaping RegularTabResolver,
        activateRecovery: @escaping RecoveryActivation = { _, _ in }
    ) {
        self.visibility = visibility
        self.webViewSessions = webViewSessions
        self.ownershipQuery = ownershipQuery
        self.trackedAdmission = trackedAdmission
        self.regularTab = regularTab
        self.activateRecovery = activateRecovery
    }

    @discardableResult
    func prepare(for windowState: BrowserWindowState) -> Bool {
        prepare(
            for: windowState,
            runtime: visibility.visiblePreparationRuntime()
        )
    }

    @discardableResult
    func prepare(
        for windowState: BrowserWindowState,
        runtime: VisibleWebViewPreparationRuntime
    ) -> Bool {
        let prepared = visibility.prepareVisibleWebViews(
            for: windowState,
            runtime: runtime,
            webViewSessions: webViewSessions,
            existingWebView: { [ownershipQuery] tabID, windowID in
                ownershipQuery.webView(for: tabID, in: windowID)
            },
            createWebView: { [regularTab, trackedAdmission] tabHandle, windowHandle in
                guard windowHandle === windowState,
                      let tab = resolveVisibleTab(
                        matching: tabHandle,
                        in: windowState,
                        regularTab: regularTab
                      ) else {
                    return nil
                }
                return trackedAdmission.webView(for: tab, in: windowState.id)
            }
        )
        for tabID in visibility.visibleTabIDs(in: windowState.id) {
            activateRecovery(tabID, windowState.id)
        }
        return prepared
    }

    func schedule(for windowState: BrowserWindowState) {
        let runtime = visibility.visiblePreparationRuntime()
        visibility.schedulePrepareVisibleWebViews(
            for: windowState,
            runtime: runtime,
            prepare: { [weak self, weak windowState] windowHandle in
                guard let self, let windowState,
                      windowHandle === windowState else {
                    return false
                }
                return self.prepare(for: windowState, runtime: runtime)
            }
        )
    }
}

@MainActor
func resolveVisibleTab(
    _ tabID: UUID,
    in windowState: BrowserWindowState,
    regularTab: WebViewVisiblePreparationService.RegularTabResolver
) -> Tab? {
    if windowState.isIncognito {
        return windowState.ephemeralTabs.first { $0.id == tabID }
    }
    return regularTab(tabID)
}

@MainActor
func resolveVisibleTab(
    matching handle: any WebRuntimeTabHandle,
    in windowState: BrowserWindowState,
    regularTab: WebViewVisiblePreparationService.RegularTabResolver
) -> Tab? {
    guard let tab = resolveVisibleTab(
        handle.id,
        in: windowState,
        regularTab: regularTab
    ), tab === handle else {
        return nil
    }
    return tab
}

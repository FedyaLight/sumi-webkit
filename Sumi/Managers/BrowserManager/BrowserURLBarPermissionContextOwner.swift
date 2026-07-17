import Combine
import SumiDomain

@MainActor
final class BrowserURLBarPermissionContextOwner {
    private let runtime: BrowserManagerPermissionRuntime
    private let webViews: BrowserWebViewRoutingService

    init(
        runtime: BrowserManagerPermissionRuntime,
        webViews: BrowserWebViewRoutingService
    ) {
        self.runtime = runtime
        self.webViews = webViews
    }

    var context: URLBarPermissionContext {
        URLBarPermissionContext(
            coordinator: runtime.permissionCoordinator,
            runtimeController: runtime.runtimePermissionController,
            popupStore: runtime.blockedPopupStore,
            externalSchemeStore: runtime.externalSchemeSessionStore,
            indicatorEventStore: runtime.permissionIndicatorEventStore,
            systemPermissionService: runtime.systemPermissionService,
            externalAppResolver: runtime.externalAppResolver,
            siteActivityRevision: { [runtime] in
                runtime.permissionSiteActivityStore.revision
            },
            updateIndicator: { [webViews] viewModel, tab, windowState in
                viewModel.update(
                    tab: tab,
                    webView: webViews.windowOwnedWebView(
                        for: tab,
                        in: windowState.id
                    )
                )
            },
            updatePrompt: { presenter, tab, windowState in
                presenter.update(tab: tab, windowState: windowState)
            }
        )
    }

    var loadDependencies: SumiCurrentSitePermissionsViewModel.LoadDependencies {
        SumiCurrentSitePermissionsViewModel.LoadDependencies(
            coordinator: runtime.permissionCoordinator,
            systemPermissionService: runtime.systemPermissionService,
            runtimeController: runtime.runtimePermissionController,
            autoplayStore: runtime.autoplayStore,
            blockedPopupStore: runtime.blockedPopupStore,
            externalSchemeSessionStore: runtime.externalSchemeSessionStore,
            indicatorEventStore: runtime.permissionIndicatorEventStore,
            siteActivityStore: runtime.permissionSiteActivityStore
        )
    }

    var blockedPopupChanges: AnyPublisher<Void, Never> {
        runtime.blockedPopupStore.objectWillChange.eraseVoid()
    }

    var externalSchemeChanges: AnyPublisher<Void, Never> {
        runtime.externalSchemeSessionStore.objectWillChange.eraseVoid()
    }

    var indicatorEventChanges: AnyPublisher<Void, Never> {
        runtime.permissionIndicatorEventStore.objectWillChange.eraseVoid()
    }

    var siteActivityChanges: AnyPublisher<Void, Never> {
        runtime.permissionSiteActivityStore.objectWillChange.eraseVoid()
    }
}

private extension Publisher where Failure == Never {
    func eraseVoid() -> AnyPublisher<Void, Never> {
        map { _ in () }.eraseToAnyPublisher()
    }
}

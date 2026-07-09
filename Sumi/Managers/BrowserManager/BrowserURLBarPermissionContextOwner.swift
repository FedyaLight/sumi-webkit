import Combine

@MainActor
final class BrowserURLBarPermissionContextOwner {
    private let permissionRuntime: @MainActor () -> BrowserManagerPermissionRuntime
    private let siteActivityRevision: @MainActor () -> Int
    private let updateIndicator: @MainActor (SumiPermissionIndicatorViewModel, Tab, BrowserWindowState) -> Void
    private let updatePrompt: @MainActor (SumiPermissionPromptPresenter, Tab, BrowserWindowState) -> Void

    init(
        permissionRuntime: @escaping @MainActor () -> BrowserManagerPermissionRuntime,
        siteActivityRevision: @escaping @MainActor () -> Int,
        updateIndicator: @escaping @MainActor (SumiPermissionIndicatorViewModel, Tab, BrowserWindowState) -> Void,
        updatePrompt: @escaping @MainActor (SumiPermissionPromptPresenter, Tab, BrowserWindowState) -> Void
    ) {
        self.permissionRuntime = permissionRuntime
        self.siteActivityRevision = siteActivityRevision
        self.updateIndicator = updateIndicator
        self.updatePrompt = updatePrompt
    }

    var context: URLBarPermissionContext {
        let runtime = permissionRuntime()
        return URLBarPermissionContext(
            coordinator: runtime.permissionCoordinator,
            runtimeController: runtime.runtimePermissionController,
            popupStore: runtime.blockedPopupStore,
            externalSchemeStore: runtime.externalSchemeSessionStore,
            indicatorEventStore: runtime.permissionIndicatorEventStore,
            systemPermissionService: runtime.systemPermissionService,
            externalAppResolver: runtime.externalAppResolver,
            siteActivityRevision: siteActivityRevision,
            updateIndicator: updateIndicator,
            updatePrompt: updatePrompt
        )
    }

    var loadDependencies: SumiCurrentSitePermissionsViewModel.LoadDependencies {
        let runtime = permissionRuntime()
        return SumiCurrentSitePermissionsViewModel.LoadDependencies(
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
        permissionRuntime().blockedPopupStore.objectWillChange.eraseVoid()
    }

    var externalSchemeChanges: AnyPublisher<Void, Never> {
        permissionRuntime().externalSchemeSessionStore.objectWillChange.eraseVoid()
    }

    var indicatorEventChanges: AnyPublisher<Void, Never> {
        permissionRuntime().permissionIndicatorEventStore.objectWillChange.eraseVoid()
    }

    var siteActivityChanges: AnyPublisher<Void, Never> {
        permissionRuntime().permissionSiteActivityStore.objectWillChange.eraseVoid()
    }
}

@MainActor
extension BrowserURLBarPermissionContextOwner {
    convenience init(browserManager: BrowserManager) {
        let permissionRuntime = browserManager.permissionRuntime
        self.init(
            permissionRuntime: {
                permissionRuntime
            },
            siteActivityRevision: { [weak browserManager] in
                browserManager?.permissionRuntime.permissionSiteActivityStore.revision ?? 0
            },
            updateIndicator: { [weak browserManager] viewModel, tab, windowState in
                guard let browserManager else { return }
                let webView = browserManager.webViewRoutingService.windowOwnedWebView(for: tab, in: windowState.id)
                viewModel.update(
                    tab: tab,
                    webView: webView
                )
            },
            updatePrompt: { presenter, tab, windowState in
                presenter.update(
                    tab: tab,
                    windowState: windowState
                )
            }
        )
    }
}

private extension Publisher where Failure == Never {
    func eraseVoid() -> AnyPublisher<Void, Never> {
        map { _ in () }.eraseToAnyPublisher()
    }
}

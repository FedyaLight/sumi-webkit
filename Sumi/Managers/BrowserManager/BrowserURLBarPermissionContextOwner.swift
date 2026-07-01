import Combine

@MainActor
final class BrowserURLBarPermissionContextOwner {
    struct Dependencies {
        let permissionRuntime: @MainActor () -> BrowserManagerPermissionRuntime
        let siteActivityRevision: @MainActor () -> Int
        let updateIndicator: @MainActor (SumiPermissionIndicatorViewModel, Tab, BrowserWindowState) -> Void
        let updatePrompt: @MainActor (SumiPermissionPromptPresenter, Tab, BrowserWindowState) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    var context: URLBarPermissionContext {
        let runtime = dependencies.permissionRuntime()
        return URLBarPermissionContext(
            coordinator: runtime.permissionCoordinator,
            runtimeController: runtime.runtimePermissionController,
            popupStore: runtime.blockedPopupStore,
            externalSchemeStore: runtime.externalSchemeSessionStore,
            indicatorEventStore: runtime.permissionIndicatorEventStore,
            systemPermissionService: runtime.systemPermissionService,
            externalAppResolver: runtime.externalAppResolver,
            siteActivityRevision: dependencies.siteActivityRevision,
            updateIndicator: dependencies.updateIndicator,
            updatePrompt: dependencies.updatePrompt
        )
    }

    var loadDependencies: SumiCurrentSitePermissionsViewModel.LoadDependencies {
        let runtime = dependencies.permissionRuntime()
        return SumiCurrentSitePermissionsViewModel.LoadDependencies(
            coordinator: runtime.permissionCoordinator,
            systemPermissionService: runtime.systemPermissionService,
            runtimeController: runtime.runtimePermissionController,
            autoplayStore: SumiAutoplayPolicyStoreAdapter.shared,
            blockedPopupStore: runtime.blockedPopupStore,
            externalSchemeSessionStore: runtime.externalSchemeSessionStore,
            indicatorEventStore: runtime.permissionIndicatorEventStore,
            siteActivityStore: runtime.permissionSiteActivityStore
        )
    }

    var blockedPopupChanges: AnyPublisher<Void, Never> {
        dependencies.permissionRuntime().blockedPopupStore.objectWillChange.eraseVoid()
    }

    var externalSchemeChanges: AnyPublisher<Void, Never> {
        dependencies.permissionRuntime().externalSchemeSessionStore.objectWillChange.eraseVoid()
    }

    var indicatorEventChanges: AnyPublisher<Void, Never> {
        dependencies.permissionRuntime().permissionIndicatorEventStore.objectWillChange.eraseVoid()
    }

    var siteActivityChanges: AnyPublisher<Void, Never> {
        dependencies.permissionRuntime().permissionSiteActivityStore.objectWillChange.eraseVoid()
    }
}

extension BrowserURLBarPermissionContextOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        let permissionRuntime = browserManager.permissionRuntime
        return Self(
            permissionRuntime: {
                permissionRuntime
            },
            siteActivityRevision: { [weak browserManager] in
                browserManager?.permissionRuntime.permissionSiteActivityStore.revision ?? 0
            },
            updateIndicator: { [weak browserManager] viewModel, tab, windowState in
                guard let browserManager else { return }
                let webView = browserManager.windowOwnedWebView(for: tab, in: windowState.id)
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

import Foundation

@MainActor
final class TabRuntimePreparationOwner {
    struct Dependencies {
        let runtimeContext: @MainActor () -> TabManagerRuntimeContext?
        let settings: @MainActor () -> SumiSettingsService?
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func prepare(_ tab: Tab) {
        let runtimeContext = dependencies.runtimeContext()
        runtimeContext?.webViewLifecycle.prepareTab(tab)

        if tab.sumiSettings == nil {
            tab.sumiSettings = dependencies.settings() ?? runtimeContext?.settings
        }
    }
}

extension TabRuntimePreparationOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            runtimeContext: { [weak tabManager] in
                tabManager?.runtimeContext
            },
            settings: { [weak tabManager] in
                tabManager?.sumiSettings
            }
        )
    }
}

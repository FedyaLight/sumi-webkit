import Foundation

@MainActor
final class TabRuntimePreparationOwner {
    private let runtimeContext: @MainActor () -> TabManagerRuntimeContext?
    private let settings: @MainActor () -> SumiSettingsService?

    init(
        runtimeContext: @escaping @MainActor () -> TabManagerRuntimeContext?,
        settings: @escaping @MainActor () -> SumiSettingsService?
    ) {
        self.runtimeContext = runtimeContext
        self.settings = settings
    }

    func prepare(_ tab: Tab) {
        let runtimeContext = runtimeContext()
        runtimeContext?.webViewLifecycle.prepareTab(tab)

        if tab.sumiSettings == nil {
            tab.sumiSettings = settings() ?? runtimeContext?.settings
        }
    }
}

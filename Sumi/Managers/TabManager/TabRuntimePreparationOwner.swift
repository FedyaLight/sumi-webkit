import Foundation

@MainActor
final class TabRuntimePreparationOwner {
    private let runtimePorts: @MainActor () -> RuntimePortRegistry?
    private let settings: @MainActor () -> SumiSettingsService?

    init(
        runtimePorts: @escaping @MainActor () -> RuntimePortRegistry?,
        settings: @escaping @MainActor () -> SumiSettingsService?
    ) {
        self.runtimePorts = runtimePorts
        self.settings = settings
    }

    func prepare(_ tab: Tab) {
        let ports = runtimePorts()
        ports?.webViewLifecycle.prepareTab(tab)

        if tab.sumiSettings == nil {
            tab.sumiSettings = settings() ?? ports?.settings
        }
    }
}

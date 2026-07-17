import Foundation

@MainActor
final class TabEphemeralLifecycleOwner {
    private let runtimePreparation: TabRuntimePreparationOwner
    private let tabFactory: TabFactory

    init(
        runtimePreparation: TabRuntimePreparationOwner,
        tabFactory: TabFactory
    ) {
        self.runtimePreparation = runtimePreparation
        self.tabFactory = tabFactory
    }

    @discardableResult
    func createEphemeralTab(
        url: URL,
        in windowState: BrowserWindowState,
        profile: Profile
    ) -> Tab {
        let nextIndex = windowState.ephemeralTabs.map(\.index).max().map { $0 + 1 } ?? 0
        let newTab = tabFactory.makeTab(
            url: url,
            name: url.host ?? "New Tab",
            favicon: "globe",
            spaceId: nil,
            index: nextIndex
        )
        newTab.profileId = profile.id
        _ = runtimePreparation.prepare(newTab)

        windowState.appendEphemeralTab(newTab)
        windowState.currentTabId = newTab.id

        RuntimeDiagnostics.emit("🔒 [TabEphemeralLifecycleOwner] Created ephemeral tab: \(newTab.id) in window: \(windowState.id)")

        return newTab
    }
}

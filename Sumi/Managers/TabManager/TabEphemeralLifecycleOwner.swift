import Foundation

@MainActor
final class TabEphemeralLifecycleOwner {
    private let prepareTabForRuntime: @MainActor (Tab) -> Void
    private let tabFactory: TabFactory

    init(
        prepareTabForRuntime: @escaping @MainActor (Tab) -> Void,
        tabFactory: TabFactory
    ) {
        self.prepareTabForRuntime = prepareTabForRuntime
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
        prepareTabForRuntime(newTab)

        windowState.appendEphemeralTab(newTab)
        windowState.currentTabId = newTab.id

        RuntimeDiagnostics.emit("🔒 [TabEphemeralLifecycleOwner] Created ephemeral tab: \(newTab.id) in window: \(windowState.id)")

        return newTab
    }
}

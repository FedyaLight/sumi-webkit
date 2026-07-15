import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionNormalWindowSelection {
    let window: BrowserWindowState
    let tab: Tab
    let tabID: UUID
    let profileID: UUID
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalWindowSelectionResolver {
    private let windows: any ExtensionWindowQuery
    private let tabProfiles: any ExtensionTabProfileResolving
    private let windowProfileID: @MainActor (BrowserWindowState) -> UUID?
    private let preparedTabs: ExtensionPreparedNormalTabQuery

    init(
        windows: any ExtensionWindowQuery,
        tabProfiles: any ExtensionTabProfileResolving,
        windowProfileID: @escaping @MainActor (BrowserWindowState) -> UUID?,
        preparedTabs: ExtensionPreparedNormalTabQuery
    ) {
        self.windows = windows
        self.tabProfiles = tabProfiles
        self.windowProfileID = windowProfileID
        self.preparedTabs = preparedTabs
    }

    func resolve(
        _ window: BrowserWindowState
    ) -> ExtensionNormalWindowSelection? {
        guard windows.extensionWindowState(for: window.id) === window,
              window.isIncognito == false,
              let tabID = window.currentTabId,
              let tab = windows.currentExtensionTab(in: window),
              tab.id == tabID,
              tab.isEphemeral == false,
              let profileID = windowProfileID(window),
              tabProfiles.profileID(for: tab) == profileID,
              preparedTabs.containsPreparedTab(tab)
        else { return nil }
        return ExtensionNormalWindowSelection(
            window: window,
            tab: tab,
            tabID: tabID,
            profileID: profileID
        )
    }
}

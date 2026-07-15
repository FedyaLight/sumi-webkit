import Foundation

/// Revalidates only browser-owned window, Tab, and profile identity.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalWindowBrowserIdentityValidator {
    private let windowQuery: any ExtensionWindowQuery
    private let tabQuery: any ExtensionTabQuery
    private let profiles: any ExtensionTabProfileResolving
    private let windowProfileID: @MainActor (BrowserWindowState) -> UUID?

    init(
        windowQuery: any ExtensionWindowQuery,
        tabQuery: any ExtensionTabQuery,
        profiles: any ExtensionTabProfileResolving,
        windowProfileID: @escaping @MainActor (BrowserWindowState) -> UUID?
    ) {
        self.windowQuery = windowQuery
        self.tabQuery = tabQuery
        self.profiles = profiles
        self.windowProfileID = windowProfileID
    }

    func validate(
        _ projection: ExtensionNormalWindowProjection,
        for window: BrowserWindowState
    ) -> Tab? {
        guard projection.windowIdentity == ObjectIdentifier(window),
              windowQuery.extensionWindowState(for: window.id) === window,
              window.currentTabId == projection.selectedTabID,
              let selectedTab = windowQuery.currentExtensionTab(in: window),
              selectedTab.id == projection.selectedTabID,
              ObjectIdentifier(selectedTab) == projection.selectedTabIdentity,
              windowProfileID(window) == projection.profileID,
              profiles.profileID(for: selectedTab) == projection.profileID,
              projection.windowAdapter.represents(window)
        else { return nil }
        return selectedTab
    }

    func preferredWindow(for tab: Tab) -> BrowserWindowState? {
        guard let window = windowQuery.preferredExtensionWindowState(
                  containing: tab
              ),
              windowQuery.extensionWindowState(for: window.id) === window
        else { return nil }
        return window
    }

    func isExactRegistered(_ window: BrowserWindowState) -> Bool {
        windowQuery.extensionWindowState(for: window.id) === window
    }

    func profileID(for tab: Tab) -> UUID? {
        profiles.profileID(for: tab)
    }

    func canPublishWithoutNormalWindow(_ tab: Tab) -> Bool {
        tabQuery.isTransientExtensionTab(tab)
            && tabQuery.isAuxiliaryMiniWindowTab(tab) == false
    }
}

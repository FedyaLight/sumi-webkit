import SumiWebRuntime

/// Resolves the selected tab without widening the sidebar boundary to the
/// complete shell runtime.
@MainActor
final class SidebarExtensionActionTabQuery {
    private let windowTabs: BrowserWindowTabContext
    private let membership: TabCollectionMembershipOwner
    private let selection: ShellSelectionService
    private let tabStore: DefaultTabRuntimeStore

    init(
        windowTabs: BrowserWindowTabContext,
        membership: TabCollectionMembershipOwner,
        selection: ShellSelectionService,
        tabStore: DefaultTabRuntimeStore
    ) {
        self.windowTabs = windowTabs
        self.membership = membership
        self.selection = selection
        self.tabStore = tabStore
    }

    func currentTab(in windowState: BrowserWindowState) -> Tab? {
        windowTabs.currentTab(for: windowState)
            ?? windowState.currentTabId.flatMap(membership.tab(for:))
            ?? selection.currentTab(
                for: windowState,
                tabStore: tabStore
            )
    }
}

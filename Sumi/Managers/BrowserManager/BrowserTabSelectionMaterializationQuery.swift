import Foundation

@MainActor
final class BrowserTabSelectionMaterializationQuery {
    private let state: BrowserTabSelectionStateApplication
    private let splitQuery: WindowSplitQuery
    private let membership: TabCollectionMembershipOwner

    init(
        state: BrowserTabSelectionStateApplication,
        splitQuery: WindowSplitQuery,
        membership: TabCollectionMembershipOwner
    ) {
        self.state = state
        self.splitQuery = splitQuery
        self.membership = membership
    }

    func visibleTabs(
        including selected: Tab,
        in windowState: BrowserWindowState
    ) -> [Tab] {
        let visibleIDs = splitQuery.visibleTabIDs(in: windowState.id)
        guard visibleIDs.isEmpty == false else { return [selected] }
        var tabs = visibleIDs.compactMap {
            tab($0, in: windowState)
        }
        if tabs.contains(where: { $0 === selected }) == false {
            tabs.append(selected)
        }
        return tabs
    }

    func tab(
        _ tabID: UUID,
        in windowState: BrowserWindowState
    ) -> Tab? {
        if windowState.isIncognito {
            return windowState.ephemeralTabs.first { $0.id == tabID }
        }
        return membership.tab(for: tabID)
    }

    func isVisible(_ tab: Tab, in windowState: BrowserWindowState) -> Bool {
        guard let selected = state.currentTab(in: windowState) else {
            return false
        }
        return visibleTabs(including: selected, in: windowState)
            .contains { $0 === tab }
    }
}

import Foundation
import SumiDomain

struct ShortcutHostedSplitUnloadPlan {
    let pinIDs: Set<UUID>
    let targetWindowState: BrowserWindowShortcutMutationState
    let replacesPresentation: Bool
}

/// Admits a hosted split unload and projects the exact window state that the
/// retirement transaction must publish. Background groups preserve the current
/// presentation; the presented group hands off to a regular tab or empty state.
@MainActor
final class ShortcutHostedSplitUnloadPlanner {
    private let runtimeConnection: TabRuntimePortConnection
    private let groups: SplitGroupStore
    private let spaces: TabSpaceCollectionStateOwner
    private let regularTabs: RegularTabCollectionOwner
    private let splitMembership: SplitGroupMembershipQuery

    init(
        runtimeConnection: TabRuntimePortConnection,
        groups: SplitGroupStore,
        spaces: TabSpaceCollectionStateOwner,
        regularTabs: RegularTabCollectionOwner,
        splitMembership: SplitGroupMembershipQuery
    ) {
        self.runtimeConnection = runtimeConnection
        self.groups = groups
        self.spaces = spaces
        self.regularTabs = regularTabs
        self.splitMembership = splitMembership
    }

    func plan(
        group: SumiDomain.SplitGroup,
        in windowState: BrowserWindowState
    ) -> ShortcutHostedSplitUnloadPlan? {
        guard runtimeConnection.current != nil,
              group.container.isShortcutSidebar,
              groups.group(id: group.id) == group
        else { return nil }

        let pinIDs = Set(group.memberIDs.compactMap { memberID -> UUID? in
            guard case .shortcutPin(let pinID) = memberID else { return nil }
            return pinID
        })
        guard pinIDs.count == group.memberIDs.count else { return nil }

        let replacesPresentation =
            windowState.splitSelection?.groupID == group.id
            || windowState.currentShortcutPinId.map(pinIDs.contains) == true
        var target = windowState.unpublishedShortcutMutationState
        if replacesPresentation {
            applyFallback(to: &target, in: windowState)
        }
        return ShortcutHostedSplitUnloadPlan(
            pinIDs: pinIDs,
            targetWindowState: target,
            replacesPresentation: replacesPresentation
        )
    }

    private func applyFallback(
        to target: inout BrowserWindowShortcutMutationState,
        in windowState: BrowserWindowState
    ) {
        target.splitSelection = nil
        if let fallback = visibleRegularTab(in: windowState) {
            _ = WindowTabSelectionStateApplicator.applyFallback(
                fallback,
                to: &target,
                splitMembership: splitMembership,
                updateSpaceFromTab: true,
                rememberSelection: true
            )
        } else {
            target.currentTabId = nil
            target.currentShortcutPinId = nil
            target.currentShortcutPinRole = nil
            target.isShowingEmptyState = true
        }
    }

    private func visibleRegularTab(in windowState: BrowserWindowState) -> Tab? {
        guard let spaceID = windowState.currentSpaceId,
              let space = spaces.space(with: spaceID)
        else { return nil }
        return regularTabs.tabs(in: space).first
    }
}

import SumiDomain

@MainActor
enum ShortcutLiveRetirementSplitWindowProjection {
    static func reconcile(
        _ update: ShortcutLiveRetirementWindowProjection.Update,
        windowID: UUID,
        sourceGroups: [SumiDomain.SplitGroup],
        replacementGroups: [SumiDomain.SplitGroup],
        deletedPinIDs: Set<UUID>,
        registry: LiveShortcutTabRegistry
    ) -> ShortcutLiveRetirementWindowProjection.Update {
        guard let selection = update.target.splitSelection,
              let source = sourceGroups.first(where: {
                  $0.id == selection.groupID
              }), source.memberIDs.contains(where: {
                  guard case .shortcutPin(let pinID) = $0 else { return false }
                  return deletedPinIDs.contains(pinID)
              }) else { return update }
        let replacement = replacementGroups.first { $0.id == source.id }
        let active: SplitMemberID? = (
            replacement?.contains(selection.activeMemberID) == true
                ? selection.activeMemberID : nil
        ) ?? replacement?.memberIDs.first ?? source.memberIDs.first {
            guard case .shortcutPin(let pinID) = $0 else { return true }
            return deletedPinIDs.contains(pinID) == false
        }
        var target = update.target
        target.splitSelection = replacement.flatMap { group in
            active.map { WindowSplitSelection(
                groupID: group.id, activeMemberID: $0
            ) }
        }
        apply(active, windowID: windowID, registry: registry, to: &target)
        return .init(
            target: target,
            didClearCurrentSelection: update.didClearCurrentSelection,
            requiresPersistence: update.requiresPersistence
                || target != update.target
        )
    }

    static func targetIsValid(
        _ state: BrowserWindowShortcutMutationState,
        replacementGroups: [SumiDomain.SplitGroup],
        deletedPinIDs: Set<UUID>
    ) -> Bool {
        guard let selection = state.splitSelection else { return true }
        guard let group = replacementGroups.first(where: {
            $0.id == selection.groupID
        }), group.contains(selection.activeMemberID) else { return false }
        return group.memberIDs.allSatisfy { member in
            guard case .shortcutPin(let pinID) = member else { return true }
            return deletedPinIDs.contains(pinID) == false
        }
    }

    private static func apply(
        _ member: SplitMemberID?,
        windowID: UUID,
        registry: LiveShortcutTabRegistry,
        to state: inout BrowserWindowShortcutMutationState
    ) {
        switch member {
        case .regularTab(let tabID):
            state.currentTabId = tabID
            state.currentShortcutPinId = nil
            state.currentShortcutPinRole = nil
            state.isShowingEmptyState = false
        case .shortcutPin(let pinID):
            guard let tab = registry.tab(for: pinID, in: windowID) else {
                state.currentTabId = nil
                state.currentShortcutPinId = nil
                state.currentShortcutPinRole = nil
                state.isShowingEmptyState = true
                return
            }
            state.currentTabId = tab.id
            state.currentShortcutPinId = pinID
            state.currentShortcutPinRole = tab.shortcutPinRole
            state.isShowingEmptyState = false
        case nil:
            state.currentTabId = nil
            state.currentShortcutPinId = nil
            state.currentShortcutPinRole = nil
            state.isShowingEmptyState = true
        }
    }
}

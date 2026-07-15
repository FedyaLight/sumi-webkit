import Foundation

enum ShortcutLiveRetirementWindowPostcondition {
    static func excludesCurrentReferences(
        pinIDs: Set<UUID>,
        tabIDs: Set<UUID>,
        from state: BrowserWindowShortcutMutationState
    ) -> Bool {
        referencesCurrentSelection(
            pinIDs: pinIDs, tabIDs: tabIDs, in: state
        ) == false
    }

    static func referencesCurrentSelection(
        pinIDs: Set<UUID>,
        tabIDs: Set<UUID>,
        in state: BrowserWindowShortcutMutationState
    ) -> Bool {
        state.currentTabId.map {
            pinIDs.contains($0) || tabIDs.contains($0)
        } == true
            || state.currentShortcutPinId.map(pinIDs.contains) == true
    }

    static func excludesDeletedReferences(
        pinIDs: Set<UUID>,
        tabIDs: Set<UUID>,
        from state: BrowserWindowShortcutMutationState
    ) -> Bool {
        excludesCurrentReferences(
            pinIDs: pinIDs, tabIDs: tabIDs, from: state
        )
            && state.selectedShortcutPinForSpace.values
                .contains(where: pinIDs.contains) == false
            && state.selectionHistory.recentSelectionItemsBySpace.values
                .flatMap { $0 }.contains { item in
                    guard case .shortcutPin(let pinID) = item else {
                        return false
                    }
                    return pinIDs.contains(pinID)
                } == false
    }
}

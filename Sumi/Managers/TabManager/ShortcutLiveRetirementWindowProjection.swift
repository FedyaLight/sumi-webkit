import Foundation

@MainActor
enum ShortcutLiveRetirementWindowProjection {
    struct Update {
        let target: BrowserWindowShortcutMutationState
        let didClearCurrentSelection: Bool
        let requiresPersistence: Bool
    }

    static func removingInstances(
        _ entries: [LiveShortcutTabEntry],
        from source: BrowserWindowShortcutMutationState,
        targetOverride: BrowserWindowShortcutMutationState?
    ) -> Update {
        var target = source
        entries.forEach { removeInstance($0, from: &target) }
        let didClear = target.currentTabId != source.currentTabId
            || target.currentShortcutPinId != source.currentShortcutPinId
        if let targetOverride { target = targetOverride }
        return Update(
            target: target,
            didClearCurrentSelection: didClear,
            requiresPersistence: target != source
        )
    }

    static func removingDeletedPins(
        _ pinIDs: Set<UUID>,
        entries: [LiveShortcutTabEntry],
        from source: BrowserWindowShortcutMutationState
    ) -> Update {
        var target = source
        var persistedStateChanged = false
        for pinID in pinIDs {
            if target.currentTabId == pinID {
                target.currentTabId = nil
                persistedStateChanged = true
            }
            if target.currentShortcutPinId == pinID {
                target.currentShortcutPinId = nil
                target.currentShortcutPinRole = nil
                persistedStateChanged = true
            }
            let rememberedSpaces = target.selectedShortcutPinForSpace
                .compactMap { $0.value == pinID ? $0.key : nil }
            rememberedSpaces.forEach {
                target.selectedShortcutPinForSpace.removeValue(forKey: $0)
            }
            persistedStateChanged = persistedStateChanged
                || rememberedSpaces.isEmpty == false
            target.selectionHistory
                .removeFromShortcutLiveSelectionHistory(pinID)
        }
        for entry in entries where pinIDs.contains(entry.pinId) {
            if target.currentTabId == entry.tab.id {
                target.currentTabId = nil
                persistedStateChanged = true
            }
        }
        return Update(
            target: target,
            didClearCurrentSelection:
                target.currentTabId != source.currentTabId
                || target.currentShortcutPinId != source.currentShortcutPinId,
            requiresPersistence: persistedStateChanged
        )
    }

    private static func removeInstance(
        _ entry: LiveShortcutTabEntry,
        from state: inout BrowserWindowShortcutMutationState
    ) {
        if state.currentTabId == entry.tab.id
            || state.currentTabId == entry.pinId {
            state.currentTabId = nil
        }
        if state.currentShortcutPinId == entry.pinId {
            state.currentShortcutPinId = nil
            state.currentShortcutPinRole = nil
        }
    }
}

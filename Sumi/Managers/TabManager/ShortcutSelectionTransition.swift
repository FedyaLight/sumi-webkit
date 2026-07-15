import Foundation
import SumiDomain

/// Reconciles current selection and per-Space remembered selection when a live
/// shortcut changes launcher identity or Space binding.
@MainActor
enum ShortcutSelectionTransition {
    @discardableResult
    static func apply(
        tab: Tab,
        source: ShortcutBindingIdentity?,
        targetPin: ShortcutPin,
        isSelected: Bool,
        in windowState: BrowserWindowState
    ) -> Bool {
        var state = windowState.unpublishedShortcutMutationState
        let previous = state
        let requiresPersistence = apply(
            tab: tab,
            source: source,
            targetPin: targetPin,
            isSelected: isSelected,
            to: &state
        )
        if state != previous {
            precondition(windowState.commitShortcutMutationState(state))
        }
        return requiresPersistence
    }

    static func apply(
        tab: Tab,
        source: ShortcutBindingIdentity?,
        targetPin: ShortcutPin,
        isSelected: Bool,
        to state: inout BrowserWindowShortcutMutationState
    ) -> Bool {
        let previous = Snapshot(state)
        let target = ShortcutBindingIdentity(tab: tab)
        guard source != target else {
            applyCurrentSelection(
                tab: tab,
                pin: targetPin,
                isSelected: isSelected,
                to: &state
            )
            return previous != Snapshot(state)
        }

        let pinIds = Set([source?.pinId, targetPin.id].compactMap(\.self))
        let hadActiveMemory = state.selectedShortcutPinForSpace.values
            .contains(where: pinIds.contains)
        let historySpaces = spacesRemembering(
            pinIds: pinIds,
            in: state
        )

        state.selectedShortcutPinForSpace = state
            .selectedShortcutPinForSpace
            .filter { pinIds.contains($0.value) == false }
        if targetPin.role == .essential {
            replaceHistory(
                pinIds: pinIds,
                with: targetPin.id,
                in: &state
            )
        } else {
            pinIds.forEach {
                state.selectionHistory
                    .removeFromShortcutLiveSelectionHistory($0)
            }
            if let targetSpaceId = tab.spaceId,
               isSelected || hadActiveMemory || historySpaces.isEmpty == false {
                state.selectionHistory.recordSelection(
                    .shortcutPin(targetPin.id),
                    in: targetSpaceId
                )
            }
        }

        if targetPin.role == .spacePinned,
           let targetSpaceId = tab.spaceId,
           isSelected || hadActiveMemory {
            state.selectedShortcutPinForSpace[targetSpaceId] = targetPin.id
        }
        applyCurrentSelection(
            tab: tab,
            pin: targetPin,
            isSelected: isSelected,
            to: &state
        )
        if isSelected,
           targetPin.role == .essential,
           let currentSpaceId = state.currentSpaceId {
            state.selectionHistory.recordSelection(
                .shortcutPin(targetPin.id),
                in: currentSpaceId
            )
        }
        if isSelected == false,
           state.currentShortcutPinId.map(pinIds.contains) == true {
            state.currentShortcutPinId = nil
            state.currentShortcutPinRole = nil
        }
        return previous != Snapshot(state)
    }

    private static func applyCurrentSelection(
        tab: Tab,
        pin: ShortcutPin,
        isSelected: Bool,
        to state: inout BrowserWindowShortcutMutationState
    ) {
        guard isSelected else { return }
        state.currentTabId = tab.id
        state.currentShortcutPinId = pin.id
        state.currentShortcutPinRole = pin.role
        state.isShowingEmptyState = false
        if pin.role == .spacePinned, let targetSpaceId = tab.spaceId {
            state.currentSpaceId = targetSpaceId
        }
    }

    private static func spacesRemembering(
        pinIds: Set<UUID>,
        in state: BrowserWindowShortcutMutationState
    ) -> Set<UUID> {
        Set(state.selectionHistory.recentSelectionItemsBySpace.compactMap { spaceId, items in
            items.contains { item in
                guard case .shortcutPin(let pinId) = item else { return false }
                return pinIds.contains(pinId)
            } ? spaceId : nil
        })
    }

    private static func replaceHistory(
        pinIds: Set<UUID>,
        with targetPinId: UUID,
        in state: inout BrowserWindowShortcutMutationState
    ) {
        for (spaceId, items) in state.selectionHistory
            .recentSelectionItemsBySpace {
            var replaced: [BrowserWindowSelectionHistoryItem] = []
            for item in items {
                let next: BrowserWindowSelectionHistoryItem
                if case .shortcutPin(let pinId) = item,
                   pinIds.contains(pinId) {
                    next = .shortcutPin(targetPinId)
                } else {
                    next = item
                }
                if replaced.contains(next) == false { replaced.append(next) }
            }
            state.selectionHistory
                .recentSelectionItemsBySpace[spaceId] = replaced
        }
    }
}

private extension ShortcutSelectionTransition {
    @MainActor
    struct Snapshot: Equatable {
        let currentTabId: UUID?
        let currentSpaceId: UUID?
        let currentShortcutPinId: UUID?
        let currentShortcutPinRole: ShortcutPinRole?
        let isShowingEmptyState: Bool
        let selectedShortcutPinForSpace: [UUID: UUID]

        init(_ state: BrowserWindowShortcutMutationState) {
            currentTabId = state.currentTabId
            currentSpaceId = state.currentSpaceId
            currentShortcutPinId = state.currentShortcutPinId
            currentShortcutPinRole = state.currentShortcutPinRole
            isShowingEmptyState = state.isShowingEmptyState
            selectedShortcutPinForSpace = state.selectedShortcutPinForSpace
        }
    }
}

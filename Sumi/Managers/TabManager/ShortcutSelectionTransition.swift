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
        apply(
            tabID: tab.id,
            source: source,
            target: ShortcutBindingIdentity(
                pinId: targetPin.id,
                role: targetPin.role,
                spaceId: targetPin.spaceId
            ),
            isSelected: isSelected,
            to: &state
        )
    }

    static func apply(
        tabID: UUID,
        source: ShortcutBindingIdentity?,
        target: ShortcutBindingIdentity,
        isSelected: Bool,
        to state: inout BrowserWindowShortcutMutationState
    ) -> Bool {
        let previous = Snapshot(state)
        guard source != target else {
            if isSelected {
                ShortcutCurrentSelectionProjection.apply(
                    tabID: tabID,
                    target: target,
                    to: &state
                )
            }
            return previous != Snapshot(state)
        }

        let pinIds = Set([source?.pinId, target.pinId].compactMap(\.self))
        let hadActiveMemory = state.selectedShortcutPinForSpace.values
            .contains(where: pinIds.contains)
        let historySpaces = spacesRemembering(
            pinIds: pinIds,
            in: state
        )

        state.selectedShortcutPinForSpace = state
            .selectedShortcutPinForSpace
            .filter { pinIds.contains($0.value) == false }
        if target.role == .favorite {
            replaceHistory(
                pinIds: pinIds,
                with: target.pinId,
                in: &state
            )
        } else {
            pinIds.forEach {
                state.selectionHistory
                    .removeFromShortcutLiveSelectionHistory($0)
            }
            if let targetSpaceId = target.spaceId,
               isSelected || hadActiveMemory || historySpaces.isEmpty == false {
                state.selectionHistory.recordSelection(
                    .shortcutPin(target.pinId),
                    in: targetSpaceId
                )
            }
        }

        if target.role == .spacePinned,
           let targetSpaceId = target.spaceId,
           isSelected || hadActiveMemory {
            state.selectedShortcutPinForSpace[targetSpaceId] = target.pinId
        }
        if isSelected {
            ShortcutCurrentSelectionProjection.apply(
                tabID: tabID,
                target: target,
                to: &state
            )
        }
        if isSelected,
           target.role == .favorite,
           let currentSpaceId = state.currentSpaceId {
            state.selectionHistory.recordSelection(
                .shortcutPin(target.pinId),
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

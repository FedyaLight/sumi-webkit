import Foundation
import SumiDomain

struct ShortcutBindingIdentity: Equatable {
    let pinId: UUID
    let role: ShortcutPinRole
    let spaceId: UUID?

    @MainActor
    init?(tab: Tab) {
        guard let pinId = tab.shortcutPinId,
              let role = tab.shortcutPinRole else {
            return nil
        }
        self.pinId = pinId
        self.role = role
        self.spaceId = tab.spaceId
    }
}

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
        let previous = Snapshot(windowState)
        let target = ShortcutBindingIdentity(tab: tab)
        guard source != target else {
            applyCurrentSelection(
                tab: tab,
                pin: targetPin,
                isSelected: isSelected,
                in: windowState
            )
            return previous != Snapshot(windowState)
        }

        let pinIds = Set([source?.pinId, targetPin.id].compactMap(\.self))
        let hadActiveMemory = windowState.selectedShortcutPinForSpace.values
            .contains(where: pinIds.contains)
        let historySpaces = spacesRemembering(
            pinIds: pinIds,
            in: windowState
        )

        windowState.selectedShortcutPinForSpace = windowState
            .selectedShortcutPinForSpace
            .filter { pinIds.contains($0.value) == false }
        if targetPin.role == .essential {
            replaceHistory(
                pinIds: pinIds,
                with: targetPin.id,
                in: windowState
            )
        } else {
            pinIds.forEach {
                windowState.selectionHistory
                    .removeFromShortcutLiveSelectionHistory($0)
            }
            if let targetSpaceId = tab.spaceId,
               isSelected || hadActiveMemory || historySpaces.isEmpty == false {
                windowState.selectionHistory.recordSelection(
                    .shortcutPin(targetPin.id),
                    in: targetSpaceId
                )
            }
        }

        if targetPin.role == .spacePinned,
           let targetSpaceId = tab.spaceId,
           isSelected || hadActiveMemory {
            windowState.selectedShortcutPinForSpace[targetSpaceId] = targetPin.id
        }
        applyCurrentSelection(
            tab: tab,
            pin: targetPin,
            isSelected: isSelected,
            in: windowState
        )
        if isSelected,
           targetPin.role == .essential,
           let currentSpaceId = windowState.currentSpaceId {
            windowState.selectionHistory.recordSelection(
                .shortcutPin(targetPin.id),
                in: currentSpaceId
            )
        }
        if isSelected == false,
           windowState.currentShortcutPinId.map(pinIds.contains) == true {
            windowState.currentShortcutPinId = nil
            windowState.currentShortcutPinRole = nil
        }
        return previous != Snapshot(windowState)
    }

    private static func applyCurrentSelection(
        tab: Tab,
        pin: ShortcutPin,
        isSelected: Bool,
        in windowState: BrowserWindowState
    ) {
        guard isSelected else { return }
        windowState.currentTabId = tab.id
        windowState.currentShortcutPinId = pin.id
        windowState.currentShortcutPinRole = pin.role
        windowState.isShowingEmptyState = false
        if pin.role == .spacePinned, let targetSpaceId = tab.spaceId {
            windowState.currentSpaceId = targetSpaceId
        }
    }

    private static func spacesRemembering(
        pinIds: Set<UUID>,
        in windowState: BrowserWindowState
    ) -> Set<UUID> {
        Set(windowState.selectionHistory.recentSelectionItemsBySpace.compactMap { spaceId, items in
            items.contains { item in
                guard case .shortcutPin(let pinId) = item else { return false }
                return pinIds.contains(pinId)
            } ? spaceId : nil
        })
    }

    private static func replaceHistory(
        pinIds: Set<UUID>,
        with targetPinId: UUID,
        in windowState: BrowserWindowState
    ) {
        for (spaceId, items) in windowState.selectionHistory
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
            windowState.selectionHistory
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

        init(_ state: BrowserWindowState) {
            currentTabId = state.currentTabId
            currentSpaceId = state.currentSpaceId
            currentShortcutPinId = state.currentShortcutPinId
            currentShortcutPinRole = state.currentShortcutPinRole
            isShowingEmptyState = state.isShowingEmptyState
            selectedShortcutPinForSpace = state.selectedShortcutPinForSpace
        }
    }
}

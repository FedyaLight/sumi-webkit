import Foundation
import SumiDomain

/// Durable window-session fields that tab-to-shortcut conversion can mutate.
/// Selection history is runtime navigation memory and intentionally excluded.
struct ShortcutConversionWindowSessionState: Equatable {
    let currentTabId: UUID?
    let currentSpaceId: UUID?
    let currentShortcutPinId: UUID?
    let currentShortcutPinRole: ShortcutPinRole?
    let isShowingEmptyState: Bool
    let activeTabForSpace: [UUID: UUID]
    let selectedShortcutPinForSpace: [UUID: UUID]

    @MainActor
    init(_ windowState: BrowserWindowState) {
        currentTabId = windowState.currentTabId
        currentSpaceId = windowState.currentSpaceId
        currentShortcutPinId = windowState.currentShortcutPinId
        currentShortcutPinRole = windowState.currentShortcutPinRole
        isShowingEmptyState = windowState.isShowingEmptyState
        activeTabForSpace = windowState.activeTabForSpace
        selectedShortcutPinForSpace = windowState.selectedShortcutPinForSpace
    }

    init(_ state: BrowserWindowShortcutMutationState) {
        currentTabId = state.currentTabId
        currentSpaceId = state.currentSpaceId
        currentShortcutPinId = state.currentShortcutPinId
        currentShortcutPinRole = state.currentShortcutPinRole
        isShowingEmptyState = state.isShowingEmptyState
        activeTabForSpace = state.activeTabForSpace
        selectedShortcutPinForSpace = state.selectedShortcutPinForSpace
    }
}

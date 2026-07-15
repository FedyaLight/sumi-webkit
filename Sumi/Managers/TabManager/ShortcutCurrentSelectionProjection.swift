import Foundation

@MainActor
enum ShortcutCurrentSelectionProjection {
    static func apply(
        tabID: UUID,
        target: ShortcutBindingIdentity,
        to state: inout BrowserWindowShortcutMutationState
    ) {
        state.currentTabId = tabID
        state.currentShortcutPinId = target.pinId
        state.currentShortcutPinRole = target.role
        state.isShowingEmptyState = false
        if target.role == .spacePinned, let targetSpaceID = target.spaceId {
            state.currentSpaceId = targetSpaceID
        }
    }
}

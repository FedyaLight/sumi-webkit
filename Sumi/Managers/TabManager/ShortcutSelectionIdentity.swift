import Foundation

/// Canonical identity rule for a window-selected live shortcut. Persisted
/// shortcut metadata is authoritative only when no exact current tab exists.
@MainActor
enum ShortcutSelectionIdentity {
    static func isSelected(
        tabId: UUID?,
        pinId: UUID?,
        in windowState: BrowserWindowState
    ) -> Bool {
        if let currentTabId = windowState.currentTabId {
            return currentTabId == tabId || currentTabId == pinId
        }
        guard let pinId else { return false }
        return windowState.currentShortcutPinId == pinId
    }
}

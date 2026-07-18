import Foundation

struct ShortcutSelectionSnapshot: Equatable {
    let currentTabID: UUID?
    let currentShortcutPinID: UUID?

    init(
        currentTabID: UUID? = nil,
        currentShortcutPinID: UUID? = nil
    ) {
        self.currentTabID = currentTabID
        self.currentShortcutPinID = currentShortcutPinID
    }

    @MainActor
    init(windowState: BrowserWindowState) {
        self.init(
            currentTabID: windowState.currentTabId,
            currentShortcutPinID: windowState.currentShortcutPinId
        )
    }
}

/// Canonical identity rule for a window-selected live shortcut. Persisted
/// shortcut metadata is authoritative only when no exact current tab exists.
@MainActor
enum ShortcutSelectionIdentity {
    static func isSelected(
        tabId: UUID?,
        pinId: UUID?,
        in snapshot: ShortcutSelectionSnapshot
    ) -> Bool {
        if let currentTabID = snapshot.currentTabID {
            return currentTabID == tabId || currentTabID == pinId
        }
        guard let pinId else { return false }
        return snapshot.currentShortcutPinID == pinId
    }

    static func isSelected(
        tabId: UUID?,
        pinId: UUID?,
        in windowState: BrowserWindowState
    ) -> Bool {
        isSelected(
            tabId: tabId,
            pinId: pinId,
            in: ShortcutSelectionSnapshot(windowState: windowState)
        )
    }
}

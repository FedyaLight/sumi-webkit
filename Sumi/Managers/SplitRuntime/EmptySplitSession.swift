import Foundation

/// Tracks only the ephemeral blank tab created by the split shortcut. All
/// structural replacement is delegated to the normal split-drop transaction.
@MainActor
final class EmptySplitSession {
    private let replacePlaceholder: @MainActor (
        Tab,
        UUID,
        BrowserWindowState
    ) -> Bool
    private let removeTab: @MainActor (UUID) -> Void
    private var placeholderTabIDByWindowID: [UUID: UUID] = [:]

    init(
        replacePlaceholder: @escaping @MainActor (
            Tab,
            UUID,
            BrowserWindowState
        ) -> Bool,
        removeTab: @escaping @MainActor (UUID) -> Void
    ) {
        self.replacePlaceholder = replacePlaceholder
        self.removeTab = removeTab
    }

    func register(tabID: UUID, in windowID: UUID) {
        placeholderTabIDByWindowID[windowID] = tabID
    }

    func commit(tabID: UUID, in windowID: UUID) {
        guard placeholderTabIDByWindowID[windowID] == tabID else { return }
        placeholderTabIDByWindowID.removeValue(forKey: windowID)
    }

    @discardableResult
    func replace(with tab: Tab, in windowState: BrowserWindowState) -> Bool {
        guard let placeholderTabID = placeholderTabIDByWindowID[
            windowState.id
        ], replacePlaceholder(tab, placeholderTabID, windowState) else {
            return false
        }
        placeholderTabIDByWindowID.removeValue(forKey: windowState.id)
        if placeholderTabID != tab.id {
            removeTab(placeholderTabID)
        }
        return true
    }

    @discardableResult
    func cancel(in windowState: BrowserWindowState) -> Bool {
        guard let placeholderTabID = placeholderTabIDByWindowID.removeValue(
            forKey: windowState.id
        ) else {
            return false
        }
        removeTab(placeholderTabID)
        return true
    }

    func removeWindow(_ windowID: UUID) {
        placeholderTabIDByWindowID.removeValue(forKey: windowID)
    }
}

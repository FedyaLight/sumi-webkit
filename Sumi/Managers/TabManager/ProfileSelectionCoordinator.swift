import Foundation

/// Reconciles visible selection after a profile change. It owns no WebView
/// replacement or profile-assignment transaction state.
@MainActor
final class ProfileSelectionCoordinator {
    private let selectionContext: TabSelectionContextProjection
    private let selection: TabSelectionStateOwner
    private let pins: ShortcutPinCollectionStateOwner
    private let runtimeConnection: TabRuntimePortConnection
    private let persistence: TabStructuralPersistenceService

    init(
        selectionContext: TabSelectionContextProjection,
        selection: TabSelectionStateOwner,
        pins: ShortcutPinCollectionStateOwner,
        runtimeConnection: TabRuntimePortConnection,
        persistence: TabStructuralPersistenceService
    ) {
        self.selectionContext = selectionContext
        self.selection = selection
        self.pins = pins
        self.runtimeConnection = runtimeConnection
        self.persistence = persistence
    }

    func handleProfileSwitch(contextWindowID: UUID? = nil) {
        let visible = selectionContext.tabs(in: contextWindowID)
        let current = selection.currentTab
        if contextWindowID == nil,
           shouldPreserveContextlessShortcutLiveTab(current) {
            runtimeConnection.current?.updateTabVisibility()
            return
        }

        let currentIsVisible = current.map { current in
            visible.contains(where: { $0.id == current.id })
        } ?? false
        if !currentIsVisible {
            selection.replaceCurrentTab(visible.first)
            persistence.persistSelection()
        }
        runtimeConnection.current?.updateTabVisibility()
    }

    private func shouldPreserveContextlessShortcutLiveTab(
        _ tab: Tab?
    ) -> Bool {
        guard let tab,
              tab.isShortcutLiveInstance,
              tab.shortcutPinRole != .essential,
              let shortcutPinID = tab.shortcutPinId,
              pins.shortcutPin(by: shortcutPinID) != nil else {
            return false
        }
        return true
    }
}

import Foundation

/// Applies only the visible runtime effect that follows a committed regular
/// residence. Background tabs therefore remain free of WebView work.
@MainActor
final class RegularTabVisibleRuntimeEffects {
    private let selection: TabSelectionStateOwner
    private let windows: ShortcutTabWindowQuery
    private let runtimeConnection: TabRuntimePortConnection

    init(
        selection: TabSelectionStateOwner,
        windows: ShortcutTabWindowQuery,
        runtimeConnection: TabRuntimePortConnection
    ) {
        self.selection = selection
        self.windows = windows
        self.runtimeConnection = runtimeConnection
    }

    func materializeIfVisible(_ tab: Tab) {
        guard tab.id == selection.currentTab?.id else { return }
        if let windowState = windows.windowStateDisplaying(tabId: tab.id) {
            runtimeConnection.current?.webViewLifecycle
                .materializeVisibleTabWebViewIfNeeded(tab, in: windowState)
        } else {
            runtimeConnection.current?.webViewLifecycle.loadTab(tab)
        }
    }
}

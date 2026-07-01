import Foundation

@MainActor
extension GlanceManager {
    struct Runtime {
        let windowStateContainingTab: @MainActor (Tab) -> BrowserWindowState?
        let hasLoadedInitialTabData: @MainActor () -> Bool
        let tab: @MainActor (UUID) -> Tab?
        let shortcutPin: @MainActor (UUID) -> ShortcutPin?
        let shortcutLiveTab: @MainActor (UUID, UUID) -> Tab?
        let activateShortcutPin: @MainActor (ShortcutPin, UUID, UUID?) -> Tab
        let currentTab: @MainActor (BrowserWindowState) -> Tab?
        let restoreSourceSelection: @MainActor (Tab, BrowserWindowState) -> Void
        let visibleSplitTabCount: @MainActor (UUID) -> Int
        let dismissFloatingBarIfVisible: @MainActor (UUID) -> Bool
        let isFindBarVisible: @MainActor () -> Bool
        let findCurrentTabId: @MainActor () -> UUID?
        let hideFindBar: @MainActor () -> Void
        let updateFindManagerCurrentTab: @MainActor () -> Void
        let persistWindowSession: @MainActor (BrowserWindowState) -> Void
        let makePreviewTab: @MainActor (URL, Tab?, BrowserWindowState?) -> Tab
        let adoptPreviewTab: @MainActor (Tab, Tab?, BrowserWindowState?) -> Tab
        let selectPromotedTab: @MainActor (Tab, BrowserWindowState) -> Void
        let selectPromotedTabInActiveWindow: @MainActor (Tab) -> Void
        let createSplitPlaceholder: @MainActor (BrowserWindowState) -> Void
        let registerPromotedHost: @MainActor (
            SumiWebViewContainerView,
            UUID,
            UUID,
            @escaping @MainActor () -> Void
        ) -> Bool
    }
}

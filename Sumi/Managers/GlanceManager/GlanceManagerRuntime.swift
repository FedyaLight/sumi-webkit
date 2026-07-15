import Foundation
import SumiWebRuntime
import WebKit

@MainActor
extension GlanceManager {
    struct Runtime {
        let windowStateContainingTab: @MainActor (Tab) -> BrowserWindowState?
        let hasLoadedInitialTabData: @MainActor () -> Bool
        let tab: @MainActor (UUID) -> Tab?
        let shortcutPin: @MainActor (UUID) -> ShortcutPin?
        let activateShortcutPin: @MainActor (ShortcutPin, UUID, UUID?) -> Tab?
        let currentTab: @MainActor (BrowserWindowState) -> Tab?
        let restoreSourceSelection: @MainActor (Tab, BrowserWindowState) -> Void
        let visibleSplitTabCount: @MainActor (UUID) -> Int
        let dismissFloatingBarIfVisible: @MainActor (UUID) -> Bool
        let isFindBarVisible: @MainActor () -> Bool
        let findCurrentTabId: @MainActor () -> UUID?
        let hideFindBar: @MainActor () -> Void
        let updateFindManagerCurrentTab: @MainActor () -> Void
        let persistWindowSession: @MainActor (BrowserWindowState) -> Void
        let makePreviewTab: @MainActor (URL, Tab?, BrowserWindowState?) -> Tab?
        let adoptPreviewTab: @MainActor (Tab, Tab?, BrowserWindowState?) -> Tab
        let selectPromotedTab: @MainActor (Tab, BrowserWindowState) -> Void
        let selectPromotedTabInActiveWindow: @MainActor (Tab) -> Void
        let createSplitPlaceholder: @MainActor (BrowserWindowState) -> Void
        let registerPromotedHost: @MainActor (
            SumiWebViewContainerView,
            UUID,
            UUID,
            @escaping PromotedHostAttachmentCompletion
        ) -> Bool
        let previewWebView: @MainActor (Tab) -> WKWebView?
        let ensurePreviewWebView: @MainActor (Tab, UUID) -> WKWebView?
        let ownsPreviewWebView: @MainActor (Tab, WKWebView) -> Bool
        let releasePreviewWebView: @MainActor (Tab) -> Void
    }
}

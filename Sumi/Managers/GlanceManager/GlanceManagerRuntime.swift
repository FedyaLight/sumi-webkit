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
        let dismissCommandPaletteIfVisible: @MainActor (UUID) -> Bool
        let isFindBarVisible: @MainActor () -> Bool
        let hideFindBar: @MainActor () -> Void
        let dismissFindSessionIfOwned: @MainActor (UUID) -> Void
        let persistWindowSession: @MainActor (BrowserWindowState) -> Void
        let withPreparedPreviewTab: @MainActor (
            URL,
            Tab?,
            BrowserWindowState?,
            @MainActor (Tab) -> Bool
        ) -> Bool
        let adoptPreviewTab: @MainActor (Tab, Tab?, BrowserWindowState?) -> Tab?
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
        let installPreviewWebView: @MainActor (
            Tab,
            WKWebViewConfiguration,
            URL
        ) -> WKWebView?
        let ownsPreviewWebView: @MainActor (Tab, WKWebView) -> Bool
        let releasePreviewWebView: @MainActor (Tab) -> Void
    }
}

import AppKit
import Foundation
import WebKit

/// Read-only browser projection needed by action-popup admission,
/// presentation, telemetry and focus restoration. It exposes resolved values,
/// never the browser graph or its query/presentation services.
@available(macOS 15.5, *)
@MainActor
protocol ExtensionActionPopupBrowserProjection: AnyObject {
    func popupWindowState(id: UUID) -> BrowserWindowState?
    func popupActiveWindow() -> BrowserWindowState?
    func popupWindow(containing tab: Tab) -> BrowserWindowState?
    func popupAppKitWindow(for window: BrowserWindowState) -> NSWindow?
    func popupTab(id: UUID, in window: BrowserWindowState) -> Tab?
    func popupCurrentTab(in window: BrowserWindowState) -> Tab?
    func popupProfile(id: UUID) -> Profile?
    func popupProfileID(for tab: Tab) -> UUID?
    func popupWindow(_ window: BrowserWindowState, matches profileID: UUID) -> Bool
    func popupLiveWebView(for tab: Tab) -> WKWebView?
    func popupFallbackAnchorView(windowID: UUID) -> NSView?
    func popupAppearance(
        anchorWindow: NSWindow,
        fallback: NSAppearance
    ) -> NSAppearance?
    func popupTabIsPublished(_ tab: Tab) -> Bool
}

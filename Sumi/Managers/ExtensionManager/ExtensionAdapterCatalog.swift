import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionAdapterCatalog {
    private let miniWindows: ExtensionMiniWindowAdapterCatalog
    private let windows: ExtensionWindowAdapterCatalog
    private let tabs: ExtensionTabAdapterCatalog

    init(
        miniWindows: ExtensionMiniWindowAdapterCatalog,
        windows: ExtensionWindowAdapterCatalog,
        tabs: ExtensionTabAdapterCatalog
    ) {
        self.miniWindows = miniWindows
        self.windows = windows
        self.tabs = tabs
    }

    func miniWindowAdapter(for tab: Tab) -> ExtensionMiniWindowAdapter? {
        miniWindows.adapter(for: tab)
    }

    func miniWindowAdapter(
        for sessionId: UUID,
        tab: Tab,
        window: NSWindow,
        isPrivate: Bool,
        shouldActivateApp: Bool
    ) -> ExtensionMiniWindowAdapter? {
        miniWindows.adapter(
            for: sessionId,
            tab: tab,
            window: window,
            isPrivate: isPrivate,
            shouldActivateApp: shouldActivateApp
        )
    }

    func windowAdapter(
        for windowId: UUID,
        preparedTabVisibility: ExtensionPreparedTabVisibility
    ) -> ExtensionWindowAdapter? {
        windows.adapter(
            for: windowId,
            preparedTabVisibility: preparedTabVisibility
        )
    }

    func publishedNormalWindowAdapter(
        for windowState: BrowserWindowState,
        extensionContext: WKWebExtensionContext
    ) -> ExtensionWindowAdapter? {
        windows.publishedAdapter(
            for: windowState,
            extensionContext: extensionContext
        )
    }

    func stableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
        tabs.stableAdapter(for: tab)
    }
}

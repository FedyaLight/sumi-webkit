import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class BrowserExtensionTabMutationAdapter:
    ExtensionTabMutation
{
    private let createTab: @MainActor (
        URL?, Space?, Bool, WKWebExtensionContext?
    ) -> Tab
    private let createTransientTab: @MainActor (
        URL, Space?, WKWebExtensionContext?
    ) -> Tab
    private let pinTab: @MainActor (Tab, BrowserWindowState?, Space?) -> Void
    private let selectTab: @MainActor (Tab, BrowserWindowState) -> Void
    private let promoteTransientTab: @MainActor (Tab) -> Bool

    init(
        createTab: @escaping @MainActor (
            URL?, Space?, Bool, WKWebExtensionContext?
        ) -> Tab,
        createTransientTab: @escaping @MainActor (
            URL, Space?, WKWebExtensionContext?
        ) -> Tab,
        pinTab: @escaping @MainActor (
            Tab, BrowserWindowState?, Space?
        ) -> Void,
        selectTab: @escaping @MainActor (Tab, BrowserWindowState) -> Void,
        promoteTransientTab: @escaping @MainActor (Tab) -> Bool
    ) {
        self.createTab = createTab
        self.createTransientTab = createTransientTab
        self.pinTab = pinTab
        self.selectTab = selectTab
        self.promoteTransientTab = promoteTransientTab
    }

    func createExtensionTab(
        url: URL?,
        in space: Space?,
        activate: Bool,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Tab {
        createTab(url, space, activate, webExtensionContextOverride)
    }

    func createTransientExtensionTab(
        url: URL,
        in space: Space?,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Tab {
        createTransientTab(url, space, webExtensionContextOverride)
    }

    func pinExtensionTab(
        _ tab: Tab,
        targetWindow: BrowserWindowState?,
        targetSpace: Space?
    ) {
        pinTab(tab, targetWindow, targetSpace)
    }

    func selectExtensionTab(
        _ tab: Tab,
        in windowState: BrowserWindowState
    ) {
        selectTab(tab, windowState)
    }

    func promoteTransientExtensionTab(_ tab: Tab) -> Bool {
        promoteTransientTab(tab)
    }
}

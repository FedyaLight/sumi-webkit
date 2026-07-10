import AppKit
import Foundation

@available(macOS 15.5, *)
@MainActor
final class BrowserExtensionWindowQueryAdapter: ExtensionWindowQuery {
    private let windowRegistry: @MainActor () -> WindowRegistry?
    private let primaryTrackedWindowID: @MainActor (UUID) -> UUID?
    private let tabs: @MainActor (BrowserWindowState) -> [Tab]
    private let currentTab: @MainActor (BrowserWindowState) -> Tab?
    private let currentTabForActiveWindow: @MainActor () -> Tab?
    private let windowContainingTab: @MainActor (Tab) -> BrowserWindowState?

    init(
        windowRegistry: @escaping @MainActor () -> WindowRegistry?,
        primaryTrackedWindowID: @escaping @MainActor (UUID) -> UUID?,
        tabs: @escaping @MainActor (BrowserWindowState) -> [Tab],
        currentTab: @escaping @MainActor (BrowserWindowState) -> Tab?,
        currentTabForActiveWindow: @escaping @MainActor () -> Tab?,
        windowContainingTab: @escaping @MainActor (Tab) -> BrowserWindowState?
    ) {
        self.windowRegistry = windowRegistry
        self.primaryTrackedWindowID = primaryTrackedWindowID
        self.tabs = tabs
        self.currentTab = currentTab
        self.currentTabForActiveWindow = currentTabForActiveWindow
        self.windowContainingTab = windowContainingTab
    }

    func extensionWindowState(for windowId: UUID) -> BrowserWindowState? {
        windowRegistry()?.windows[windowId]
    }

    var activeExtensionWindowState: BrowserWindowState? {
        windowRegistry()?.activeWindow
    }

    var allExtensionWindowStates: [BrowserWindowState] {
        windowRegistry()?.allWindows ?? []
    }

    func extensionWindowState(containing tab: Tab) -> BrowserWindowState? {
        windowContainingTab(tab)
    }

    func extensionWindowState(
        forAppKitWindow window: NSWindow
    ) -> BrowserWindowState? {
        windowRegistry()?.windowState(containing: window)
    }

    func appKitWindow(for windowState: BrowserWindowState) -> NSWindow? {
        windowRegistry()?.appKitWindow(for: windowState)
    }

    func currentExtensionTab(in windowState: BrowserWindowState) -> Tab? {
        currentTab(windowState)
    }

    func currentExtensionTabForActiveWindow() -> Tab? {
        currentTabForActiveWindow()
    }

    func currentExtensionTabForPopup() -> Tab? {
        currentTabForActiveWindow()
    }

    func tabsForExtensionWindow(_ windowState: BrowserWindowState) -> [Tab] {
        tabs(windowState)
    }

    func preferredExtensionWindowState(
        containing tab: Tab
    ) -> BrowserWindowState? {
        if let windowID = primaryTrackedWindowID(tab.id),
           let window = extensionWindowState(for: windowID) {
            return window
        }
        if let containingWindow = windowContainingTab(tab) {
            return containingWindow
        }
        if let spaceID = tab.spaceId,
           let displayingSpaceWindow = windowDisplaying(spaceID: spaceID) {
            return displayingSpaceWindow
        }
        if let activeWindow = activeExtensionWindowState,
           tabs(activeWindow).contains(where: { $0.id == tab.id }) {
            return activeWindow
        }
        return allExtensionWindowStates
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .first { window in
                tabs(window).contains(where: { $0.id == tab.id })
            }
    }

    private func windowDisplaying(spaceID: UUID) -> BrowserWindowState? {
        if let activeWindow = activeExtensionWindowState,
           activeWindow.currentSpaceId == spaceID {
            return activeWindow
        }
        let activeWindowID = activeExtensionWindowState?.id
        return allExtensionWindowStates
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .first { window in
                window.id != activeWindowID && window.currentSpaceId == spaceID
            }
    }
}

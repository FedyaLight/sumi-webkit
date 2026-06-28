import AppKit
import Foundation
import WebKit

@MainActor
final class BrowserActionOwner {
    struct Dependencies {
        let tabOpeningOwner: @MainActor @Sendable () -> BrowserTabOpeningOwner
        let tabManager: @MainActor @Sendable () -> TabManager
        let liveFolderManager: @MainActor @Sendable () -> SumiLiveFolderManager
        let windowRegistry: @MainActor @Sendable () -> WindowRegistry?
        let updateSavedSidebarVisibility: @MainActor @Sendable (Bool) -> Void
        let toggleSavedSidebarVisibility: @MainActor @Sendable () -> Void
        let updateSavedSidebarWidth: @MainActor @Sendable (CGFloat) -> Void
        let schedulePersistWindowSession: @MainActor @Sendable (BrowserWindowState, UInt64) -> Void
    }

    private let dependencies: Dependencies
    private let sidebarActionOwner: BrowserSidebarActionOwner

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        self.sidebarActionOwner = BrowserSidebarActionOwner(
            dependencies: BrowserSidebarActionOwner.Dependencies(
                tabManager: dependencies.tabManager,
                liveFolderManager: dependencies.liveFolderManager
            )
        )
    }

    func toggleSidebar() {
        if let windowState = sidebarToggleTargetWindowState() {
            toggleSidebar(for: windowState)
        } else {
            dependencies.toggleSavedSidebarVisibility()
        }
    }

    func toggleSidebar(for windowState: BrowserWindowState) {
        windowState.isSidebarVisible.toggle()
        dependencies.updateSavedSidebarVisibility(windowState.isSidebarVisible)
        dependencies.updateSavedSidebarWidth(windowState.savedSidebarWidth)
        dependencies.schedulePersistWindowSession(windowState, 150_000_000)
    }

    func spaceForSidebarActions(in windowState: BrowserWindowState) -> Space? {
        sidebarActionOwner.spaceForSidebarActions(in: windowState)
    }

    func createFolderInCurrentSpace(in windowState: BrowserWindowState) {
        sidebarActionOwner.createFolderInCurrentSpace(in: windowState)
    }

    func createRSSLiveFolderInCurrentSpace(in windowState: BrowserWindowState) {
        sidebarActionOwner.createRSSLiveFolderInCurrentSpace(in: windowState)
    }

    func createGitHubPullRequestsLiveFolderInCurrentSpace(in windowState: BrowserWindowState) {
        sidebarActionOwner.createGitHubPullRequestsLiveFolderInCurrentSpace(in: windowState)
    }

    func createGitHubIssuesLiveFolderInCurrentSpace(in windowState: BrowserWindowState) {
        sidebarActionOwner.createGitHubIssuesLiveFolderInCurrentSpace(in: windowState)
    }

    @discardableResult
    func createNewTab() -> Tab {
        dependencies.tabOpeningOwner().createNewTab()
    }

    @discardableResult
    func createNewTab(
        in windowState: BrowserWindowState,
        url: String = SumiSurface.emptyTabURL.absoluteString
    ) -> Tab {
        dependencies.tabOpeningOwner().createNewTab(in: windowState, url: url)
    }

    @discardableResult
    func createNewTabAfterSidebarInsertion(
        in windowState: BrowserWindowState,
        url: String = SumiSurface.emptyTabURL.absoluteString
    ) -> Tab {
        dependencies.tabOpeningOwner().createNewTabAfterSidebarInsertion(in: windowState, url: url)
    }

    @discardableResult
    func openNewTab(
        url: String = SumiSurface.emptyTabURL.absoluteString,
        context: BrowserTabOpenContext
    ) -> Tab {
        dependencies.tabOpeningOwner().openNewTab(url: url, context: context)
    }

    func resolvedTabOpenSpace(for context: BrowserTabOpenContext) -> Space? {
        dependencies.tabOpeningOwner().resolvedTabOpenSpace(for: context)
    }

    @discardableResult
    func createPopupTab(
        from sourceTab: Tab,
        webViewConfigurationOverride: WKWebViewConfiguration? = nil,
        activate: Bool = true
    ) -> Tab? {
        dependencies.tabOpeningOwner().createPopupTab(
            from: sourceTab,
            webViewConfigurationOverride: webViewConfigurationOverride,
            activate: activate
        )
    }

    func duplicateTab(_ tab: Tab, in windowState: BrowserWindowState) {
        dependencies.tabOpeningOwner().duplicateTab(tab, in: windowState)
    }

    func prepareBackgroundTabIfNeeded(_ tab: Tab, in windowState: BrowserWindowState?) {
        dependencies.tabOpeningOwner().prepareBackgroundTabIfNeeded(tab, in: windowState)
    }

    private func sidebarToggleTargetWindowState() -> BrowserWindowState? {
        if let activeWindow = dependencies.windowRegistry()?.activeWindow {
            return activeWindow
        }

        guard let windowRegistry = dependencies.windowRegistry() else {
            return nil
        }

        if let keyWindow = NSApp.keyWindow,
           let keyWindowState = windowRegistry.allWindows.first(where: { windowState in
               guard let browserWindow = windowState.window else { return false }
               if browserWindow === keyWindow {
                   return true
               }
               return browserWindow.childWindows?.contains(where: { $0 === keyWindow }) == true
           }) {
            windowRegistry.setActive(keyWindowState)
            return keyWindowState
        }

        if windowRegistry.allWindows.count == 1,
           let onlyWindow = windowRegistry.allWindows.first {
            windowRegistry.setActive(onlyWindow)
            return onlyWindow
        }

        return nil
    }
}

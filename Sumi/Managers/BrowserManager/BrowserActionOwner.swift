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
        let settings: @MainActor @Sendable () -> SumiSettingsService?
        let activePageTab: @MainActor @Sendable (BrowserWindowState) -> Tab?
        let hasValidCurrentSelection: @MainActor @Sendable (BrowserWindowState) -> Bool
        let cancelEmptySplitPlaceholder: @MainActor @Sendable (BrowserWindowState) -> Void
        let commitEmptySplitPlaceholder: @MainActor @Sendable (UUID, BrowserWindowState) -> Void
        let replaceEmptySplitPlaceholder: @MainActor @Sendable (Tab, BrowserWindowState) -> Bool
        let selectTab: @MainActor @Sendable (Tab, BrowserWindowState) -> Void
        let dismissWorkspaceThemePickerIfNeededDiscarding: @MainActor @Sendable () -> Void
        let updateSavedSidebarVisibility: @MainActor @Sendable (Bool) -> Void
        let toggleSavedSidebarVisibility: @MainActor @Sendable () -> Void
        let updateSavedSidebarWidth: @MainActor @Sendable (CGFloat) -> Void
        let persistWindowSession: @MainActor @Sendable (BrowserWindowState) -> Void
        let schedulePersistWindowSession: @MainActor @Sendable (BrowserWindowState, UInt64) -> Void
    }

    private let dependencies: Dependencies
    private let floatingBarNavigationOwner = FloatingBarNavigationOwner()

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
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

    func focusFloatingBarForActiveWindow(
        prefill: String,
        navigateCurrentTab: Bool,
        presentationReason: FloatingBarPresentationReason
    ) {
        floatingBarNavigationOwner.focusActiveWindow(
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            presentationReason: presentationReason,
            actions: floatingBarActions
        )
    }

    func focusFloatingBar(
        in windowState: BrowserWindowState,
        prefill: String,
        navigateCurrentTab: Bool,
        presentationReason: FloatingBarPresentationReason
    ) {
        floatingBarNavigationOwner.focus(
            in: windowState,
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            presentationReason: presentationReason,
            actions: floatingBarActions
        )
    }

    func showNewTabFloatingBar(in windowState: BrowserWindowState) {
        floatingBarNavigationOwner.showNewTab(
            in: windowState,
            actions: floatingBarActions
        )
    }

    func openNewTabOrFloatingBar(in windowState: BrowserWindowState) {
        floatingBarNavigationOwner.openNewTabSurface(
            in: windowState,
            actions: floatingBarActions
        )
    }

    func spaceForSidebarActions(in windowState: BrowserWindowState) -> Space? {
        let tabManager = dependencies.tabManager()
        return windowState.currentSpaceId
            .flatMap { spaceId in tabManager.spaces.first(where: { $0.id == spaceId }) }
            ?? tabManager.currentSpace
    }

    func createFolderInCurrentSpace(in windowState: BrowserWindowState) {
        guard let space = spaceForSidebarActions(in: windowState) else { return }
        _ = dependencies.tabManager().createFolder(for: space.id)
    }

    func createRSSLiveFolderInCurrentSpace(in windowState: BrowserWindowState) {
        guard let space = spaceForSidebarActions(in: windowState),
              let feedURLString = promptForLiveFolderFeedURL()
        else {
            return
        }
        dependencies.liveFolderManager().createRSSFolder(in: space.id, feedURLString: feedURLString)
    }

    func createGitHubPullRequestsLiveFolderInCurrentSpace(in windowState: BrowserWindowState) {
        guard let space = spaceForSidebarActions(in: windowState) else { return }
        dependencies.liveFolderManager().createGitHubFolder(in: space.id, kind: .githubPullRequests)
    }

    func createGitHubIssuesLiveFolderInCurrentSpace(in windowState: BrowserWindowState) {
        guard let space = spaceForSidebarActions(in: windowState) else { return }
        dependencies.liveFolderManager().createGitHubFolder(in: space.id, kind: .githubIssues)
    }

    func updateFloatingBarDraft(
        in windowState: BrowserWindowState,
        text: String
    ) {
        floatingBarNavigationOwner.updateDraft(
            in: windowState,
            text: text,
            actions: floatingBarActions
        )
    }

    func dismissFloatingBar(
        in windowState: BrowserWindowState,
        preserveDraft: Bool,
        cancelEmptySplitPlaceholder: Bool
    ) {
        floatingBarNavigationOwner.dismiss(
            in: windowState,
            preserveDraft: preserveDraft,
            cancelEmptySplitPlaceholder: cancelEmptySplitPlaceholder,
            actions: floatingBarActions
        )
    }

    func dismissFloatingBarForActiveWindow(preserveDraft: Bool) {
        floatingBarNavigationOwner.dismissActiveWindow(
            preserveDraft: preserveDraft,
            actions: floatingBarActions
        )
    }

    @discardableResult
    func dismissFloatingBarIfVisible(
        in windowId: UUID,
        preserveDraft: Bool
    ) -> Bool {
        floatingBarNavigationOwner.dismissIfVisible(
            in: windowId,
            preserveDraft: preserveDraft,
            actions: floatingBarActions
        )
    }

    func floatingBarCommitNavigatesCurrentTab(in windowState: BrowserWindowState) -> Bool {
        floatingBarNavigationOwner.commitNavigatesCurrentTab(
            in: windowState,
            actions: floatingBarActions
        )
    }

    func commitFloatingBarSuggestion(
        _ suggestion: SearchManager.SearchSuggestion,
        in windowState: BrowserWindowState,
        navigatesCurrentTab: Bool
    ) {
        floatingBarNavigationOwner.commitSuggestion(
            suggestion,
            in: windowState,
            navigatesCurrentTab: navigatesCurrentTab,
            actions: floatingBarActions
        )
    }

    func commitFloatingBarNavigation(
        to urlString: String,
        in windowState: BrowserWindowState,
        navigatesCurrentTab: Bool
    ) {
        floatingBarNavigationOwner.commitNavigation(
            to: urlString,
            in: windowState,
            navigatesCurrentTab: navigatesCurrentTab,
            actions: floatingBarActions
        )
    }

    func openFloatingBarSuggestion(
        _ suggestion: SearchManager.SearchSuggestion,
        in windowState: BrowserWindowState,
        navigatesCurrentTab: Bool
    ) {
        floatingBarNavigationOwner.openSuggestion(
            suggestion,
            in: windowState,
            navigatesCurrentTab: navigatesCurrentTab,
            actions: floatingBarActions
        )
    }

    func dismissFloatingBarAfterSelection(in windowState: BrowserWindowState) {
        floatingBarNavigationOwner.dismissAfterSelection(
            in: windowState,
            actions: floatingBarActions
        )
    }

    func sanitizeFloatingBarState(in windowState: BrowserWindowState) {
        floatingBarNavigationOwner.sanitize(
            in: windowState,
            hasValidCurrentSelection: dependencies.hasValidCurrentSelection(windowState),
            actions: floatingBarActions
        )
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

    private var floatingBarActions: FloatingBarNavigationOwner.Actions {
        FloatingBarNavigationOwner.Actions(
            activeWindow: {
                self.dependencies.windowRegistry()?.activeWindow
            },
            window: { windowId in
                self.dependencies.windowRegistry()?.windows[windowId]
            },
            activePageTab: dependencies.activePageTab,
            cancelEmptySplitPlaceholder: dependencies.cancelEmptySplitPlaceholder,
            commitEmptySplitPlaceholder: dependencies.commitEmptySplitPlaceholder,
            replaceEmptySplitPlaceholder: dependencies.replaceEmptySplitPlaceholder,
            selectTab: dependencies.selectTab,
            createNewTab: { [weak self] windowState, url in
                self?.createNewTab(in: windowState, url: url)
            },
            createNewTabAfterSidebarInsertion: { [weak self] windowState, url in
                self?.createNewTabAfterSidebarInsertion(in: windowState, url: url)
            },
            configuredNewTabPageURL: {
                guard let settings = self.dependencies.settings(),
                      settings.newTabMode == .specificPage
                else {
                    return nil
                }
                return settings.resolvedNewTabPageURL.absoluteString
            },
            normalizeURL: { text in
                let template = self.dependencies.settings()?.resolvedSearchEngineTemplate
                    ?? SearchProvider.google.queryTemplate
                return Sumi.normalizeURL(text, queryTemplate: template)
            },
            applySettingsSurfaceNavigation: { text in
                let template = self.dependencies.settings()?.resolvedSearchEngineTemplate
                    ?? SearchProvider.google.queryTemplate
                let normalized = Sumi.normalizeURL(text, queryTemplate: template)
                guard let url = URL(string: normalized),
                      SumiSurface.isSettingsSurfaceURL(url)
                else { return }
                self.dependencies.settings()?.applyNavigationFromSettingsSurfaceURL(url)
            },
            dismissWorkspaceThemePickerIfNeededDiscarding: dependencies.dismissWorkspaceThemePickerIfNeededDiscarding,
            persistWindowSession: dependencies.persistWindowSession,
            schedulePersistWindowSession: { windowState in
                self.dependencies.schedulePersistWindowSession(windowState, 450_000_000)
            }
        )
    }

    private func promptForLiveFolderFeedURL() -> String? {
        let alert = NSAlert()
        alert.messageText = "New RSS Live Folder"
        alert.informativeText = "Enter an RSS or Atom feed URL."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "https://example.com/feed.xml"
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased()) else {
            return nil
        }
        return value
    }
}

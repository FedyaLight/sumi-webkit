import AppKit
import SwiftData

/// Adapts app-shell entry points (AppDelegate menu/mouse commands, window
/// lifecycle, persistence, and termination hooks) to the browser owners that
/// execute them. Replaces the former god-object conformances of
/// `BrowserManager` to the app routing protocols.
@MainActor
final class BrowserAppCommandRouter {
    struct Dependencies {
        let floatingBarRouting: @MainActor () -> BrowserFloatingBarRoutingOwner?
        let historyNavigation: @MainActor () -> BrowserHistoryNavigationOwner?
        let windowShellCommands: @MainActor () -> BrowserWindowShellCommandOwner?
        let activePageRouting: @MainActor () -> BrowserActivePageRoutingOwner?
        let themeEditor: @MainActor () -> BrowserWorkspaceThemeEditorOwner?
        let requireTabManager: @MainActor () -> TabManager
        let requireModelContext: @MainActor () -> ModelContext
        let closeCurrentTab: @MainActor () -> Void
        let closeCurrentTabInWindow: @MainActor (BrowserWindowState) -> Void
        let persistWindowSession: @MainActor (BrowserWindowState) -> Void
        let cleanupAllTabs: @MainActor () -> Void
        let flushPendingWindowSessionPersistence: @MainActor () -> Void
        let performAllWindowsClosedSiteDataCleanup: @MainActor () async -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }
}

extension BrowserAppCommandRouter: BrowserMouseButtonCommandRouting {
    func focusFloatingBar(
        in windowState: BrowserWindowState,
        prefill: String,
        navigateCurrentTab: Bool
    ) {
        dependencies.floatingBarRouting()?.focusFloatingBar(
            in: windowState,
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            presentationReason: .keyboard
        )
    }

    func goBack(in windowState: BrowserWindowState) {
        dependencies.historyNavigation()?.goBack(in: windowState)
    }

    func goForward(in windowState: BrowserWindowState) {
        dependencies.historyNavigation()?.goForward(in: windowState)
    }
}

extension BrowserAppCommandRouter: BrowserTabCommandRouting {
    func closeCurrentTab() {
        dependencies.closeCurrentTab()
    }

    func closeCurrentTab(in windowState: BrowserWindowState) {
        dependencies.closeCurrentTabInWindow(windowState)
    }
}

extension BrowserAppCommandRouter: WindowCommandRouting {
    func closeActiveWindow() {
        dependencies.windowShellCommands()?.closeActiveWindow()
    }

    func closeWindow(_ windowState: BrowserWindowState) {
        dependencies.windowShellCommands()?.closeWindow(windowState)
    }
}

extension BrowserAppCommandRouter: BrowserWindowLifecycleHandling {
    var tabManager: TabManager {
        dependencies.requireTabManager()
    }

    func persistWindowSession(for windowState: BrowserWindowState) {
        dependencies.persistWindowSession(windowState)
    }
}

extension BrowserAppCommandRouter: ExternalURLHandling {
    func presentExternalURL(_ url: URL) {
        dependencies.activePageRouting()?.presentExternalURL(url)
    }
}

extension BrowserAppCommandRouter: BrowserPersistenceHandling {
    var modelContext: ModelContext {
        dependencies.requireModelContext()
    }

    func cleanupAllTabs() {
        dependencies.cleanupAllTabs()
    }

    func flushPendingWindowSessionPersistence() {
        dependencies.flushPendingWindowSessionPersistence()
    }

    func flushRuntimeStatePersistenceAwaitingResult() async -> Int {
        await dependencies.requireTabManager().flushRuntimeStatePersistenceAwaitingResult()
    }

    func persistFullReconcileAwaitingResult(reason: String) async -> Bool {
        await dependencies.requireTabManager().persistFullReconcileAwaitingResult(reason: reason)
    }
}

extension BrowserAppCommandRouter: BrowserAppTerminationHandling {
    func dismissFloatingBarForActiveWindow(preserveDraft: Bool) {
        dependencies.floatingBarRouting()?.dismissFloatingBarForActiveWindow(
            preserveDraft: preserveDraft
        )
    }

    func dismissThemePickerCommittingIfNeeded() {
        dependencies.themeEditor()?.dismissThemePickerCommittingIfNeeded()
    }

    func performAllWindowsClosedSiteDataCleanup() async {
        await dependencies.performAllWindowsClosedSiteDataCleanup()
    }
}

extension BrowserAppCommandRouter.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            floatingBarRouting: { [weak browserManager] in
                browserManager?.floatingBarRoutingOwner
            },
            historyNavigation: { [weak browserManager] in
                browserManager?.historyNavigationOwner
            },
            windowShellCommands: { [weak browserManager] in
                browserManager?.windowShellCommandOwner
            },
            activePageRouting: { [weak browserManager] in
                browserManager?.activePageRoutingOwner
            },
            themeEditor: { [weak browserManager] in
                browserManager?.workspaceThemeEditorOwner
            },
            requireTabManager: { [weak browserManager] in
                guard let browserManager else {
                    preconditionFailure(
                        "BrowserManager was released before app command routing resolved TabManager."
                    )
                }
                return browserManager.tabManager
            },
            requireModelContext: { [weak browserManager] in
                guard let browserManager else {
                    preconditionFailure(
                        "BrowserManager was released before app command routing resolved ModelContext."
                    )
                }
                return browserManager.modelContext
            },
            closeCurrentTab: { [weak browserManager] in
                browserManager?.tabLifecycleService.closeOrchestration.closeCurrentTab()
            },
            closeCurrentTabInWindow: { [weak browserManager] windowState in
                browserManager?.tabLifecycleService.closeOrchestration.closeCurrentTab(
                    in: windowState
                )
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.persistWindowSession(for: windowState)
            },
            cleanupAllTabs: { [weak browserManager] in
                browserManager?.shutdownCleanupOwner.cleanupAllTabs()
            },
            flushPendingWindowSessionPersistence: { [weak browserManager] in
                browserManager?.flushPendingWindowSessionPersistence()
            },
            performAllWindowsClosedSiteDataCleanup: { [weak browserManager] in
                guard let browserManager else { return }
                await browserManager.dataServices.siteDataPolicyEnforcementService
                    .performAllWindowsClosedCleanup(
                        profiles: browserManager.profileManager.profiles
                    )
            }
        )
    }
}

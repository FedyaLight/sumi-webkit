import Foundation

/// Performs the concrete browser-resource teardown required before app
/// termination. Every collaborator remains usable after BrowserManager itself
/// is released, allowing AppKit's asynchronous quit finalizer to finish.
@MainActor
final class BrowserShutdownCleanupService {
    private var didCleanUp = false
    private let extensions: SumiExtensionsModule
    private let auxiliaryWindows: AuxiliaryWindowTeardownRegistry
    private let glance: GlanceManager
    private let tabs: TabManager
    private let shell: BrowserShellRuntime

    init(
        extensions: SumiExtensionsModule,
        auxiliaryWindows: AuxiliaryWindowTeardownRegistry,
        glance: GlanceManager,
        tabs: TabManager,
        shell: BrowserShellRuntime
    ) {
        self.extensions = extensions
        self.auxiliaryWindows = auxiliaryWindows
        self.glance = glance
        self.tabs = tabs
        self.shell = shell
    }

    func cleanupAllTabs() {
        guard beginCleanup() else { return }
        RuntimeDiagnostics.emit("🔄 [BrowserShutdown] Cleaning up all tabs")
        extensions.cancelNativeMessagingSessionsIfLoaded(
            reason: "BrowserShutdown.cleanupAllTabs"
        )
        extensions.closeAllOptionsWindowsIfLoaded()
        auxiliaryWindows.closeAllIfLoaded(reason: .appQuit)
        glance.dismissGlance(persistsWindowSession: false)

        for tab in uniqueTabsForCleanup() {
            RuntimeDiagnostics.emit("🔄 [BrowserShutdown] Cleaning up tab: \(tab.name)")
            tab.cleanupNormalTabPermissionRuntime(reason: "browser-shutdown-cleanup-all-tabs")
            tab.performComprehensiveWebViewCleanup()
        }

        shell.webViewCoordinator?.lifecycleService.cleanupAllWebViews()
    }

    /// Terminal fallback for an AppKit quit callback that outlived the browser
    /// root. It must not touch Tab runtime ports, which intentionally fail fast
    /// once BrowserManager is gone.
    func cleanupAfterBrowserRuntimeDeallocation() {
        guard beginCleanup() else { return }
        RuntimeDiagnostics.emit(
            "🔄 [BrowserShutdown] Cleaning up after browser runtime deallocation"
        )
        extensions.cancelNativeMessagingSessionsIfLoaded(
            reason: "BrowserShutdown.cleanupAfterBrowserRuntimeDeallocation"
        )
        extensions.closeAllOptionsWindowsIfLoaded()
        glance.dismissGlance(persistsWindowSession: false)
        shell.webViewCoordinator?.lifecycleService
            .cleanupAfterBrowserRuntimeDeallocation()
        auxiliaryWindows.closeAllAfterBrowserRuntimeDeallocationIfLoaded()
    }

    private func uniqueTabsForCleanup() -> [Tab] {
        Self.uniqueTabsForCleanup(
            essential: tabs.shortcutPresentationOwner
                .activeShortcutTabs(role: .essential),
            all: tabs.tabCollectionMembershipOwner.allTabs(),
            ephemeral: shell.windowRegistry?.allWindows
                .flatMap(\.ephemeralTabs) ?? []
        )
    }

    private func beginCleanup() -> Bool {
        guard didCleanUp == false else { return false }
        didCleanUp = true
        return true
    }

    static func uniqueTabsForCleanup(
        essential: [Tab],
        all: [Tab],
        ephemeral: [Tab]
    ) -> [Tab] {
        var seenTabIDs = Set<UUID>()
        var result: [Tab] = []

        func append(_ tab: Tab) {
            guard seenTabIDs.insert(tab.id).inserted else { return }
            result.append(tab)
        }

        essential.forEach(append)
        all.forEach(append)
        ephemeral.forEach(append)
        return result
    }
}

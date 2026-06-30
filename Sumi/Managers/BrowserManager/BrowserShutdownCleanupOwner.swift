import Foundation

@MainActor
final class BrowserShutdownCleanupOwner {
    struct Dependencies {
        let emitDiagnostic: @MainActor (String) -> Void
        let cancelNativeMessagingSessions: @MainActor (String) -> Void
        let closeAllOptionsWindows: @MainActor () -> Void
        let closeAllAuxiliaryWindows: @MainActor () -> Void
        let dismissGlance: @MainActor () -> Void
        let pinnedTabs: @MainActor () -> [Tab]
        let regularTabs: @MainActor () -> [Tab]
        let ephemeralTabs: @MainActor () -> [Tab]
        let cleanupTab: @MainActor (Tab) -> Void
        let cleanupAllWebViews: @MainActor () -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func cleanupAllTabs() {
        dependencies.emitDiagnostic("🔄 [BrowserManager] Cleaning up all tabs")
        dependencies.cancelNativeMessagingSessions("BrowserManager.cleanupAllTabs")
        dependencies.closeAllOptionsWindows()
        dependencies.closeAllAuxiliaryWindows()
        dependencies.dismissGlance()

        for tab in uniqueTabsForCleanup() {
            dependencies.cleanupTab(tab)
        }

        dependencies.cleanupAllWebViews()
    }

    private func uniqueTabsForCleanup() -> [Tab] {
        var seenTabIDs = Set<UUID>()
        var tabs: [Tab] = []

        func append(_ tab: Tab) {
            guard seenTabIDs.insert(tab.id).inserted else { return }
            tabs.append(tab)
        }

        dependencies.pinnedTabs().forEach(append)
        dependencies.regularTabs().forEach(append)
        dependencies.ephemeralTabs().forEach(append)
        return tabs
    }
}

extension BrowserShutdownCleanupOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            emitDiagnostic: { message in
                RuntimeDiagnostics.emit(message)
            },
            cancelNativeMessagingSessions: { [weak browserManager] reason in
                browserManager?.extensionsModule.cancelNativeMessagingSessionsIfLoaded(reason: reason)
            },
            closeAllOptionsWindows: { [weak browserManager] in
                browserManager?.extensionsModule.closeAllOptionsWindowsIfLoaded()
            },
            closeAllAuxiliaryWindows: { [weak browserManager] in
                browserManager?.auxiliaryWindowManager.closeAll(reason: .appQuit)
            },
            dismissGlance: { [weak browserManager] in
                browserManager?.glanceManager.dismissGlance(persistsWindowSession: false)
            },
            pinnedTabs: { [weak browserManager] in
                browserManager?.tabManager.allPinnedTabsAllProfiles ?? []
            },
            regularTabs: { [weak browserManager] in
                browserManager?.tabManager.allTabs() ?? []
            },
            ephemeralTabs: { [weak browserManager] in
                browserManager?.windowRegistry?.allWindows.flatMap(\.ephemeralTabs) ?? []
            },
            cleanupTab: { tab in
                RuntimeDiagnostics.emit("🔄 [BrowserManager] Cleaning up tab: \(tab.name)")
                tab.cleanupNormalTabPermissionRuntime(reason: "browser-manager-cleanup-all-tabs")
                tab.performComprehensiveWebViewCleanup()
            },
            cleanupAllWebViews: { [weak browserManager] in
                guard let browserManager else { return }
                browserManager.webViewCoordinator?.cleanupAllWebViews(
                    tabManager: browserManager.tabManager
                )
            }
        )
    }
}

import Foundation

@MainActor
final class BrowserShutdownCleanupOwner {
    private let emitDiagnostic: @MainActor (String) -> Void
    private let cancelNativeMessagingSessions: @MainActor (String) -> Void
    private let closeAllOptionsWindows: @MainActor () -> Void
    private let closeAllAuxiliaryWindows: @MainActor () -> Void
    private let dismissGlance: @MainActor () -> Void
    private let pinnedTabs: @MainActor () -> [Tab]
    private let regularTabs: @MainActor () -> [Tab]
    private let ephemeralTabs: @MainActor () -> [Tab]
    private let cleanupTab: @MainActor (Tab) -> Void
    private let cleanupAllWebViews: @MainActor () -> Void

    init(
        emitDiagnostic: @escaping @MainActor (String) -> Void,
        cancelNativeMessagingSessions: @escaping @MainActor (String) -> Void,
        closeAllOptionsWindows: @escaping @MainActor () -> Void,
        closeAllAuxiliaryWindows: @escaping @MainActor () -> Void,
        dismissGlance: @escaping @MainActor () -> Void,
        pinnedTabs: @escaping @MainActor () -> [Tab],
        regularTabs: @escaping @MainActor () -> [Tab],
        ephemeralTabs: @escaping @MainActor () -> [Tab],
        cleanupTab: @escaping @MainActor (Tab) -> Void,
        cleanupAllWebViews: @escaping @MainActor () -> Void
    ) {
        self.emitDiagnostic = emitDiagnostic
        self.cancelNativeMessagingSessions = cancelNativeMessagingSessions
        self.closeAllOptionsWindows = closeAllOptionsWindows
        self.closeAllAuxiliaryWindows = closeAllAuxiliaryWindows
        self.dismissGlance = dismissGlance
        self.pinnedTabs = pinnedTabs
        self.regularTabs = regularTabs
        self.ephemeralTabs = ephemeralTabs
        self.cleanupTab = cleanupTab
        self.cleanupAllWebViews = cleanupAllWebViews
    }

    convenience init(browserManager: BrowserManager) {
        self.init(
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
                browserManager?.tabManager.shortcutPresentationOwner.activeShortcutTabs(role: .essential) ?? []
            },
            regularTabs: { [weak browserManager] in
                browserManager?.tabManager.tabCollectionMembershipOwner.allTabs() ?? []
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

    func cleanupAllTabs() {
        emitDiagnostic("🔄 [BrowserManager] Cleaning up all tabs")
        cancelNativeMessagingSessions("BrowserManager.cleanupAllTabs")
        closeAllOptionsWindows()
        closeAllAuxiliaryWindows()
        dismissGlance()

        for tab in uniqueTabsForCleanup() {
            cleanupTab(tab)
        }

        cleanupAllWebViews()
    }

    private func uniqueTabsForCleanup() -> [Tab] {
        var seenTabIDs = Set<UUID>()
        var tabs: [Tab] = []

        func append(_ tab: Tab) {
            guard seenTabIDs.insert(tab.id).inserted else { return }
            tabs.append(tab)
        }

        pinnedTabs().forEach(append)
        regularTabs().forEach(append)
        ephemeralTabs().forEach(append)
        return tabs
    }
}

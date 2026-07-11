import Foundation

/// Rewrites a shortcut-hosted split back to canonical pin proxies and retires
/// every window-local live instance in one structural publication.
@MainActor
final class ShortcutHostedSplitUnloadService {
    private let runtimeLease: () -> SplitShortcutRuntimeLease?
    private let selectTabWithoutPersistence: (Tab, BrowserWindowState) -> Void
    private let showEmptyStateWithoutPersistence: (BrowserWindowState) -> Void
    private let performImmediateVisualHandoff: (BrowserWindowState) -> Void
    private let refreshCompositor: (BrowserWindowState) -> Void
    private let persistWindowSession: (BrowserWindowState) -> Void

    init(
        runtimeLease: @escaping () -> SplitShortcutRuntimeLease?,
        selectTabWithoutPersistence: @escaping (Tab, BrowserWindowState) -> Void,
        showEmptyStateWithoutPersistence: @escaping (BrowserWindowState) -> Void,
        performImmediateVisualHandoff: @escaping (BrowserWindowState) -> Void,
        refreshCompositor: @escaping (BrowserWindowState) -> Void,
        persistWindowSession: @escaping (BrowserWindowState) -> Void
    ) {
        self.runtimeLease = runtimeLease
        self.selectTabWithoutPersistence = selectTabWithoutPersistence
        self.showEmptyStateWithoutPersistence = showEmptyStateWithoutPersistence
        self.performImmediateVisualHandoff = performImmediateVisualHandoff
        self.refreshCompositor = refreshCompositor
        self.persistWindowSession = persistWindowSession
    }

    @discardableResult
    func unloadShortcutHostedSplitGroup(
        _ group: SplitGroup,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard let runtime = runtimeLease() else { return false }
        guard group.isShortcutHosted else { return false }
        let tabManager = runtime.tabManager
        var retirements: [PreparedShortcutLiveTabRetirement] = []
        var hasVisualReplacement = false
        var didCommit = false
        tabManager.structuralLookupCoordinator.withTransaction {
            var proxyGroup = group
            for member in group.members where member.isShortcutBacked {
                guard let pinId = member.pinId else { continue }
                guard let retirement = tabManager.shortcutLiveTabRetirement
                    .prepareRetirement(
                        pinId: pinId,
                        in: windowState.id
                    ) else { return }
                retirements.append(retirement)
                if group.tabIds.contains(member.tabId) {
                    proxyGroup = proxyGroup.replacingMemberTab(
                        member.tabId,
                        with: pinId
                    )
                }
            }
            hasVisualReplacement = prepareVisualReplacement(
                in: windowState,
                tabManager: tabManager
            )
            tabManager.splitGroupStructureOwner.upsertSplitGroup(
                proxyGroup.settingActiveTab(proxyGroup.tabIds.first)
            )
            didCommit = true
        }
        guard didCommit else { return false }
        if hasVisualReplacement == false {
            showEmptyStateWithoutPersistence(windowState)
            performImmediateVisualHandoff(windowState)
        }
        retirements.forEach {
            _ = tabManager.shortcutLiveTabRetirement.finish($0)
        }
        runtime.splitManager.refreshPublishedState(for: windowState.id)
        refreshCompositor(windowState)
        persistWindowSession(windowState)
        return true
    }

    private func prepareVisualReplacement(
        in windowState: BrowserWindowState,
        tabManager: TabManager
    ) -> Bool {
        guard let fallback = fallbackVisibleRegularTab(
            in: windowState,
            tabManager: tabManager
        ) else {
            return false
        }
        selectTabWithoutPersistence(fallback, windowState)
        performImmediateVisualHandoff(windowState)
        return true
    }

    private func fallbackVisibleRegularTab(
        in windowState: BrowserWindowState,
        tabManager: TabManager
    ) -> Tab? {
        guard let spaceId = windowState.currentSpaceId,
              let space = tabManager.spaceStateOwner.space(with: spaceId)
        else { return nil }
        return tabManager.regularTabCollectionOwner.tabs(in: space).first
    }
}

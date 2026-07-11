import Foundation

/// Materializes shortcut split leaves and applies window focus. All selection
/// mutations are non-persisting; public operations own one final session write.
@MainActor
final class SplitShortcutFocusService {
    private let runtimeLease: () -> SplitShortcutRuntimeLease?
    private let selectTabWithoutPersistence: (Tab, BrowserWindowState) -> Void
    private let refreshCompositor: (BrowserWindowState) -> Void
    private let persistWindowSession: (BrowserWindowState) -> Void

    init(
        runtimeLease: @escaping () -> SplitShortcutRuntimeLease?,
        selectTabWithoutPersistence: @escaping (Tab, BrowserWindowState) -> Void,
        refreshCompositor: @escaping (BrowserWindowState) -> Void,
        persistWindowSession: @escaping (BrowserWindowState) -> Void
    ) {
        self.runtimeLease = runtimeLease
        self.selectTabWithoutPersistence = selectTabWithoutPersistence
        self.refreshCompositor = refreshCompositor
        self.persistWindowSession = persistWindowSession
    }

    func focusSplitGroup(
        _ group: SplitGroup,
        in windowState: BrowserWindowState
    ) {
        guard let runtime = runtimeLease() else { return }
        guard canFocus(group, in: windowState) else {
            queueFocus(group, in: windowState)
            return
        }
        guard applyFocusWithinRuntimeLease(
            group,
            in: windowState,
            runtime: runtime
        ) else { return }
        persistWindowSession(windowState)
    }

    func completePendingSplitGroupFocusIfReady(
        in windowState: BrowserWindowState,
        spaceId: UUID
    ) {
        guard let runtime = runtimeLease(),
              let request = windowState.pendingSplitGroupFocusRequest,
              request.targetSpaceId == spaceId else { return }

        windowState.pendingSplitGroupFocusRequest = nil
        guard let group = runtime.tabManager.splitGroupCollectionStateOwner
            .group(with: request.groupId),
              applyFocusWithinRuntimeLease(
                group,
                in: windowState,
                runtime: runtime
              ) else {
            refreshCompositor(windowState)
            return
        }
        persistWindowSession(windowState)
    }

    /// Internal transaction helper for a caller that already owns the one
    /// runtime lease for its complete mutation sequence.
    @discardableResult
    func applyFocusWithinRuntimeLease(
        _ group: SplitGroup,
        in windowState: BrowserWindowState,
        runtime: SplitShortcutRuntimeLease
    ) -> Bool {
        guard canFocus(group, in: windowState) else { return false }
        let tabManager = runtime.tabManager
        let resolvedGroup = materializeShortcutMembers(
            in: group,
            windowState: windowState,
            tabManager: tabManager
        )
        let targetTabId = resolvedGroup.activeTabId
            .flatMap { resolvedGroup.contains($0) ? $0 : nil }
            ?? resolvedGroup.tabIds.first
        guard let targetTab = targetTabId.flatMap(
            tabManager.tabCollectionMembershipOwner.tab(for:)
        ) else {
            refreshCompositor(windowState)
            return false
        }

        if tabManager.splitGroupCollectionStateOwner
            .group(with: resolvedGroup.id) == nil {
            tabManager.splitGroupStructureOwner.upsertSplitGroup(resolvedGroup)
        }
        selectTabWithoutPersistence(targetTab, windowState)
        runtime.splitManager.refreshPublishedState(for: windowState.id)
        refreshCompositor(windowState)
        return true
    }

    /// Internal counterpart used by a larger operation-scoped lease.
    func refreshPresentationWithinRuntimeLease(
        in windowState: BrowserWindowState,
        runtime: SplitShortcutRuntimeLease
    ) {
        runtime.splitManager.refreshPublishedState(for: windowState.id)
        refreshCompositor(windowState)
    }

    private func canFocus(
        _ group: SplitGroup,
        in windowState: BrowserWindowState
    ) -> Bool {
        group.hostSpaceId == nil
            || group.hostSpaceId == windowState.currentSpaceId
    }

    private func queueFocus(
        _ group: SplitGroup,
        in windowState: BrowserWindowState
    ) {
        guard let hostSpaceId = group.hostSpaceId else { return }
        windowState.pendingSplitGroupFocusRequest = SplitGroupFocusRequest(
            groupId: group.id,
            targetSpaceId: hostSpaceId
        )
    }

    private func materializeShortcutMembers(
        in group: SplitGroup,
        windowState: BrowserWindowState,
        tabManager: TabManager
    ) -> SplitGroup {
        var updatedGroup = group
        var didChange = false

        for leafId in group.tabIds
            where tabManager.tabCollectionMembershipOwner.tab(for: leafId) == nil {
            guard let member = updatedGroup.member(for: leafId),
                  let pinId = member.pinId,
                  let pin = tabManager.shortcutPinCollectionStateOwner
                    .shortcutPin(by: pinId) else { continue }
            let liveTab = tabManager.shortcutTabMaterializer.materialize(
                pin,
                in: windowState.id,
                currentSpaceId: group.hostSpaceId
                    ?? pin.spaceId
                    ?? windowState.currentSpaceId
            )
            updatedGroup = updatedGroup.replacingMemberTab(
                leafId,
                with: liveTab.id
            )
            didChange = true
        }
        for member in updatedGroup.members where member.isShortcutBacked {
            guard updatedGroup.tabIds.contains(member.tabId),
                  tabManager.tabCollectionMembershipOwner
                    .tab(for: member.tabId) == nil,
                  let pinId = member.pinId,
                  let pin = tabManager.shortcutPinCollectionStateOwner
                    .shortcutPin(by: pinId) else { continue }
            let liveTab = tabManager.shortcutTabMaterializer.materialize(
                pin,
                in: windowState.id,
                currentSpaceId: group.hostSpaceId
                    ?? pin.spaceId
                    ?? windowState.currentSpaceId
            )
            updatedGroup = updatedGroup.replacingMemberTab(
                member.tabId,
                with: liveTab.id
            )
            didChange = true
        }
        if didChange {
            tabManager.splitGroupStructureOwner.upsertSplitGroup(updatedGroup)
        }
        return updatedGroup
    }
}

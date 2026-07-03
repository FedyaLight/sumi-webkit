import CoreGraphics
import Foundation
import SwiftUI

@MainActor
struct SplitViewRuntime {
    let tabManager: @MainActor () -> TabManager?
    let currentTab: @MainActor (BrowserWindowState) -> Tab?
    let selectTab: @MainActor (Tab, BrowserWindowState) -> Void
    let refreshCompositor: @MainActor (BrowserWindowState) -> Void
    let schedulePersistWindowSession: @MainActor (BrowserWindowState) -> Void
    let focusFloatingBar: @MainActor (BrowserWindowState, FloatingBarPresentationReason) -> Void
}

@MainActor
final class SplitViewManager: ObservableObject {
    typealias WindowSplitPreviewState = SplitPreviewStateOwner.WindowSplitPreviewState

    weak var windowRegistry: WindowRegistry?
    private var runtime: SplitViewRuntime?

    private var splitDropTargetResolver = SplitDropTargetResolver()

    private lazy var previewStateOwner = SplitPreviewStateOwner(
        activeWindowId: { [weak self] in self?.windowRegistry?.activeWindow?.id },
        notifyActiveWindowPreviewChanged: { [weak self] in self?.objectWillChange.send() },
        refreshWindow: { [weak self] windowId in self?.refreshWindow(windowId) }
    )

    private lazy var membershipResolutionOwner = SplitMembershipResolutionOwner(
        tabManager: { [weak self] in self?.tabManager }
    )

    private lazy var emptyPlaceholderOwner = SplitEmptyPlaceholderOwner(
        tabManager: { [weak self] in self?.tabManager },
        membershipResolution: membershipResolutionOwner,
        selectTab: { [weak self] tab, windowState in self?.runtime?.selectTab(tab, windowState) },
        notifyChanged: { [weak self] windowId in self?.notifyChanged(for: windowId) }
    )

    init(runtime: SplitViewRuntime? = nil) {
        self.runtime = runtime
    }

    func attach(runtime: SplitViewRuntime) {
        self.runtime = runtime
    }

    private var tabManager: TabManager? {
        runtime?.tabManager()
    }

    // MARK: - Queries

    func previewState(for windowId: UUID) -> WindowSplitPreviewState {
        previewStateOwner.previewState(for: windowId)
    }

    func splitGroup(for windowId: UUID) -> SplitGroup? {
        guard let windowState = windowRegistry?.windows[windowId] else { return nil }
        guard let currentTabId = windowState.currentTabId else { return nil }
        return tabManager?.splitGroupStructureOwner.splitGroup(containing: currentTabId)
    }

    func visibleTabIds(for windowId: UUID) -> [UUID] {
        guard isPreviewActive(for: windowId) == false else {
            guard let windowState = windowRegistry?.windows[windowId] else { return [] }
            return windowState.currentTabId.map { [$0] } ?? []
        }
        return splitGroup(for: windowId)?.tabIds ?? []
    }

    func isSplit(for windowId: UUID) -> Bool {
        splitGroup(for: windowId) != nil
    }

    func isTabVisibleInSplit(_ tabId: UUID, in windowId: UUID) -> Bool {
        splitGroup(for: windowId)?.contains(tabId) == true
    }

    func isTabActiveInSplit(_ tabId: UUID, in windowId: UUID) -> Bool {
        let group = splitGroup(for: windowId)
        return activeTabId(for: windowId, in: group) == tabId
    }

    func isPreviewActive(for windowId: UUID) -> Bool {
        previewStateOwner.isPreviewActive(for: windowId)
    }

    // MARK: - Layout & lifecycle

    func updateLayoutSizes(groupId: UUID, path: [Int], sizes: [Double], for windowId: UUID) {
        guard let tabManager,
              let group = tabManager.splitGroupCollectionStateOwner.group(with: groupId)
        else { return }
        let updatedTree = group.layoutTree
            .updatingChildSizes(at: path, sizes: sizes)
            .canonicalizedForTiles() ?? group.layoutTree
        tabManager.splitGroupStructureOwner.upsertSplitGroup(
            SplitGroup(
                id: group.id,
                layoutKind: group.layoutKind,
                layoutTree: updatedTree,
                activeTabId: activeTabId(for: windowId, in: group),
                host: group.host,
                members: group.members
            )
        )
        notifyChanged(for: windowId)
    }

    func refreshPublishedState(for windowId: UUID) {
        previewStateOwner.syncPublishedStateIfNeeded(for: windowId)
    }

    func cleanupWindow(_ windowId: UUID) {
        emptyPlaceholderOwner.cleanupWindow(windowId)
        previewStateOwner.cleanupWindow(windowId)
    }

    func handleTabClosure(_ tabId: UUID) {
        splitDropTargetResolver.removeAllCachedCandidates(keepingCapacity: true)
        tabManager?.splitGroupStructureOwner.removeSplitGroups(containing: tabId)
        guard let windows = windowRegistry?.windows else { return }
        for windowState in windows.values {
            runtime?.refreshCompositor(windowState)
        }
        objectWillChange.send()
    }

    func updateActiveSide(for tabId: UUID, in windowId: UUID) {
        guard let tabManager,
              let group = tabManager.splitGroupStructureOwner.splitGroup(containing: tabId)
        else { return }
        tabManager.splitGroupStructureOwner.upsertSplitGroup(group.settingActiveTab(tabId), schedulePersistence: false)
        notifyChanged(for: windowId)
    }

    func exitSplit(for windowId: UUID) {
        guard let group = splitGroup(for: windowId) else { return }
        let windowState = windowRegistry?.windows[windowId]
        let focusTab = windowState.flatMap {
            membershipResolutionOwner.preferredFocusTabAfterUnsplit(group, in: $0)
        }
        tabManager?.splitGroupStructureOwner.removeSplitGroup(id: group.id)
        if let focusTab, let windowState {
            runtime?.selectTab(focusTab, windowState)
        }
        notifyChanged(for: windowId)
    }

    func unsplitActiveGroup(for windowId: UUID) {
        exitSplit(for: windowId)
    }

    func setLayoutKind(_ layoutKind: SplitLayoutKind, for windowId: UUID) {
        guard let group = splitGroup(for: windowId) else { return }
        tabManager?.splitGroupStructureOwner.upsertSplitGroup(group.settingLayoutKind(layoutKind))
        notifyChanged(for: windowId)
    }

    func expandSplitPane(tabId: UUID, in windowState: BrowserWindowState) {
        guard let tabManager,
              let tab = tabManager.tab(for: tabId),
              let group = tabManager.splitGroupStructureOwner.splitGroup(containing: tabId)
        else { return }

        if let remainingGroup = group.removing(tabId: tabId) {
            tabManager.splitGroupStructureOwner.upsertSplitGroup(remainingGroup)
        } else {
            tabManager.splitGroupStructureOwner.removeSplitGroup(id: group.id)
        }
        runtime?.selectTab(tab, windowState)
        runtime?.refreshCompositor(windowState)
        notifyChanged(for: windowState.id)
    }

    // MARK: - Empty split placeholder

    func createEmptySplit(
        side: SplitDropSide = .right,
        in windowState: BrowserWindowState,
        floatingBarPresentationReason: FloatingBarPresentationReason = .keyboard
    ) {
        guard let tabManager,
              let current = runtime?.currentTab(windowState),
              current.representsSumiNativeSurface == false
        else { return }
        let targetSpace =
            windowState.currentSpaceId.flatMap { id in tabManager.spaces.first(where: { $0.id == id }) }
            ?? tabManager.currentSpace
        let tab = tabManager.createNewTab(
            url: SumiSurface.emptyTabURL.absoluteString,
            in: targetSpace,
            activate: false
        )
        enterSplit(with: tab, placeOn: side, in: windowState)
        if tabManager.splitGroupStructureOwner.splitGroup(containing: tab.id) != nil {
            emptyPlaceholderOwner.registerPlaceholder(tabId: tab.id, for: windowState.id)
        }
        runtime?.focusFloatingBar(windowState, floatingBarPresentationReason)
    }

    func commitEmptySplitPlaceholder(tabId: UUID, in windowState: BrowserWindowState) {
        emptyPlaceholderOwner.commitPlaceholder(tabId: tabId, in: windowState)
    }

    @discardableResult
    func replaceEmptySplitPlaceholder(with tab: Tab, in windowState: BrowserWindowState) -> Bool {
        emptyPlaceholderOwner.replacePlaceholder(with: tab, in: windowState)
    }

    @discardableResult
    func cancelEmptySplitPlaceholder(in windowState: BrowserWindowState) -> Bool {
        emptyPlaceholderOwner.cancelPlaceholder(in: windowState)
    }

    // MARK: - Drop commit

    func enterSplit(
        with tab: Tab,
        placeOn side: SplitDropSide = .right,
        in windowState: BrowserWindowState
    ) {
        guard let tabManager else { return }
        guard tab.representsSumiNativeSurface == false else { return }
        guard let current = runtime?.currentTab(windowState), current.representsSumiNativeSurface == false else { return }

        let anchorGroup = tabManager.splitGroupStructureOwner.splitGroup(containing: current.id)
        let anchorTab = anchorGroup?.activeTabId.flatMap { tabManager.tab(for: $0) } ?? current
        dropTab(tab, placeOn: side, relativeTo: anchorTab.id, in: windowState)
    }

    @discardableResult
    func dropTab(
        _ tab: Tab,
        placeOn side: SplitDropSide,
        relativeTo targetTabId: UUID?,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard let tabManager else { return false }
        guard let targetTab = targetTabId.flatMap({ tabManager.tab(for: $0) }) ?? runtime?.currentTab(windowState),
              targetTab.representsSumiNativeSurface == false else { return false }
        return dropTab(
            tab,
            on: SplitDropTarget(tabId: targetTab.id, side: side, targetRect: .zero),
            in: windowState
        )
    }

    @discardableResult
    func dropTab(
        _ tab: Tab,
        on target: SplitDropTarget,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard let tabManager else { return false }
        let side = target.side
        guard tab.representsSumiNativeSurface == false else { return false }
        guard let targetTab = tabManager.tab(for: target.tabId) ?? runtime?.currentTab(windowState),
              targetTab.representsSumiNativeSurface == false
        else { return false }

        let targetGroup = tabManager.splitGroupStructureOwner.splitGroup(containing: targetTab.id)
        if let targetGroup, targetGroup.contains(tab.id) {
            let updated: SplitGroup?
            if let resolved = targetGroup.resolvingDrop(
                draggedTabId: tab.id,
                target: target,
                bounds: target.targetRect
            ) {
                updated = SplitGroup(
                    id: targetGroup.id,
                    layoutKind: targetGroup.layoutKind,
                    layoutTree: resolved.layoutTree,
                    activeTabId: tab.id,
                    host: targetGroup.host,
                    members: targetGroup.members
                )
            } else if target.scope == .group, side != .center {
                updated = targetGroup.movingTabToRootEdge(tab.id, side: side)
            } else {
                updated = targetGroup.movingTab(tab.id, relativeTo: targetTab.id, side: side)
            }
            guard let updated else { return false }
            tabManager.splitGroupStructureOwner.upsertSplitGroup(updated)
            runtime?.selectTab(tab, windowState)
            runtime?.refreshCompositor(windowState)
            notifyChanged(for: windowState.id)
            return true
        }

        let sourceGroup = membershipResolutionOwner.sourceSplitGroup(for: tab)

        if let targetGroup {
            guard let resolvedIncoming = membershipResolutionOwner.resolvedSplitTab(
                tab,
                host: targetGroup.host,
                sourceGroup: sourceGroup,
                in: windowState
            ) else {
                return false
            }
            let group: SplitGroup?
            if side == .center {
                group = SplitGroup(
                    id: targetGroup.id,
                    layoutKind: targetGroup.layoutKind,
                    layoutTree: targetGroup.layoutTree.replacingTab(targetTab.id, with: resolvedIncoming.tab.id),
                    activeTabId: resolvedIncoming.tab.id,
                    host: targetGroup.host,
                    members: targetGroup.removingMember(tabId: targetTab.id).members + [resolvedIncoming.member]
                )
            } else if let resolved = targetGroup.resolvingDrop(
                draggedTabId: resolvedIncoming.tab.id,
                target: target,
                bounds: target.targetRect
            ) {
                group = SplitGroup(
                    id: targetGroup.id,
                    layoutKind: targetGroup.layoutKind,
                    layoutTree: resolved.layoutTree,
                    activeTabId: resolvedIncoming.tab.id,
                    host: targetGroup.host,
                    members: targetGroup.upsertingMember(resolvedIncoming.member).members
                )
            } else if target.scope == .group {
                group = targetGroup.insertingAtRoot(
                    tabId: resolvedIncoming.tab.id,
                    side: side
                )?.upsertingMember(resolvedIncoming.member)
            } else {
                group = targetGroup.inserting(
                    tabId: resolvedIncoming.tab.id,
                    relativeTo: targetTab.id,
                    side: side
                )?.upsertingMember(resolvedIncoming.member)
            }
            guard let group else { return false }
            removeFromSourceSplitIfNeeded(
                sourceGroup,
                movedTabId: membershipResolutionOwner.sourceRemovalId(for: tab, in: sourceGroup) ?? tab.id,
                excludingGroupId: group.id
            )
            tabManager.splitGroupStructureOwner.upsertSplitGroup(group)
            runtime?.selectTab(resolvedIncoming.tab, windowState)
            runtime?.refreshCompositor(windowState)
            notifyChanged(for: windowState.id)
            return true
        }

        let host = membershipResolutionOwner.initialHost(for: tab, targetTab: targetTab, in: windowState)
        guard let resolvedIncoming = membershipResolutionOwner.resolvedSplitTab(
            tab,
            host: host,
            sourceGroup: sourceGroup,
            in: windowState
        ),
        let resolvedAnchor = membershipResolutionOwner.resolvedSplitTab(
            targetTab,
            host: host,
            sourceGroup: tabManager.splitGroupStructureOwner.splitGroup(containing: targetTab.id),
            in: windowState
        ) else {
            return false
        }
        let ids: [UUID]
        switch side {
        case .left, .top:
            ids = [resolvedIncoming.tab.id, resolvedAnchor.tab.id]
        case .right, .bottom, .center:
            ids = [resolvedAnchor.tab.id, resolvedIncoming.tab.id]
        }
        let kind: SplitLayoutKind = (side == .top || side == .bottom) ? .horizontal : .vertical
        guard let group = SplitGroup.make(
            tabIds: ids,
            layoutKind: kind,
            activeTabId: resolvedIncoming.tab.id,
            host: host,
            members: [resolvedAnchor.member, resolvedIncoming.member]
        ) else { return false }

        removeFromSourceSplitIfNeeded(
            sourceGroup,
            movedTabId: membershipResolutionOwner.sourceRemovalId(for: tab, in: sourceGroup) ?? tab.id,
            excludingGroupId: group.id
        )
        tabManager.splitGroupStructureOwner.upsertSplitGroup(group)
        runtime?.selectTab(resolvedIncoming.tab, windowState)
        runtime?.refreshCompositor(windowState)
        notifyChanged(for: windowState.id)
        return true
    }

    private func removeFromSourceSplitIfNeeded(
        _ sourceGroup: SplitGroup?,
        movedTabId: UUID,
        excludingGroupId: UUID
    ) {
        guard let sourceGroup, sourceGroup.id != excludingGroupId else { return }
        if let remaining = sourceGroup.removing(tabId: movedTabId) {
            tabManager?.splitGroupStructureOwner.upsertSplitGroup(remaining)
        } else {
            tabManager?.splitGroupStructureOwner.removeSplitGroup(id: sourceGroup.id)
        }
    }

    // MARK: - Drop target resolution

    func dropTarget(
        at location: CGPoint,
        in bounds: CGRect,
        for windowId: UUID,
        draggedTabId: UUID? = nil
    ) -> SplitDropTarget? {
        guard bounds.width > 0, bounds.height > 0, bounds.contains(location) else { return nil }
        guard let windowState = windowRegistry?.windows[windowId],
              let tabManager else {
            return nil
        }

        if let currentTabId = windowState.currentTabId,
           let group = tabManager.splitGroupStructureOwner.splitGroup(containing: currentTabId) {
            return splitDropTargetResolver.target(
                in: group,
                at: location,
                bounds: bounds,
                draggedTabId: draggedTabId
            )
        }

        guard let currentTab = windowState.currentTabId.flatMap({ tabManager.tab(for: $0) })
                ?? runtime?.currentTab(windowState),
              currentTab.representsSumiNativeSurface == false else {
            return nil
        }

        return splitDropTargetResolver.firstSplitTarget(
            currentTabId: currentTab.id,
            at: location,
            bounds: bounds,
            draggedTabId: draggedTabId
        )
    }

    // MARK: - Preview

    func beginPreview(
        targetRect: CGRect? = nil,
        style: SplitDropPreviewStyle = .edge,
        for windowId: UUID
    ) {
        previewStateOwner.beginPreview(targetRect: targetRect, style: style, for: windowId)
    }

    func updatePreview(
        targetRect: CGRect?,
        style: SplitDropPreviewStyle = .edge,
        for windowId: UUID
    ) {
        previewStateOwner.updatePreview(targetRect: targetRect, style: style, for: windowId)
    }

    func endPreview(for windowId: UUID) {
        previewStateOwner.endPreview(for: windowId)
    }

    // MARK: - Shared plumbing

    private func activeTabId(for windowId: UUID, in group: SplitGroup?) -> UUID? {
        guard let group else { return nil }
        let current = windowRegistry?.windows[windowId]?.currentTabId
        if let current, group.contains(current) { return current }
        if let active = group.activeTabId, group.contains(active) { return active }
        return group.tabIds.first
    }

    private func notifyChanged(for windowId: UUID) {
        previewStateOwner.syncPublishedStateIfNeeded(for: windowId, forceNotify: true)
        refreshWindow(windowId)
    }

    private func refreshWindow(_ windowId: UUID) {
        if let windowState = windowRegistry?.windows[windowId] {
            runtime?.refreshCompositor(windowState)
            runtime?.schedulePersistWindowSession(windowState)
        }
    }
}

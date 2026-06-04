import CoreGraphics
import Foundation
import SwiftUI

@MainActor
final class SplitViewManager: ObservableObject {
    struct WindowSplitPreviewState: Equatable {
        var isActive: Bool = false
        var targetRect: CGRect? = nil
        var style: SplitDropPreviewStyle = .edge
    }

    private struct TransientWindowSplitState: Equatable {
        var isPreviewActive: Bool = false
        var previewTargetRect: CGRect? = nil
        var previewStyle: SplitDropPreviewStyle = .edge
    }

    private struct FullGroupCandidateCacheKey: Hashable {
        let tabIds: Set<UUID>

        init(tabIds: [UUID]) {
            self.tabIds = Set(tabIds)
        }
    }

    private struct ResolvedSplitTab {
        let tab: Tab
        let member: SplitGroupMember
    }

    private static let previewPlaceholderTabId = UUID()

    private var activeWindowPreviewState = WindowSplitPreviewState()

    weak var browserManager: BrowserManager?
    weak var windowRegistry: WindowRegistry?

    private var transientWindowSplitStates: [UUID: TransientWindowSplitState] = [:]
    private var pendingLegacySnapshotsByWindow: [UUID: LegacySplitSessionSnapshot] = [:]
    private var emptySplitPlaceholderTabIdsByWindow: [UUID: UUID] = [:]
    private var fullGroupCandidateTreesByKey: [FullGroupCandidateCacheKey: [SplitLayoutTree]] = [:]

    init(browserManager: BrowserManager? = nil) {
        self.browserManager = browserManager
    }

    func previewState(for windowId: UUID) -> WindowSplitPreviewState {
        let transient = transientState(for: windowId)
        return WindowSplitPreviewState(
            isActive: transient.isPreviewActive,
            targetRect: transient.previewTargetRect,
            style: transient.previewStyle
        )
    }

    func splitGroup(for windowId: UUID) -> SplitGroup? {
        applyPendingLegacySnapshotIfPossible(for: windowId)
        guard let windowState = windowRegistry?.windows[windowId] else { return nil }
        guard let currentTabId = windowState.currentTabId else { return nil }
        return browserManager?.tabManager.splitGroup(containing: currentTabId)
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
        transientState(for: windowId).isPreviewActive
    }

    func updateLayoutSizes(groupId: UUID, path: [Int], sizes: [Double], for windowId: UUID) {
        guard let group = browserManager?.tabManager.splitGroup(with: groupId) else { return }
        let updatedTree = group.layoutTree
            .updatingChildSizes(at: path, sizes: sizes)
            .canonicalizedForTiles() ?? group.layoutTree
        browserManager?.tabManager.upsertSplitGroup(
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
        syncPublishedStateIfNeeded(for: windowId)
    }

    func cleanupWindow(_ windowId: UUID) {
        transientWindowSplitStates.removeValue(forKey: windowId)
        pendingLegacySnapshotsByWindow.removeValue(forKey: windowId)
        emptySplitPlaceholderTabIdsByWindow.removeValue(forKey: windowId)
        syncPublishedStateIfNeeded(for: windowId)
    }

    func handleTabClosure(_ tabId: UUID) {
        fullGroupCandidateTreesByKey.removeAll(keepingCapacity: true)
        browserManager?.tabManager.removeSplitGroups(containing: tabId)
        guard let windows = windowRegistry?.windows else { return }
        for windowState in windows.values {
            browserManager?.refreshCompositor(for: windowState)
        }
        objectWillChange.send()
    }

    func updateActiveSide(for tabId: UUID, in windowId: UUID) {
        guard let group = browserManager?.tabManager.splitGroup(containing: tabId) else { return }
        browserManager?.tabManager.upsertSplitGroup(group.settingActiveTab(tabId), schedulePersistence: false)
        notifyChanged(for: windowId)
    }

    func exitSplit(for windowId: UUID) {
        guard let group = splitGroup(for: windowId) else { return }
        let windowState = windowRegistry?.windows[windowId]
        let focusTab = windowState.flatMap { preferredFocusTabAfterUnsplit(group, in: $0) }
        browserManager?.tabManager.removeSplitGroup(id: group.id)
        if let focusTab, let windowState {
            browserManager?.selectTab(focusTab, in: windowState)
        }
        notifyChanged(for: windowId)
    }

    func unsplitActiveGroup(for windowId: UUID) {
        exitSplit(for: windowId)
    }

    func setLayoutKind(_ layoutKind: SplitLayoutKind, for windowId: UUID) {
        guard let group = splitGroup(for: windowId) else { return }
        browserManager?.tabManager.upsertSplitGroup(group.settingLayoutKind(layoutKind))
        notifyChanged(for: windowId)
    }

    func createEmptySplit(
        side: SplitDropSide = .right,
        in windowState: BrowserWindowState,
        floatingBarPresentationReason: FloatingBarPresentationReason = .keyboard
    ) {
        guard let bm = browserManager,
              let current = bm.currentTab(for: windowState),
              current.representsSumiNativeSurface == false
        else { return }
        let targetSpace =
            windowState.currentSpaceId.flatMap { id in bm.tabManager.spaces.first(where: { $0.id == id }) }
            ?? bm.tabManager.currentSpace
        let tab = bm.tabManager.createNewTab(
            url: SumiSurface.emptyTabURL.absoluteString,
            in: targetSpace,
            activate: false
        )
        enterSplit(with: tab, placeOn: side, in: windowState)
        if bm.tabManager.splitGroup(containing: tab.id) != nil {
            emptySplitPlaceholderTabIdsByWindow[windowState.id] = tab.id
        }
        bm.focusFloatingBar(
            in: windowState,
            prefill: "",
            navigateCurrentTab: true,
            presentationReason: floatingBarPresentationReason
        )
    }

    func expandSplitPane(tabId: UUID, in windowState: BrowserWindowState) {
        guard let bm = browserManager,
              let tab = bm.tabManager.tab(for: tabId),
              let group = bm.tabManager.splitGroup(containing: tabId)
        else { return }

        if let remainingGroup = group.removing(tabId: tabId) {
            bm.tabManager.upsertSplitGroup(remainingGroup)
        } else {
            bm.tabManager.removeSplitGroup(id: group.id)
        }
        bm.selectTab(tab, in: windowState)
        bm.refreshCompositor(for: windowState)
        notifyChanged(for: windowState.id)
    }

    func commitEmptySplitPlaceholder(tabId: UUID, in windowState: BrowserWindowState) {
        guard emptySplitPlaceholderTabIdsByWindow[windowState.id] == tabId else { return }
        emptySplitPlaceholderTabIdsByWindow.removeValue(forKey: windowState.id)
    }

    @discardableResult
    func replaceEmptySplitPlaceholder(with tab: Tab, in windowState: BrowserWindowState) -> Bool {
        guard let placeholderTabId = emptySplitPlaceholderTabIdsByWindow[windowState.id],
              let group = browserManager?.tabManager.splitGroup(containing: placeholderTabId),
              group.contains(placeholderTabId)
        else { return false }

        emptySplitPlaceholderTabIdsByWindow.removeValue(forKey: windowState.id)
        guard let resolved = resolvedSplitTab(
            tab,
            host: group.host,
            sourceGroup: nil,
            in: windowState
        ) else {
            return false
        }
        let updated = SplitGroup(
            id: group.id,
            layoutKind: group.layoutKind,
            layoutTree: group.layoutTree.replacingTab(placeholderTabId, with: resolved.tab.id),
            activeTabId: resolved.tab.id,
            host: group.host,
            members: group.removingMember(tabId: placeholderTabId).members + [resolved.member]
        )

        browserManager?.tabManager.upsertSplitGroup(updated)
        if placeholderTabId != resolved.tab.id {
            browserManager?.tabManager.removeTab(placeholderTabId)
        }
        browserManager?.selectTab(resolved.tab, in: windowState)
        notifyChanged(for: windowState.id)
        return true
    }

    @discardableResult
    func cancelEmptySplitPlaceholder(in windowState: BrowserWindowState) -> Bool {
        guard let placeholderTabId = emptySplitPlaceholderTabIdsByWindow.removeValue(forKey: windowState.id),
              browserManager?.tabManager.tab(for: placeholderTabId) != nil
        else { return false }

        browserManager?.tabManager.removeTab(placeholderTabId)
        notifyChanged(for: windowState.id)
        return true
    }

    func enterSplit(
        with tab: Tab,
        placeOn side: SplitDropSide = .right,
        in windowState: BrowserWindowState
    ) {
        guard let bm = browserManager else { return }
        let tm = bm.tabManager
        guard tab.representsSumiNativeSurface == false else { return }
        guard let current = bm.currentTab(for: windowState), current.representsSumiNativeSurface == false else { return }

        let anchorGroup = tm.splitGroup(containing: current.id)
        let anchorTab = anchorGroup?.activeTabId.flatMap { tm.tab(for: $0) } ?? current
        dropTab(tab, placeOn: side, relativeTo: anchorTab.id, in: windowState)
    }

    @discardableResult
    func dropTab(
        _ tab: Tab,
        placeOn side: SplitDropSide,
        relativeTo targetTabId: UUID?,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard let bm = browserManager else { return false }
        let tm = bm.tabManager
        guard let targetTab = targetTabId.flatMap({ tm.tab(for: $0) }) ?? bm.currentTab(for: windowState),
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
        guard let bm = browserManager else { return false }
        let tm = bm.tabManager
        let side = target.side
        guard tab.representsSumiNativeSurface == false else { return false }
        guard let targetTab = tm.tab(for: target.tabId) ?? bm.currentTab(for: windowState),
              targetTab.representsSumiNativeSurface == false
        else { return false }

        let targetGroup = tm.splitGroup(containing: targetTab.id)
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
            tm.upsertSplitGroup(updated)
            bm.selectTab(tab, in: windowState)
            bm.refreshCompositor(for: windowState)
            notifyChanged(for: windowState.id)
            return true
        }

        let sourceGroup = sourceSplitGroup(for: tab)

        if let targetGroup {
            guard let resolvedIncoming = resolvedSplitTab(
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
                movedTabId: sourceRemovalId(for: tab, in: sourceGroup) ?? tab.id,
                excludingGroupId: group.id
            )
            tm.upsertSplitGroup(group)
            bm.compositorManager.loadTab(resolvedIncoming.tab)
            bm.selectTab(resolvedIncoming.tab, in: windowState)
            bm.refreshCompositor(for: windowState)
            notifyChanged(for: windowState.id)
            return true
        }

        let host = initialHost(for: tab, targetTab: targetTab, in: windowState)
        guard let resolvedIncoming = resolvedSplitTab(
            tab,
            host: host,
            sourceGroup: sourceGroup,
            in: windowState
        ),
        let resolvedAnchor = resolvedSplitTab(
            targetTab,
            host: host,
            sourceGroup: tm.splitGroup(containing: targetTab.id),
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
            movedTabId: sourceRemovalId(for: tab, in: sourceGroup) ?? tab.id,
            excludingGroupId: group.id
        )
        tm.upsertSplitGroup(group)
        bm.compositorManager.loadTab(resolvedAnchor.tab)
        bm.compositorManager.loadTab(resolvedIncoming.tab)
        bm.selectTab(resolvedIncoming.tab, in: windowState)
        bm.refreshCompositor(for: windowState)
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
            browserManager?.tabManager.upsertSplitGroup(remaining)
        } else {
            browserManager?.tabManager.removeSplitGroup(id: sourceGroup.id)
        }
    }

    func dropTarget(
        at location: CGPoint,
        in bounds: CGRect,
        for windowId: UUID,
        draggedTabId: UUID? = nil
    ) -> SplitDropTarget? {
        resolveDropTarget(
            at: location,
            in: bounds,
            for: windowId,
            draggedTabId: draggedTabId
        )
    }

    private func resolveDropTarget(
        at location: CGPoint,
        in bounds: CGRect,
        for windowId: UUID,
        draggedTabId: UUID? = nil
    ) -> SplitDropTarget? {
        guard bounds.width > 0, bounds.height > 0, bounds.contains(location) else { return nil }
        guard let windowState = windowRegistry?.windows[windowId],
              let tabManager = browserManager?.tabManager else {
            return nil
        }

        if let currentTabId = windowState.currentTabId,
           let group = tabManager.splitGroup(containing: currentTabId) {
            return resolvedDropTarget(
                in: group,
                at: location,
                bounds: bounds,
                draggedTabId: draggedTabId
            )
        }

        guard let currentTab = windowState.currentTabId.flatMap({ tabManager.tab(for: $0) })
                ?? browserManager?.currentTab(for: windowState),
              currentTab.representsSumiNativeSurface == false else {
            return nil
        }

        guard let side = SplitDropCaptureHitPolicy.side(
            at: location,
            in: bounds,
            mode: .create
        ) else {
            return nil
        }
        return SplitDropTarget(
            tabId: currentTab.id,
            side: side,
            targetRect: previewRectForFirstSplit(
                currentTabId: currentTab.id,
                previewTabId: draggedTabId ?? UUID(),
                side: side,
                in: bounds
            ) ?? bounds,
            intent: .firstSplit
        )
    }

    private func resolvedDropTarget(
        in group: SplitGroup,
        at location: CGPoint,
        bounds: CGRect,
        draggedTabId: UUID?
    ) -> SplitDropTarget? {
        guard let canonicalGroup = group.canonicalizedForTiles() else { return nil }
        let previewTabId = draggedTabId ?? Self.previewPlaceholderTabId
        let draggedTabIsInGroup = draggedTabId.map { canonicalGroup.contains($0) } ?? false
        let canInsertEdge = draggedTabIsInGroup || canonicalGroup.tabIds.count < SplitGroup.maximumTabs

        if draggedTabIsInGroup,
           canonicalGroup.tabIds.count == SplitGroup.maximumTabs,
           let flatFourTarget = resolvedFullFlatFourTarget(
               in: canonicalGroup,
               at: location,
               bounds: bounds,
               draggedTabId: draggedTabId
           ) {
            return flatFourTarget
        }

        if draggedTabIsInGroup,
           canonicalGroup.tabIds.count == SplitGroup.maximumTabs,
           canonicalGroup.layoutTree.isFlatFourLeafLine {
            return nil
        }

        if canInsertEdge {
            if let flatThreePairTarget = resolvedFlatThreePairTarget(
                in: canonicalGroup,
                at: location,
                bounds: bounds,
                draggedTabId: draggedTabId
            ) {
                return flatThreePairTarget
            }

            if let leafLocalTarget = resolvedLeafLocalOrthogonalTarget(
                in: canonicalGroup,
                at: location,
                bounds: bounds,
                previewTabId: previewTabId
            ) {
                return leafLocalTarget
            }

            if let pairTarget = resolvedFlatFourPairTarget(
                in: canonicalGroup,
                at: location,
                bounds: bounds,
                draggedTabId: draggedTabId
            ) {
                return pairTarget
            }

            if let mixedPairTarget = resolvedMixedThreeOnePairTarget(
                in: canonicalGroup,
                at: location,
                bounds: bounds,
                draggedTabId: draggedTabId
            ) {
                return mixedPairTarget
            }

            if let parentSiblingTarget = resolvedParentSiblingEdgeTarget(
                in: canonicalGroup,
                at: location,
                bounds: bounds,
                draggedTabId: draggedTabId
            ) {
                return parentSiblingTarget
            }

            if let fullGroupPairTarget = resolvedFullGroupPanePairTarget(
                in: canonicalGroup,
                at: location,
                bounds: bounds,
                draggedTabId: draggedTabId
            ) {
                return fullGroupPairTarget
            }

            if draggedTabIsInGroup == false,
               let rootSide = SplitDropCaptureHitPolicy.side(at: location, in: bounds, mode: .create) {
                let target = SplitDropTarget(
                    tabId: canonicalGroup.layoutTree.edgeTabId(for: rootSide, in: bounds)
                        ?? canonicalGroup.tabIds.first
                        ?? previewTabId,
                    side: rootSide,
                    targetRect: bounds,
                    scope: .group,
                    previewStyle: .edge,
                    planePath: [],
                    intent: .rootEdge
                )
                if let resolved = canonicalGroup.resolvingDrop(
                    draggedTabId: previewTabId,
                    target: target,
                    bounds: bounds
                ) {
                    return resolved.target
                }
            }

            let planes = canonicalGroup.layoutTree.tilePlanes(in: bounds)
                .filter { $0.rect.contains(location) }
                .sorted { lhs, rhs in
                    if lhs.path.count != rhs.path.count {
                        return lhs.path.count > rhs.path.count
                    }
                    return lhs.rect.width * lhs.rect.height < rhs.rect.width * rhs.rect.height
                }

            for plane in planes {
                for side in SplitDropCaptureHitPolicy.sides(at: location, in: plane.rect, mode: .create) {
                    guard let node = canonicalGroup.layoutTree.node(at: plane.path),
                          let targetTabId = node.edgeTabId(for: side, in: plane.rect) ?? node.tabIds.first
                    else {
                        continue
                    }
                    let scope: SplitDropTargetScope = plane.path.isEmpty ? .group : .plane
                    let target = SplitDropTarget(
                        tabId: targetTabId,
                        side: side,
                        targetRect: plane.rect,
                        scope: scope,
                        previewStyle: .edge,
                        planePath: plane.path,
                        intent: plane.path.isEmpty ? .rootEdge : .planeEdge
                    )
                    guard let resolved = canonicalGroup.resolvingDrop(
                        draggedTabId: previewTabId,
                        target: target,
                        bounds: bounds
                    ) else {
                        continue
                    }
                    return resolved.target
                }
            }

            if let siblingTarget = resolvedSiblingEdgeTarget(
                in: canonicalGroup,
                at: location,
                bounds: bounds,
                previewTabId: previewTabId
            ) {
                return siblingTarget
            }
        }

        guard draggedTabIsInGroup == false,
              let hit = canonicalGroup.layoutTree.leafHit(at: location, in: bounds),
              SplitDropCaptureHitPolicy.side(at: location, in: hit.rect, mode: .rearrange) == .center
        else {
            return nil
        }

        let target = SplitDropTarget(
            tabId: hit.tabId,
            side: .center,
            targetRect: hit.rect,
            scope: .pane,
            previewStyle: .center,
            planePath: hit.path,
            intent: .paneCenter
        )
        return canonicalGroup.resolvingDrop(
            draggedTabId: previewTabId,
            target: target,
            bounds: bounds
        )?.target
    }

    private func resolvedLeafLocalOrthogonalTarget(
        in group: SplitGroup,
        at location: CGPoint,
        bounds: CGRect,
        previewTabId: UUID
    ) -> SplitDropTarget? {
        guard group.tabIds.count < SplitGroup.maximumTabs,
              case .split(let rootAxis, _, let children) = group.layoutTree,
              children.count == 2,
              children.allSatisfy({ child in
                  if case .leaf = child { return true }
                  return false
              }),
              let hit = group.layoutTree.leafHit(at: location, in: bounds)
        else {
            return nil
        }
        guard isNearInternalDivider(
            location: location,
            leafRect: hit.rect,
            bounds: bounds,
            rootAxis: rootAxis
        ) == false else {
            return nil
        }

        for side in SplitDropCaptureHitPolicy.sides(at: location, in: hit.rect, mode: .create) {
            guard let insertionAxis = side.insertionAxis,
                  insertionAxis != rootAxis
            else {
                continue
            }
            let target = SplitDropTarget(
                tabId: hit.tabId,
                side: side,
                targetRect: hit.rect,
                scope: .plane,
                previewStyle: .edge,
                planePath: hit.path,
                intent: .planeEdge
            )
            guard let resolved = group.resolvingDrop(
                draggedTabId: previewTabId,
                target: target,
                bounds: bounds
            ) else {
                continue
            }
            return resolved.target
        }
        return nil
    }

    private func isNearInternalDivider(
        location: CGPoint,
        leafRect: CGRect,
        bounds: CGRect,
        rootAxis: SplitAxis
    ) -> Bool {
        let threshold: CGFloat = 24
        switch rootAxis {
        case .row:
            let internalEdge: CGFloat?
            if leafRect.minX > bounds.minX {
                internalEdge = leafRect.minX
            } else if leafRect.maxX < bounds.maxX {
                internalEdge = leafRect.maxX
            } else {
                internalEdge = nil
            }
            guard let internalEdge else { return false }
            return abs(location.x - internalEdge) <= threshold
        case .column:
            let internalEdge: CGFloat?
            if leafRect.minY > bounds.minY {
                internalEdge = leafRect.minY
            } else if leafRect.maxY < bounds.maxY {
                internalEdge = leafRect.maxY
            } else {
                internalEdge = nil
            }
            guard let internalEdge else { return false }
            return abs(location.y - internalEdge) <= threshold
        }
    }

    private func resolvedSiblingEdgeTarget(
        in group: SplitGroup,
        at location: CGPoint,
        bounds: CGRect,
        previewTabId: UUID
    ) -> SplitDropTarget? {
        guard case .split(let rootAxis, _, let children) = group.layoutTree,
              children.allSatisfy({ child in
                  if case .leaf = child { return true }
                  return false
              }),
              let hit = group.layoutTree.leafHit(at: location, in: bounds)
        else {
            return nil
        }

        for side in SplitDropCaptureHitPolicy.sides(at: location, in: hit.rect, mode: .create) {
            guard side.insertionAxis == rootAxis else { continue }
            let target = SplitDropTarget(
                tabId: hit.tabId,
                side: side,
                targetRect: hit.rect,
                scope: .pane,
                previewStyle: .edge,
                planePath: hit.path,
                intent: .siblingEdge
            )
            guard let resolved = group.resolvingDrop(
                draggedTabId: previewTabId,
                target: target,
                bounds: bounds
            ) else {
                continue
            }
            return resolved.target
        }
        return nil
    }

    private func resolvedFlatThreePairTarget(
        in group: SplitGroup,
        at location: CGPoint,
        bounds: CGRect,
        draggedTabId: UUID?
    ) -> SplitDropTarget? {
        guard let draggedTabId,
              group.tabIds.count == 3,
              case .split(let rootAxis, _, let children) = group.layoutTree,
              children.allSatisfy({ child in
                  if case .leaf = child { return true }
                  return false
              }),
              let hit = group.layoutTree.leafHit(at: location, in: bounds),
              hit.tabId != draggedTabId
        else {
            return nil
        }
        guard isNearInternalDivider(
            location: location,
            leafRect: hit.rect,
            bounds: bounds,
            rootAxis: rootAxis
        ) == false else {
            return nil
        }

        for side in SplitDropCaptureHitPolicy.sides(at: location, in: hit.rect, mode: .create) {
            guard let insertionAxis = side.insertionAxis,
                  insertionAxis != rootAxis
            else {
                continue
            }
            let localPreviewRect = localHalfRect(for: side, in: hit.rect)
            let target = SplitDropTarget(
                tabId: hit.tabId,
                side: side,
                targetRect: localPreviewRect,
                scope: .pane,
                previewStyle: .edge,
                planePath: hit.path,
                intent: .flatThreePair
            )
            guard let resolved = group.resolvingDrop(
                draggedTabId: draggedTabId,
                target: target,
                bounds: bounds
            ) else {
                continue
            }
            return SplitDropTarget(
                tabId: resolved.target.tabId,
                side: resolved.target.side,
                targetRect: localPreviewRect,
                scope: resolved.target.scope,
                previewStyle: resolved.target.previewStyle,
                planePath: resolved.target.planePath,
                intent: resolved.target.intent,
                resolvedLayoutTree: resolved.layoutTree
            )
        }
        return nil
    }

    private func resolvedFlatFourPairTarget(
        in group: SplitGroup,
        at location: CGPoint,
        bounds: CGRect,
        draggedTabId: UUID?
    ) -> SplitDropTarget? {
        guard let draggedTabId,
              group.contains(draggedTabId),
              group.tabIds.count == SplitGroup.maximumTabs,
              case .split(let rootAxis, _, let children) = group.layoutTree,
              children.allSatisfy({ child in
                  if case .leaf = child { return true }
                  return false
              }),
              let hit = group.layoutTree.leafHit(at: location, in: bounds),
              hit.tabId != draggedTabId
        else {
            return nil
        }

        let sides = SplitDropCaptureHitPolicy.sides(at: location, in: hit.rect, mode: .create)
        guard sides.first?.insertionAxis != rootAxis else { return nil }
        for side in sides {
            guard side.insertionAxis != rootAxis else { continue }
            let target = SplitDropTarget(
                tabId: hit.tabId,
                side: side,
                targetRect: hit.rect,
                scope: .pane,
                previewStyle: .edge,
                planePath: hit.path,
                intent: .flatFourPair
            )
            guard let resolved = group.resolvingDrop(
                draggedTabId: draggedTabId,
                target: target,
                bounds: bounds
            ) else {
                continue
            }
            return resolved.target
        }
        return nil
    }

    private func resolvedMixedThreeOnePairTarget(
        in group: SplitGroup,
        at location: CGPoint,
        bounds: CGRect,
        draggedTabId: UUID?
    ) -> SplitDropTarget? {
        guard let draggedTabId,
              group.contains(draggedTabId),
              group.tabIds.count == SplitGroup.maximumTabs,
              case .split(_, _, let children) = group.layoutTree,
              children.count == 2,
              let hit = group.layoutTree.leafHit(at: location, in: bounds),
              hit.tabId != draggedTabId
        else {
            return nil
        }

        var splitTabIds: [UUID] = []
        var singletonTabId: UUID?
        for child in children {
            switch child {
            case .leaf(let id, _):
                singletonTabId = id
            case .split(_, _, let grandchildren):
                let leafIds = grandchildren.compactMap { grandchild -> UUID? in
                    if case .leaf(let id, _) = grandchild {
                        return id
                    }
                    return nil
                }
                if leafIds.count == 3 {
                    splitTabIds = leafIds
                }
            }
        }

        guard splitTabIds.isEmpty == false,
              let singletonTabId,
              (draggedTabId == singletonTabId && splitTabIds.contains(hit.tabId))
                || (hit.tabId == singletonTabId && splitTabIds.contains(draggedTabId))
        else {
            return nil
        }

        for side in SplitDropCaptureHitPolicy.sides(at: location, in: hit.rect, mode: .create) {
            guard side.insertionAxis != nil else { continue }
            let previewRect = localHalfRect(for: side, in: hit.rect)
            let target = SplitDropTarget(
                tabId: hit.tabId,
                side: side,
                targetRect: previewRect,
                scope: .pane,
                previewStyle: .edge,
                planePath: hit.path,
                intent: .mixedThreeOnePair
            )
            guard let resolved = group.resolvingDrop(
                draggedTabId: draggedTabId,
                target: target,
                bounds: bounds
            ) else {
                continue
            }
            return SplitDropTarget(
                tabId: resolved.target.tabId,
                side: resolved.target.side,
                targetRect: previewRect,
                scope: resolved.target.scope,
                previewStyle: resolved.target.previewStyle,
                planePath: resolved.target.planePath,
                intent: resolved.target.intent,
                resolvedLayoutTree: resolved.layoutTree
            )
        }
        return nil
    }

    private func resolvedParentSiblingEdgeTarget(
        in group: SplitGroup,
        at location: CGPoint,
        bounds: CGRect,
        draggedTabId: UUID?
    ) -> SplitDropTarget? {
        guard let draggedTabId,
              group.contains(draggedTabId),
              let hit = group.layoutTree.leafHit(at: location, in: bounds),
              hit.tabId != draggedTabId,
              let parentAxis = parentAxis(for: hit.path, in: group.layoutTree)
        else {
            return nil
        }

        let parentPath = Array(hit.path.dropLast())
        for side in flatFourEdgeCandidates(at: location, in: hit.rect).map(\.side) {
            guard side.insertionAxis == parentAxis else { continue }
            let scope: SplitDropTargetScope = parentPath.isEmpty ? .group : .plane
            let target = SplitDropTarget(
                tabId: hit.tabId,
                side: side,
                targetRect: hit.rect,
                scope: scope,
                previewStyle: .edge,
                planePath: parentPath,
                intent: .siblingEdge
            )
            guard let resolved = group.resolvingDrop(
                draggedTabId: draggedTabId,
                target: target,
                bounds: bounds
            ) else {
                continue
            }
            return resolved.target
        }
        return nil
    }

    private func resolvedFullGroupPanePairTarget(
        in group: SplitGroup,
        at location: CGPoint,
        bounds: CGRect,
        draggedTabId: UUID?
    ) -> SplitDropTarget? {
        guard let draggedTabId,
              group.contains(draggedTabId),
              group.tabIds.count == SplitGroup.maximumTabs,
              let hit = group.layoutTree.leafHit(at: location, in: bounds),
              hit.tabId != draggedTabId
        else {
            return nil
        }

        let candidates = flatFourEdgeCandidates(at: location, in: hit.rect)
        for side in candidates.map(\.side) {
            guard let insertionAxis = side.insertionAxis else { continue }
            if parentAxis(for: hit.path, in: group.layoutTree) == insertionAxis {
                continue
            }

            let previewRect = localHalfRect(for: side, in: hit.rect)
            guard let resolvedTree = bestFullGroupPairTree(
                in: group.layoutTree,
                draggedTabId: draggedTabId,
                targetTabId: hit.tabId,
                side: side,
                desiredRect: previewRect,
                bounds: bounds
            ) else {
                continue
            }

            let target = SplitDropTarget(
                tabId: hit.tabId,
                side: side,
                targetRect: previewRect,
                scope: .pane,
                previewStyle: .edge,
                planePath: hit.path,
                intent: .fullGroupPanePair,
                resolvedLayoutTree: resolvedTree
            )
            guard let resolved = group.resolvingDrop(
                draggedTabId: draggedTabId,
                target: target,
                bounds: bounds
            ) else {
                continue
            }
            return SplitDropTarget(
                tabId: resolved.target.tabId,
                side: resolved.target.side,
                targetRect: previewRect,
                scope: resolved.target.scope,
                previewStyle: resolved.target.previewStyle,
                planePath: resolved.target.planePath,
                intent: resolved.target.intent,
                resolvedLayoutTree: resolved.layoutTree
            )
        }
        return nil
    }

    private func resolvedFullFlatFourTarget(
        in group: SplitGroup,
        at location: CGPoint,
        bounds: CGRect,
        draggedTabId: UUID?
    ) -> SplitDropTarget? {
        guard let draggedTabId,
              group.contains(draggedTabId),
              group.tabIds.count == SplitGroup.maximumTabs,
              case .split(let rootAxis, _, let children) = group.layoutTree,
              children.allSatisfy({ child in
                  if case .leaf = child { return true }
                  return false
              }),
              let hit = group.layoutTree.leafHit(at: location, in: bounds)
        else {
            return nil
        }

        let candidates = flatFourEdgeCandidates(at: location, in: hit.rect)
        for side in candidates.map(\.side) {
            guard let insertionAxis = side.insertionAxis else { continue }
            if insertionAxis == rootAxis {
                guard hit.tabId != draggedTabId else { continue }
                let target = SplitDropTarget(
                    tabId: hit.tabId,
                    side: side,
                    targetRect: hit.rect,
                    scope: .pane,
                    previewStyle: .edge,
                    planePath: hit.path,
                    intent: .flatFourReorder
                )
                guard let resolved = group.resolvingDrop(
                    draggedTabId: draggedTabId,
                    target: target,
                    bounds: bounds
                ) else {
                    continue
                }
                return resolved.target
            }

            if hit.tabId == draggedTabId {
                let target = SplitDropTarget(
                    tabId: hit.tabId,
                    side: side,
                    targetRect: bounds,
                    scope: .group,
                    previewStyle: .edge,
                    planePath: [],
                    intent: .rootEdge
                )
                guard let resolved = group.resolvingDrop(
                    draggedTabId: draggedTabId,
                    target: target,
                    bounds: bounds
                ) else {
                    continue
                }
                return resolved.target
            }

            let previewRect = localHalfRect(for: side, in: hit.rect)
            let target = SplitDropTarget(
                tabId: hit.tabId,
                side: side,
                targetRect: previewRect,
                scope: .pane,
                previewStyle: .edge,
                planePath: hit.path,
                intent: .flatFourPair
            )
            guard let resolved = group.resolvingDrop(
                draggedTabId: draggedTabId,
                target: target,
                bounds: bounds
            ) else {
                continue
            }
            return SplitDropTarget(
                tabId: resolved.target.tabId,
                side: resolved.target.side,
                targetRect: previewRect,
                scope: resolved.target.scope,
                previewStyle: resolved.target.previewStyle,
                planePath: resolved.target.planePath,
                intent: resolved.target.intent,
                resolvedLayoutTree: resolved.layoutTree
            )
        }

        guard hit.tabId != draggedTabId,
              let middleSide = fullFlatFourMiddleRootSide(
                for: rootAxis,
                at: location,
                in: hit.rect
              )
        else {
            return nil
        }

        let target = SplitDropTarget(
            tabId: hit.tabId,
            side: middleSide,
            targetRect: bounds,
            scope: .group,
            previewStyle: .edge,
            planePath: [],
            intent: .rootEdge
        )
        return group.resolvingDrop(
            draggedTabId: draggedTabId,
            target: target,
            bounds: bounds
        )?.target
    }

    private struct FullGroupPairCandidate {
        let tree: SplitLayoutTree
        let overlapRatio: CGFloat
        let preservedPairCount: Int
        let rootAxisMatches: Bool
        let areaDelta: CGFloat
        let stableMovement: CGFloat

        func isBetter(than other: FullGroupPairCandidate?) -> Bool {
            guard let other else { return true }
            if abs(overlapRatio - other.overlapRatio) > 0.0001 {
                return overlapRatio > other.overlapRatio
            }
            if preservedPairCount != other.preservedPairCount {
                return preservedPairCount > other.preservedPairCount
            }
            if rootAxisMatches != other.rootAxisMatches {
                return rootAxisMatches
            }
            if abs(areaDelta - other.areaDelta) > 0.0001 {
                return areaDelta < other.areaDelta
            }
            return stableMovement < other.stableMovement
        }
    }

    private struct SplitPairSignature: Hashable {
        let axis: SplitAxis
        let first: UUID
        let second: UUID
    }

    private func bestFullGroupPairTree(
        in tree: SplitLayoutTree,
        draggedTabId: UUID,
        targetTabId: UUID,
        side: SplitDropSide,
        desiredRect: CGRect,
        bounds: CGRect
    ) -> SplitLayoutTree? {
        guard let pairAxis = side.insertionAxis,
              tree.tabIds.count == SplitGroup.maximumTabs,
              tree.contains(draggedTabId),
              tree.contains(targetTabId),
              draggedTabId != targetTabId
        else {
            return nil
        }

        let orderedPair = pairOrder(
            draggedTabId: draggedTabId,
            targetTabId: targetTabId,
            side: side
        )
        let originalRootAxis = rootAxis(of: tree)
        let currentRects = tree.leafRects(in: bounds)
        let preservedPairs = directLeafPairSignatures(in: tree)
            .filter { $0.first != draggedTabId && $0.second != draggedTabId }
        var bestCandidate: FullGroupPairCandidate?

        for candidate in fullGroupCandidateTrees(tabIds: tree.tabIds) {
            guard candidate.hasDirectedLeafPair(
                axis: pairAxis,
                first: orderedPair.first,
                second: orderedPair.second
            ) else {
                continue
            }
            let candidateRects = candidate.leafRects(in: bounds)
            guard candidate.hasSameStructure(as: tree) == false,
                  let draggedRect = candidateRects[draggedTabId]
            else {
                continue
            }
            let overlapRatio = intersectionArea(draggedRect, desiredRect)
                / max(1, area(of: desiredRect))
            guard overlapRatio > 0 else { continue }
            let candidatePairs = directLeafPairSignatures(in: candidate)
            let preservedPairCount = preservedPairs.filter { candidatePairs.contains($0) }.count
            let areaDelta = abs(area(of: draggedRect) - area(of: desiredRect))
                / max(1, area(of: bounds))
            let stableMovement = stableLeafMovement(
                from: currentRects,
                to: candidateRects,
                excluding: draggedTabId
            )
            let scoredCandidate = FullGroupPairCandidate(
                tree: candidate,
                overlapRatio: overlapRatio,
                preservedPairCount: preservedPairCount,
                rootAxisMatches: rootAxis(of: candidate) == originalRootAxis,
                areaDelta: areaDelta,
                stableMovement: stableMovement
            )
            if scoredCandidate.isBetter(than: bestCandidate) {
                bestCandidate = scoredCandidate
            }
        }

        return bestCandidate?.tree
    }

    private func fullGroupCandidateTrees(tabIds: [UUID]) -> [SplitLayoutTree] {
        guard tabIds.count == SplitGroup.maximumTabs,
              Set(tabIds).count == tabIds.count
        else { return [] }
        let cacheKey = FullGroupCandidateCacheKey(tabIds: tabIds)
        if let cached = fullGroupCandidateTreesByKey[cacheKey] {
            return cached
        }

        var seen = Set<SplitLayoutTree>()
        var result: [SplitLayoutTree] = []

        func append(_ tree: SplitLayoutTree) {
            guard let canonical = tree.canonicalizedForTiles(),
                  seen.insert(canonical).inserted
            else {
                return
            }
            result.append(canonical)
        }

        for rootAxis in [SplitAxis.row, .column] {
            forEachPermutation(of: tabIds) { ids in
                let childAxis = perpendicularAxis(to: rootAxis)
                append(
                    SplitLayoutTree.split(
                        axis: rootAxis,
                        size: 1,
                        children: [
                            equalLeafSplit(axis: childAxis, tabIds: Array(ids[0 ..< 2]), size: 0.5),
                            equalLeafSplit(axis: childAxis, tabIds: Array(ids[2 ..< 4]), size: 0.5)
                        ]
                    )
                )

                append(
                    SplitLayoutTree.split(
                        axis: rootAxis,
                        size: 1,
                        children: [
                            equalLeafSplit(axis: childAxis, tabIds: Array(ids[0 ..< 3]), size: 0.5),
                            SplitLayoutTree.leaf(tabId: ids[3], size: 0.5)
                        ]
                    )
                )
                append(
                    SplitLayoutTree.split(
                        axis: rootAxis,
                        size: 1,
                        children: [
                            SplitLayoutTree.leaf(tabId: ids[0], size: 0.5),
                            equalLeafSplit(axis: childAxis, tabIds: Array(ids[1 ..< 4]), size: 0.5)
                        ]
                    )
                )

                for splitIndex in 0 ..< 3 {
                    var cursor = 0
                    let children: [SplitLayoutTree] = (0 ..< 3).map { index in
                        if index == splitIndex {
                            let split = equalLeafSplit(
                                axis: childAxis,
                                tabIds: Array(ids[cursor ..< cursor + 2]),
                                size: 1.0 / 3.0
                            )
                            cursor += 2
                            return split
                        }
                        let leaf = SplitLayoutTree.leaf(tabId: ids[cursor], size: 1.0 / 3.0)
                        cursor += 1
                        return leaf
                    }
                    append(SplitLayoutTree.split(axis: rootAxis, size: 1, children: children))
                }
            }
        }
        if fullGroupCandidateTreesByKey.count >= 32 {
            fullGroupCandidateTreesByKey.removeAll(keepingCapacity: true)
        }
        fullGroupCandidateTreesByKey[cacheKey] = result
        return result
    }

    private func equalLeafSplit(axis: SplitAxis, tabIds: [UUID], size: Double) -> SplitLayoutTree {
        let childSize = 1 / Double(max(1, tabIds.count))
        return SplitLayoutTree.split(
            axis: axis,
            size: size,
            children: tabIds.map { SplitLayoutTree.leaf(tabId: $0, size: childSize) }
        )
    }

    private func forEachPermutation(of ids: [UUID], _ body: ([UUID]) -> Void) {
        guard ids.isEmpty == false else {
            body([])
            return
        }

        var values = ids
        func permute(from startIndex: Int) {
            if startIndex == values.count {
                body(values)
                return
            }

            for index in startIndex ..< values.count {
                values.swapAt(startIndex, index)
                permute(from: startIndex + 1)
                values.swapAt(startIndex, index)
            }
        }
        permute(from: 0)
    }

    private func pairOrder(
        draggedTabId: UUID,
        targetTabId: UUID,
        side: SplitDropSide
    ) -> (first: UUID, second: UUID) {
        if side == .left || side == .top {
            return (draggedTabId, targetTabId)
        }
        return (targetTabId, draggedTabId)
    }

    private func perpendicularAxis(to axis: SplitAxis) -> SplitAxis {
        axis == .row ? .column : .row
    }

    private func rootAxis(of tree: SplitLayoutTree) -> SplitAxis? {
        if case .split(let axis, _, _) = tree {
            return axis
        }
        return nil
    }

    private func parentAxis(for path: [Int], in tree: SplitLayoutTree) -> SplitAxis? {
        guard path.isEmpty == false else { return nil }
        var node = tree
        for index in path.dropLast() {
            guard case .split(_, _, let children) = node,
                  children.indices.contains(index)
            else {
                return nil
            }
            node = children[index]
        }
        if case .split(let axis, _, _) = node {
            return axis
        }
        return nil
    }

    private func directLeafPairSignatures(in tree: SplitLayoutTree) -> Set<SplitPairSignature> {
        switch tree {
        case .leaf:
            return []
        case .split(let axis, _, let children):
            var result = Set<SplitPairSignature>()
            if children.count == 2,
               case .leaf(let first, _) = children[0],
               case .leaf(let second, _) = children[1] {
                result.insert(SplitPairSignature(axis: axis, first: first, second: second))
            }
            for child in children {
                result.formUnion(directLeafPairSignatures(in: child))
            }
            return result
        }
    }

    private func stableLeafMovement(
        from currentRects: [UUID: CGRect],
        to candidateRects: [UUID: CGRect],
        excluding draggedTabId: UUID
    ) -> CGFloat {
        currentRects.reduce(CGFloat(0)) { partial, element in
            let (tabId, currentRect) = element
            guard tabId != draggedTabId,
                  let candidateRect = candidateRects[tabId]
            else {
                return partial
            }
            return partial + hypot(
                currentRect.midX - candidateRect.midX,
                currentRect.midY - candidateRect.midY
            )
        }
    }

    private func area(of rect: CGRect) -> CGFloat {
        guard rect.isNull == false,
              rect.isInfinite == false
        else {
            return 0
        }
        return max(0, rect.width) * max(0, rect.height)
    }

    private func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        area(of: lhs.intersection(rhs))
    }

    private func fullFlatFourMiddleRootSide(
        for rootAxis: SplitAxis,
        at location: CGPoint,
        in rect: CGRect
    ) -> SplitDropSide? {
        guard rect.width > 0, rect.height > 0, rect.contains(location) else { return nil }
        let lowerBound: CGFloat = 1.0 / 3.0
        let upperBound: CGFloat = 2.0 / 3.0
        switch rootAxis {
        case .row:
            let normalizedY = (location.y - rect.minY) / rect.height
            guard normalizedY > lowerBound, normalizedY < upperBound else { return nil }
            return location.y >= rect.midY ? .top : .bottom
        case .column:
            let normalizedX = (location.x - rect.minX) / rect.width
            guard normalizedX > lowerBound, normalizedX < upperBound else { return nil }
            return location.x >= rect.midX ? .right : .left
        }
    }

    private func flatFourEdgeCandidates(
        at location: CGPoint,
        in rect: CGRect
    ) -> [(side: SplitDropSide, distance: CGFloat)] {
        guard rect.width > 0, rect.height > 0, rect.contains(location) else { return [] }
        let threshold: CGFloat = 1.0 / 3.0
        let candidates: [(SplitDropSide, CGFloat, CGFloat)] = [
            (.left, location.x - rect.minX, rect.width),
            (.right, rect.maxX - location.x, rect.width),
            (.top, rect.maxY - location.y, rect.height),
            (.bottom, location.y - rect.minY, rect.height)
        ]
        return candidates
            .compactMap { side, distance, length -> (side: SplitDropSide, distance: CGFloat)? in
                guard length > 0 else { return nil }
                let normalized = distance / length
                guard normalized <= threshold else { return nil }
                return (side, normalized)
            }
            .sorted { lhs, rhs in
                if lhs.distance == rhs.distance {
                    return lhs.side.rawValue < rhs.side.rawValue
                }
                return lhs.distance < rhs.distance
            }
    }

    private func localHalfRect(for side: SplitDropSide, in rect: CGRect) -> CGRect {
        switch side {
        case .left:
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width / 2, height: rect.height)
        case .right:
            return CGRect(x: rect.midX, y: rect.minY, width: rect.width / 2, height: rect.height)
        case .top:
            return CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2)
        case .bottom:
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2)
        case .center:
            return rect
        }
    }

    private func previewRectForFirstSplit(
        currentTabId: UUID,
        previewTabId: UUID,
        side: SplitDropSide,
        in bounds: CGRect
    ) -> CGRect? {
        SplitLayoutTree.leaf(tabId: currentTabId, size: 1)
            .insertingAtRoot(tabId: previewTabId, side: side)
            .leafRect(for: previewTabId, in: bounds)
    }

    func beginPreview(
        targetRect: CGRect? = nil,
        style: SplitDropPreviewStyle = .edge,
        for windowId: UUID
    ) {
        var transient = transientState(for: windowId)
        transient.previewTargetRect = targetRect
        transient.previewStyle = style
        transient.isPreviewActive = true
        setTransientState(transient, for: windowId)
        refreshWindow(windowId)
    }

    func updatePreview(
        targetRect: CGRect?,
        style: SplitDropPreviewStyle = .edge,
        for windowId: UUID
    ) {
        var transient = transientState(for: windowId)
        guard transient.isPreviewActive else { return }
        transient.previewTargetRect = targetRect
        transient.previewStyle = style
        setTransientState(transient, for: windowId)
    }

    func endPreview(for windowId: UUID) {
        var transient = transientState(for: windowId)
        guard transient.isPreviewActive
            || transient.previewTargetRect != nil
            || transient.previewStyle != .edge
        else { return }
        transient.isPreviewActive = false
        transient.previewTargetRect = nil
        transient.previewStyle = .edge
        setTransientState(transient, for: windowId)
        refreshWindow(windowId)
    }

    func restoreSession(_ snapshot: LegacySplitSessionSnapshot?, for windowId: UUID) {
        guard let snapshot else {
            pendingLegacySnapshotsByWindow.removeValue(forKey: windowId)
            return
        }
        pendingLegacySnapshotsByWindow[windowId] = snapshot
        applyPendingLegacySnapshotIfPossible(for: windowId)
    }

    private func resolvedSplitTab(
        _ candidate: Tab,
        host: SplitGroupHost,
        sourceGroup: SplitGroup?,
        in windowState: BrowserWindowState
    ) -> ResolvedSplitTab? {
        guard let tm = browserManager?.tabManager else { return nil }

        let sourceMember = sourceMember(for: candidate, sourceGroup: sourceGroup)
        let sourcePin = sourceMember?.pinId.flatMap { tm.shortcutPin(by: $0) }
        if let pin = shortcutPin(for: candidate) ?? sourcePin {
            let liveTab = resolvedLiveShortcutTab(for: pin, candidate: candidate, in: windowState)
            return ResolvedSplitTab(
                tab: liveTab,
                member: SplitGroupMember(
                    tabId: liveTab.id,
                    pinId: pin.id,
                    origin: sourceMember?.origin ?? splitMemberOrigin(for: pin)
                )
            )
        }

        if host.isShortcutPinned {
            guard let spaceId = host.spaceId ?? candidate.spaceId ?? windowState.currentSpaceId else {
                return nil
            }
            let insertionIndex = tm.spacePinnedPins(for: spaceId).count
            guard let pin = tm.convertTabToShortcutPin(
                candidate,
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: nil,
                at: insertionIndex,
                openTargetFolder: false
            ),
            let liveTab = tm.shortcutLiveTab(for: pin.id, in: windowState.id)
            else {
                return nil
            }
            return ResolvedSplitTab(
                tab: liveTab,
                member: SplitGroupMember(
                    tabId: liveTab.id,
                    pinId: pin.id,
                    origin: .generatedSpacePinnedFromRegular(spaceId: spaceId, index: insertionIndex)
                )
            )
        }

        return ResolvedSplitTab(
            tab: candidate,
            member: sourceMember ?? SplitGroupMember(
                tabId: candidate.id,
                pinId: nil,
                origin: .regular(spaceId: candidate.spaceId, index: candidate.index)
            )
        )
    }

    private func initialHost(
        for incoming: Tab,
        targetTab: Tab,
        in windowState: BrowserWindowState
    ) -> SplitGroupHost {
        let incomingPin = shortcutPin(for: incoming)
        let targetPin = shortcutPin(for: targetTab)
        if incomingPin != nil, targetPin != nil {
            let spaceId = incomingPin?.spaceId
                ?? targetPin?.spaceId
                ?? targetTab.spaceId
                ?? incoming.spaceId
                ?? windowState.currentSpaceId
            if let spaceId {
                return .shortcutPinned(
                    spaceId: spaceId,
                    profileId: incomingPin?.profileId ?? targetPin?.profileId ?? windowState.currentProfileId,
                    index: initialShortcutHostIndex(
                        incomingPin: incomingPin,
                        targetPin: targetPin,
                        incomingTab: incoming,
                        targetTab: targetTab,
                        in: windowState
                    )
                )
            }
        }

        return .regular(spaceId: targetTab.spaceId ?? incoming.spaceId ?? windowState.currentSpaceId)
    }

    private func initialShortcutHostIndex(
        incomingPin: ShortcutPin?,
        targetPin: ShortcutPin?,
        incomingTab: Tab,
        targetTab: Tab,
        in windowState: BrowserWindowState
    ) -> Int? {
        let pins = [incomingPin, targetPin].compactMap { $0 }
        let spacePinnedPins = pins.filter { $0.role == .spacePinned }
        guard !spacePinnedPins.isEmpty else { return 0 }

        if let focusedPin = spacePinnedPins.first(where: { pin in
            windowState.currentShortcutPinId == pin.id
                || windowState.currentTabId == incomingTab.id && incomingPin?.id == pin.id
                || windowState.currentTabId == targetTab.id && targetPin?.id == pin.id
        }) {
            return focusedPin.index
        }

        return targetPin?.role == .spacePinned ? targetPin?.index : incomingPin?.index
    }

    private func shortcutPin(for tab: Tab) -> ShortcutPin? {
        guard let tm = browserManager?.tabManager else { return nil }
        if let shortcutPinId = tab.shortcutPinId,
           let pin = tm.shortcutPin(by: shortcutPinId) {
            return pin
        }
        if let pin = tm.shortcutPin(by: tab.id) {
            return pin
        }
        return nil
    }

    private func sourceSplitGroup(for tab: Tab) -> SplitGroup? {
        guard let tm = browserManager?.tabManager else { return nil }
        if let group = tm.splitGroup(containing: tab.id) {
            return group
        }
        if let pinId = tab.shortcutPinId,
           let group = tm.splitGroup(containingPinId: pinId) {
            return group
        }
        if let pin = tm.shortcutPin(by: tab.id),
           let group = tm.splitGroup(containingPinId: pin.id) {
            return group
        }
        return nil
    }

    private func sourceMember(
        for tab: Tab,
        sourceGroup: SplitGroup?
    ) -> SplitGroupMember? {
        guard let tm = browserManager?.tabManager else { return nil }
        let pinId = tab.shortcutPinId ?? tm.shortcutPin(by: tab.id)?.id
        let candidateGroups: [SplitGroup?] = [
            sourceGroup,
            tm.splitGroup(containing: tab.id),
            pinId.flatMap { tm.splitGroup(containingPinId: $0) }
        ]
        var seenGroupIds = Set<UUID>()
        for group in candidateGroups.compactMap({ $0 }) where seenGroupIds.insert(group.id).inserted {
            if let pinId, let member = group.member(forPinId: pinId) {
                return member
            }
            if let member = group.member(for: tab.id) {
                return member
            }
        }
        return nil
    }

    private func sourceRemovalId(for tab: Tab, in sourceGroup: SplitGroup?) -> UUID? {
        guard let sourceGroup else { return nil }
        if sourceGroup.tabIds.contains(tab.id) {
            return tab.id
        }

        if let pinId = tab.shortcutPinId ?? browserManager?.tabManager.shortcutPin(by: tab.id)?.id,
           let member = sourceGroup.member(forPinId: pinId) {
            if sourceGroup.tabIds.contains(member.tabId) {
                return member.tabId
            }
            if sourceGroup.tabIds.contains(pinId) {
                return pinId
            }
        }

        guard let member = sourceGroup.member(for: tab.id) else {
            return nil
        }
        if sourceGroup.tabIds.contains(member.tabId) {
            return member.tabId
        }
        if let pinId = member.pinId, sourceGroup.tabIds.contains(pinId) {
            return pinId
        }
        return nil
    }

    private func resolvedLiveShortcutTab(
        for pin: ShortcutPin,
        candidate: Tab,
        in windowState: BrowserWindowState
    ) -> Tab {
        guard let tm = browserManager?.tabManager else { return candidate }
        if candidate.isShortcutLiveInstance,
           candidate.shortcutPinId == pin.id,
           tm.tab(for: candidate.id) != nil {
            return candidate
        }
        if let liveTab = tm.shortcutLiveTab(for: pin.id, in: windowState.id) {
            return liveTab
        }
        return tm.activateShortcutPin(
            pin,
            in: windowState.id,
            currentSpaceId: pin.spaceId ?? windowState.currentSpaceId
        )
    }

    private func splitMemberOrigin(for pin: ShortcutPin) -> SplitGroupMemberOrigin {
        switch pin.role {
        case .essential:
            return .essential(profileId: pin.profileId, index: pin.index)
        case .spacePinned:
            return .spacePinned(
                spaceId: pin.spaceId ?? browserManager?.windowRegistry?.activeWindow?.currentSpaceId ?? UUID(),
                folderId: pin.folderId,
                index: pin.index
            )
        }
    }

    private func activeTabId(for windowId: UUID, in group: SplitGroup?) -> UUID? {
        guard let group else { return nil }
        let current = windowRegistry?.windows[windowId]?.currentTabId
        if let current, group.contains(current) { return current }
        if let active = group.activeTabId, group.contains(active) { return active }
        return group.tabIds.first
    }

    private func preferredFocusTabAfterUnsplit(
        _ group: SplitGroup,
        in windowState: BrowserWindowState
    ) -> Tab? {
        let candidateIds = [
            windowState.currentTabId,
            group.activeTabId
        ] + group.tabIds.map(Optional.some)

        for candidateId in candidateIds {
            guard let candidateId else { continue }
            if let tab = browserManager?.tabManager.tab(for: candidateId) {
                return tab
            }
            if let pinId = group.member(for: candidateId)?.pinId,
               let tab = browserManager?.tabManager.shortcutLiveTab(for: pinId, in: windowState.id) {
                return tab
            }
            if let tab = browserManager?.tabManager.shortcutLiveTab(for: candidateId, in: windowState.id) {
                return tab
            }
        }
        return nil
    }

    private func transientState(for windowId: UUID) -> TransientWindowSplitState {
        transientWindowSplitStates[windowId] ?? TransientWindowSplitState()
    }

    private func applyPendingLegacySnapshotIfPossible(for windowId: UUID) {
        guard let snapshot = pendingLegacySnapshotsByWindow[windowId],
              let tabManager = browserManager?.tabManager,
              let group = LegacySplitSessionMigrator.makeSplitGroup(from: snapshot, tabManager: tabManager)
        else {
            return
        }
        pendingLegacySnapshotsByWindow.removeValue(forKey: windowId)
        tabManager.upsertSplitGroup(group)
        notifyChanged(for: windowId)
    }

    private func setTransientState(_ state: TransientWindowSplitState, for windowId: UUID) {
        let previous = transientState(for: windowId)
        guard previous != state else { return }
        if state.isPreviewActive == false,
           state.previewTargetRect == nil {
            transientWindowSplitStates.removeValue(forKey: windowId)
        } else {
            transientWindowSplitStates[windowId] = state
        }
        syncPublishedStateIfNeeded(for: windowId)
    }

    private func syncPublishedStateIfNeeded(for windowId: UUID, forceNotify: Bool = false) {
        guard windowRegistry?.activeWindow?.id == windowId else { return }
        let transient = transientState(for: windowId)
        let next = WindowSplitPreviewState(
            isActive: transient.isPreviewActive,
            targetRect: transient.previewTargetRect,
            style: transient.previewStyle
        )
        guard forceNotify || activeWindowPreviewState != next else { return }

        objectWillChange.send()
        activeWindowPreviewState = next
    }

    private func notifyChanged(for windowId: UUID) {
        syncPublishedStateIfNeeded(for: windowId, forceNotify: true)
        refreshWindow(windowId)
    }

    private func refreshWindow(_ windowId: UUID) {
        if let windowState = windowRegistry?.windows[windowId] {
            browserManager?.refreshCompositor(for: windowState)
            browserManager?.schedulePersistWindowSession(for: windowState)
        }
    }

}

private extension SplitLayoutTree {
    func hasDirectedLeafPair(axis expectedAxis: SplitAxis, first expectedFirst: UUID, second expectedSecond: UUID) -> Bool {
        switch self {
        case .leaf:
            return false
        case .split(let axis, _, let children):
            if axis == expectedAxis,
               children.count == 2,
               case .leaf(let first, _) = children[0],
               case .leaf(let second, _) = children[1],
               first == expectedFirst,
               second == expectedSecond {
                return true
            }
            return children.contains {
                $0.hasDirectedLeafPair(
                    axis: expectedAxis,
                    first: expectedFirst,
                    second: expectedSecond
                )
            }
        }
    }
}

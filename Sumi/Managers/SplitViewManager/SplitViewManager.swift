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
    struct WindowSplitPreviewState: Equatable {
        var isActive: Bool = false
        var targetRect: CGRect?
        var style: SplitDropPreviewStyle = .edge
    }

    private struct TransientWindowSplitState: Equatable {
        var isPreviewActive: Bool = false
        var previewTargetRect: CGRect?
        var previewStyle: SplitDropPreviewStyle = .edge
    }

    private struct ResolvedSplitTab {
        let tab: Tab
        let member: SplitGroupMember
    }

    private var activeWindowPreviewState = WindowSplitPreviewState()

    weak var windowRegistry: WindowRegistry?
    private var runtime: SplitViewRuntime?

    private var transientWindowSplitStates: [UUID: TransientWindowSplitState] = [:]
    private var pendingLegacySnapshotsByWindow: [UUID: LegacySplitSessionSnapshot] = [:]
    private var emptySplitPlaceholderTabIdsByWindow: [UUID: UUID] = [:]
    private var splitDropTargetResolver = SplitDropTargetResolver()

    init(runtime: SplitViewRuntime? = nil) {
        self.runtime = runtime
    }

    func attach(runtime: SplitViewRuntime) {
        self.runtime = runtime
    }

    private var tabManager: TabManager? {
        runtime?.tabManager()
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
        return tabManager?.splitGroup(containing: currentTabId)
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
        guard let tabManager,
              let group = tabManager.splitGroup(with: groupId)
        else { return }
        let updatedTree = group.layoutTree
            .updatingChildSizes(at: path, sizes: sizes)
            .canonicalizedForTiles() ?? group.layoutTree
        tabManager.upsertSplitGroup(
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
        splitDropTargetResolver.removeAllCachedCandidates(keepingCapacity: true)
        tabManager?.removeSplitGroups(containing: tabId)
        guard let windows = windowRegistry?.windows else { return }
        for windowState in windows.values {
            runtime?.refreshCompositor(windowState)
        }
        objectWillChange.send()
    }

    func updateActiveSide(for tabId: UUID, in windowId: UUID) {
        guard let tabManager,
              let group = tabManager.splitGroup(containing: tabId)
        else { return }
        tabManager.upsertSplitGroup(group.settingActiveTab(tabId), schedulePersistence: false)
        notifyChanged(for: windowId)
    }

    func exitSplit(for windowId: UUID) {
        guard let group = splitGroup(for: windowId) else { return }
        let windowState = windowRegistry?.windows[windowId]
        let focusTab = windowState.flatMap { preferredFocusTabAfterUnsplit(group, in: $0) }
        tabManager?.removeSplitGroup(id: group.id)
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
        tabManager?.upsertSplitGroup(group.settingLayoutKind(layoutKind))
        notifyChanged(for: windowId)
    }

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
        if tabManager.splitGroup(containing: tab.id) != nil {
            emptySplitPlaceholderTabIdsByWindow[windowState.id] = tab.id
        }
        runtime?.focusFloatingBar(windowState, floatingBarPresentationReason)
    }

    func expandSplitPane(tabId: UUID, in windowState: BrowserWindowState) {
        guard let tabManager,
              let tab = tabManager.tab(for: tabId),
              let group = tabManager.splitGroup(containing: tabId)
        else { return }

        if let remainingGroup = group.removing(tabId: tabId) {
            tabManager.upsertSplitGroup(remainingGroup)
        } else {
            tabManager.removeSplitGroup(id: group.id)
        }
        runtime?.selectTab(tab, windowState)
        runtime?.refreshCompositor(windowState)
        notifyChanged(for: windowState.id)
    }

    func commitEmptySplitPlaceholder(tabId: UUID, in windowState: BrowserWindowState) {
        guard emptySplitPlaceholderTabIdsByWindow[windowState.id] == tabId else { return }
        emptySplitPlaceholderTabIdsByWindow.removeValue(forKey: windowState.id)
    }

    @discardableResult
    func replaceEmptySplitPlaceholder(with tab: Tab, in windowState: BrowserWindowState) -> Bool {
        guard let placeholderTabId = emptySplitPlaceholderTabIdsByWindow[windowState.id],
              let tabManager,
              let group = tabManager.splitGroup(containing: placeholderTabId),
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

        tabManager.upsertSplitGroup(updated)
        if placeholderTabId != resolved.tab.id {
            tabManager.removeTab(placeholderTabId)
        }
        runtime?.selectTab(resolved.tab, windowState)
        notifyChanged(for: windowState.id)
        return true
    }

    @discardableResult
    func cancelEmptySplitPlaceholder(in windowState: BrowserWindowState) -> Bool {
        guard let placeholderTabId = emptySplitPlaceholderTabIdsByWindow.removeValue(forKey: windowState.id),
              tabManager?.tab(for: placeholderTabId) != nil
        else { return false }

        tabManager?.removeTab(placeholderTabId)
        notifyChanged(for: windowState.id)
        return true
    }

    func enterSplit(
        with tab: Tab,
        placeOn side: SplitDropSide = .right,
        in windowState: BrowserWindowState
    ) {
        guard let tabManager else { return }
        guard tab.representsSumiNativeSurface == false else { return }
        guard let current = runtime?.currentTab(windowState), current.representsSumiNativeSurface == false else { return }

        let anchorGroup = tabManager.splitGroup(containing: current.id)
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

        let targetGroup = tabManager.splitGroup(containing: targetTab.id)
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
            tabManager.upsertSplitGroup(updated)
            runtime?.selectTab(tab, windowState)
            runtime?.refreshCompositor(windowState)
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
            tabManager.upsertSplitGroup(group)
            runtime?.selectTab(resolvedIncoming.tab, windowState)
            runtime?.refreshCompositor(windowState)
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
            sourceGroup: tabManager.splitGroup(containing: targetTab.id),
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
        tabManager.upsertSplitGroup(group)
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
            tabManager?.upsertSplitGroup(remaining)
        } else {
            tabManager?.removeSplitGroup(id: sourceGroup.id)
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
              let tabManager else {
            return nil
        }

        if let currentTabId = windowState.currentTabId,
           let group = tabManager.splitGroup(containing: currentTabId) {
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
        guard let tabManager else { return nil }

        let sourceMember = sourceMember(for: candidate, sourceGroup: sourceGroup)
        let sourcePin = sourceMember?.pinId.flatMap { tabManager.shortcutPin(by: $0) }
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
            let insertionIndex = tabManager.spacePinnedPins(for: spaceId).count
            guard let pin = tabManager.convertTabToShortcutPin(
                candidate,
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: nil,
                at: insertionIndex,
                openTargetFolder: false
            ),
            let liveTab = tabManager.shortcutLiveTab(for: pin.id, in: windowState.id)
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
        guard let tabManager else { return nil }
        if let shortcutPinId = tab.shortcutPinId,
           let pin = tabManager.shortcutPin(by: shortcutPinId) {
            return pin
        }
        if let pin = tabManager.shortcutPin(by: tab.id) {
            return pin
        }
        return nil
    }

    private func sourceSplitGroup(for tab: Tab) -> SplitGroup? {
        guard let tabManager else { return nil }
        if let group = tabManager.splitGroup(containing: tab.id) {
            return group
        }
        if let pinId = tab.shortcutPinId,
           let group = tabManager.splitGroup(containingPinId: pinId) {
            return group
        }
        if let pin = tabManager.shortcutPin(by: tab.id),
           let group = tabManager.splitGroup(containingPinId: pin.id) {
            return group
        }
        return nil
    }

    private func sourceMember(
        for tab: Tab,
        sourceGroup: SplitGroup?
    ) -> SplitGroupMember? {
        guard let tabManager else { return nil }
        let pinId = tab.shortcutPinId ?? tabManager.shortcutPin(by: tab.id)?.id
        let candidateGroups: [SplitGroup?] = [
            sourceGroup,
            tabManager.splitGroup(containing: tab.id),
            pinId.flatMap { tabManager.splitGroup(containingPinId: $0) },
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

        if let pinId = tab.shortcutPinId ?? tabManager?.shortcutPin(by: tab.id)?.id,
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
        guard let tabManager else { return candidate }
        if candidate.isShortcutLiveInstance,
           candidate.shortcutPinId == pin.id,
           tabManager.tab(for: candidate.id) != nil {
            return candidate
        }
        if let liveTab = tabManager.shortcutLiveTab(for: pin.id, in: windowState.id) {
            return liveTab
        }
        return tabManager.activateShortcutPin(
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
                spaceId: pin.spaceId ?? windowRegistry?.activeWindow?.currentSpaceId ?? UUID(),
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
            group.activeTabId,
        ] + group.tabIds.map(Optional.some)

        for candidateId in candidateIds {
            guard let candidateId else { continue }
            if let tab = tabManager?.tab(for: candidateId) {
                return tab
            }
            if let pinId = group.member(for: candidateId)?.pinId,
               let tab = tabManager?.shortcutLiveTab(for: pinId, in: windowState.id) {
                return tab
            }
            if let tab = tabManager?.shortcutLiveTab(for: candidateId, in: windowState.id) {
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
              let tabManager,
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
            runtime?.refreshCompositor(windowState)
            runtime?.schedulePersistWindowSession(windowState)
        }
    }
}

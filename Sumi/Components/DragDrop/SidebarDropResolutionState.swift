import CoreGraphics
import Foundation
import SumiDomain

enum SidebarSplitPairingPresentation: Equatable {
    /// A new two-member group. The dragged tab reserves an empty pill while
    /// the existing row is projected into `companionRect`.
    case projectedPair(companionRect: CGRect)
    /// Adding to an existing group uses the same whole-row containment cue as
    /// dropping onto a folder.
    case existingGroupRow
}

struct SidebarSplitPairingTarget: Equatable {
    let memberID: SplitMemberID
    let side: SplitDropSide
    let rect: CGRect
    let presentation: SidebarSplitPairingPresentation

    func projectedTarget(
        for candidateMemberID: SplitMemberID
    ) -> SidebarSplitPairingTarget? {
        guard memberID == candidateMemberID,
              case .projectedPair = presentation else {
            return nil
        }
        return self
    }
}

struct SidebarSplitPairingCandidate: Equatable {
    let frame: CGRect
    let memberIDs: [SplitMemberID]
}

enum SidebarSplitPairingPolicy {
    private static let hitVerticalInset: CGFloat = 7
    private static let visualHorizontalInset =
        SplitGroupSidebarVisualLayout.outerRowInset
        + SplitGroupSidebarVisualLayout.horizontalInset
    private static let visualVerticalInset =
        SplitGroupSidebarVisualLayout.verticalInset
    private static let memberSpacing =
        SplitGroupSidebarVisualLayout.segmentSpacing

    static func target(
        at location: CGPoint,
        draggedItem: SumiDragItem?,
        candidate: SidebarSplitPairingCandidate
    ) -> SidebarSplitPairingTarget? {
        guard let draggedItem,
              draggedItem.kind == .tab,
              !candidate.memberIDs.isEmpty,
              candidate.memberIDs.count < SplitGroup.maximumMembers,
              candidate.frame.insetBy(dx: 0, dy: hitVerticalInset).contains(location)
        else {
            return nil
        }

        let sourceMemberID = draggedItem.splitMemberID
            ?? .regularTab(draggedItem.tabId)
        guard !candidate.memberIDs.contains(sourceMemberID) else { return nil }

        if candidate.memberIDs.count >= 2 {
            return SidebarSplitPairingTarget(
                memberID: candidate.memberIDs[candidate.memberIDs.count - 1],
                side: .right,
                rect: candidate.frame,
                presentation: .existingGroupRow
            )
        }

        let contentFrame = candidate.frame.insetBy(
            dx: visualHorizontalInset,
            dy: visualVerticalInset
        )
        let memberWidth = SplitGroupSidebarVisualLayout.segmentWidth(
            rowWidth: candidate.frame.width
                - SplitGroupSidebarVisualLayout.outerRowInset * 2,
            segmentCount: 2
        )
        guard memberWidth > 0, let memberID = candidate.memberIDs.first else {
            return nil
        }
        let side: SplitDropSide =
            location.x < candidate.frame.midX ? .left : .right
        let leftRect = CGRect(
            x: contentFrame.minX,
            y: contentFrame.minY,
            width: memberWidth,
            height: contentFrame.height
        )
        let rightRect = CGRect(
            x: leftRect.maxX + memberSpacing,
            y: contentFrame.minY,
            width: memberWidth,
            height: contentFrame.height
        )
        let projectedRect = side == .left ? leftRect : rightRect
        let existingRect = side == .left ? rightRect : leftRect
        return SidebarSplitPairingTarget(
            memberID: memberID,
            side: side,
            rect: projectedRect,
            presentation: .projectedPair(companionRect: existingRect)
        )
    }
}

/// Mathematical slots for dropping generic items within sections.
enum DropZoneSlot: Equatable {
    case essentials(slot: Int)
    case spacePinned(spaceId: UUID, slot: Int)
    case spaceRegular(spaceId: UUID, slot: Int)
    case folder(folderId: UUID, slot: Int)
    case empty

    var asDragContainer: TabDragManager.DragContainer {
        switch self {
        case .essentials: return .essentials
        case .spacePinned(let id, _): return .spacePinned(id)
        case .spaceRegular(let id, _): return .spaceRegular(id)
        case .folder(let id, _): return .folder(id)
        default: return .none
        }
    }

    var visualIndex: Int {
        switch self {
        case .essentials(let index): return index
        case .spacePinned(_, let index): return index
        case .spaceRegular(_, let index): return index
        case .folder(_, let index): return index
        default: return 0
        }
    }
}

enum FolderDropIntent: Equatable {
    case none
    case contain(folderId: UUID)
    case insertIntoFolder(folderId: UUID, index: Int)
}

enum SidebarDeferredDropTarget: Equatable {
    case split(
        memberID: SplitMemberID,
        side: SplitDropSide,
        residence: DropZoneSlot
    )
}

struct SidebarDropResolution: Equatable {
    let slot: DropZoneSlot
    let folderIntent: FolderDropIntent
    let activeHoveredFolderId: UUID?
    let presentedRegularBoundary: SidebarVisualSceneProjection.RegularBoundary?
    let splitPairingTarget: SidebarSplitPairingTarget?
    /// Scroll-normalized SwiftUI-global line chosen by the same geometry
    /// decision as `slot`. The presenter never reconstructs it from the slot.
    let indicatorLineRect: CGRect?

    init(
        slot: DropZoneSlot,
        folderIntent: FolderDropIntent,
        activeHoveredFolderId: UUID?,
        presentedRegularBoundary: SidebarVisualSceneProjection.RegularBoundary? = nil,
        splitPairingTarget: SidebarSplitPairingTarget? = nil,
        indicatorLineRect: CGRect? = nil
    ) {
        self.slot = slot
        self.folderIntent = folderIntent
        self.activeHoveredFolderId = activeHoveredFolderId
        self.presentedRegularBoundary = presentedRegularBoundary
        self.splitPairingTarget = splitPairingTarget
        self.indicatorLineRect = indicatorLineRect
    }

    func anchored(in geometry: SidebarGeometrySnapshot) -> Self {
        Self(
            slot: slot,
            folderIntent: folderIntent,
            activeHoveredFolderId: activeHoveredFolderId,
            presentedRegularBoundary: presentedRegularBoundary,
            splitPairingTarget: splitPairingTarget,
            indicatorLineRect: splitPairingTarget == nil
                ? SidebarDropIndicatorGeometry.lineRect(
                    slot: slot,
                    folderIntent: folderIntent,
                    geometry: geometry
                )
                : nil
        )
    }

    static let empty = SidebarDropResolution(
        slot: .empty,
        folderIntent: .none,
        activeHoveredFolderId: nil
    )

    var deferredTarget: SidebarDeferredDropTarget? {
        if let splitPairingTarget {
            return .split(
                memberID: splitPairingTarget.memberID,
                side: splitPairingTarget.side,
                residence: slot
            )
        }
        return nil
    }
}

@MainActor
enum SidebarDropResolver {
    private static let rowStride: CGFloat = SidebarRowLayout.rowHeight
    private static let folderHeaderTopLevelBeforeBandHeight: CGFloat = 10
    private static let spacePinnedTopEdgeDropAllowance: CGFloat = SidebarRowLayout.rowHeight

    static func resolve(
        location: CGPoint,
        state: SidebarDragState,
        draggedItem: SumiDragItem?,
        scope: SidebarDragScope? = nil,
        allowsDeferredTargets: Bool = true
    ) -> SidebarDropResolution {
        let activeScope = scope ?? state.activeDragScope
        let hoveredPage = state.hoveredInteractivePage(
            at: location,
            matching: activeScope
        )
        let baseLocation = state.baseGeometryLocation(from: location)
        return resolve(
            location: baseLocation,
            state: state,
            draggedItem: draggedItem,
            hoveredPage: hoveredPage,
            scope: activeScope,
            allowsDeferredTargets: allowsDeferredTargets
        ).anchored(in: state.geometry.geometrySnapshot)
    }

    private static func resolve(
        location: CGPoint,
        state: SidebarDragState,
        draggedItem: SumiDragItem?,
        hoveredPage: SidebarPageGeometryMetrics?,
        scope: SidebarDragScope?,
        allowsDeferredTargets: Bool
    ) -> SidebarDropResolution {
        if let essentialsResolution = resolveEssentials(
            location: location,
            state: state,
            draggedItem: draggedItem,
            hoveredPage: hoveredPage,
            scope: scope
        ) {
            return essentialsResolution
        }

        if allowsDeferredTargets,
           let pairingResolution = resolveSplitPairingTarget(
            location: location,
            state: state,
            draggedItem: draggedItem,
            hoveredPage: hoveredPage
        ) {
            return pairingResolution
        }

        if let folderResolution = resolveFolderTarget(
            location: location,
            state: state,
            draggedItem: draggedItem,
            hoveredPage: hoveredPage
        ) {
            return folderResolution
        }

        if let pinnedResolution = resolveSpacePinnedTarget(
            location: location,
            state: state,
            draggedItem: draggedItem,
            hoveredPage: hoveredPage
        ) {
            return pinnedResolution
        }

        if let regularResolution = resolveRegularTarget(
            location: location,
            state: state,
            hoveredPage: hoveredPage
        ) {
            return regularResolution
        }

        return SidebarDropResolution(
            slot: .empty,
            folderIntent: .none,
            activeHoveredFolderId: nil
        )
    }

    private static func resolveSplitPairingTarget(
        location: CGPoint,
        state: SidebarDragState,
        draggedItem: SumiDragItem?,
        hoveredPage: SidebarPageGeometryMetrics?
    ) -> SidebarDropResolution? {
        guard let hoveredPage,
              let hit = SidebarSplitPairingHitTest.hit(
                  at: location,
                  state: state,
                  hoveredPage: hoveredPage
              ),
              let target = SidebarSplitPairingPolicy.target(
                  at: location,
                  draggedItem: draggedItem,
                  candidate: hit.candidate
              ) else {
            return nil
        }
        return hit.resolution(target: target)
    }

    @discardableResult
    static func updateState(
        location: CGPoint,
        previewLocation: CGPoint? = nil,
        state: SidebarDragState,
        draggedItem: SumiDragItem?,
        scope: SidebarDragScope? = nil
    ) -> SidebarDropResolution {
        state.updateDragLocation(
            location,
            previewLocation: previewLocation
        )
        let resolution = resolve(
            location: location,
            state: state,
            draggedItem: draggedItem,
            scope: scope
        )
        let presentedResolution: SidebarDropResolution
        if let deferredTarget = resolution.deferredTarget {
            if state.admitsDeferredDropTarget(deferredTarget) {
                presentedResolution = resolution
            } else {
                presentedResolution = resolve(
                    location: location,
                    state: state,
                    draggedItem: draggedItem,
                    scope: scope,
                    allowsDeferredTargets: false
                )
            }
        } else {
            state.leaveDeferredDropTargets()
            presentedResolution = resolution
        }
        state.presentDropResolution(presentedResolution)
        state.updateEssentialsPreviewState(
            at: location,
            resolution: presentedResolution.slot
        )
        return presentedResolution
    }

    private static func resolveSpacePinnedTarget(
        location: CGPoint,
        state: SidebarDragState,
        draggedItem: SumiDragItem?,
        hoveredPage: SidebarPageGeometryMetrics?
    ) -> SidebarDropResolution? {
        guard let hoveredPage,
              let pinnedFrame = state.sectionFrame(for: .spacePinned, in: hoveredPage.spaceId),
              spacePinnedHitFrame(
                pinnedFrame: pinnedFrame,
                hoveredPage: hoveredPage
              ).contains(location) else {
            return nil
        }

        // Clean handoff between Essentials and Pinned
        let essentialsBoundaryY = state.essentialsLayoutMetricsBySpace[hoveredPage.spaceId]?.dropHitFrame.maxY
            ?? (hoveredPage.frame.minY + 26) // fallback to legacy
        guard location.y >= essentialsBoundaryY else {
            return nil
        }

        let topLevelItems = state.topLevelPinnedItemsBySpace[hoveredPage.spaceId] ?? []

        if let metrics = state.pinnedListHitTargets[hoveredPage.spaceId] {
            return SidebarDropResolution(
                slot: .spacePinned(
                    spaceId: hoveredPage.spaceId,
                    slot: metrics.rowBoundaryIndex(forGlobalY: location.y)
                ),
                folderIntent: .none,
                activeHoveredFolderId: nil
            )
        }

        if !topLevelItems.isEmpty,
           let slot = resolveTopLevelPinnedSlot(location: location, topLevelItems: topLevelItems) {
            if draggedItem?.kind == .folder,
               let directItem = topLevelItems.first(where: { $0.frame.contains(location) }),
               directItem.itemId == draggedItem?.tabId {
                return emptyResolution
            }

            return SidebarDropResolution(
                slot: .spacePinned(spaceId: hoveredPage.spaceId, slot: slot),
                folderIntent: .none,
                activeHoveredFolderId: nil
            )
        }

        let hasFolderTargets = state.folderDropTargets.values.contains { $0.spaceId == hoveredPage.spaceId }
        guard !hasFolderTargets else {
            return nil
        }

        let localY = max(0, location.y - pinnedFrame.minY)
        return SidebarDropResolution(
            slot: .spacePinned(
                spaceId: hoveredPage.spaceId,
                slot: midpointSlotIndex(localY: localY)
            ),
            folderIntent: .none,
            activeHoveredFolderId: nil
        )
    }

    private static func spacePinnedHitFrame(
        pinnedFrame: CGRect,
        hoveredPage: SidebarPageGeometryMetrics
    ) -> CGRect {
        let topY = max(
            hoveredPage.frame.minY,
            pinnedFrame.minY - spacePinnedTopEdgeDropAllowance
        )
        let resolvedMaxY = max(pinnedFrame.maxY, pinnedFrame.minY + SidebarRowLayout.rowHeight)
        return CGRect(
            x: pinnedFrame.minX,
            y: topY,
            width: pinnedFrame.width,
            height: max(0, resolvedMaxY - topY)
        )
    }

    private static func resolveTopLevelPinnedSlot(
        location: CGPoint,
        topLevelItems: [SidebarTopLevelPinnedItemMetrics]
    ) -> Int? {
        guard let firstItem = topLevelItems.first,
              let lastItem = topLevelItems.last else {
            return 0
        }

        if location.y < firstItem.frame.minY {
            return firstItem.topLevelIndex
        }

        for item in topLevelItems where item.frame.contains(location) {
            return location.y < item.frame.midY
                ? item.topLevelIndex
                : item.topLevelIndex + 1
        }

        for pair in zip(topLevelItems, topLevelItems.dropFirst()) {
            let previous = pair.0
            let next = pair.1
            if location.y >= previous.frame.maxY, location.y < next.frame.minY {
                return location.y < ((previous.frame.maxY + next.frame.minY) / 2)
                    ? previous.topLevelIndex + 1
                    : next.topLevelIndex
            }
        }

        if location.y >= lastItem.frame.maxY {
            return lastItem.topLevelIndex + 1
        }

        let nearest = topLevelItems.min { lhs, rhs in
            abs(location.y - lhs.frame.midY) < abs(location.y - rhs.frame.midY)
        }
        guard let nearest else { return nil }
        return location.y < nearest.frame.midY
            ? nearest.topLevelIndex
            : nearest.topLevelIndex + 1
    }

    private static func resolveFolderTarget(
        location: CGPoint,
        state: SidebarDragState,
        draggedItem: SumiDragItem?,
        hoveredPage: SidebarPageGeometryMetrics?
    ) -> SidebarDropResolution? {
        guard let hoveredPage else { return nil }
        let targets = (state.folderTargetsBySpace[hoveredPage.spaceId] ?? [])
            .filter { containingArea(for: $0, at: location) < .greatestFiniteMagnitude }
            .sorted { lhs, rhs in
            let leftArea = containingArea(for: lhs, at: location)
            let rightArea = containingArea(for: rhs, at: location)
            if leftArea != rightArea { return leftArea < rightArea }
            let leftY = lhs.headerFrame?.minY ?? lhs.bodyFrame?.minY ?? lhs.afterFrame?.minY ?? .greatestFiniteMagnitude
            let rightY = rhs.headerFrame?.minY ?? rhs.bodyFrame?.minY ?? rhs.afterFrame?.minY ?? .greatestFiniteMagnitude
            if leftY != rightY { return leftY < rightY }
            return lhs.folderId.uuidString < rhs.folderId.uuidString
        }

        for target in targets {
            if let headerFrame = target.headerFrame, headerFrame.contains(location) {
                return resolveFolderHeader(
                    target,
                    frame: headerFrame,
                    location: location,
                    draggedItem: draggedItem
                )
            }

            if let bodyFrame = target.bodyFrame, bodyFrame.contains(location) {
                return resolveFolderBody(
                    target,
                    frame: bodyFrame,
                    location: location,
                    state: state,
                    draggedItem: draggedItem
                )
            }

            if let afterFrame = target.afterFrame, afterFrame.contains(location) {
                return resolveFolderAfter(
                    target,
                    draggedItem: draggedItem
                )
            }
        }

        return nil
    }

    private static func containingArea(
        for target: SidebarFolderDropTargetMetrics,
        at location: CGPoint
    ) -> CGFloat {
        [target.headerFrame, target.bodyFrame, target.afterFrame]
            .compactMap { $0 }
            .filter { $0.contains(location) }
            .map { max($0.width * $0.height, 0) }
            .min() ?? .greatestFiniteMagnitude
    }

    private static func resolveFolderHeader(
        _ target: SidebarFolderDropTargetMetrics,
        frame: CGRect,
        location: CGPoint,
        draggedItem: SumiDragItem?
    ) -> SidebarDropResolution {
        if draggedItem?.kind == .folder, draggedItem?.tabId == target.folderId {
            return emptyResolution
        }

        if location.y < frame.minY + min(folderHeaderTopLevelBeforeBandHeight, frame.height / 3) {
            return parentContainerResolution(for: target, slot: target.topLevelIndex)
        }

        if target.isOpen {
            return insertIntoFolderResolution(for: target, index: 0)
        }

        return containResolution(for: target)
    }

    private static func resolveFolderBody(
        _ target: SidebarFolderDropTargetMetrics,
        frame: CGRect,
        location: CGPoint,
        state: SidebarDragState,
        draggedItem: SumiDragItem?
    ) -> SidebarDropResolution {
        if draggedItem?.kind == .folder, draggedItem?.tabId == target.folderId {
            return emptyResolution
        }

        guard target.isOpen else {
            return containResolution(for: target)
        }

        guard target.childCount > 0 else {
            return insertIntoFolderResolution(for: target, index: 0)
        }

        let childTargets = state.folderChildrenByFolder[target.folderId] ?? []

        if let childResolution = resolveOpenFolderChildRows(
            target,
            location: location,
            childTargets: childTargets
        ) {
            return childResolution
        }

        let localY = max(0, location.y - frame.minY)
        let rowContentHeight = CGFloat(target.childCount) * rowStride
        guard localY <= rowContentHeight else {
            return insertIntoFolderResolution(for: target, index: target.childCount)
        }

        let safeIndex = midpointSlotIndex(localY: localY, itemCount: target.childCount)
        return insertIntoFolderResolution(for: target, index: safeIndex)
    }

    private static func resolveOpenFolderChildRows(
        _ target: SidebarFolderDropTargetMetrics,
        location: CGPoint,
        childTargets: [SidebarFolderChildDropTargetMetrics]
    ) -> SidebarDropResolution? {
        guard let firstChild = childTargets.first,
              let lastChild = childTargets.last else {
            return nil
        }

        if location.y < firstChild.frame.minY {
            return insertIntoFolderResolution(for: target, index: 0)
        }

        for child in childTargets where child.frame.contains(location) {
            let index = location.y < child.frame.midY
                ? child.index
                : child.index + 1
            return insertIntoFolderResolution(for: target, index: index)
        }

        for pair in zip(childTargets, childTargets.dropFirst()) {
            let previous = pair.0
            let next = pair.1
            if location.y >= previous.frame.maxY, location.y < next.frame.minY {
                return insertIntoFolderResolution(for: target, index: previous.index + 1)
            }
        }

        if location.y > lastChild.frame.maxY {
            return insertIntoFolderResolution(for: target, index: target.childCount)
        }

        return nil
    }

    private static func resolveFolderAfter(
        _ target: SidebarFolderDropTargetMetrics,
        draggedItem: SumiDragItem?
    ) -> SidebarDropResolution {
        if draggedItem?.kind == .folder, draggedItem?.tabId == target.folderId {
            return emptyResolution
        }

        return parentContainerResolution(for: target, slot: target.topLevelIndex + 1)
    }

    private static func containResolution(
        for target: SidebarFolderDropTargetMetrics
    ) -> SidebarDropResolution {
        SidebarDropResolution(
            slot: .folder(folderId: target.folderId, slot: target.childCount),
            folderIntent: .contain(folderId: target.folderId),
            activeHoveredFolderId: target.folderId
        )
    }

    private static func insertIntoFolderResolution(
        for target: SidebarFolderDropTargetMetrics,
        index: Int
    ) -> SidebarDropResolution {
        let safeIndex = max(0, min(index, target.childCount))
        return SidebarDropResolution(
            slot: .folder(folderId: target.folderId, slot: safeIndex),
            folderIntent: .insertIntoFolder(folderId: target.folderId, index: safeIndex),
            activeHoveredFolderId: target.folderId
        )
    }

    private static func parentContainerResolution(
        for target: SidebarFolderDropTargetMetrics,
        slot: Int
    ) -> SidebarDropResolution {
        if let parentFolderId = target.parentFolderId {
            return SidebarDropResolution(
                slot: .folder(folderId: parentFolderId, slot: max(0, slot)),
                folderIntent: .insertIntoFolder(folderId: parentFolderId, index: max(0, slot)),
                activeHoveredFolderId: nil
            )
        }

        return SidebarDropResolution(
            slot: .spacePinned(spaceId: target.spaceId, slot: max(0, slot)),
            folderIntent: .none,
            activeHoveredFolderId: nil
        )
    }

    private static var emptyResolution: SidebarDropResolution {
        .empty
    }

    private static func resolveRegularTarget(
        location: CGPoint,
        state: SidebarDragState,
        hoveredPage: SidebarPageGeometryMetrics?
    ) -> SidebarDropResolution? {
        guard let hoveredPage else { return nil }
        let spaceId = hoveredPage.spaceId
        let outerFrame = state.sectionFrame(for: .spaceRegular, in: spaceId)
            ?? state.regularListHitTargets[spaceId]?.frame
        let foundSlot = resolveRegularSection(
            location: location,
            spaceId: spaceId,
            outerFrame: outerFrame,
            state: state
        )

        if foundSlot != .empty {
            return SidebarDropResolution(
                slot: foundSlot,
                folderIntent: .none,
                activeHoveredFolderId: nil,
                presentedRegularBoundary: state.regularListHitTargets[spaceId]?
                    .presentedBoundary(at: foundSlot.visualIndex)
            )
        }

        if let regularFrame = outerFrame,
           location.x >= regularFrame.minX,
           location.x <= regularFrame.maxX,
           location.y >= regularFrame.maxY {
            return SidebarDropResolution(
                slot: .spaceRegular(spaceId: spaceId, slot: 9999),
                folderIntent: .none,
                activeHoveredFolderId: nil,
                presentedRegularBoundary: state.regularListHitTargets[spaceId]?
                    .presentedBoundary(
                        at: state.regularListHitTargets[spaceId]?.rowCount ?? 0
                    )
            )
        }

        return nil
    }

    private static func resolveRegularSection(
        location: CGPoint,
        spaceId: UUID,
        outerFrame: CGRect?,
        state: SidebarDragState
    ) -> DropZoneSlot {
        guard let outerFrame else { return .empty }

        guard let metrics = state.regularListHitTargets[spaceId] else {
            guard outerFrame.contains(location) else {
                return .empty
            }
            let localY = location.y - outerFrame.minY
            let slotIndex = midpointSlotIndex(localY: max(0, localY))
            return .spaceRegular(spaceId: spaceId, slot: slotIndex)
        }

        guard outerFrame.contains(location) else {
            return .empty
        }

        if location.y < metrics.frame.minY {
            return .spaceRegular(spaceId: spaceId, slot: 0)
        }

        guard metrics.rowCount > 0 else {
            return .spaceRegular(spaceId: spaceId, slot: 0)
        }

        if location.y <= metrics.frame.maxY {
            let localY = max(0, location.y - metrics.frame.minY)
            return .spaceRegular(
                spaceId: spaceId,
                slot: metrics.rowBoundaryIndex(forLocalY: localY)
            )
        }

        return .spaceRegular(spaceId: spaceId, slot: metrics.rowCount)
    }

    private static func resolveEssentials(
        location: CGPoint,
        state: SidebarDragState,
        draggedItem: SumiDragItem?,
        hoveredPage: SidebarPageGeometryMetrics?,
        scope: SidebarDragScope?
    ) -> SidebarDropResolution? {
        guard let hoveredPage,
              let metrics = state.essentialsLayoutMetricsBySpace[hoveredPage.spaceId],
              scope?.matches(profileId: metrics.profileId) != false,
              metrics.containsDropLocation(location) else {
            _ = draggedItem
            return nil
        }
        guard metrics.canAcceptDrop || metrics.visibleItemCount > 0 else {
            return nil
        }

        // Clean handoff between Essentials and Pinned. `metrics` is the same
        // value the guard above resolved, so no second lookup is needed.
        guard location.y < metrics.dropHitFrame.maxY else {
            return nil
        }

        return resolveEssentials(
            location: location,
            metrics: metrics
        )
    }

    private static func resolveEssentials(
        location: CGPoint,
        metrics: SidebarEssentialsLayoutMetrics
    ) -> SidebarDropResolution {
        guard metrics.visibleItemCount > 0 else {
            return SidebarDropResolution(
                slot: .essentials(slot: 0),
                folderIntent: .none,
                activeHoveredFolderId: nil
            )
        }

        let slot = resolvedEssentialsSlot(location: location, metrics: metrics)

        return SidebarDropResolution(
            slot: .essentials(slot: slot),
            folderIntent: .none,
            activeHoveredFolderId: nil
        )
    }

    private static func resolvedEssentialsSlot(
        location: CGPoint,
        metrics: SidebarEssentialsLayoutMetrics
    ) -> Int {
        let orderedSlots = metrics.dropSlotFrames

        if let containingSlot = orderedSlots.first(where: { $0.frame.contains(location) }) {
            return max(0, min(containingSlot.slot, metrics.visibleItemCount))
        }

        guard let nearestSlot = orderedSlots.min(by: { lhs, rhs in
            squaredDistance(from: location, to: lhs.frame) < squaredDistance(from: location, to: rhs.frame)
        }) else {
            return 0
        }

        return max(0, min(nearestSlot.slot, metrics.visibleItemCount))
    }

    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx: CGFloat
        if point.x < rect.minX {
            dx = rect.minX - point.x
        } else if point.x > rect.maxX {
            dx = point.x - rect.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < rect.minY {
            dy = rect.minY - point.y
        } else if point.y > rect.maxY {
            dy = point.y - rect.maxY
        } else {
            dy = 0
        }

        return (dx * dx) + (dy * dy)
    }

    private static func midpointSlotIndex(localY: CGFloat, itemCount: Int? = nil) -> Int {
        let rawIndex = Int(floor((localY / rowStride) + 0.5))
        guard let itemCount else {
            return max(0, rawIndex)
        }
        return max(0, min(rawIndex, itemCount))
    }
}

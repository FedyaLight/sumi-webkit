import CoreGraphics
import Foundation

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

struct SidebarDropResolution: Equatable {
    let slot: DropZoneSlot
    let folderIntent: FolderDropIntent
    let activeHoveredFolderId: UUID?
}

@MainActor
enum SidebarDropResolver {
    private static let rowStride: CGFloat = SidebarRowLayout.rowHeight
    private static let folderHeaderTopLevelBeforeBandHeight: CGFloat = 10

    static func resolve(
        location: CGPoint,
        state: SidebarDragState,
        draggedItem: SumiDragItem?,
        scope: SidebarDragScope? = nil
    ) -> SidebarDropResolution {
        let activeScope = scope ?? state.activeDragScope
        let hoveredPage = state.hoveredInteractivePage(
            at: location,
            matching: activeScope
        )
        if hoveredPage == nil {
            state.requestGeometryRefresh()
        }
        return resolve(
            location: location,
            state: state,
            draggedItem: draggedItem,
            hoveredPage: hoveredPage,
            scope: activeScope
        )
    }

    private static func resolve(
        location: CGPoint,
        state: SidebarDragState,
        draggedItem: SumiDragItem?,
        hoveredPage: SidebarPageGeometryMetrics?,
        scope: SidebarDragScope?
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
        state.hoveredSlot = resolution.slot
        state.folderDropIntent = resolution.folderIntent
        state.activeHoveredFolderId = resolution.activeHoveredFolderId
        state.updateEssentialsPreviewState(
            at: location,
            resolution: resolution.slot
        )
        return resolution
    }

    private static func resolveSpacePinnedTarget(
        location: CGPoint,
        state: SidebarDragState,
        draggedItem: SumiDragItem?,
        hoveredPage: SidebarPageGeometryMetrics?
    ) -> SidebarDropResolution? {
        guard let hoveredPage,
              let pinnedFrame = state.sectionFrame(for: .spacePinned, in: hoveredPage.spaceId),
              pinnedFrame.contains(location) else {
            return nil
        }

        let topLevelItems = state.topLevelPinnedItemTargets.values
            .filter { $0.spaceId == hoveredPage.spaceId }
            .sorted { lhs, rhs in
                if lhs.topLevelIndex != rhs.topLevelIndex {
                    return lhs.topLevelIndex < rhs.topLevelIndex
                }
                return lhs.itemId.uuidString < rhs.itemId.uuidString
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
        let targets = state.folderDropTargets.values
            .filter { $0.spaceId == hoveredPage.spaceId }
            .sorted { lhs, rhs in
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
                    state: state,
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

    private static func resolveFolderHeader(
        _ target: SidebarFolderDropTargetMetrics,
        frame: CGRect,
        location: CGPoint,
        state: SidebarDragState,
        draggedItem: SumiDragItem?
    ) -> SidebarDropResolution {
        if draggedItem?.kind == .folder, draggedItem?.tabId == target.folderId {
            return emptyResolution
        }

        if draggedItem?.kind == .folder {
            return topLevelPinnedReorderResolution(
                for: target,
                location: location,
                state: state,
                fallbackFrame: frame
            )
        }

        if location.y < frame.minY + min(folderHeaderTopLevelBeforeBandHeight, frame.height / 3) {
            return topLevelPinnedResolution(for: target, slot: target.topLevelIndex)
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

        if draggedItem?.kind == .folder {
            return topLevelPinnedReorderResolution(
                for: target,
                location: location,
                state: state,
                fallbackFrame: frame
            )
        }

        guard target.isOpen else {
            return containResolution(for: target)
        }

        guard target.childCount > 0 else {
            return insertIntoFolderResolution(for: target, index: 0)
        }

        let childTargets = state.folderChildDropTargets.values
            .filter { $0.folderId == target.folderId }
            .sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return lhs.childId.uuidString < rhs.childId.uuidString
            }

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
            return topLevelPinnedResolution(for: target, slot: target.topLevelIndex + 1)
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
            return topLevelPinnedResolution(for: target, slot: target.topLevelIndex + 1)
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

        return topLevelPinnedResolution(for: target, slot: target.topLevelIndex + 1)
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

    private static func topLevelPinnedResolution(
        for target: SidebarFolderDropTargetMetrics,
        slot: Int
    ) -> SidebarDropResolution {
        SidebarDropResolution(
            slot: .spacePinned(spaceId: target.spaceId, slot: max(0, slot)),
            folderIntent: .none,
            activeHoveredFolderId: nil
        )
    }

    private static func topLevelPinnedReorderResolution(
        for target: SidebarFolderDropTargetMetrics,
        location: CGPoint,
        state: SidebarDragState,
        fallbackFrame: CGRect
    ) -> SidebarDropResolution {
        let reportedFrame = state.topLevelPinnedItemTargets[target.folderId].flatMap { metrics in
            metrics.spaceId == target.spaceId ? metrics.frame : nil
        }
        let itemFrame = reportedFrame ?? fallbackFrame
        let slot = location.y < itemFrame.midY
            ? target.topLevelIndex
            : target.topLevelIndex + 1
        return topLevelPinnedResolution(for: target, slot: slot)
    }

    private static var emptyResolution: SidebarDropResolution {
        SidebarDropResolution(
            slot: .empty,
            folderIntent: .none,
            activeHoveredFolderId: nil
        )
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
                activeHoveredFolderId: nil
            )
        }

        if let regularFrame = outerFrame,
           location.x >= regularFrame.minX,
           location.x <= regularFrame.maxX,
           location.y >= regularFrame.maxY {
            return SidebarDropResolution(
                slot: .spaceRegular(spaceId: spaceId, slot: 9999),
                folderIntent: .none,
                activeHoveredFolderId: nil
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
            return .empty
        }

        guard metrics.itemCount > 0 else {
            return .spaceRegular(spaceId: spaceId, slot: 0)
        }

        if location.y <= metrics.frame.maxY {
            let localY = max(0, location.y - metrics.frame.minY)
            let slotIndex = midpointSlotIndex(localY: localY, itemCount: metrics.itemCount)
            return .spaceRegular(spaceId: spaceId, slot: slotIndex)
        }

        return .spaceRegular(spaceId: spaceId, slot: metrics.itemCount)
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
              metrics.dropFrame.contains(location) else {
            _ = draggedItem
            return nil
        }
        guard metrics.canAcceptDrop || metrics.visibleItemCount > 0 else {
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
        let orderedSlots = metrics.dropSlotFrames.sorted { lhs, rhs in
            if lhs.slot != rhs.slot { return lhs.slot < rhs.slot }
            if lhs.frame.minY != rhs.frame.minY { return lhs.frame.minY < rhs.frame.minY }
            return lhs.frame.minX < rhs.frame.minX
        }

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

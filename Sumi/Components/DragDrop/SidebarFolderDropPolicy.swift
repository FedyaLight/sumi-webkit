import CoreGraphics
import Foundation
import SumiDomain

struct SidebarFolderDropContext {
    let targets: [SidebarFolderDropTargetMetrics]
    let childrenByFolder: [UUID: [SidebarFolderChildDropTargetMetrics]]
    let draggedItem: SumiDragItem?
}

enum SidebarFolderDropPolicy {
    private static let headerBeforeBandHeight: CGFloat = 10

    static func resolve(
        location: CGPoint,
        context: SidebarFolderDropContext
    ) -> SidebarDropResolution? {
        let targets = context.targets
            .filter {
                containingArea(for: $0, at: location)
                    < .greatestFiniteMagnitude
            }
            .sorted { lhs, rhs in
                let leftArea = containingArea(for: lhs, at: location)
                let rightArea = containingArea(for: rhs, at: location)
                if leftArea != rightArea { return leftArea < rightArea }
                let leftY = lhs.headerFrame?.minY
                    ?? lhs.bodyFrame?.minY
                    ?? lhs.afterFrame?.minY
                    ?? .greatestFiniteMagnitude
                let rightY = rhs.headerFrame?.minY
                    ?? rhs.bodyFrame?.minY
                    ?? rhs.afterFrame?.minY
                    ?? .greatestFiniteMagnitude
                if leftY != rightY { return leftY < rightY }
                return lhs.folderId.uuidString < rhs.folderId.uuidString
            }

        for target in targets {
            if let frame = target.headerFrame, frame.contains(location) {
                return resolveHeader(
                    target,
                    frame: frame,
                    location: location,
                    draggedItem: context.draggedItem
                )
            }
            if let frame = target.bodyFrame, frame.contains(location) {
                return resolveBody(
                    target,
                    frame: frame,
                    location: location,
                    childTargets: context.childrenByFolder[target.folderId]
                        ?? [],
                    draggedItem: context.draggedItem
                )
            }
            if target.afterFrame?.contains(location) == true {
                return resolveAfter(
                    target,
                    draggedItem: context.draggedItem
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

    private static func resolveHeader(
        _ target: SidebarFolderDropTargetMetrics,
        frame: CGRect,
        location: CGPoint,
        draggedItem: SumiDragItem?
    ) -> SidebarDropResolution {
        guard isSelfDrag(target, draggedItem: draggedItem) == false else {
            return .empty
        }
        if location.y < frame.minY
            + min(headerBeforeBandHeight, frame.height / 3) {
            return parentResolution(for: target, slot: target.topLevelIndex)
        }
        return target.isOpen
            ? insertionResolution(for: target, index: 0)
            : containmentResolution(for: target)
    }

    private static func resolveBody(
        _ target: SidebarFolderDropTargetMetrics,
        frame: CGRect,
        location: CGPoint,
        childTargets: [SidebarFolderChildDropTargetMetrics],
        draggedItem: SumiDragItem?
    ) -> SidebarDropResolution {
        guard isSelfDrag(target, draggedItem: draggedItem) == false else {
            return .empty
        }
        guard target.isOpen else { return containmentResolution(for: target) }
        guard target.childCount > 0 else {
            return insertionResolution(for: target, index: 0)
        }
        if let childResolution = resolveChildRows(
            target,
            location: location,
            childTargets: childTargets
        ) {
            return childResolution
        }
        let localY = max(0, location.y - frame.minY)
        let rowContentHeight = CGFloat(target.childCount)
            * SidebarDropSlotPolicy.rowStride
        guard localY <= rowContentHeight else {
            return insertionResolution(
                for: target,
                index: target.childCount
            )
        }
        return insertionResolution(
            for: target,
            index: SidebarDropSlotPolicy.midpointIndex(
                localY: localY,
                itemCount: target.childCount
            )
        )
    }

    private static func resolveChildRows(
        _ target: SidebarFolderDropTargetMetrics,
        location: CGPoint,
        childTargets: [SidebarFolderChildDropTargetMetrics]
    ) -> SidebarDropResolution? {
        guard let first = childTargets.first,
              let last = childTargets.last else { return nil }
        if location.y < first.frame.minY {
            return insertionResolution(for: target, index: 0)
        }
        for child in childTargets where child.frame.contains(location) {
            return insertionResolution(
                for: target,
                index: location.y < child.frame.midY
                    ? child.index
                    : child.index + 1
            )
        }
        for (previous, next) in zip(childTargets, childTargets.dropFirst())
            where location.y >= previous.frame.maxY
                && location.y < next.frame.minY {
            return insertionResolution(
                for: target,
                index: previous.index + 1
            )
        }
        if location.y > last.frame.maxY {
            return insertionResolution(
                for: target,
                index: target.childCount
            )
        }
        return nil
    }

    private static func resolveAfter(
        _ target: SidebarFolderDropTargetMetrics,
        draggedItem: SumiDragItem?
    ) -> SidebarDropResolution {
        guard isSelfDrag(target, draggedItem: draggedItem) == false else {
            return .empty
        }
        return parentResolution(for: target, slot: target.topLevelIndex + 1)
    }

    private static func isSelfDrag(
        _ target: SidebarFolderDropTargetMetrics,
        draggedItem: SumiDragItem?
    ) -> Bool {
        draggedItem?.kind == .folder && draggedItem?.tabId == target.folderId
    }

    private static func containmentResolution(
        for target: SidebarFolderDropTargetMetrics
    ) -> SidebarDropResolution {
        SidebarDropResolution(
            slot: .folder(folderId: target.folderId, slot: target.childCount),
            folderIntent: .contain(folderId: target.folderId),
            activeHoveredFolderId: target.folderId
        )
    }

    private static func insertionResolution(
        for target: SidebarFolderDropTargetMetrics,
        index: Int
    ) -> SidebarDropResolution {
        let safeIndex = max(0, min(index, target.childCount))
        return SidebarDropResolution(
            slot: .folder(folderId: target.folderId, slot: safeIndex),
            folderIntent: .insertIntoFolder(
                folderId: target.folderId,
                index: safeIndex
            ),
            activeHoveredFolderId: target.folderId
        )
    }

    private static func parentResolution(
        for target: SidebarFolderDropTargetMetrics,
        slot: Int
    ) -> SidebarDropResolution {
        let safeSlot = max(0, slot)
        if let parentFolderID = target.parentFolderId {
            return SidebarDropResolution(
                slot: .folder(folderId: parentFolderID, slot: safeSlot),
                folderIntent: .insertIntoFolder(
                    folderId: parentFolderID,
                    index: safeSlot
                ),
                activeHoveredFolderId: nil
            )
        }
        return SidebarDropResolution(
            slot: .spacePinned(spaceId: target.spaceId, slot: safeSlot),
            folderIntent: .none,
            activeHoveredFolderId: nil
        )
    }
}

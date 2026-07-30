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

//
//  SidebarSplitPairingHitTest.swift
//  Sumi
//

import CoreGraphics
import Foundation

/// A normalized visual-row hit. Storage differs between uniform lists and
/// measured folder rows, but split admission and drop resolution do not.
struct SidebarSplitPairingHit {
    enum Residence {
        case regular(
            spaceID: UUID,
            insertionIndex: Int,
            boundary: SidebarVisualSceneProjection.RegularBoundary?
        )
        case pinned(spaceID: UUID, insertionIndex: Int)
        case folder(folderID: UUID, insertionIndex: Int)
    }

    let residence: Residence
    let candidate: SidebarSplitPairingCandidate

    func resolution(
        target: SidebarSplitPairingTarget
    ) -> SidebarDropResolution {
        switch residence {
        case .regular(let spaceID, let insertionIndex, let boundary):
            return SidebarDropResolution(
                slot: .spaceRegular(
                    spaceId: spaceID,
                    slot: insertionIndex
                ),
                folderIntent: .none,
                activeHoveredFolderId: nil,
                presentedRegularBoundary: boundary,
                splitPairingTarget: target
            )
        case .pinned(let spaceID, let insertionIndex):
            return SidebarDropResolution(
                slot: .spacePinned(
                    spaceId: spaceID,
                    slot: insertionIndex
                ),
                folderIntent: .none,
                activeHoveredFolderId: nil,
                splitPairingTarget: target
            )
        case .folder(let folderID, let insertionIndex):
            return SidebarDropResolution(
                slot: .folder(
                    folderId: folderID,
                    slot: insertionIndex
                ),
                folderIntent: .insertIntoFolder(
                    folderId: folderID,
                    index: insertionIndex
                ),
                activeHoveredFolderId: folderID,
                splitPairingTarget: target
            )
        }
    }
}

@MainActor
enum SidebarSplitPairingHitTest {
    static func hit(
        at location: CGPoint,
        state: SidebarDragState,
        hoveredPage: SidebarPageGeometryMetrics
    ) -> SidebarSplitPairingHit? {
        regularHit(
            at: location,
            state: state,
            spaceID: hoveredPage.spaceId
        )
            ?? uniformPinnedHit(
                at: location,
                state: state,
                spaceID: hoveredPage.spaceId
            )
            ?? measuredPinnedHit(
                at: location,
                state: state,
                spaceID: hoveredPage.spaceId
            )
            ?? folderChildHit(
                at: location,
                state: state,
                spaceID: hoveredPage.spaceId
            )
    }

    private static func regularHit(
        at location: CGPoint,
        state: SidebarDragState,
        spaceID: UUID
    ) -> SidebarSplitPairingHit? {
        guard let metrics = state.regularListHitTargets[spaceID],
              let rowIndex = metrics.rowIndex(containing: location),
              let candidate = metrics.splitPairingCandidate(
                at: rowIndex
              ) else {
            return nil
        }
        let insertionIndex = rowIndex + 1
        return SidebarSplitPairingHit(
            residence: .regular(
                spaceID: spaceID,
                insertionIndex: insertionIndex,
                boundary: metrics.presentedBoundary(at: insertionIndex)
            ),
            candidate: candidate
        )
    }

    private static func uniformPinnedHit(
        at location: CGPoint,
        state: SidebarDragState,
        spaceID: UUID
    ) -> SidebarSplitPairingHit? {
        guard let metrics = state.pinnedListHitTargets[spaceID],
              let rowIndex = metrics.rowIndex(containing: location),
              let candidate = metrics.splitPairingCandidate(
                at: rowIndex
              ) else {
            return nil
        }
        return SidebarSplitPairingHit(
            residence: .pinned(
                spaceID: spaceID,
                insertionIndex: rowIndex + 1
            ),
            candidate: candidate
        )
    }

    private static func measuredPinnedHit(
        at location: CGPoint,
        state: SidebarDragState,
        spaceID: UUID
    ) -> SidebarSplitPairingHit? {
        guard let metrics =
            state.topLevelPinnedItemsBySpace[spaceID]?.first(
                where: { $0.frame.contains(location) }
            ) else {
            return nil
        }
        return SidebarSplitPairingHit(
            residence: .pinned(
                spaceID: spaceID,
                insertionIndex: metrics.topLevelIndex + 1
            ),
            candidate: SidebarSplitPairingCandidate(
                frame: metrics.frame,
                memberIDs: metrics.splitPairingMemberIDs
            )
        )
    }

    private static func folderChildHit(
        at location: CGPoint,
        state: SidebarDragState,
        spaceID: UUID
    ) -> SidebarSplitPairingHit? {
        let hoveredFolder = (
            state.folderTargetsBySpace[spaceID] ?? []
        )
        .filter { $0.bodyFrame?.contains(location) == true }
        .min {
            ($0.bodyFrame?.height ?? .greatestFiniteMagnitude)
                < ($1.bodyFrame?.height ?? .greatestFiniteMagnitude)
        }

        guard let folderID = hoveredFolder?.folderId,
              let metrics = state.folderChildrenByFolder[folderID]?.first(
                  where: { $0.frame.contains(location) }
              ) else {
            return nil
        }
        return SidebarSplitPairingHit(
            residence: .folder(
                folderID: folderID,
                insertionIndex: metrics.index + 1
            ),
            candidate: SidebarSplitPairingCandidate(
                frame: metrics.frame,
                memberIDs: metrics.splitPairingMemberIDs
            )
        )
    }
}

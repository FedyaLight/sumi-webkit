import CoreGraphics
import Foundation
import SumiDomain

struct SplitDropResolutionContext {
    private static let previewPlaceholder = SplitMember.regularTab(UUID())

    let group: SplitGroup
    let location: CGPoint
    let bounds: CGRect
    let draggedMember: SplitMember?
    let previewMember: SplitMember
    let draggedMemberIsInGroup: Bool
    let leafHit: SplitLayoutGeometry.LeafHit?

    init?(
        group: SplitGroup,
        location: CGPoint,
        bounds: CGRect,
        draggedMember: SplitMember?
    ) {
        guard bounds.width > 0,
              bounds.height > 0,
              bounds.contains(location) else {
            return nil
        }

        self.group = group
        self.location = location
        self.bounds = bounds
        self.draggedMember = draggedMember
        previewMember = draggedMember
            ?? Self.previewMember(excluding: group)
        draggedMemberIsInGroup = draggedMember.map {
            group.contains($0.memberID)
        } ?? false
        leafHit = SplitLayoutGeometry.leafHit(
            in: group.layoutTree,
            at: location,
            in: bounds
        )
    }

    var canInsertAtEdge: Bool {
        draggedMemberIsInGroup
            || group.memberIDs.count < SplitGroup.maximumMembers
    }

    private static func previewMember(
        excluding group: SplitGroup
    ) -> SplitMember {
        var preview = previewPlaceholder
        while group.contains(preview.memberID) {
            preview = .regularTab(UUID())
        }
        return preview
    }
}

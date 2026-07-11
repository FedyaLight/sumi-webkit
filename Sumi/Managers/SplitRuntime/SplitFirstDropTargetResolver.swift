import CoreGraphics
import Foundation
import SumiDomain

enum SplitFirstDropTargetResolver {
    private static let previewPlaceholder = SplitMember.regularTab(UUID())

    static func target(
        currentMember: SplitMember,
        at location: CGPoint,
        bounds: CGRect,
        draggedMember: SplitMember?
    ) -> SplitDropTarget? {
        guard bounds.width > 0,
              bounds.height > 0,
              bounds.contains(location),
              let side = SplitDropEdgeHitPolicy.side(
                  at: location,
                  in: bounds,
                  mode: .create
              ) else {
            return nil
        }

        guard draggedMember?.memberID != currentMember.memberID else {
            return nil
        }
        var placeholder = Self.previewPlaceholder
        while placeholder.memberID == currentMember.memberID {
            placeholder = .regularTab(UUID())
        }
        let previewMember = draggedMember ?? placeholder
        return SplitDropTarget(
            targetMemberID: currentMember.memberID,
            side: side,
            targetRect: SplitDropTargetGeometry.firstSplitPreviewRect(
                currentMember: currentMember,
                previewMember: previewMember,
                side: side,
                bounds: bounds
            ) ?? bounds,
            intent: .firstSplit
        )
    }
}

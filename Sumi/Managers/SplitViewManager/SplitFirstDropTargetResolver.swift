import CoreGraphics
import Foundation

enum SplitFirstDropTargetResolver {
    static func target(
        currentTabId: UUID,
        at location: CGPoint,
        bounds: CGRect,
        draggedTabId: UUID?
    ) -> SplitDropTarget? {
        guard bounds.width > 0,
              bounds.height > 0,
              bounds.contains(location),
              let side = SplitDropCaptureHitPolicy.side(
                  at: location,
                  in: bounds,
                  mode: .create
              )
        else {
            return nil
        }

        return SplitDropTarget(
            tabId: currentTabId,
            side: side,
            targetRect: SplitDropTargetGeometry.firstSplitPreviewRect(
                currentTabId: currentTabId,
                previewTabId: draggedTabId ?? UUID(),
                side: side,
                bounds: bounds
            ) ?? bounds,
            intent: .firstSplit
        )
    }
}

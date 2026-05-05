import Foundation
import SwiftUI

enum SidebarPosition: String, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left:
            return "Left"
        case .right:
            return "Right"
        }
    }

    var shellEdge: SidebarShellEdge {
        SidebarShellEdge(position: self)
    }
}

struct SidebarShellEdge: Equatable {
    let position: SidebarPosition

    var isLeft: Bool {
        position == .left
    }

    var isRight: Bool {
        position == .right
    }

    var overlayAlignment: Alignment {
        isLeft ? .leading : .trailing
    }

    var frameAlignment: Alignment {
        isLeft ? .topLeading : .topTrailing
    }

    var resizeHandleAlignment: Alignment {
        isLeft ? .trailing : .leading
    }

    var toggleSidebarSymbolName: String {
        isLeft ? "sidebar.left" : "sidebar.right"
    }

    func resizeDelta(startingMouseX: CGFloat, currentMouseX: CGFloat) -> CGFloat {
        isLeft ? (currentMouseX - startingMouseX) : (startingMouseX - currentMouseX)
    }

    var resizeIndicatorOffset: CGFloat {
        isRight ? 3 : -3
    }

    var resizeHitAreaOffset: CGFloat {
        isRight ? 5 : -5
    }

    func containsTriggerZone(
        mouseX: CGFloat,
        windowFrame: CGRect,
        triggerWidth: CGFloat,
        overshootSlack: CGFloat
    ) -> Bool {
        if isLeft {
            return mouseX >= windowFrame.minX - overshootSlack
                && mouseX <= windowFrame.minX + triggerWidth
        }

        return mouseX <= windowFrame.maxX + overshootSlack
            && mouseX >= windowFrame.maxX - triggerWidth
    }

    func containsSidebarContentZone(
        mouseX: CGFloat,
        windowFrame: CGRect,
        overlayWidth: CGFloat
    ) -> Bool {
        if isLeft {
            return mouseX >= windowFrame.minX
                && mouseX <= windowFrame.minX + overlayWidth
        }

        return mouseX <= windowFrame.maxX
            && mouseX >= windowFrame.maxX - overlayWidth
    }

    func containsKeepOpenZone(
        mouseX: CGFloat,
        windowFrame: CGRect,
        overlayWidth: CGFloat,
        keepOpenHysteresis: CGFloat
    ) -> Bool {
        if isLeft {
            return mouseX >= windowFrame.minX
                && mouseX <= windowFrame.minX + overlayWidth + keepOpenHysteresis
        }

        return mouseX <= windowFrame.maxX
            && mouseX >= windowFrame.maxX - overlayWidth - keepOpenHysteresis
    }

    func sidebarBoundaryAnchorX(in bounds: CGRect, presentationWidth: CGFloat) -> CGFloat {
        let minX = bounds.minX + 1
        let maxX = max(minX, bounds.maxX - 1)
        let rawX = isLeft
            ? bounds.minX + presentationWidth
            : bounds.maxX - presentationWidth
        return min(max(rawX, minX), maxX)
    }

    func sidebarDismissRect(in bounds: CGRect, presentationWidth: CGFloat) -> CGRect {
        let clampedWidth = min(max(presentationWidth, 0), bounds.width)
        let originX = isLeft ? bounds.minX : bounds.maxX - clampedWidth
        return CGRect(
            x: originX,
            y: bounds.minY,
            width: clampedWidth,
            height: bounds.height
        )
    }
}

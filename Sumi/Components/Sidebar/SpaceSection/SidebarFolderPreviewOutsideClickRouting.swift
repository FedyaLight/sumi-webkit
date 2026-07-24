import CoreGraphics

/// Pointer phase the preview's outside-click monitor reacts to.
enum SidebarFolderPreviewPointerPhase {
    case down
    case up
}

/// Why a close is pending, so hover re-entry can cancel a grace close without
/// cancelling the close a click already committed to.
enum SidebarFolderPreviewPendingClose: Equatable {
    case outsideClick
    case hoverGrace

    var reason: String {
        switch self {
        case .outsideClick:
            return "SidebarFolderPreviewSessionOwner.outsideClick"
        case .hoverGrace:
            return "SidebarFolderPreviewSessionOwner.closeGrace"
        }
    }
}

enum SidebarFolderPreviewOutsideClickDecision: Equatable {
    case ignore
    /// Arm the close but leave the panel standing until the gesture ends.
    case closeAfterGesture
    case closeNow
}

/// Pure routing rules for clicks that land while the folder preview is up.
///
/// The panel is passive chrome, so a click outside it must reach whatever is
/// underneath — the command palette's native interaction session solves the
/// same problem by returning the event untouched and deferring its own state
/// change. The preview needs one step more: tearing the
/// panel down between a sidebar row's `mouseDown` and `mouseUp` ends that row's
/// gesture (the transient session's teardown re-renders every folder header), so
/// the close waits for the matching mouse-up rather than the next runloop turn.
enum SidebarFolderPreviewOutsideClickRouting {
    static func decision(
        isPresented: Bool,
        phase: SidebarFolderPreviewPointerPhase,
        isInsidePanel: Bool,
        hasPendingClose: Bool
    ) -> SidebarFolderPreviewOutsideClickDecision {
        guard isPresented else { return .ignore }

        switch phase {
        case .down:
            return isInsidePanel ? .ignore : .closeAfterGesture
        case .up:
            return hasPendingClose ? .closeNow : .ignore
        }
    }

    /// The hover grace must not tear the panel down mid-click either.
    static func graceDecision(isMouseButtonHeld: Bool) -> SidebarFolderPreviewOutsideClickDecision {
        isMouseButtonHeld ? .closeAfterGesture : .closeNow
    }

    static func isInsidePanel(
        swiftUIGlobalPoint point: CGPoint,
        panelFrame: CGRect?
    ) -> Bool {
        guard let panelFrame else { return false }
        return panelFrame.contains(point)
    }
}

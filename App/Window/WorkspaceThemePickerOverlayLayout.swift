import SwiftUI

struct WorkspaceThemePickerOverlayLayout: Equatable {
    static let contentInset: CGFloat = 8
    static let sidebarGap: CGFloat = 10

    let panelLeadingInset: CGFloat
    let interactionFrame: CGRect
    let scrimFrame: CGRect
    /// Horizontal midpoint of the sidebar strip in window coordinates (for motion anchored to the sidebar).
    let sidebarHorizontalCenterX: CGFloat

    init(
        windowSize: CGSize,
        sidebarWidth: CGFloat,
        isSidebarVisible: Bool
    ) {
        let effectiveSidebarWidth = max(sidebarWidth, 0)
        let sidebarLeadingInset = isSidebarVisible ? 0 : SidebarHoverOverlayMetrics.horizontalInset
        let sidebarMaxX = sidebarLeadingInset + effectiveSidebarWidth
        sidebarHorizontalCenterX = sidebarLeadingInset + effectiveSidebarWidth / 2
        let maxPanelLeading = max(
            Self.contentInset,
            windowSize.width - GradientEditorView.panelWidth - Self.contentInset
        )

        panelLeadingInset = min(
            max(sidebarMaxX + Self.sidebarGap, Self.contentInset),
            maxPanelLeading
        )

        interactionFrame = CGRect(
            x: Self.contentInset,
            y: Self.contentInset,
            width: max(windowSize.width - (Self.contentInset * 2), 0),
            height: max(windowSize.height - (Self.contentInset * 2), 0)
        )

        let scrimLeading = min(sidebarMaxX, max(windowSize.width - Self.contentInset, 0))
        scrimFrame = CGRect(
            x: scrimLeading,
            y: Self.contentInset,
            width: max(windowSize.width - scrimLeading - Self.contentInset, 0),
            height: max(windowSize.height - (Self.contentInset * 2), 0)
        )
    }
}

/// Interaction timing for `WorkspaceThemePickerOverlay`.
enum WorkspaceThemePickerOverlayChrome {
    /// Avoids an immediate outside-tap dismiss while the overlay is still mounting from the same event stream that opened it.
    static let outsideDismissDelay: TimeInterval = 0.15
}

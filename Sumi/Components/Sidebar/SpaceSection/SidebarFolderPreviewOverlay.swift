import SwiftUI

/// Window-level host for the collapsed-folder hover preview.
///
/// Zen renders its folder popup as a XUL panel; the in-window equivalent keeps
/// the panel inside the browser window's own view tree, which is what lets a
/// folder drag start from under it instead of being swallowed by a popover's
/// dismissal.
struct SidebarFolderPreviewOverlay: View {
    @ObservedObject private var dragSessionPresentation:
        SidebarDragSessionPresentation

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var surfaceColorScheme: ColorScheme {
        themeContext.nativeSurfaceColorScheme
    }

    init(sidebarDragState: SidebarDragState) {
        _dragSessionPresentation = ObservedObject(
            wrappedValue: sidebarDragState.sessionPresentation
        )
    }

    var body: some View {
        overlayContent(
            isDragging: dragSessionPresentation.frame.isDragging
        )
    }

    @ViewBuilder
    private func overlayContent(isDragging: Bool) -> some View {
        GeometryReader { geo in
            if let presentation = windowState.sidebarFolderPreview.presentation {
                let containerFrame = geo.frame(in: .global)
                let panelFrame = SidebarFolderPreviewPlacement.frame(
                    anchorRect: presentation.anchorRect,
                    candidateCount: presentation.candidates.count,
                    sidebarPosition: presentation.sidebarPosition,
                    containerBounds: containerFrame
                )

                SidebarFolderPreviewPanel(
                    folderName: presentation.folderName,
                    candidates: presentation.candidates,
                    previousFirstResponder: presentation.previousFirstResponder,
                    onHoverChanged: { hovering in
                        windowState.sidebarFolderPreview.setPanelHovered(hovering)
                    },
                    onClose: {
                        windowState.sidebarFolderPreview.close(folderID: presentation.folderID)
                    }
                )
                // Native surfaces resolve their lightness from the space theme,
                // the same scope the downloads popover installs on its content.
                .sumiNativeSurfaceColorScheme(
                    surfaceColorScheme,
                    themeContext: PopoverPresenterChromeSupport.themeContext(
                        themeContext,
                        colorScheme: surfaceColorScheme
                    ),
                    settings: sumiSettings
                )
                .position(
                    x: panelFrame.midX - containerFrame.minX,
                    y: panelFrame.midY - containerFrame.minY
                )
                .id(presentation.id)
                .transition(
                    appearanceTransition(
                        anchorRect: presentation.anchorRect,
                        panelFrame: panelFrame,
                        sidebarPosition: presentation.sidebarPosition
                    )
                )
                // The session owner hit-tests outside clicks against this frame,
                // and placement lives here, so the resolved rect is reported
                // rather than re-derived from window geometry.
                .onAppear {
                    windowState.sidebarFolderPreview.setPanelFrame(panelFrame)
                }
                .onChange(of: panelFrame) { _, frame in
                    windowState.sidebarFolderPreview.setPanelFrame(frame)
                }
            }
        }
        // A live drag owns the pointer outright; the panel is on its way out and
        // must not intercept anything on the way.
        .allowsHitTesting(!isDragging)
        .onChange(of: isDragging) { _, dragging in
            guard dragging else { return }
            windowState.sidebarFolderPreview.dismissForSidebarDrag()
        }
    }

    private func appearanceTransition(
        anchorRect: CGRect,
        panelFrame: CGRect,
        sidebarPosition: SidebarPosition
    ) -> AnyTransition {
        guard !reduceMotion, !sumiSettings.shouldReduceChromeMotion else {
            return .identity
        }

        let sourceAnchor = SidebarFolderPreviewMotion.sourceAnchor(
            anchorRect: anchorRect,
            panelFrame: panelFrame,
            sidebarPosition: sidebarPosition
        )
        let spatialTransition = AnyTransition
            .scale(
                scale: SidebarFolderPreviewMotion.initialScale,
                anchor: sourceAnchor
            )
            .combined(with: .opacity)

        return .asymmetric(
            insertion: spatialTransition.animation(
                .interactiveSpring(
                    response: SidebarFolderPreviewMotion.appearResponse,
                    dampingFraction: 1,
                    blendDuration: 0.06
                )
            ),
            removal: spatialTransition.animation(
                .easeIn(duration: SidebarFolderPreviewMotion.dismissDuration)
            )
        )
    }
}

enum SidebarFolderPreviewMotion {
    static let initialScale: CGFloat = 0.975
    static let appearResponse: Double = 0.2
    static let dismissDuration: Double = 0.12

    static func sourceAnchor(
        anchorRect: CGRect,
        panelFrame: CGRect,
        sidebarPosition: SidebarPosition
    ) -> UnitPoint {
        let relativeY = (anchorRect.midY - panelFrame.minY) / max(panelFrame.height, 1)
        return UnitPoint(
            x: sidebarPosition == .left ? 0 : 1,
            y: min(max(relativeY, 0), 1)
        )
    }

}

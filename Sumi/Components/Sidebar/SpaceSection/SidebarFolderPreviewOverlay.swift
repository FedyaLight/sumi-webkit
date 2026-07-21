import SwiftUI

/// Window-level host for the collapsed-folder hover preview.
///
/// Zen renders its folder popup as a XUL panel; the in-window equivalent keeps
/// the panel inside the browser window's own view tree, which is what lets a
/// folder drag start from under it instead of being swallowed by a popover's
/// dismissal.
struct SidebarFolderPreviewOverlay: View {
    let sidebarDragState: SidebarDragState

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var surfaceColorScheme: ColorScheme {
        themeContext.nativeSurfaceColorScheme
    }

    var body: some View {
        SidebarDragActivityReader(activityState: sidebarDragState.activityState) { isDragging in
            overlayContent(isDragging: isDragging)
        }
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
                .transition(.opacity)
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
        // The session owner mutates outside a `withAnimation`, so the fade has to
        // be driven from here.
        .animation(appearanceAnimation, value: windowState.sidebarFolderPreview.openFolderID)
        // A live drag owns the pointer outright; the panel is on its way out and
        // must not intercept anything on the way.
        .allowsHitTesting(!isDragging)
        .onChange(of: isDragging) { _, dragging in
            guard dragging else { return }
            windowState.sidebarFolderPreview.dismissForSidebarDrag()
        }
    }

    private var appearanceAnimation: Animation? {
        reduceMotion || sumiSettings.shouldReduceChromeMotion
            ? nil
            : .easeOut(duration: 0.12)
    }
}

/// Narrow subscription to the drag-activity flag so the overlay does not
/// re-render on every drag hover sample.
private struct SidebarDragActivityReader<Content: View>: View {
    @ObservedObject var activityState: SidebarDragActivityState

    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        content(activityState.isDragging)
    }
}

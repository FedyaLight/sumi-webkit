import AppKit
import CoreGraphics

struct WebContentInputExclusionRegion: Equatable {
    static let empty = WebContentInputExclusionRegion(windowRects: [])

    let rectsInWindowCoordinates: [CGRect]

    init(windowRects: [CGRect]) {
        rectsInWindowCoordinates = windowRects
            .map(\.standardized)
            .filter { rect in
                !rect.isNull
                    && !rect.isInfinite
                    && rect.width > 0
                    && rect.height > 0
            }
    }

    var isEmpty: Bool {
        rectsInWindowCoordinates.isEmpty
    }

    func contains(windowPoint: CGPoint) -> Bool {
        rectsInWindowCoordinates.contains { $0.contains(windowPoint) }
    }

    @MainActor
    func rects(in view: NSView) -> [CGRect] {
        rectsInWindowCoordinates.compactMap { windowRect in
            let localRect = view.convert(windowRect, from: nil)
                .standardized
                .intersection(view.bounds)
                .standardized
            guard !localRect.isNull,
                  !localRect.isInfinite,
                  localRect.width > 0,
                  localRect.height > 0
            else {
                return nil
            }
            return localRect
        }
    }
}

@MainActor
enum CollapsedSidebarWebContentInputExclusion {
    static func region(
        panelView: NSView?,
        presentationContext: SidebarPresentationContext,
        isSidebarCollapsed: Bool
    ) -> WebContentInputExclusionRegion {
        guard isSidebarCollapsed,
              presentationContext.mode == .collapsedVisible,
              let panelView,
              panelView.window != nil
        else {
            return .empty
        }

        return WebContentInputExclusionRegion(
            windowRects: [panelView.convert(panelView.bounds, to: nil)]
        )
    }
}

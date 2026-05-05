import AppKit
import CoreGraphics

struct SidebarMappedDragLocations {
    let dropLocation: CGPoint
    let previewLocation: CGPoint
}

enum SidebarDragLocationMapper {
    static func swiftUITopLeftPoint(
        windowPoint: CGPoint,
        topBoundaryY: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: windowPoint.x,
            y: max(topBoundaryY, 0) - windowPoint.y
        )
    }

    static func swiftUIGlobalPoint(
        fromWindowPoint windowPoint: CGPoint,
        in window: NSWindow
    ) -> CGPoint {
        return swiftUITopLeftPoint(
            windowPoint: windowPoint,
            topBoundaryY: swiftUITopBoundaryY(in: window)
        )
    }

    static func swiftUIGlobalPoint(
        fromWindowPoint windowPoint: CGPoint,
        in view: NSView
    ) -> CGPoint? {
        guard let window = view.window else { return nil }
        return swiftUIGlobalPoint(fromWindowPoint: windowPoint, in: window)
    }

    static func swiftUIPreviewPoint(
        fromWindowPoint windowPoint: CGPoint,
        in window: NSWindow
    ) -> CGPoint {
        let previewWindow = previewCoordinateWindow(for: window)
        let previewWindowPoint: CGPoint
        if previewWindow === window {
            previewWindowPoint = windowPoint
        } else {
            let screenPoint = window.convertPoint(toScreen: windowPoint)
            previewWindowPoint = previewWindow.convertPoint(fromScreen: screenPoint)
        }

        return swiftUITopLeftPoint(
            windowPoint: previewWindowPoint,
            topBoundaryY: swiftUIFullContentBoundaryY(in: previewWindow)
        )
    }

    static func swiftUIPreviewPoint(
        fromWindowPoint windowPoint: CGPoint,
        in view: NSView
    ) -> CGPoint? {
        guard let window = view.window else { return nil }
        return swiftUIPreviewPoint(fromWindowPoint: windowPoint, in: window)
    }

    static func swiftUIPreviewPoint(
        fromLocalPoint localPoint: CGPoint,
        in view: NSView
    ) -> CGPoint {
        guard let window = view.window else { return localPoint }
        let windowPoint = view.convert(localPoint, to: nil)
        return swiftUIPreviewPoint(fromWindowPoint: windowPoint, in: window)
    }

    static func swiftUIGlobalPoint(
        fromLocalPoint localPoint: CGPoint,
        in view: NSView
    ) -> CGPoint {
        guard let window = view.window else { return localPoint }
        let windowPoint = view.convert(localPoint, to: nil)
        return swiftUIGlobalPoint(fromWindowPoint: windowPoint, in: window)
    }

    static func preferredSourceScreenPoint(
        callbackScreenPoint: NSPoint,
        currentMouseScreenPoint: NSPoint?
    ) -> NSPoint {
        currentMouseScreenPoint ?? callbackScreenPoint
    }

    static func sourceLocationsFromScreenPoint(
        callbackScreenPoint: NSPoint,
        in view: NSView,
        currentMouseScreenPoint: NSPoint? = NSEvent.mouseLocation
    ) -> SidebarMappedDragLocations? {
        guard let window = view.window else { return nil }
        let screenPoint = preferredSourceScreenPoint(
            callbackScreenPoint: callbackScreenPoint,
            currentMouseScreenPoint: currentMouseScreenPoint
        )
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        return SidebarMappedDragLocations(
            dropLocation: swiftUIGlobalPoint(fromWindowPoint: windowPoint, in: window),
            previewLocation: swiftUIPreviewPoint(fromWindowPoint: windowPoint, in: window)
        )
    }

    private static func swiftUITopBoundaryY(in window: NSWindow) -> CGFloat {
        // Sidebar geometry is reported with SwiftUI `.global`, whose vertical origin is the hosting
        // content view, not AppKit's `contentLayoutRect`. Using `contentLayoutRect.maxY` subtracts
        // titlebar/toolbar chrome and shifts drop hit-testing above the rows that draw the guide.
        swiftUIFullContentBoundaryY(in: window)
    }

    private static func swiftUIFullContentBoundaryY(in window: NSWindow) -> CGFloat {
        window.contentView?.bounds.height ?? window.frame.height
    }

    private static func previewCoordinateWindow(for window: NSWindow) -> NSWindow {
        window.parent ?? window
    }
}

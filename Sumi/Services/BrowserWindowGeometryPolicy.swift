import AppKit
import ObjectiveC

/// Owns the AppKit details that distinguish fresh placement from archived
/// restoration. Browser-window orchestration only chooses which operation its
/// transaction needs.
@MainActor
enum BrowserWindowGeometryPolicy {
    private static let restorableFrameKey =
        UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

    static func displayMode(of window: NSWindow) -> BrowserWindowDisplayMode {
        if window.isMiniaturized {
            return .miniaturized
        }
        if window.styleMask.contains(.fullScreen) {
            return .fullScreen
        }
        if window.isZoomed {
            return .zoomed
        }
        return .normal
    }

    static func snapshot(of window: NSWindow) -> BrowserWindowGeometrySnapshot {
        let displayMode = displayMode(of: window)
        if displayMode == .normal {
            captureRestorableFrame(of: window)
        }
        return BrowserWindowGeometrySnapshot(
            frame: BrowserWindowFrameSnapshot(
                restorableFrame(of: window) ?? window.frame
            ),
            displayMode: displayMode
        )
    }

    static func captureRestorableFrame(of window: NSWindow) {
        guard displayMode(of: window) == .normal else { return }
        guard restorableFrame(of: window) != window.frame else { return }
        objc_setAssociatedObject(
            window,
            restorableFrameKey,
            NSValue(rect: window.frame),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    static func placeNewWindow(
        _ window: NSWindow,
        relativeTo source: NSWindow?
    ) {
        guard let source, source !== window else {
            window.center()
            return
        }

        let sourceTopLeft = NSPoint(
            x: source.frame.minX,
            y: source.frame.maxY
        )
        let nextTopLeft = source.cascadeTopLeft(from: sourceTopLeft)
        _ = window.cascadeTopLeft(from: nextTopLeft)
    }

    static func restoreFrame(
        _ snapshot: BrowserWindowGeometrySnapshot,
        to window: NSWindow
    ) {
        let frame = snapshot.frame.cgRect
        guard frame.origin.x.isFinite,
              frame.origin.y.isFinite,
              frame.width.isFinite,
              frame.height.isFinite,
              frame.width > 0,
              frame.height > 0
        else {
            window.center()
            return
        }

        let targetScreen = NSScreen.screens.max { lhs, rhs in
            intersectionArea(lhs.visibleFrame, frame)
                < intersectionArea(rhs.visibleFrame, frame)
        } ?? NSScreen.main
        let safeFrame = targetScreen.map {
            window.constrainFrameRect(frame, to: $0)
        } ?? frame
        window.setFrame(safeFrame, display: false)
        objc_setAssociatedObject(
            window,
            restorableFrameKey,
            NSValue(rect: safeFrame),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    static func restoreDisplayMode(
        _ mode: BrowserWindowDisplayMode,
        to window: NSWindow
    ) {
        switch mode {
        case .normal:
            break
        case .zoomed:
            if window.isZoomed == false {
                window.zoom(nil)
            }
        case .fullScreen:
            if window.styleMask.contains(.fullScreen) == false {
                window.toggleFullScreen(nil)
            }
        case .miniaturized:
            if window.isMiniaturized == false {
                window.miniaturize(nil)
            }
        }
    }

    @discardableResult
    static func restorePendingFrame(
        of windowState: BrowserWindowState,
        to window: NSWindow
    ) -> Bool {
        let restorationState = windowState.restorationState
        guard restorationState.needsPendingWindowGeometryFrame(for: window),
              let geometry = restorationState.pendingWindowGeometry
        else {
            return false
        }
        restoreFrame(geometry, to: window)
        restorationState.markPendingWindowGeometryFrameApplied(to: window)
        return true
    }

    @discardableResult
    static func consumePendingRestoration(
        of windowState: BrowserWindowState,
        in window: NSWindow
    ) -> Bool {
        _ = restorePendingFrame(of: windowState, to: window)
        guard let geometry = windowState.restorationState
            .consumePendingWindowGeometry()
        else {
            return false
        }
        restoreDisplayMode(geometry.displayMode, to: window)
        return true
    }

    private static func restorableFrame(of window: NSWindow) -> NSRect? {
        (objc_getAssociatedObject(window, restorableFrameKey) as? NSValue)?
            .rectValue
    }

    private static func intersectionArea(
        _ lhs: CGRect,
        _ rhs: CGRect
    ) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard intersection.isNull == false else { return 0 }
        return intersection.width * intersection.height
    }
}

import AppKit

final class GlanceOverlayRootView: NSView {
    var onLayout: (() -> Void)?
    var onBackgroundMouseDown: (() -> Void)?
    var onActionChromeMouseDown: ((CGPoint) -> Bool)?
    var acceptsBackgroundMouseEvents = false
    var sidebarPassthroughRect: CGRect? {
        didSet {
            guard sidebarPassthroughRect != oldValue else { return }
            window?.invalidateCursorRects(for: self)
        }
    }
    var webContentCursorExclusionRect: CGRect? {
        didSet {
            guard webContentCursorExclusionRect != oldValue else { return }
            window?.invalidateCursorRects(for: self)
        }
    }
    var chromeCursorExclusionRect: CGRect? {
        didSet {
            guard chromeCursorExclusionRect != oldValue else { return }
            window?.invalidateCursorRects(for: self)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard acceptsBackgroundMouseEvents, bounds.contains(point) else { return nil }

        if let hitView = super.hitTest(point), hitView !== self {
            return hitView
        }

        if sidebarPassthroughRect?.contains(point) == true {
            return nil
        }

        return self
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if onActionChromeMouseDown?(point) == true {
            return
        }
        onBackgroundMouseDown?()
    }

    override func rightMouseDown(with event: NSEvent) {}

    override func otherMouseDown(with event: NSEvent) {}

    override func scrollWheel(with event: NSEvent) {}

    override func resetCursorRects() {
        super.resetCursorRects()
        for rect in backgroundCursorRects {
            addCursorRect(rect, cursor: .arrow)
        }
    }

    override func layout() {
        super.layout()
        onLayout?()
    }

    private var backgroundCursorRects: [CGRect] {
        GlanceOverlayCursorRegionLayout.cursorRects(
            in: bounds,
            excluding: [
                webContentCursorExclusionRect,
                chromeCursorExclusionRect,
                sidebarPassthroughRect,
            ]
        )
    }
}

enum GlanceOverlayCursorRegionLayout {
    static func cursorRects(in bounds: CGRect, excluding exclusionRects: [CGRect?]) -> [CGRect] {
        let exclusions = exclusionRects
            .compactMap { $0?.standardized }
            .map { $0.intersection(bounds) }
            .filter { !$0.isNull && $0.width > 0 && $0.height > 0 }

        let rects = exclusions.reduce(into: [bounds]) { rects, exclusion in
            rects = rects.flatMap { $0.subtracting(exclusion) }
        }
        return rects.filter { $0.width > 0 && $0.height > 0 }
    }
}

private extension CGRect {
    func subtracting(_ excludedRect: CGRect) -> [CGRect] {
        let excludedRect = excludedRect.intersection(self)
        guard !excludedRect.isNull,
              excludedRect.width > 0,
              excludedRect.height > 0
        else { return [self] }

        return [
            CGRect(x: minX, y: minY, width: width, height: max(0, excludedRect.minY - minY)),
            CGRect(x: minX, y: excludedRect.maxY, width: width, height: max(0, maxY - excludedRect.maxY)),
            CGRect(x: minX, y: excludedRect.minY, width: max(0, excludedRect.minX - minX), height: excludedRect.height),
            CGRect(x: excludedRect.maxX, y: excludedRect.minY, width: max(0, maxX - excludedRect.maxX), height: excludedRect.height),
        ].filter { $0.width > 0 && $0.height > 0 }
    }
}

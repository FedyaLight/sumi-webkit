import AppKit
import SwiftUI

enum ChromeCursorKind: Equatable {
    case arrow
    case iBeam
    case resizeLeftRight
    case pointingHand

    var cursor: NSCursor {
        switch self {
        case .arrow:
            return .arrow
        case .iBeam:
            return .iBeam
        case .resizeLeftRight:
            return .resizeLeftRight
        case .pointingHand:
            return .pointingHand
        }
    }

    func set() {
        cursor.set()
    }
}

private final class ChromeCursorNSView: NSView {
    var cursorKind: ChromeCursorKind = .arrow {
        didSet {
            guard cursorKind != oldValue else { return }
            window?.invalidateCursorRects(for: self)
            setCursorIfMouseInside()
        }
    }

    var isCursorEnabled: Bool = true {
        didSet {
            guard isCursorEnabled != oldValue else { return }
            window?.invalidateCursorRects(for: self)
            setCursorIfMouseInside()
        }
    }

    private var trackingArea: NSTrackingArea?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            clearTrackingArea()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        clearTrackingArea()

        guard isCursorEnabled else { return }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        self.trackingArea = trackingArea
        addTrackingArea(trackingArea)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isCursorEnabled else { return }
        addCursorRect(bounds, cursor: cursorKind.cursor)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        setCursorIfMouseInside()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        setCursorIfMouseInside()
    }

    private func clearTrackingArea() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }
    }

    private func setCursorIfMouseInside() {
        guard isCursorEnabled,
              let window
        else { return }

        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard bounds.contains(location) else { return }
        cursorKind.set()
    }
}

struct ChromeCursorView: NSViewRepresentable {
    var kind: ChromeCursorKind
    var isEnabled: Bool = true

    func makeNSView(context: Context) -> NSView {
        let view = ChromeCursorNSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.cursorKind = kind
        view.isCursorEnabled = isEnabled
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ChromeCursorNSView else { return }
        view.cursorKind = kind
        view.isCursorEnabled = isEnabled
    }
}

extension View {
    func chromeCursor(_ kind: ChromeCursorKind, isEnabled: Bool = true) -> some View {
        overlay(ChromeCursorView(kind: kind, isEnabled: isEnabled).allowsHitTesting(false))
    }

    /// Compatibility wrapper for older call sites.
    func alwaysArrowCursor() -> some View {
        chromeCursor(.arrow)
    }
}

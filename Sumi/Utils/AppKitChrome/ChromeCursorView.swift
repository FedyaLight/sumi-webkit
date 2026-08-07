import AppKit

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

extension NSView {
    @MainActor
    func sumi_chromeAddCursorRect(_ rect: NSRect, cursor: ChromeCursorKind) {
        let cursorRect = rect.intersection(visibleRect)
        guard cursorRect.width > 0, cursorRect.height > 0 else { return }
        addCursorRect(cursorRect, cursor: cursor.cursor)
    }

    @MainActor
    @discardableResult
    func sumi_chromeSetCursorIfMouseInside(_ cursor: ChromeCursorKind) -> Bool {
        guard sumi_chromeIsMouseLocationInsideBounds() else { return false }
        cursor.set()
        return true
    }
}

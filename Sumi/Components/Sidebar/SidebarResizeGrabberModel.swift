import AppKit

enum SidebarResizeGrabberLayout {
    static let interactionWidth: CGFloat = 7
    static let interactionHeight: CGFloat = 64
    static let hoverStripWidth: CGFloat = 18
    static let inactiveOpacity: Float = 0.30
    static let activeOpacity: Float = 0.60
    static let activationDelay: TimeInterval = 0.5
    static let hoverFlashVisibleDuration: TimeInterval = 0.7
    static let hoverFlashFadeOutDuration: TimeInterval = 0.5

    static func borderStripFrame(in bounds: CGRect, sidebarPosition: SidebarPosition) -> CGRect {
        let x = sidebarPosition == .left
            ? bounds.maxX - hoverStripWidth
            : bounds.minX
        return CGRect(
            x: x,
            y: bounds.minY,
            width: hoverStripWidth,
            height: bounds.height
        )
    }

    static func resizeZoneFrame(in bounds: CGRect, sidebarPosition: SidebarPosition) -> CGRect {
        let x = sidebarPosition == .left
            ? bounds.maxX - interactionWidth
            : bounds.minX
        return CGRect(
            x: x,
            y: bounds.midY - interactionHeight / 2,
            width: interactionWidth,
            height: interactionHeight
        )
    }

    static func indicatorFrame(in bounds: CGRect, sidebarPosition: SidebarPosition) -> CGRect {
        let x = sidebarPosition == .left
            ? bounds.maxX - SidebarResizeMetrics.grabberWidth
            : bounds.minX
        return CGRect(
            x: x,
            y: bounds.midY - SidebarResizeMetrics.grabberHeight / 2,
            width: SidebarResizeMetrics.grabberWidth,
            height: SidebarResizeMetrics.grabberHeight
        )
    }

    static func canBeginResize(
        isEnabled: Bool,
        isArmed: Bool,
        isResizeSuppressed: Bool,
        isSidebarVisible: Bool
    ) -> Bool {
        isEnabled && isArmed && !isResizeSuppressed && isSidebarVisible
    }

    static func shouldUseResizeCursor(
        isEnabled: Bool,
        isResizeSuppressed: Bool,
        isArmed: Bool,
        isResizing: Bool
    ) -> Bool {
        isEnabled
            && !isResizeSuppressed
            && (isArmed || isResizing)
    }
}

enum SidebarResizeGrabberActivationAction: Equatable {
    case none
    case schedule
    case cancel
}

struct SidebarResizeGrabberInteractionState: Equatable {
    enum VisualState: Equatable {
        case hidden
        case hoverFlash
        case persistent
    }

    private(set) var isHovering = false
    private(set) var isArmed = false
    private(set) var isResizing = false
    private(set) var isHoverFlashVisible = false
    private(set) var hoverFlashGeneration = 0

    var visualState: VisualState {
        if isArmed || isResizing {
            return .persistent
        }
        if isHoverFlashVisible {
            return .hoverFlash
        }
        return .hidden
    }

    mutating func reset() {
        isHovering = false
        isArmed = false
        isResizing = false
        isHoverFlashVisible = false
    }

    mutating func setHovering(
        _ hovering: Bool,
        isEnabled: Bool,
        isResizeSuppressed: Bool
    ) -> SidebarResizeGrabberActivationAction {
        let nextHovering = hovering && isEnabled && !isResizeSuppressed
        guard isHovering != nextHovering else {
            return nextHovering ? .schedule : .none
        }

        isHovering = nextHovering
        if nextHovering {
            return .schedule
        }

        if !isResizing {
            isArmed = false
        }
        return .cancel
    }

    mutating func beginHoverFlash() -> Int? {
        guard !isArmed, !isResizing else {
            isHoverFlashVisible = false
            return nil
        }

        isHoverFlashVisible = true
        hoverFlashGeneration += 1
        return hoverFlashGeneration
    }

    mutating func finishHoverFlash(generation: Int) -> Bool {
        guard generation == hoverFlashGeneration,
              isHoverFlashVisible,
              !isArmed,
              !isResizing
        else {
            return false
        }

        isHoverFlashVisible = false
        return true
    }

    mutating func completeActivation(canBeginResize: Bool) -> Bool {
        guard isHovering, canBeginResize else {
            isArmed = false
            return false
        }

        isArmed = true
        isHoverFlashVisible = false
        return true
    }

    mutating func beginResize(canBeginResize: Bool) -> Bool {
        guard canBeginResize else { return false }
        isResizing = true
        isHoverFlashVisible = false
        return true
    }

    mutating func endResize() {
        isResizing = false
    }
}

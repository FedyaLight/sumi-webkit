import CoreGraphics

struct DockedSidebarLayoutState: Equatable {
    var shouldRender = false
    var progress: CGFloat = 0
    private(set) var generation: UInt64 = 0

    func rendersDockedSidebar(isVisible: Bool) -> Bool {
        isVisible || shouldRender
    }

    func layoutProgress(isVisible: Bool) -> CGFloat {
        isVisible && !shouldRender && progress == 0 ? 1 : progress
    }

    @discardableResult
    mutating func beginShow() -> UInt64 {
        generation &+= 1
        shouldRender = true
        return generation
    }

    mutating func show() {
        progress = 1
    }

    @discardableResult
    mutating func beginAnimatedHide() -> UInt64 {
        generation &+= 1
        shouldRender = true
        if progress <= 0 {
            progress = 1
        }
        return generation
    }

    mutating func hide() {
        progress = 0
    }

    @discardableResult
    mutating func hideImmediately() -> UInt64 {
        generation &+= 1
        progress = 0
        shouldRender = false
        return generation
    }

    mutating func completeAnimatedHide(generation completedGeneration: UInt64, isVisible: Bool) {
        guard completedGeneration == generation,
              !isVisible
        else { return }
        shouldRender = false
    }
}

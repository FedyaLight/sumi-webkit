import CoreGraphics

struct DockedSidebarLayoutState: Equatable {
    var shouldRender = false
    var progress: CGFloat = 0

    func rendersDockedSidebar(isVisible: Bool) -> Bool {
        isVisible || shouldRender
    }

    func layoutProgress(isVisible: Bool) -> CGFloat {
        isVisible && !shouldRender && progress == 0 ? 1 : progress
    }

    mutating func beginShow() {
        shouldRender = true
    }

    mutating func show() {
        progress = 1
    }

    mutating func beginAnimatedHide() {
        shouldRender = true
        if progress <= 0 {
            progress = 1
        }
    }

    mutating func hide() {
        progress = 0
    }

    mutating func hideImmediately() {
        progress = 0
        shouldRender = false
    }

    mutating func completeAnimatedHide(isVisible: Bool) {
        guard !isVisible else { return }
        shouldRender = false
    }
}

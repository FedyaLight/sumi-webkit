import CoreGraphics
import Foundation

@MainActor
final class BrowserSidebarPresentationStateOwner {
    private var savedSidebarWidth: CGFloat = BrowserWindowState.sidebarDefaultWidth
    private var savedSidebarVisibility: Bool = true

    func updateSidebarWidth(_ width: CGFloat, for windowState: BrowserWindowState) {
        let clampedWidth = BrowserWindowState.clampedSidebarWidth(width)
        windowState.sidebarWidth = clampedWidth
        windowState.savedSidebarWidth = clampedWidth
        windowState.sidebarContentWidth = BrowserWindowState.sidebarContentWidth(for: clampedWidth)
        savedSidebarWidth = clampedWidth
    }

    func updateSavedSidebarVisibility(_ isVisible: Bool) {
        savedSidebarVisibility = isVisible
    }

    func toggleSavedSidebarVisibility() {
        savedSidebarVisibility.toggle()
    }

    func updateSavedSidebarWidth(_ width: CGFloat) {
        savedSidebarWidth = width
    }

    func savedSidebarWidth(
        for windowState: BrowserWindowState?,
        activeWindow: BrowserWindowState?
    ) -> CGFloat {
        if let windowState {
            return clampedSavedSidebarWidth(windowState.savedSidebarWidth)
        }

        if let activeWindow {
            return clampedSavedSidebarWidth(activeWindow.savedSidebarWidth)
        }

        return clampedSavedSidebarWidth(savedSidebarWidth)
    }

    func syncFromWindow(_ windowState: BrowserWindowState) {
        savedSidebarWidth = windowState.savedSidebarWidth
        savedSidebarVisibility = windowState.isSidebarVisible
    }

    private func clampedSavedSidebarWidth(_ width: CGFloat) -> CGFloat {
        max(BrowserWindowState.sidebarMinimumWidth, width)
    }
}

import AppKit
import CoreGraphics
import Foundation

@MainActor
final class BrowserSidebarPresentationOwner {
    private static let defaultPersistenceDelayNanoseconds: UInt64 = 450_000_000
    private static let togglePersistenceDelayNanoseconds: UInt64 = 150_000_000

    private let stateOwner: BrowserSidebarPresentationStateOwner
    private let windows: WindowRegistry
    private let persistence: WindowSessionPersistenceCoordinator

    init(
        stateOwner: BrowserSidebarPresentationStateOwner = BrowserSidebarPresentationStateOwner(),
        windows: WindowRegistry,
        persistence: WindowSessionPersistenceCoordinator
    ) {
        self.stateOwner = stateOwner
        self.windows = windows
        self.persistence = persistence
    }

    func updateSidebarWidth(
        _ width: CGFloat,
        for windowState: BrowserWindowState,
        persist: Bool = true
    ) {
        stateOwner.updateSidebarWidth(width, for: windowState)
        if persist {
            persistence.schedule(
                windowState,
                delayNanoseconds: Self.defaultPersistenceDelayNanoseconds
            )
        }
    }

    func updateSavedSidebarVisibility(_ isVisible: Bool) {
        stateOwner.updateSavedSidebarVisibility(isVisible)
    }

    func toggleSavedSidebarVisibility() {
        stateOwner.toggleSavedSidebarVisibility()
    }

    func updateSavedSidebarWidth(_ width: CGFloat) {
        stateOwner.updateSavedSidebarWidth(width)
    }

    func toggleSidebar() {
        if let windowState = sidebarToggleTargetWindowState() {
            toggleSidebar(for: windowState)
        } else {
            stateOwner.toggleSavedSidebarVisibility()
        }
    }

    func toggleSidebar(for windowState: BrowserWindowState) {
        windowState.isSidebarVisible.toggle()
        stateOwner.updateSavedSidebarVisibility(windowState.isSidebarVisible)
        stateOwner.updateSavedSidebarWidth(windowState.savedSidebarWidth)
        persistence.schedule(
            windowState,
            delayNanoseconds: Self.togglePersistenceDelayNanoseconds
        )
    }

    func savedSidebarWidth(for windowState: BrowserWindowState? = nil) -> CGFloat {
        stateOwner.savedSidebarWidth(
            for: windowState,
            activeWindow: windows.activeWindow
        )
    }

    func syncFromWindow(_ windowState: BrowserWindowState) {
        stateOwner.syncFromWindow(windowState)
    }

    private func sidebarToggleTargetWindowState() -> BrowserWindowState? {
        if let activeWindow = windows.activeWindow {
            return activeWindow
        }

        if let keyWindow = NSApp.keyWindow,
           let keyWindowState = windows.windowState(containing: keyWindow) {
            windows.setActive(keyWindowState)
            return keyWindowState
        }

        let allWindows = windows.allWindows
        if allWindows.count == 1,
           let onlyWindow = allWindows.first {
            windows.setActive(onlyWindow)
            return onlyWindow
        }

        return nil
    }
}

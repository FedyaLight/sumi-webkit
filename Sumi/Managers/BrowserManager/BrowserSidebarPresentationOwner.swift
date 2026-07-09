import AppKit
import CoreGraphics
import Foundation

@MainActor
final class BrowserSidebarPresentationOwner {
    private static let defaultPersistenceDelayNanoseconds: UInt64 = 450_000_000
    private static let togglePersistenceDelayNanoseconds: UInt64 = 150_000_000

    private let stateOwner: BrowserSidebarPresentationStateOwner
    private let activeWindowAction: @MainActor () -> BrowserWindowState?
    private let allWindowsAction: @MainActor () -> [BrowserWindowState]
    private let setActiveWindowAction: @MainActor (BrowserWindowState) -> Void
    private let keyWindowStateAction: @MainActor () -> BrowserWindowState?
    private let schedulePersistWindowSessionAction: @MainActor (BrowserWindowState, UInt64) -> Void

    init(
        stateOwner: BrowserSidebarPresentationStateOwner = BrowserSidebarPresentationStateOwner(),
        activeWindow: @escaping @MainActor () -> BrowserWindowState?,
        allWindows: @escaping @MainActor () -> [BrowserWindowState],
        setActiveWindow: @escaping @MainActor (BrowserWindowState) -> Void,
        keyWindowState: @escaping @MainActor () -> BrowserWindowState?,
        schedulePersistWindowSession: @escaping @MainActor (BrowserWindowState, UInt64) -> Void
    ) {
        self.stateOwner = stateOwner
        self.activeWindowAction = activeWindow
        self.allWindowsAction = allWindows
        self.setActiveWindowAction = setActiveWindow
        self.keyWindowStateAction = keyWindowState
        self.schedulePersistWindowSessionAction = schedulePersistWindowSession
    }

    convenience init(browserManager: BrowserManager) {
        self.init(
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            allWindows: { [weak browserManager] in
                browserManager?.windowRegistry?.allWindows ?? []
            },
            setActiveWindow: { [weak browserManager] windowState in
                browserManager?.windowRegistry?.setActive(windowState)
            },
            keyWindowState: { [weak browserManager] in
                guard let browserManager,
                      let keyWindow = NSApp.keyWindow
                else { return nil }

                return browserManager.windowRegistry?.windowState(containing: keyWindow)
            },
            schedulePersistWindowSession: { [weak browserManager] windowState, delayNanoseconds in
                browserManager?.windowSessionBundle.activationOwner.schedulePersistWindowSession(
                    for: windowState,
                    delayNanoseconds: delayNanoseconds
                )
            }
        )
    }

    func updateSidebarWidth(
        _ width: CGFloat,
        for windowState: BrowserWindowState,
        persist: Bool = true
    ) {
        stateOwner.updateSidebarWidth(width, for: windowState)
        if persist {
            schedulePersistWindowSessionAction(
                windowState,
                Self.defaultPersistenceDelayNanoseconds
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
        schedulePersistWindowSessionAction(
            windowState,
            Self.togglePersistenceDelayNanoseconds
        )
    }

    func savedSidebarWidth(for windowState: BrowserWindowState? = nil) -> CGFloat {
        stateOwner.savedSidebarWidth(
            for: windowState,
            activeWindow: activeWindowAction()
        )
    }

    func syncFromWindow(_ windowState: BrowserWindowState) {
        stateOwner.syncFromWindow(windowState)
    }

    private func sidebarToggleTargetWindowState() -> BrowserWindowState? {
        if let activeWindow = activeWindowAction() {
            return activeWindow
        }

        if let keyWindowState = keyWindowStateAction() {
            setActiveWindowAction(keyWindowState)
            return keyWindowState
        }

        let allWindows = allWindowsAction()
        if allWindows.count == 1,
           let onlyWindow = allWindows.first {
            setActiveWindowAction(onlyWindow)
            return onlyWindow
        }

        return nil
    }
}

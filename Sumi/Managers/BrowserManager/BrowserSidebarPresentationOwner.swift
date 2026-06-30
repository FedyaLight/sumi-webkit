import AppKit
import CoreGraphics
import Foundation

@MainActor
final class BrowserSidebarPresentationOwner {
    struct Dependencies {
        let activeWindow: @MainActor () -> BrowserWindowState?
        let allWindows: @MainActor () -> [BrowserWindowState]
        let setActiveWindow: @MainActor (BrowserWindowState) -> Void
        let keyWindowState: @MainActor () -> BrowserWindowState?
        let schedulePersistWindowSession: @MainActor (BrowserWindowState, UInt64) -> Void
    }

    private static let defaultPersistenceDelayNanoseconds: UInt64 = 450_000_000
    private static let togglePersistenceDelayNanoseconds: UInt64 = 150_000_000

    private let stateOwner: BrowserSidebarPresentationStateOwner
    private let dependencies: Dependencies

    init(
        stateOwner: BrowserSidebarPresentationStateOwner = BrowserSidebarPresentationStateOwner(),
        dependencies: Dependencies
    ) {
        self.stateOwner = stateOwner
        self.dependencies = dependencies
    }

    func updateSidebarWidth(
        _ width: CGFloat,
        for windowState: BrowserWindowState,
        persist: Bool = true
    ) {
        stateOwner.updateSidebarWidth(width, for: windowState)
        if persist {
            dependencies.schedulePersistWindowSession(
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
        dependencies.schedulePersistWindowSession(
            windowState,
            Self.togglePersistenceDelayNanoseconds
        )
    }

    func savedSidebarWidth(for windowState: BrowserWindowState?) -> CGFloat {
        stateOwner.savedSidebarWidth(
            for: windowState,
            activeWindow: dependencies.activeWindow()
        )
    }

    func syncFromWindow(_ windowState: BrowserWindowState) {
        stateOwner.syncFromWindow(windowState)
    }

    private func sidebarToggleTargetWindowState() -> BrowserWindowState? {
        if let activeWindow = dependencies.activeWindow() {
            return activeWindow
        }

        if let keyWindowState = dependencies.keyWindowState() {
            dependencies.setActiveWindow(keyWindowState)
            return keyWindowState
        }

        let allWindows = dependencies.allWindows()
        if allWindows.count == 1,
           let onlyWindow = allWindows.first {
            dependencies.setActiveWindow(onlyWindow)
            return onlyWindow
        }

        return nil
    }
}

extension BrowserSidebarPresentationOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
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

                return browserManager.windowRegistry?.allWindows.first { windowState in
                    guard let browserWindow = windowState.window else { return false }
                    if browserWindow === keyWindow {
                        return true
                    }
                    return browserWindow.childWindows?.contains(where: { $0 === keyWindow }) == true
                }
            },
            schedulePersistWindowSession: { [weak browserManager] windowState, delayNanoseconds in
                browserManager?.schedulePersistWindowSession(
                    for: windowState,
                    delayNanoseconds: delayNanoseconds
                )
            }
        )
    }
}

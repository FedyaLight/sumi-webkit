import Foundation

@MainActor
final class BrowserWindowLifecycleOwner {
    private var didAttach = false

    @discardableResult
    func attachIfNeeded(
        windowRegistry: WindowRegistry,
        browserRuntimeIsAvailable: @escaping @MainActor () -> Bool,
        setupWindowState: @escaping @MainActor (BrowserWindowState) -> Void,
        handleWindowWillClose: @escaping @MainActor (UUID) -> Void,
        notifyWindowClosedIfLoaded: @escaping @MainActor (UUID) -> Void,
        cleanupWebViews: @escaping @MainActor (UUID) -> Void,
        cleanupSplitWindow: @escaping @MainActor (UUID) -> Void,
        scheduleWindowClosedMediaReconcile: @escaping @MainActor () -> Void,
        windowState: @escaping @MainActor (UUID) -> BrowserWindowState?,
        closeIncognitoWindow: @escaping @MainActor (BrowserWindowState) async -> Void,
        setActiveWindowState: @escaping @MainActor (BrowserWindowState) -> Void,
        handleWindowVisibilityChanged: @escaping @MainActor (BrowserWindowState) -> Void,
        prepareForAllWindowsClosed: @escaping @MainActor () -> Void,
        performAllWindowsClosedSiteDataCleanup: @escaping @MainActor () async -> Void,
        cleanupWindowAfterRuntimeDeallocation: @escaping @MainActor (UUID) -> Void
    ) -> Bool {
        guard didAttach == false else { return false }
        didAttach = true

        windowRegistry.onWindowRegister = { windowState in
            setupWindowState(windowState)
        }

        for existingWindowState in windowRegistry.allWindows {
            setupWindowState(existingWindowState)
        }

        windowRegistry.onWindowClose = { windowId in
            guard browserRuntimeIsAvailable() else {
                cleanupWindowAfterRuntimeDeallocation(windowId)
                return
            }

            handleWindowWillClose(windowId)
            notifyWindowClosedIfLoaded(windowId)
            cleanupWebViews(windowId)
            cleanupSplitWindow(windowId)
            scheduleWindowClosedMediaReconcile()

            if let closingWindowState = windowState(windowId),
               closingWindowState.isIncognito {
                Task {
                    await closeIncognitoWindow(closingWindowState)
                }
            }
        }

        windowRegistry.onActiveWindowChange = { activeWindowState in
            setActiveWindowState(activeWindowState)
        }

        windowRegistry.onWindowVisibilityChange = { visibleWindowState in
            handleWindowVisibilityChanged(visibleWindowState)
        }

        windowRegistry.onAllWindowsClosed = {
            prepareForAllWindowsClosed()
            Task { @MainActor in
                await performAllWindowsClosedSiteDataCleanup()
            }
        }

        return true
    }
}

import AppKit

@MainActor
final class BrowserMouseButtonRoutingOwner {
    @discardableResult
    func handleOtherMouseDown(
        _ event: NSEvent,
        mouseButtonRouter: any BrowserMouseButtonCommandRouting,
        windowRegistry: WindowRegistry
    ) -> Bool {
        handleMouseButton(
            event.buttonNumber,
            eventWindow: event.window,
            mouseButtonRouter: mouseButtonRouter,
            windowRegistry: windowRegistry
        )
    }

    @discardableResult
    func handleMouseButton(
        _ buttonNumber: Int,
        eventWindow: NSWindow?,
        mouseButtonRouter: any BrowserMouseButtonCommandRouting,
        windowRegistry: WindowRegistry
    ) -> Bool {
        switch buttonNumber {
        case 2:
            guard let windowState = targetWindow(eventWindow: eventWindow, windowRegistry: windowRegistry) else {
                return false
            }
            mouseButtonRouter.focusFloatingBar(
                in: windowState,
                prefill: "",
                navigateCurrentTab: false
            )
            return true
        case 3:
            guard let windowState = targetWindow(eventWindow: eventWindow, windowRegistry: windowRegistry) else {
                return false
            }
            mouseButtonRouter.goBack(in: windowState)
            return true
        case 4:
            guard let windowState = targetWindow(eventWindow: eventWindow, windowRegistry: windowRegistry) else {
                return false
            }
            mouseButtonRouter.goForward(in: windowState)
            return true
        default:
            return false
        }
    }

    private func targetWindow(
        eventWindow: NSWindow?,
        windowRegistry: WindowRegistry
    ) -> BrowserWindowState? {
        if let eventWindow,
           let eventWindowState = windowRegistry.windowState(containing: eventWindow) {
            return eventWindowState
        }
        return windowRegistry.activeWindow
    }
}

import AppKit

@MainActor
final class BrowserMouseButtonRoutingOwner {
    private let sidebarMouseButtonCaptureRegistry: SidebarMouseButtonCaptureRegistry

    init(sidebarMouseButtonCaptureRegistry: SidebarMouseButtonCaptureRegistry) {
        self.sidebarMouseButtonCaptureRegistry = sidebarMouseButtonCaptureRegistry
    }

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
            windowRegistry: windowRegistry,
            deferMiddleButtonToSidebar: containsSidebarMiddleMouseButtonTarget(
                event,
                windowRegistry: windowRegistry
            ),
            deferSideButtonsToSidebar: sidebarMouseButtonCaptureRegistry
                .containsWorkspaceMouseButtonEvent(event)
        )
    }

    @discardableResult
    func handleMouseButton(
        _ buttonNumber: Int,
        eventWindow: NSWindow?,
        mouseButtonRouter: any BrowserMouseButtonCommandRouting,
        windowRegistry: WindowRegistry,
        deferMiddleButtonToSidebar: Bool = false,
        deferSideButtonsToSidebar: Bool = false
    ) -> Bool {
        if deferMiddleButtonToSidebar, buttonNumber == 2 {
            return false
        }

        if deferSideButtonsToSidebar,
           SidebarMouseButtonWorkspaceNavigationPolicy.spaceOffset(for: buttonNumber) != nil {
            return false
        }

        switch buttonNumber {
        case 2:
            guard let windowState = targetWindow(eventWindow: eventWindow, windowRegistry: windowRegistry) else {
                return false
            }
            mouseButtonRouter.focusCommandPalette(
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

    private func containsSidebarMiddleMouseButtonTarget(
        _ event: NSEvent,
        windowRegistry: WindowRegistry
    ) -> Bool {
        guard event.type == .otherMouseDown,
              event.buttonNumber == 2,
              let windowState = targetWindow(
                eventWindow: event.window,
                windowRegistry: windowRegistry
              ),
              let eventWindow = event.window ?? windowRegistry.appKitWindow(for: windowState)
        else {
            return false
        }

        return windowState.sidebarInteractionState.interactiveOwner(
            at: event.locationInWindow,
            in: eventWindow,
            eventType: .otherMouseDown,
            eventButtonNumber: event.buttonNumber
        ) != nil
    }
}

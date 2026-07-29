import AppKit
import ObjectiveC

/// Owns the geometry and visibility of one window's standard AppKit buttons.
///
/// The buttons never leave AppKit's titlebar hierarchy. Custom placement treats their native
/// titlebar container as one cluster, so AppKit updates the shared tracking area together with the
/// visible frames and remains the sole owner of hover, actions and the zoom button's menu.
@MainActor
final class BrowserWindowTrafficLightPlacement {
    private enum FullScreenTransition {
        case none
        case entering
        case exiting
    }

    private weak var window: NSWindow?
    private var buttons: [BrowserWindowTrafficLightAction: NSButton] = [:]
    private var nativeButtonFrames: [BrowserWindowTrafficLightAction: CGRect] = [:]
    private var nativeTitlebarContainerHeight: CGFloat?
    private var requestedRendering: BrowserWindowTrafficLightRendering = .hidden
    private var isLeadingSidebarChrome = false
    private var fullScreenTransition: FullScreenTransition = .none
    private var isApplying = false
    private var isClosing = false
    private var lifecycleReapplyTask: Task<Void, Never>?

    init(window: NSWindow) {
        self.window = window
        refreshButtons()
        installWindowObservers()
        enforce()
    }

    isolated deinit {
        lifecycleReapplyTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func apply(
        rendering: BrowserWindowTrafficLightRendering,
        isLeadingSidebarChrome: Bool = true
    ) {
        guard requestedRendering != rendering
                || self.isLeadingSidebarChrome != isLeadingSidebarChrome
        else { return }
        requestedRendering = rendering
        self.isLeadingSidebarChrome = isLeadingSidebarChrome
        enforce()
    }

    func reapply() {
        enforce()
    }

    func resign() {
        requestedRendering = .hidden
        isLeadingSidebarChrome = false
        enforce()
    }

    // Kept internal for deterministic transition tests. Production transitions arrive through
    // the window notifications installed below.
    func beginFullScreenTransition(isEntering: Bool) {
        fullScreenTransition = isEntering ? .entering : .exiting
        enforce()
    }

    func endFullScreenTransition() {
        fullScreenTransition = .none
        if !refreshButtons() {
            captureNativeLayout()
        }
        enforce()
    }

    private var effectiveRendering: BrowserWindowTrafficLightRendering {
        switch fullScreenTransition {
        case .entering:
            return isLeadingSidebarChrome ? .system : .hidden
        case .exiting:
            return .hidden
        case .none:
            if window?.styleMask.contains(.fullScreen) == true {
                return isLeadingSidebarChrome ? .system : .hidden
            }
            // A stale SwiftUI `.system` request may survive one actor turn after AppKit exits
            // fullscreen. System placement is never valid in a normal window.
            if requestedRendering == .system {
                return .hidden
            }
            return requestedRendering
        }
    }

    private func enforce() {
        guard !isClosing, !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        refreshButtons()
        if effectiveRendering.showsPlaceholder {
            warmSnapshot()
        }

        switch effectiveRendering {
        case .chrome, .handoff:
            applyChromeLayout()
            setNativeClusterVisible(true)
            setButtonAccessibilityVisible(true)
        case .hidden, .travelling:
            setButtonAccessibilityVisible(false)
            setNativeClusterVisible(false)
            if keepsChromePlacementWhileHidden {
                applyChromeLayout()
            } else {
                restoreNativeLayout()
            }
        case .system:
            setNativeClusterVisible(false)
            restoreNativeLayout()
            setNativeClusterVisible(true)
            setButtonAccessibilityVisible(true)
        }
    }

    /// A left-side browser window has one fixed chrome position. Collapsing only changes visual
    /// availability; it does not send invisible buttons back to another coordinate system.
    private var keepsChromePlacementWhileHidden: Bool {
        guard isLeadingSidebarChrome,
              fullScreenTransition == .none,
              window?.styleMask.contains(.fullScreen) != true
        else { return false }
        return true
    }

    private func applyChromeLayout() {
        guard let closeButton = buttons[.close],
              let titlebarView = closeButton.superview,
              let titlebarContainer = titlebarView.superview,
              let containerHost = titlebarContainer.superview,
              let closeNativeFrame = nativeButtonFrames[.close]
        else { return }

        // Follow AppKit's native cluster seam rather than moving three isolated children. Setting
        // the container frame is what makes NSTitlebarView rebuild its shared hover tracking area.
        var containerFrame = titlebarContainer.frame
        containerFrame.origin.x = containerHost.bounds.minX
        containerFrame.origin.y = containerHost.bounds.maxY
            - SidebarChromeMetrics.controlStripHeight
        containerFrame.size.width = containerHost.bounds.width
        containerFrame.size.height = SidebarChromeMetrics.controlStripHeight
        if titlebarContainer.frame != containerFrame {
            titlebarContainer.frame = containerFrame
        }

        let chromeCenterInHost = CGPoint(
            x: containerHost.bounds.minX + BrowserWindowTrafficLightMetrics.chromeLeading,
            y: containerHost.bounds.maxY
                - SidebarChromeMetrics.topControlInset
                - SidebarChromeMetrics.controlStripHeight / 2
        )
        let chromeOriginInTitlebar = titlebarView.convert(chromeCenterInHost, from: containerHost)

        for action in BrowserWindowTrafficLightAction.allCases {
            guard let button = buttons[action],
                  let nativeFrame = nativeButtonFrames[action]
            else { continue }

            let targetOrigin = CGPoint(
                x: chromeOriginInTitlebar.x
                    + nativeFrame.minX - closeNativeFrame.minX,
                y: chromeOriginInTitlebar.y - button.frame.height / 2
            )
            if button.frame.origin != targetOrigin {
                button.setFrameOrigin(targetOrigin)
            }
            // AppKit rebuilds the shared titlebar tracking area from these native views. Lifecycle
            // re-enforcement must invalidate them even when geometry is unchanged.
            button.needsDisplay = true
        }
    }

    private func restoreNativeLayout() {
        if let closeButton = buttons[.close],
           let titlebarContainer = closeButton.superview?.superview,
           let containerHost = titlebarContainer.superview,
           let nativeTitlebarContainerHeight {
            var containerFrame = titlebarContainer.frame
            containerFrame.origin.x = containerHost.bounds.minX
            containerFrame.origin.y = containerHost.bounds.maxY
                - nativeTitlebarContainerHeight
            containerFrame.size.width = containerHost.bounds.width
            containerFrame.size.height = nativeTitlebarContainerHeight
            if titlebarContainer.frame != containerFrame {
                titlebarContainer.frame = containerFrame
            }
        }

        for action in BrowserWindowTrafficLightAction.allCases {
            guard let button = buttons[action],
                  let nativeFrame = nativeButtonFrames[action],
                  button.frame.origin != nativeFrame.origin
            else { continue }
            button.setFrameOrigin(nativeFrame.origin)
            button.needsDisplay = true
        }
    }

    /// Called only at construction, after AppKit completes fullscreen, or when it replaces the
    /// standard button instances. Chrome placement never feeds its own origins back into this.
    private func captureNativeLayout() {
        if let closeButton = buttons[.close],
           let titlebarContainer = closeButton.superview?.superview,
           titlebarContainer.frame.height > 0 {
            nativeTitlebarContainerHeight = titlebarContainer.frame.height
        }

        for action in BrowserWindowTrafficLightAction.allCases {
            guard let button = buttons[action],
                  button.frame.width > 0,
                  button.frame.height > 0
            else { continue }
            nativeButtonFrames[action] = button.frame
        }

        let frames = BrowserWindowTrafficLightAction.allCases.compactMap {
            nativeButtonFrames[$0]
        }
        if BrowserWindowTrafficLightGeometry.learnedClusterWidth == nil,
           let width = BrowserWindowTrafficLightGeometry.measuredClusterWidth(
               fromNativeFrames: frames
           ) {
            BrowserWindowTrafficLightGeometry.learnedClusterWidth = width
        }
    }

    private func setNativeClusterVisible(_ isVisible: Bool) {
        guard let titlebarView = buttons[.close]?.superview,
              titlebarView.isHidden == isVisible
        else { return }
        titlebarView.isHidden = !isVisible
        titlebarView.needsDisplay = true
    }

    private func setButtonAccessibilityVisible(_ isVisible: Bool) {
        for action in BrowserWindowTrafficLightAction.allCases {
            guard let button = buttons[action] else { continue }

            let identifier = isVisible ? action.accessibilityIdentifier : nil
            if button.identifier?.rawValue != identifier {
                button.identifier = identifier.map(NSUserInterfaceItemIdentifier.init(_:))
                button.setAccessibilityIdentifier(identifier)
            }
            if button.isAccessibilityHidden() == isVisible {
                button.setAccessibilityHidden(!isVisible)
            }
        }
    }

    /// AppKit can replace the standard button instances after rebuilding titlebar chrome.
    @discardableResult
    private func refreshButtons() -> Bool {
        guard let window else { return false }

        var currentButtons: [BrowserWindowTrafficLightAction: NSButton] = [:]
        for action in BrowserWindowTrafficLightAction.allCases {
            if let button = window.standardWindowButton(action.buttonType) {
                currentButtons[action] = button
            }
        }

        let changed = buttons.count != currentButtons.count
            || BrowserWindowTrafficLightAction.allCases.contains {
                buttons[$0] !== currentButtons[$0]
            }
        guard changed else { return false }

        buttons = currentButtons
        nativeButtonFrames.removeAll(keepingCapacity: true)
        nativeTitlebarContainerHeight = nil
        captureNativeLayout()
        return true
    }

    // MARK: - Placeholder snapshot

    private func warmSnapshot() {
        guard let window,
              let superview = buttons[.close]?.superview
        else { return }

        let frames = BrowserWindowTrafficLightAction.allCases.compactMap { action
            -> (NSButton, CGRect)? in
            guard let button = buttons[action], button.frame.width > 0 else { return nil }
            return (button, button.frame)
        }
        guard frames.count == BrowserWindowTrafficLightAction.allCases.count else { return }

        let bounds = frames.reduce(CGRect.null) { $0.union($1.1) }
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return }

        let items = frames.map { button, frame in
            BrowserWindowTrafficLightSnapshotItem(
                button: button,
                frame: CGRect(
                    x: frame.minX - bounds.minX,
                    y: superview.isFlipped
                        ? frame.minY - bounds.minY
                        : bounds.maxY - frame.maxY,
                    width: frame.width,
                    height: frame.height
                )
            )
        }
        BrowserWindowTrafficLightSnapshotStore.warm(
            isKeyWindow: window.isKeyWindow,
            items: items,
            size: bounds.size,
            scale: window.backingScaleFactor
        )
    }

    // MARK: - Window lifecycle

    private func installWindowObservers() {
        guard let window else { return }
        let center = NotificationCenter.default

        for name in [
            NSWindow.didResizeNotification,
            NSWindow.didChangeBackingPropertiesNotification,
        ] {
            center.addObserver(
                self,
                selector: #selector(handleWindowLayoutChange(_:)),
                name: name,
                object: window
            )
        }

        for name in [
            NSWindow.willBeginSheetNotification,
            NSWindow.didEndSheetNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
        ] {
            center.addObserver(
                self,
                selector: #selector(handleWindowLifecycleChange(_:)),
                name: name,
                object: window
            )
        }

        center.addObserver(
            self,
            selector: #selector(handleWillEnterFullScreen(_:)),
            name: NSWindow.willEnterFullScreenNotification,
            object: window
        )
        center.addObserver(
            self,
            selector: #selector(handleWillExitFullScreen(_:)),
            name: NSWindow.willExitFullScreenNotification,
            object: window
        )
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            center.addObserver(
                self,
                selector: #selector(handleFullScreenDidChange(_:)),
                name: name,
                object: window
            )
        }
        center.addObserver(
            self,
            selector: #selector(handleWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    @objc private func handleWindowLayoutChange(_ notification: Notification) {
        _ = notification
        enforce()
    }

    @objc private func handleWindowLifecycleChange(_ notification: Notification) {
        _ = notification
        enforce()
        scheduleLifecycleReapply()
    }

    /// Key and sheet notifications are emitted while AppKit is still updating its private
    /// titlebar hierarchy. Reassert once after that transaction; one coalesced actor task is
    /// sufficient and leaves stable windows with no timer, observer churn, or display work.
    private func scheduleLifecycleReapply() {
        lifecycleReapplyTask?.cancel()
        lifecycleReapplyTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self, !self.isClosing else { return }
            self.lifecycleReapplyTask = nil
            self.enforce()
        }
    }

    @objc private func handleWillEnterFullScreen(_ notification: Notification) {
        _ = notification
        beginFullScreenTransition(isEntering: true)
    }

    @objc private func handleWillExitFullScreen(_ notification: Notification) {
        _ = notification
        beginFullScreenTransition(isEntering: false)
    }

    @objc private func handleFullScreenDidChange(_ notification: Notification) {
        _ = notification
        endFullScreenTransition()
    }

    @objc private func handleWindowWillClose(_ notification: Notification) {
        _ = notification
        lifecycleReapplyTask?.cancel()
        lifecycleReapplyTask = nil
        isClosing = true
    }
}

@MainActor
extension NSWindow {
    private static let trafficLightPlacementKey =
        UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

    var browserTrafficLightPlacement: BrowserWindowTrafficLightPlacement {
        if let existing = objc_getAssociatedObject(self, Self.trafficLightPlacementKey)
            as? BrowserWindowTrafficLightPlacement {
            return existing
        }

        let placement = BrowserWindowTrafficLightPlacement(window: self)
        objc_setAssociatedObject(
            self,
            Self.trafficLightPlacementKey,
            placement,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return placement
    }
}

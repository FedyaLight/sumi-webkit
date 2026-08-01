import AppKit
import ObjectiveC

/// Owns visibility of one window's standard AppKit buttons.
///
/// AppKit remains the sole owner of the titlebar hierarchy, button frames, shared hover tracking,
/// actions, and the zoom button's tiling menu. Sidebar transitions may hide individual buttons but
/// never resize, translate, hide, or reparent an AppKit titlebar view.
@MainActor
final class BrowserWindowTrafficLightPlacement {
    private enum FullScreenTransition {
        case none
        case entering
        case exiting
    }

    private weak var window: NSWindow?
    private var buttons: [BrowserWindowTrafficLightAction: NSButton] = [:]
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

    // Internal for deterministic transition tests. Production transitions arrive via AppKit.
    func beginFullScreenTransition(isEntering: Bool) {
        fullScreenTransition = isEntering ? .entering : .exiting
        enforce()
    }

    func endFullScreenTransition() {
        fullScreenTransition = .none
        refreshButtons()
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
            // SwiftUI may publish the pre-exit fullscreen state for one actor turn. AppKit owns
            // that transition; a normal window must not reveal a stale `.system` request.
            return requestedRendering == .system ? .hidden : requestedRendering
        }
    }

    private func enforce() {
        guard !isClosing, !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        refreshButtons()
        let isVisible = effectiveRendering.showsNativeButtons
        setNativeButtonsVisible(isVisible)
        setButtonAccessibilityVisible(isVisible)
    }

    private func setNativeButtonsVisible(_ isVisible: Bool) {
        for action in BrowserWindowTrafficLightAction.allCases {
            guard let button = buttons[action], button.isHidden == isVisible else { continue }
            button.isHidden = !isVisible
            button.needsDisplay = true
        }
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

    /// AppKit can replace the standard button instances after rebuilding fullscreen or modal
    /// chrome. Refresh identity only; their hierarchy and geometry remain untouched.
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
        return true
    }

    private func installWindowObservers() {
        guard let window else { return }
        let center = NotificationCenter.default

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

    @objc private func handleWindowLifecycleChange(_ notification: Notification) {
        _ = notification
        enforce()
        scheduleLifecycleReapply()
    }

    /// Modal lifecycle notifications can arrive before AppKit finishes replacing titlebar
    /// children. One coalesced actor turn reasserts only individual button visibility.
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

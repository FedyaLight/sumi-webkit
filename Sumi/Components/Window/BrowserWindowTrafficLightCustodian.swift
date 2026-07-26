import AppKit
import ObjectiveC

/// Native geometry of the standard window button cluster, as AppKit itself lays it out.
///
/// The values differ per macOS release (macOS 26 grew the buttons to 14pt on a 23pt pitch, older
/// releases used 12pt on a 20pt pitch), so they are derived from the live buttons rather than
/// hardcoded. `fallback` only covers the window that is measured before any button was ever seen
/// in its titlebar.
struct BrowserWindowTrafficLightGeometry: Equatable {
    var diameter: CGFloat
    var centerSpacing: CGFloat

    static var fallback: BrowserWindowTrafficLightGeometry {
        if #available(macOS 26.0, *) {
            return BrowserWindowTrafficLightGeometry(diameter: 14, centerSpacing: 23)
        }
        return BrowserWindowTrafficLightGeometry(diameter: 12, centerSpacing: 20)
    }

    /// Derives the cluster geometry from the buttons' native frames, ordered close → minimize → zoom.
    /// Returns `nil` when the frames cannot describe a standard cluster (zero sizes, wrong count,
    /// non-monotonic or uneven spacing), so a bogus measurement can never displace the fallback.
    static func measured(fromNativeFrames frames: [CGRect]) -> BrowserWindowTrafficLightGeometry? {
        guard frames.count == 3 else { return nil }

        let diameter = frames[0].width
        guard diameter > 0, frames.allSatisfy({ $0.width == diameter && $0.height == diameter })
        else { return nil }

        let firstSpacing = frames[1].midX - frames[0].midX
        let secondSpacing = frames[2].midX - frames[1].midX
        guard firstSpacing > 0, abs(firstSpacing - secondSpacing) <= 0.5 else { return nil }

        return BrowserWindowTrafficLightGeometry(
            diameter: diameter,
            centerSpacing: (firstSpacing + secondSpacing) / 2
        )
    }
}

/// The single owner of a window's live `standardWindowButton` instances.
///
/// The browser chrome hosts the real buttons inside the sidebar header instead of the titlebar, so
/// they need an owner: AppKit keeps its own references to them and re-frames or re-homes them on
/// any titlebar relayout (key transitions, sheets, fullscreen, zoom, screen changes), and more than
/// one cluster view can be alive at once while the sidebar swaps between its docked column and its
/// collapsed overlay. Without arbitration those views fight over the same three buttons and AppKit
/// wins the race, which is what dragged them back to the window's top-left corner.
///
/// The custodian is that arbiter: exactly one host view holds custody at a time, every reparent and
/// every frame write goes through `enforceLayout()`, and when nobody claims the buttons they are
/// returned to the titlebar they came from.
@MainActor
final class BrowserWindowTrafficLightCustodian {
    private struct TitlebarHome {
        let superview: NSView
        let frame: NSRect
    }

    private static var learnedGeometry: BrowserWindowTrafficLightGeometry?

    /// Geometry used by everything that has to reserve space for the cluster, including SwiftUI
    /// layout that runs before any window exists.
    static var resolvedGeometry: BrowserWindowTrafficLightGeometry {
        learnedGeometry ?? .fallback
    }

    private weak var window: NSWindow?
    private weak var custodialHost: NSView?
    private var buttonsByAction: [BrowserWindowTrafficLightAction: NSButton] = [:]
    private var titlebarHomesByAction: [BrowserWindowTrafficLightAction: TitlebarHome] = [:]
    private var observedButtons: [NSButton] = []
    private var isEnforcing = false

    init(window: NSWindow) {
        self.window = window
        captureButtonsIfNeeded()
        installWindowObservers()
    }

    isolated deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var geometry: BrowserWindowTrafficLightGeometry { Self.resolvedGeometry }

    // MARK: - Custody

    /// Hands custody to `host` and applies the requested presentation. Called on every SwiftUI
    /// update, so it must stay cheap and idempotent when nothing changed.
    func attach(
        host: NSView,
        presentation: BrowserWindowTrafficLightPresentation,
        actionProvider: BrowserWindowTrafficLightActionProvider?
    ) {
        guard presentation.isAttached else {
            detach(host: host)
            return
        }

        captureButtonsIfNeeded()
        custodialHost = host
        applyButtonState(presentation: presentation, actionProvider: actionProvider)
        enforceLayout()
    }

    /// Releases custody if `host` currently holds it, returning the buttons to their titlebar home.
    /// A host that never held custody is ignored, so a losing claimant tearing down later cannot
    /// yank the buttons away from the winner.
    func detach(host: NSView) {
        guard custodialHost === host else { return }

        custodialHost = nil
        returnButtonsToTitlebar()
    }

    /// Re-asserts parentage and frames. Safe to call from anywhere; does nothing unless `host` holds
    /// custody.
    func enforce(host: NSView) {
        guard custodialHost === host else { return }
        enforceLayout()
    }

    func hostedButton(for action: BrowserWindowTrafficLightAction) -> NSButton? {
        buttonsByAction[action]
    }

    // MARK: - Layout enforcement

    private func enforceLayout() {
        guard let host = custodialHost, isEnforcing == false else { return }

        isEnforcing = true
        defer { isEnforcing = false }

        for (index, action) in BrowserWindowTrafficLightAction.allCases.enumerated() {
            guard let button = buttonsByAction[action] else { continue }

            if button.superview !== host {
                button.translatesAutoresizingMaskIntoConstraints = true
                button.autoresizingMask = []
                host.addSubview(button)
            }

            let size = resolvedSize(for: button)
            let origin = NSPoint(
                x: CGFloat(index) * geometry.centerSpacing,
                y: max((host.bounds.height - size.height) / 2, 0).rounded()
            )
            let desiredFrame = NSRect(origin: origin, size: size)
            if button.frame != desiredFrame {
                button.frame = desiredFrame
            }
        }
    }

    /// AppKit sizes the buttons itself and that size is authoritative for how they draw; the learned
    /// diameter is only a stand-in for a button that has not been laid out yet.
    private func resolvedSize(for button: NSButton) -> NSSize {
        let currentSize = button.frame.size
        guard currentSize.width > 0, currentSize.height > 0 else {
            return NSSize(width: geometry.diameter, height: geometry.diameter)
        }
        return currentSize
    }

    private func returnButtonsToTitlebar() {
        guard isEnforcing == false else { return }

        isEnforcing = true
        defer { isEnforcing = false }

        for action in BrowserWindowTrafficLightAction.allCases {
            guard let button = buttonsByAction[action],
                  let home = titlebarHomesByAction[action]
            else { continue }

            if button.superview !== home.superview {
                home.superview.addSubview(button)
            }
            if button.frame != home.frame {
                button.frame = home.frame
            }
        }

        // Once the buttons live in the titlebar again, the window's own native-button policy is the
        // authority on whether they show: hidden for the custom browser chrome, visible for the
        // fullscreen titlebar. Reapplying it here keeps the handover correct no matter whether
        // custody is released before or after the fullscreen notification lands.
        window?.setNativeStandardWindowButtonsForBrowserFullScreenChromeVisible(
            window?.styleMask.contains(.fullScreen) == true
        )
    }

    // MARK: - Button capture

    private func captureButtonsIfNeeded() {
        guard let window else { return }

        var didChangeButtons = false
        for action in BrowserWindowTrafficLightAction.allCases {
            guard let button = window.standardWindowButton(action.buttonType) else { continue }

            if buttonsByAction[action] !== button {
                buttonsByAction[action] = button
                // A style-mask change makes AppKit build fresh buttons; the home recorded for the
                // replaced instance describes a view that is no longer ours to return anything to.
                titlebarHomesByAction[action] = nil
                didChangeButtons = true
            }
            // The first sighting happens while the buttons still sit in the titlebar, which is the
            // only moment their native placement can be read.
            if titlebarHomesByAction[action] == nil,
               let superview = button.superview,
               superview !== custodialHost {
                titlebarHomesByAction[action] = TitlebarHome(superview: superview, frame: button.frame)
            }
        }

        guard didChangeButtons else { return }
        learnGeometryIfNeeded()
        installButtonObservers()
    }

    private func learnGeometryIfNeeded() {
        guard Self.learnedGeometry == nil else { return }

        let frames = BrowserWindowTrafficLightAction.allCases.compactMap {
            titlebarHomesByAction[$0]?.frame
        }
        guard let geometry = BrowserWindowTrafficLightGeometry.measured(fromNativeFrames: frames)
        else { return }

        Self.learnedGeometry = geometry
    }

    // MARK: - Observation

    /// A wrong frame *is* the reported symptom, so observing every frame change on the buttons
    /// themselves catches any AppKit relayout without having to enumerate the transitions that
    /// trigger one. `isEnforcing` keeps our own writes from re-entering.
    private func installButtonObservers() {
        let center = NotificationCenter.default
        for button in observedButtons {
            center.removeObserver(self, name: NSView.frameDidChangeNotification, object: button)
        }

        observedButtons = BrowserWindowTrafficLightAction.allCases.compactMap { buttonsByAction[$0] }
        for button in observedButtons {
            button.postsFrameChangedNotifications = true
            center.addObserver(
                self,
                selector: #selector(handleEnforcementTrigger(_:)),
                name: NSView.frameDidChangeNotification,
                object: button
            )
        }
    }

    /// Window-level transitions that re-home the buttons without necessarily changing their frame
    /// first; the frame observer covers the rest.
    private func installWindowObservers() {
        guard let window else { return }

        let center = NotificationCenter.default
        let windowNotificationNames: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didEndSheetNotification,
            NSWindow.didResizeNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.didChangeBackingPropertiesNotification,
        ]
        for name in windowNotificationNames {
            center.addObserver(
                self,
                selector: #selector(handleEnforcementTrigger(_:)),
                name: name,
                object: window
            )
        }
        center.addObserver(
            self,
            selector: #selector(handleEnforcementTrigger(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func handleEnforcementTrigger(_ notification: Notification) {
        // `isEnforcing` means this notification is an echo of our own write.
        guard custodialHost != nil, isEnforcing == false else { return }
        captureButtonsIfNeeded()
        enforceLayout()
    }

    // MARK: - Button state

    private func applyButtonState(
        presentation: BrowserWindowTrafficLightPresentation,
        actionProvider: BrowserWindowTrafficLightActionProvider?
    ) {
        let targetWindow = actionProvider?.resolvedTargetWindow(preferred: window) ?? window

        for action in BrowserWindowTrafficLightAction.allCases {
            guard let button = buttonsByAction[action] else { continue }

            button.target = targetWindow
            button.action = action.selector
            button.isHidden = false
            button.alphaValue = 1
            // Enablement tracks what the window can actually do, not whether the sidebar is settled:
            // AppKit greys a disabled button out, and flashing the cluster grey for the length of
            // the sidebar's collapse is the kind of glitch this cluster exists to avoid. A panel in
            // motion is made unclickable by the host view's hit test and by hiding it from
            // accessibility, both of which leave the buttons drawn exactly as the system draws them.
            button.isEnabled = actionProvider?.isEnabled(action, preferred: targetWindow) ?? false
            button.identifier = NSUserInterfaceItemIdentifier(action.accessibilityIdentifier)
            button.setAccessibilityIdentifier(action.accessibilityIdentifier)
            button.setAccessibilityLabel(
                actionProvider?.accessibilityLabel(for: action, preferred: targetWindow)
                    ?? action.accessibilityLabel
            )
            button.setAccessibilityHidden(!presentation.isInteractive)
        }
    }
}

@MainActor
extension NSWindow {
    private static let trafficLightCustodianKey =
        UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

    /// The one custodian that owns this window's standard window buttons. It hangs off the window
    /// rather than off a lookup table so its lifetime is the window's by construction: no registry
    /// to keep in sync, and nothing left behind when the window closes.
    var browserTrafficLightCustodian: BrowserWindowTrafficLightCustodian {
        if let existing = objc_getAssociatedObject(self, Self.trafficLightCustodianKey)
            as? BrowserWindowTrafficLightCustodian {
            return existing
        }

        let custodian = BrowserWindowTrafficLightCustodian(window: self)
        objc_setAssociatedObject(
            self,
            Self.trafficLightCustodianKey,
            custodian,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return custodian
    }
}

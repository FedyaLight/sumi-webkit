import AppKit
import ObjectiveC.runtime

struct NativeWindowControlsMetrics: Equatable {
    static let fallbackHostedSize = NSSize(width: 60, height: 18)

    let buttonFrames: [NSWindow.ButtonType: NSRect]
    let buttonGroupRect: NSRect
    let normalizedButtonFrames: [NSWindow.ButtonType: NSRect]

    init(
        buttonFrames: [NSWindow.ButtonType: NSRect],
        buttonGroupRect: NSRect
    ) {
        let resolvedGroupRect = buttonGroupRect.isNull ? .zero : buttonGroupRect

        self.buttonFrames = buttonFrames
        self.buttonGroupRect = resolvedGroupRect
        self.normalizedButtonFrames = buttonFrames.mapValues { frame in
            frame.offsetBy(
                dx: -resolvedGroupRect.minX,
                dy: -resolvedGroupRect.minY
            )
        }
    }

    var buttonGroupSize: NSSize {
        buttonGroupRect.size
    }

    var buttonGroupWidth: CGFloat {
        max(buttonGroupSize.width, 0)
    }
}

enum BrowserWindowControlsAccessibilityIdentifiers {
    static let closeButton = "browser-window-close-button"
    static let minimizeButton = "browser-window-minimize-button"
    static let zoomButton = "browser-window-zoom-button"

    static func identifier(for type: NSWindow.ButtonType) -> String {
        switch type {
        case .closeButton:
            return closeButton
        case .miniaturizeButton:
            return minimizeButton
        case .zoomButton:
            return zoomButton
        default:
            return "browser-window-control-\(type.rawValue)"
        }
    }
}

@MainActor
final class NativeWindowControlsHostController {
    let buttonTypes: [NSWindow.ButtonType]

    private weak var window: NSWindow?
    private weak var nativeTitlebarView: NSView?
    private weak var preferredHostView: NSView?

    private(set) var cachedMetrics: NativeWindowControlsMetrics?

    init(
        window: NSWindow,
        buttonTypes: [NSWindow.ButtonType] = SumiBrowserChromeConfiguration.buttonTypes
    ) {
        self.window = window
        self.buttonTypes = buttonTypes
        nativeTitlebarView = window.titlebarView
        refreshNativeMetricsIfAvailable()
    }

    var hostedControlStripWidth: CGFloat {
        ceil(cachedMetrics?.buttonGroupWidth ?? NativeWindowControlsMetrics.fallbackHostedSize.width)
    }

    func setPreferredHostView(_ hostView: NSView?) {
        preferredHostView = hostView

        if let hostView {
            claimButtons(into: hostView)
        } else {
            restoreButtonsToTitlebar()
        }
    }

    func releaseHostViewIfNeeded(_ hostView: NSView) {
        guard preferredHostView === hostView || buttonsAreHosted(in: hostView) else {
            return
        }

        if preferredHostView === hostView {
            preferredHostView = nil
        }

        restoreButtonsToTitlebar()
    }

    func layoutHostedButtonsIfNeeded(in hostView: NSView) {
        guard preferredHostView === hostView else { return }
        claimButtons(into: hostView)
    }

    func handleWindowGeometryChange() {
        refreshNativeMetricsIfAvailable()

        guard let preferredHostView else { return }
        claimButtons(into: preferredHostView)
    }

    func buttonsAreHosted(in hostView: NSView) -> Bool {
        guard let window else { return false }

        return buttonTypes.contains { type in
            window.standardWindowButton(type)?.superview === hostView
        }
    }

    private func claimButtons(into hostView: NSView) {
        guard let window else { return }

        window.restoreNativeWindowButtonVisibility(buttonTypes: buttonTypes)
        refreshNativeMetricsIfAvailable()

        for type in buttonTypes {
            guard let button = window.standardWindowButton(type) else { continue }

            if button.superview !== hostView {
                button.removeFromSuperview()
                hostView.addSubview(button)
            }
        }

        layoutButtons(in: hostView, window: window)
    }

    private func restoreButtonsToTitlebar() {
        guard let window,
              let nativeTitlebarView = nativeTitlebarView ?? window.titlebarView
        else {
            return
        }

        for type in buttonTypes {
            guard let button = window.standardWindowButton(type) else { continue }

            if button.superview !== nativeTitlebarView {
                button.removeFromSuperview()
                nativeTitlebarView.addSubview(button)
            }

            if let frame = cachedMetrics?.buttonFrames[type] {
                button.frame = frame
            }
        }

        window.prepareNativeWindowControlsForBrowserChrome(buttonTypes: buttonTypes)
        refreshNativeMetricsIfAvailable()
    }

    private func refreshNativeMetricsIfAvailable() {
        guard let window else { return }

        nativeTitlebarView = nativeTitlebarView ?? window.titlebarView

        if let metrics = window.captureNativeWindowControlsMetricsIfButtonsInTitlebar(
            for: buttonTypes
        ) {
            cachedMetrics = metrics
            window.cachedNativeWindowControlsMetrics = metrics
        } else if let cachedMetrics = window.cachedNativeWindowControlsMetrics {
            self.cachedMetrics = cachedMetrics
        }
    }

    private func layoutButtons(in hostView: NSView, window: NSWindow) {
        let metrics = cachedMetrics ?? window.cachedNativeWindowControlsMetrics
        let groupSize = metrics?.buttonGroupSize ?? NativeWindowControlsMetrics.fallbackHostedSize
        let containerHeight = boundsHeight(for: hostView, fallback: groupSize.height)
        let groupOriginY = floor((containerHeight - groupSize.height) / 2)

        for type in buttonTypes {
            guard let button = window.standardWindowButton(type) else { continue }

            let normalizedFrame = metrics?.normalizedButtonFrames[type]
                ?? NSRect(origin: .zero, size: fallbackButtonSize(for: button))
            let frame = normalizedFrame.offsetBy(dx: 0, dy: groupOriginY)

            button.isBordered = false
            button.translatesAutoresizingMaskIntoConstraints = true
            button.frame = frame
        }
    }

    private func boundsHeight(for hostView: NSView, fallback: CGFloat) -> CGFloat {
        if hostView.bounds.height > 0 {
            return hostView.bounds.height
        }

        return max(fallback, NativeWindowControlsMetrics.fallbackHostedSize.height)
    }

    private func fallbackButtonSize(for button: NSButton) -> NSSize {
        button.bounds.size == .zero
            ? NSSize(width: 14, height: 14)
            : button.bounds.size
    }
}

private enum NativeWindowControlsAssociatedKeys {
    static var titlebarView: UInt8 = 0
    static var cachedMetrics: UInt8 = 0
    static var hostController: UInt8 = 0
}

@MainActor
extension NSWindow {
    var titlebarView: NSView? {
        if let cached = objc_getAssociatedObject(
            self,
            &NativeWindowControlsAssociatedKeys.titlebarView
        ) as? NSView {
            return cached
        }

        guard let resolved = standardWindowButton(.closeButton)?.superview else {
            return nil
        }

        objc_setAssociatedObject(
            self,
            &NativeWindowControlsAssociatedKeys.titlebarView,
            resolved,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )

        return resolved
    }

    var cachedNativeWindowControlsMetrics: NativeWindowControlsMetrics? {
        get {
            objc_getAssociatedObject(
                self,
                &NativeWindowControlsAssociatedKeys.cachedMetrics
            ) as? NativeWindowControlsMetrics
        }
        set {
            objc_setAssociatedObject(
                self,
                &NativeWindowControlsAssociatedKeys.cachedMetrics,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    func browserChromeNativeWindowControlsHostController(
        buttonTypes: [NSWindow.ButtonType] = SumiBrowserChromeConfiguration.buttonTypes
    ) -> NativeWindowControlsHostController {
        if let cached = objc_getAssociatedObject(
            self,
            &NativeWindowControlsAssociatedKeys.hostController
        ) as? NativeWindowControlsHostController {
            return cached
        }

        let controller = NativeWindowControlsHostController(
            window: self,
            buttonTypes: buttonTypes
        )
        objc_setAssociatedObject(
            self,
            &NativeWindowControlsAssociatedKeys.hostController,
            controller,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return controller
    }

    func prepareNativeWindowControlsForBrowserChrome(
        buttonTypes: [NSWindow.ButtonType] = SumiBrowserChromeConfiguration.buttonTypes
    ) {
        guard let titlebarView else { return }

        restoreNativeWindowButtonVisibility(buttonTypes: buttonTypes)
        titlebarView.needsLayout = true
        titlebarView.layoutSubtreeIfNeeded()
    }

    func restoreNativeWindowButtonVisibility(
        buttonTypes: [NSWindow.ButtonType] = SumiBrowserChromeConfiguration.buttonTypes
    ) {
        for type in buttonTypes {
            guard let button = standardWindowButton(type) else { continue }
            button.isHidden = false
            button.alphaValue = 1
            button.isEnabled = true
            button.setAccessibilityIdentifier(
                BrowserWindowControlsAccessibilityIdentifiers.identifier(for: type)
            )
        }
    }

    func captureNativeWindowControlsMetricsIfButtonsInTitlebar(
        for buttonTypes: [NSWindow.ButtonType] = SumiBrowserChromeConfiguration.buttonTypes
    ) -> NativeWindowControlsMetrics? {
        guard let titlebarView else { return nil }

        for type in buttonTypes {
            guard let button = standardWindowButton(type),
                  button.superview === titlebarView
            else {
                return nil
            }
        }

        restoreNativeWindowButtonVisibility(buttonTypes: buttonTypes)
        titlebarView.needsLayout = true
        titlebarView.layoutSubtreeIfNeeded()

        var buttonFrames: [NSWindow.ButtonType: NSRect] = [:]
        var buttonGroupRect: NSRect = .null

        for type in buttonTypes {
            guard let button = standardWindowButton(type) else { return nil }
            let frame = button.frame
            buttonFrames[type] = frame
            buttonGroupRect = buttonGroupRect.isNull ? frame : buttonGroupRect.union(frame)
        }

        let metrics = NativeWindowControlsMetrics(
            buttonFrames: buttonFrames,
            buttonGroupRect: buttonGroupRect
        )
        cachedNativeWindowControlsMetrics = metrics
        return metrics
    }

    var isReadyForBrowserChromeNativeWindowControls: Bool {
        guard toolbar?.identifier == SumiBrowserChromeConfiguration.toolbarIdentifier,
              titlebarView != nil
        else {
            return false
        }

        return SumiBrowserChromeConfiguration.buttonTypes.allSatisfy { type in
            standardWindowButton(type) != nil
        }
    }
}

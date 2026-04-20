import AppKit
import ObjectiveC.runtime

@MainActor
final class NativeWindowButtonHostController {
    let buttonTypes: [NSWindow.ButtonType]

    private weak var hostView: NSView?
    private(set) weak var window: NSWindow?
    private(set) var nativeButtonFrames: [NSWindow.ButtonType: NSRect] = [:]
    private(set) var nativeTitlebarHeight: CGFloat?

    init(
        hostView: NSView,
        buttonTypes: [NSWindow.ButtonType] = SumiBrowserChromeConfiguration.buttonTypes
    ) {
        self.hostView = hostView
        self.buttonTypes = buttonTypes
    }

    func setWindow(_ window: NSWindow?) {
        guard self.window !== window else {
            refreshNativeMetrics()
            return
        }

        restoreButtonsToTitlebar(of: self.window, onlyIfHostedByHost: true)
        self.window = window
        nativeButtonFrames = [:]
        nativeTitlebarHeight = nil
        refreshNativeMetrics()
    }

    func refreshNativeMetrics() {
        guard let window else { return }

        if let titlebarView = window.titlebarView,
           titlebarView.bounds.height > 0 {
            nativeTitlebarHeight = titlebarView.bounds.height
        }

        window.cacheNativeWindowButtonFramesIfNeeded(for: buttonTypes)

        for type in buttonTypes where nativeButtonFrames[type] == nil {
            if let cachedFrame = window.cachedNativeWindowButtonFrame(for: type) {
                nativeButtonFrames[type] = cachedFrame
                continue
            }

            guard let button = window.standardWindowButton(type) else { continue }
            nativeButtonFrames[type] = button.frame
        }
    }

    func claimButtons() {
        guard let hostView, let window else { return }

        refreshNativeMetrics()
        window.restoreNativeWindowButtonVisibility()

        for type in buttonTypes {
            guard let button = window.standardWindowButton(type) else { continue }
            if button.superview !== hostView {
                button.removeFromSuperview()
                hostView.addSubview(button)
            }
        }
    }

    func restoreButtonsToTitlebar(onlyIfHostedByHost: Bool) {
        restoreButtonsToTitlebar(of: window, onlyIfHostedByHost: onlyIfHostedByHost)
    }

    func prepareForRemoval() {
        restoreButtonsToTitlebar(onlyIfHostedByHost: true)
        window = nil
        nativeButtonFrames = [:]
        nativeTitlebarHeight = nil
    }

    private func restoreButtonsToTitlebar(
        of window: NSWindow?,
        onlyIfHostedByHost: Bool
    ) {
        guard let hostView,
              let window,
              let titlebarView = window.titlebarView
        else {
            return
        }

        for type in buttonTypes {
            guard let button = window.standardWindowButton(type) else { continue }
            if onlyIfHostedByHost && button.superview !== hostView {
                continue
            }

            if button.superview !== titlebarView {
                button.removeFromSuperview()
                titlebarView.addSubview(button)
            }

            if let frame = nativeButtonFrames[type] {
                button.frame = frame
            }
        }

        window.restoreNativeWindowButtonVisibility()
        titlebarView.needsLayout = true
        titlebarView.layoutSubtreeIfNeeded()
    }
}

private enum NativeWindowControlsAssociatedKeys {
    static var titlebarView: UInt8 = 0
    static var nativeWindowButtonFrames: UInt8 = 1
}

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

    func cacheNativeWindowButtonFramesIfNeeded(for buttonTypes: [NSWindow.ButtonType]) {
        var cachedFrames = nativeWindowButtonFrames

        for type in buttonTypes where cachedFrames[type.rawValue] == nil {
            guard let button = standardWindowButton(type) else { continue }
            cachedFrames[type.rawValue] = NSValue(rect: button.frame)
        }

        nativeWindowButtonFrames = cachedFrames
    }

    func cachedNativeWindowButtonFrame(for type: NSWindow.ButtonType) -> NSRect? {
        nativeWindowButtonFrames[type.rawValue]?.rectValue
    }

    func restoreNativeWindowButtonVisibility() {
        for type in SumiBrowserChromeConfiguration.buttonTypes {
            guard let button = standardWindowButton(type) else { continue }
            button.isHidden = false
            button.alphaValue = 1
            button.isEnabled = true
        }
    }

    var isReadyForBrowserChromeNativeWindowControls: Bool {
        guard toolbar?.identifier == SumiBrowserChromeConfiguration.toolbarIdentifier,
              titlebarView != nil
        else {
            return false
        }

        return SumiBrowserChromeConfiguration.buttonTypes.allSatisfy { type in
            cachedNativeWindowButtonFrame(for: type) != nil || standardWindowButton(type) != nil
        }
    }

    private var nativeWindowButtonFrames: [UInt: NSValue] {
        get {
            objc_getAssociatedObject(
                self,
                &NativeWindowControlsAssociatedKeys.nativeWindowButtonFrames
            ) as? [UInt: NSValue] ?? [:]
        }
        set {
            objc_setAssociatedObject(
                self,
                &NativeWindowControlsAssociatedKeys.nativeWindowButtonFrames,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

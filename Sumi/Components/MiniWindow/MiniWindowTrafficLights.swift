import AppKit
import SwiftUI

private enum MiniWindowTrafficLightsMetrics {
    static let fallbackSize = NSSize(width: 60, height: 18)
    static let buttonSpacing: CGFloat = 8
}

@MainActor
private final class MiniWindowTrafficLightsHostController {
    let buttonTypes: [NSWindow.ButtonType]

    private weak var hostView: NSView?
    private weak var window: NSWindow?
    private weak var nativeTitlebarView: NSView?

    private(set) var nativeButtonFrames: [NSWindow.ButtonType: NSRect] = [:]

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
        self.nativeTitlebarView = window?.titlebarView
        self.nativeButtonFrames = [:]
        refreshNativeMetrics()
    }

    func refreshNativeMetrics() {
        guard let window else { return }

        let resolvedTitlebarView = nativeTitlebarView ?? window.titlebarView
        nativeTitlebarView = resolvedTitlebarView

        for type in buttonTypes {
            guard let button = window.standardWindowButton(type) else { continue }

            if button.superview === resolvedTitlebarView || nativeButtonFrames[type] == nil {
                nativeButtonFrames[type] = button.frame
            }
        }
    }

    func claimButtons() {
        guard let hostView, let window else { return }

        window.restoreNativeWindowButtonVisibility(buttonTypes: buttonTypes)
        refreshNativeMetrics()

        for type in buttonTypes {
            guard let button = window.standardWindowButton(type) else { continue }
            if button.superview !== hostView {
                button.removeFromSuperview()
                hostView.addSubview(button)
            }
        }
    }

    func prepareForRemoval() {
        restoreButtonsToTitlebar(of: window, onlyIfHostedByHost: true)
        window = nil
        nativeTitlebarView = nil
        nativeButtonFrames = [:]
    }

    private func restoreButtonsToTitlebar(
        of window: NSWindow?,
        onlyIfHostedByHost: Bool
    ) {
        guard let hostView,
              let window,
              let nativeTitlebarView = nativeTitlebarView ?? window.titlebarView
        else {
            return
        }

        for type in buttonTypes {
            guard let button = window.standardWindowButton(type) else { continue }
            if onlyIfHostedByHost && button.superview !== hostView {
                continue
            }

            if button.superview !== nativeTitlebarView {
                button.removeFromSuperview()
                nativeTitlebarView.addSubview(button)
            }

            if let frame = nativeButtonFrames[type] {
                button.frame = frame
            }
        }

        window.restoreNativeWindowButtonVisibility(buttonTypes: buttonTypes)
        nativeTitlebarView.needsLayout = true
        nativeTitlebarView.layoutSubtreeIfNeeded()
    }
}

struct MiniWindowTrafficLights: NSViewRepresentable {
    var window: NSWindow?

    func makeNSView(context: Context) -> MiniWindowTrafficLightsContainerView {
        let view = MiniWindowTrafficLightsContainerView()
        view.windowReference = window
        return view
    }

    func updateNSView(_ nsView: MiniWindowTrafficLightsContainerView, context: Context) {
        nsView.windowReference = window
    }

    static func dismantleNSView(_ nsView: MiniWindowTrafficLightsContainerView, coordinator: ()) {
        nsView.prepareForRemoval()
    }
}

final class MiniWindowTrafficLightsContainerView: NSView {
    weak var windowReference: NSWindow? {
        didSet {
            guard windowReference !== oldValue else {
                buttonHostController.refreshNativeMetrics()
                needsLayout = true
                layoutSubtreeIfNeeded()
                invalidateIntrinsicContentSize()
                return
            }

            buttonHostController.setWindow(windowReference)
            needsLayout = true
            layoutSubtreeIfNeeded()
            invalidateIntrinsicContentSize()
        }
    }

    private lazy var buttonHostController = MiniWindowTrafficLightsHostController(hostView: self)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        let buttonFrames = buttonHostController.buttonTypes.compactMap { buttonHostController.nativeButtonFrames[$0] }
        guard buttonFrames.isEmpty == false else {
            return MiniWindowTrafficLightsMetrics.fallbackSize
        }

        let totalWidth = buttonFrames.reduce(CGFloat.zero) { partialResult, frame in
            partialResult + frame.width
        }
        let spacingWidth = MiniWindowTrafficLightsMetrics.buttonSpacing * CGFloat(max(buttonFrames.count - 1, 0))
        let maxHeight = buttonFrames.reduce(CGFloat.zero) { partialResult, frame in
            max(partialResult, frame.height)
        }

        return NSSize(
            width: max(totalWidth + spacingWidth, MiniWindowTrafficLightsMetrics.fallbackSize.width),
            height: max(maxHeight, MiniWindowTrafficLightsMetrics.fallbackSize.height)
        )
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if windowReference == nil {
            windowReference = window
        }
    }

    override func layout() {
        super.layout()

        guard let windowReference else { return }

        buttonHostController.claimButtons()
        layoutButtons(for: windowReference)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    func prepareForRemoval() {
        buttonHostController.prepareForRemoval()
    }

    private func layoutButtons(for window: NSWindow) {
        var xOffset: CGFloat = 0
        let containerHeight = bounds.height > 0 ? bounds.height : intrinsicContentSize.height

        for type in buttonHostController.buttonTypes {
            guard let button = window.standardWindowButton(type) else { continue }

            let size = buttonHostController.nativeButtonFrames[type]?.size
                ?? (button.bounds.size == .zero ? NSSize(width: 14, height: 14) : button.bounds.size)
            let yOffset = floor((containerHeight - size.height) / 2)

            button.isBordered = false
            button.translatesAutoresizingMaskIntoConstraints = true
            button.frame = NSRect(origin: NSPoint(x: xOffset, y: yOffset), size: size)
            xOffset += size.width + MiniWindowTrafficLightsMetrics.buttonSpacing
        }
    }
}

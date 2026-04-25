import AppKit
import SwiftUI

private enum MiniWindowTrafficLightsMetrics {
    static let fallbackSize = NSSize(width: 60, height: 18)
    static let buttonSpacing: CGFloat = 8
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
    private var appearanceObservers: [NSObjectProtocol] = []
    private var isDeferredAppearanceRelayoutScheduled = false

    weak var windowReference: NSWindow? {
        didSet {
            if windowReference !== oldValue {
                buttonHostController?.releaseHostViewIfNeeded(self)
                buttonHostController = nil
                ensureButtonHostController()
                installAppearanceObservers()
            } else {
                ensureButtonHostController()
            }

            needsLayout = true
            layoutSubtreeIfNeeded()
            invalidateIntrinsicContentSize()
        }
    }

    private var buttonHostController: NativeWindowControlsHostController?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        let hostedSize = buttonHostController?.hostedControlStripSize
            ?? MiniWindowTrafficLightsMetrics.fallbackSize
        return NSSize(
            width: max(hostedSize.width, MiniWindowTrafficLightsMetrics.fallbackSize.width),
            height: max(hostedSize.height, MiniWindowTrafficLightsMetrics.fallbackSize.height)
        )
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if windowReference == nil {
            windowReference = window
        } else {
            installAppearanceObservers()
        }
    }

    override func layout() {
        super.layout()

        ensureButtonHostController()
        buttonHostController?.layoutHostedButtonsIfNeeded(in: self)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    func prepareForRemoval() {
        removeAppearanceObservers()
        buttonHostController?.releaseHostViewIfNeeded(self)
        buttonHostController = nil
    }

    private func ensureButtonHostController() {
        guard buttonHostController == nil,
              let windowReference
        else {
            return
        }

        let controller = NativeWindowControlsHostController(
            window: windowReference,
            layoutMode: .compact(spacing: MiniWindowTrafficLightsMetrics.buttonSpacing)
        )
        buttonHostController = controller
        controller.setPreferredHostView(self)
    }

    private func installAppearanceObservers() {
        removeAppearanceObservers()
        guard let windowReference else { return }

        appearanceObservers = [
            NotificationCenter.default.addObserver(
                forName: .sumiWindowDidChangeEffectiveAppearance,
                object: windowReference,
                queue: nil
            ) { [weak self] _ in
                self?.handleEffectiveAppearanceChange()
            },
            NotificationCenter.default.addObserver(
                forName: .sumiApplicationDidChangeEffectiveAppearance,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.handleEffectiveAppearanceChange()
            },
        ]
    }

    private func removeAppearanceObservers() {
        for observer in appearanceObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        appearanceObservers.removeAll()
    }

    private func handleEffectiveAppearanceChange() {
        buttonHostController?.handleEffectiveAppearanceChange()
        buttonHostController?.enforceHostedLayoutIfNeeded()
        needsLayout = true
        layoutSubtreeIfNeeded()
        invalidateIntrinsicContentSize()
        scheduleDeferredAppearanceRelayout()
    }

    private func scheduleDeferredAppearanceRelayout() {
        guard isDeferredAppearanceRelayoutScheduled == false else { return }

        isDeferredAppearanceRelayoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.isDeferredAppearanceRelayoutScheduled = false
            self.buttonHostController?.handleEffectiveAppearanceChange()
            self.buttonHostController?.enforceHostedLayoutIfNeeded()
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
            self.invalidateIntrinsicContentSize()
        }
    }
}

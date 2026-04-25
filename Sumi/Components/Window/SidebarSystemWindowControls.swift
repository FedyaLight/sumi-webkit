import AppKit
import SwiftUI

enum SidebarChromeMetrics {
    static let horizontalPadding: CGFloat = 8
    static let windowControlsLeadingInset: CGFloat = 8
    static let controlStripHeight: CGFloat = 38
    static let controlSpacing: CGFloat = 8
}

enum SidebarWindowControlsPlacement: Equatable {
    case sidebar
    case titlebar

    static func resolve(
        presentationMode _: SidebarPresentationMode,
        isFullScreen: Bool
    ) -> Self {
        isFullScreen ? .titlebar : .sidebar
    }
}

struct SidebarSystemWindowControlsHost: NSViewRepresentable {
    var presentationMode: SidebarPresentationMode
    var window: NSWindow?

    func makeNSView(context: Context) -> SidebarSystemWindowControlsContainerView {
        let view = SidebarSystemWindowControlsContainerView()
        view.presentationMode = presentationMode
        view.setPreferredWindowReference(window)
        return view
    }

    func updateNSView(_ nsView: SidebarSystemWindowControlsContainerView, context: Context) {
        nsView.presentationMode = presentationMode
        nsView.setPreferredWindowReference(window)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: SidebarSystemWindowControlsContainerView,
        context: Context
    ) -> CGSize? {
        nsView.fittingSize
    }

    static func dismantleNSView(_ nsView: SidebarSystemWindowControlsContainerView, coordinator: ()) {
        nsView.prepareForRemoval()
    }
}

final class SidebarSystemWindowControlsContainerView: NSView {
    private var windowObservers: [NSObjectProtocol] = []
    private weak var preferredWindowReference: NSWindow?
    private weak var windowReference: NSWindow?
    private var isFullscreenState = false
    private var isDeferredAppearanceRelayoutScheduled = false

    var presentationMode: SidebarPresentationMode = .docked {
        didSet {
            updatePlacementIfNeeded()
        }
    }

    private(set) var currentPlacement: SidebarWindowControlsPlacement = .titlebar

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        guard desiredPlacement == .sidebar else {
            return .zero
        }

        let width = nativeWindowControlsHostController?.hostedControlStripWidth
            ?? ceil(NativeWindowControlsMetrics.fallbackHostedSize.width)
        return NSSize(width: width, height: SidebarChromeMetrics.controlStripHeight)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncWindowReference(resolvedWindowReference)
    }

    override func layout() {
        super.layout()

        guard currentPlacement == .sidebar else { return }
        nativeWindowControlsHostController?.layoutHostedButtonsIfNeeded(in: self)
    }

    func syncWindowReference(_ window: NSWindow?) {
        guard windowReference !== window else {
            updatePlacementIfNeeded()
            return
        }

        releaseHostedButtonsFromCurrentWindow()
        removeWindowObservers()
        windowReference = window
        isFullscreenState = window?.styleMask.contains(.fullScreen) ?? false
        installWindowObservers()
        updatePlacementIfNeeded(force: true)
    }

    func setPreferredWindowReference(_ window: NSWindow?) {
        preferredWindowReference = window
        syncWindowReference(resolvedWindowReference)
    }

    func prepareForRemoval() {
        releaseHostedButtonsFromCurrentWindow()
        removeWindowObservers()
        windowReference = nil
        isFullscreenState = false
        currentPlacement = .titlebar
        invalidateIntrinsicContentSize()
    }

    private func installWindowObservers() {
        guard let windowReference else { return }

        let notifications: [Notification.Name] = [
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didResizeNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didChangeScreenNotification,
        ]

        windowObservers = notifications.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: windowReference,
                queue: .main
            ) { [weak self] _ in
                self?.handleWindowNotification(name)
            }
        }

        windowObservers.append(
            NotificationCenter.default.addObserver(
                forName: .sumiWindowDidChangeEffectiveAppearance,
                object: windowReference,
                queue: nil
            ) { [weak self] _ in
                self?.handleEffectiveAppearanceChange()
            }
        )
        windowObservers.append(
            NotificationCenter.default.addObserver(
                forName: .sumiApplicationDidChangeEffectiveAppearance,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.handleEffectiveAppearanceChange()
            }
        )
    }

    private func removeWindowObservers() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
    }

    private var desiredPlacement: SidebarWindowControlsPlacement {
        SidebarWindowControlsPlacement.resolve(
            presentationMode: presentationMode,
            isFullScreen: isFullscreenState
        )
    }

    private var resolvedWindowReference: NSWindow? {
        preferredReadyWindowReference ?? attachedReadyWindowReference
    }

    private var preferredReadyWindowReference: NSWindow? {
        guard let preferredWindowReference,
              preferredWindowReference.isReadyForBrowserChromeNativeWindowControls
        else {
            return nil
        }

        return preferredWindowReference
    }

    private var attachedReadyWindowReference: NSWindow? {
        guard preferredReadyWindowReference == nil,
              let window,
              window.isReadyForBrowserChromeNativeWindowControls
        else {
            return nil
        }

        return window
    }

    private var nativeWindowControlsHostController: NativeWindowControlsHostController? {
        guard let windowReference else { return nil }
        return windowReference.browserChromeNativeWindowControlsHostController()
    }

    private func releaseHostedButtonsFromCurrentWindow() {
        nativeWindowControlsHostController?.releaseHostViewIfNeeded(self)
    }

    private func updatePlacementIfNeeded(force: Bool = false) {
        let placement = desiredPlacement

        if let nativeWindowControlsHostController {
            switch placement {
            case .sidebar:
                nativeWindowControlsHostController.setPreferredHostView(self)
                nativeWindowControlsHostController.layoutHostedButtonsIfNeeded(in: self)
            case .titlebar:
                nativeWindowControlsHostController.releaseHostViewIfNeeded(self)
            }
        }

        if force == false && placement == currentPlacement {
            invalidateIntrinsicContentSize()
            needsLayout = true
            return
        }

        currentPlacement = placement
        invalidateIntrinsicContentSize()
        needsLayout = true
        superview?.needsLayout = true
    }

    private func handleWindowNotification(_ name: Notification.Name) {
        switch name {
        case NSWindow.didEnterFullScreenNotification:
            isFullscreenState = true
        case NSWindow.didExitFullScreenNotification:
            isFullscreenState = false
        default:
            isFullscreenState = windowReference?.styleMask.contains(.fullScreen) ?? false
        }

        nativeWindowControlsHostController?.handleWindowGeometryChange()
        updatePlacementIfNeeded(force: true)
    }

    private func handleEffectiveAppearanceChange() {
        nativeWindowControlsHostController?.handleEffectiveAppearanceChange()
        nativeWindowControlsHostController?.enforceHostedLayoutIfNeeded()
        updatePlacementIfNeeded(force: true)
        scheduleDeferredAppearanceRelayout()
    }

    private func scheduleDeferredAppearanceRelayout() {
        guard isDeferredAppearanceRelayoutScheduled == false else { return }

        isDeferredAppearanceRelayoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.isDeferredAppearanceRelayoutScheduled = false
            self.nativeWindowControlsHostController?.handleEffectiveAppearanceChange()
            self.nativeWindowControlsHostController?.enforceHostedLayoutIfNeeded()
            self.updatePlacementIfNeeded(force: true)
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
        }
    }
}

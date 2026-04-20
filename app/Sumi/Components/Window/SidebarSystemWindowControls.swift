import AppKit
import SwiftUI

enum SidebarChromeMetrics {
    static let collapsedTopInset: CGFloat = 4
    static let horizontalPadding: CGFloat = 8
    static let controlStripHeight: CGFloat = 38
    static let controlSpacing: CGFloat = 8

    static func topInset(for presentationMode: SidebarPresentationMode) -> CGFloat {
        switch presentationMode {
        case .docked:
            return 0
        case .collapsedHidden, .collapsedVisible:
            return collapsedTopInset
        }
    }
}

enum SidebarWindowControlsPlacement: Equatable {
    case sidebar
    case titlebarReservedSpace
    case titlebar

    static func resolve(
        presentationMode: SidebarPresentationMode,
        isFullScreen: Bool
    ) -> Self {
        if isFullScreen || presentationMode == .collapsedHidden {
            return .titlebar
        }
        if presentationMode == .docked {
            return .titlebarReservedSpace
        }
        return .sidebar
    }

    var showsReservedWidth: Bool {
        switch self {
        case .sidebar, .titlebarReservedSpace:
            return true
        case .titlebar:
            return false
        }
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
    private lazy var buttonHostController = NativeWindowButtonHostController(hostView: self)

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
        guard desiredPlacement.showsReservedWidth else {
            return .zero
        }

        return sidebarGeometry.hostSize
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncWindowReference(resolvedWindowReference)
    }

    override func layout() {
        super.layout()

        guard currentPlacement == .sidebar,
              let windowReference
        else {
            return
        }

        layoutButtonsInSidebar(for: windowReference)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    func syncWindowReference(_ window: NSWindow?) {
        guard windowReference !== window else {
            buttonHostController.refreshNativeMetrics()
            updatePlacementIfNeeded()
            return
        }

        removeWindowObservers()
        windowReference = window
        buttonHostController.setWindow(window)
        installWindowObservers()
        updatePlacementIfNeeded(force: true)
    }

    func setPreferredWindowReference(_ window: NSWindow?) {
        preferredWindowReference = window
        syncWindowReference(resolvedWindowReference)
    }

    func prepareForRemoval() {
        buttonHostController.prepareForRemoval()
        removeWindowObservers()
        windowReference = nil
        currentPlacement = .titlebar
        invalidateIntrinsicContentSize()
    }

    private func installWindowObservers() {
        guard let windowReference else { return }

        let notifications: [Notification.Name] = [
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didResizeNotification,
        ]

        windowObservers = notifications.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: windowReference,
                queue: .main
            ) { [weak self] _ in
                self?.updatePlacementIfNeeded(force: true)
            }
        }
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
            isFullScreen: windowReference?.styleMask.contains(.fullScreen) ?? false
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

    private func updatePlacementIfNeeded(force: Bool = false) {
        guard windowReference != nil else {
            currentPlacement = desiredPlacement
            invalidateIntrinsicContentSize()
            return
        }

        buttonHostController.refreshNativeMetrics()

        let placement = desiredPlacement

        if force == false && placement == currentPlacement {
            if placement == .sidebar {
                needsLayout = true
                layoutSubtreeIfNeeded()
            }
            return
        }

        switch placement {
        case .sidebar:
            moveButtonsToSidebar()
        case .titlebarReservedSpace, .titlebar:
            buttonHostController.restoreButtonsToTitlebar(onlyIfHostedByHost: false)
        }

        currentPlacement = placement
        invalidateIntrinsicContentSize()
        needsLayout = true
        superview?.needsLayout = true
    }

    private func moveButtonsToSidebar() {
        buttonHostController.claimButtons()

        guard let windowReference else { return }
        layoutButtonsInSidebar(for: windowReference)
    }

    private func layoutButtonsInSidebar(for window: NSWindow) {
        let geometry = sidebarGeometry
        let verticalOffset = floor(max(bounds.height - geometry.hostSize.height, 0) / 2)

        for type in buttonHostController.buttonTypes {
            guard let button = window.standardWindowButton(type),
                  let frame = geometry.buttonFrames[type]
            else {
                continue
            }

            button.translatesAutoresizingMaskIntoConstraints = true
            button.frame = frame.offsetBy(dx: 0, dy: verticalOffset)
        }
    }

    private var sidebarGeometry: SidebarWindowControlsGeometry {
        SidebarWindowControlsGeometry(
            buttonTypes: buttonHostController.buttonTypes,
            nativeButtonFrames: buttonHostController.nativeButtonFrames,
            nativeTitlebarHeight: buttonHostController.nativeTitlebarHeight
        )
    }
}

private struct SidebarWindowControlsGeometry {
    static let initialTitlebarHeight = SidebarChromeMetrics.controlStripHeight
    static let initialButtonFrames: [NSWindow.ButtonType: NSRect] = [
        .closeButton: NSRect(x: 12, y: 11, width: 14, height: 16),
        .miniaturizeButton: NSRect(x: 32, y: 11, width: 14, height: 16),
        .zoomButton: NSRect(x: 52, y: 11, width: 14, height: 16),
    ]

    let hostSize: NSSize
    let buttonFrames: [NSWindow.ButtonType: NSRect]

    init(
        buttonTypes: [NSWindow.ButtonType],
        nativeButtonFrames: [NSWindow.ButtonType: NSRect],
        nativeTitlebarHeight: CGFloat?
    ) {
        let titlebarHeight = max(
            nativeTitlebarHeight ?? Self.initialTitlebarHeight,
            Self.initialTitlebarHeight
        )

        var resolvedFrames: [NSWindow.ButtonType: NSRect] = [:]
        var maxX: CGFloat = 0

        for type in buttonTypes {
            let nativeFrame = nativeButtonFrames[type] ?? Self.initialFrame(for: type)
            let topInset = max(titlebarHeight - nativeFrame.maxY, 0)
            let frame = NSRect(
                x: nativeFrame.minX,
                y: max(
                    SidebarChromeMetrics.controlStripHeight - topInset - nativeFrame.height,
                    0
                ),
                width: nativeFrame.width,
                height: nativeFrame.height
            )
            resolvedFrames[type] = frame
            maxX = max(maxX, frame.maxX)
        }

        buttonFrames = resolvedFrames
        hostSize = NSSize(width: maxX, height: SidebarChromeMetrics.controlStripHeight)
    }

    private static func initialFrame(for type: NSWindow.ButtonType) -> NSRect {
        initialButtonFrames[type] ?? NSRect(x: 0, y: 11, width: 14, height: 16)
    }
}

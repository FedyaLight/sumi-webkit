import AppKit
import SwiftUI

enum BrowserWindowControlsAccessibilityIdentifiers {
    static let closeButton = "browser-window-close-button"
    static let minimizeButton = "browser-window-minimize-button"
    static let zoomButton = "browser-window-zoom-button"
    static let miniBrowserWindow = "mini-browser-window"
    static let zoomMenu = "browser-window-zoom-menu"
    static let leftHalfMenuItem = "browser-window-left-half-menu-item"
    static let rightHalfMenuItem = "browser-window-right-half-menu-item"
    static let topHalfMenuItem = "browser-window-top-half-menu-item"
    static let bottomHalfMenuItem = "browser-window-bottom-half-menu-item"
    static let fillMenuItem = "browser-window-fill-menu-item"
    static let centerMenuItem = "browser-window-center-menu-item"
    static let leftThirdMenuItem = "browser-window-left-third-menu-item"
    static let rightThirdMenuItem = "browser-window-right-third-menu-item"
    static let fullScreenMenuItem = "browser-window-full-screen-menu-item"

    static let allButtonIdentifiers: Set<String> = [
        closeButton,
        minimizeButton,
        zoomButton,
    ]
}

enum BrowserWindowTrafficLightKind: CaseIterable, Identifiable, Hashable {
    case close
    case minimize
    case zoom

    var id: Self { self }

    var buttonType: NSWindow.ButtonType {
        switch self {
        case .close:
            return .closeButton
        case .minimize:
            return .miniaturizeButton
        case .zoom:
            return .zoomButton
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .close:
            return BrowserWindowControlsAccessibilityIdentifiers.closeButton
        case .minimize:
            return BrowserWindowControlsAccessibilityIdentifiers.minimizeButton
        case .zoom:
            return BrowserWindowControlsAccessibilityIdentifiers.zoomButton
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .close:
            return "Close window"
        case .minimize:
            return "Minimize window"
        case .zoom:
            return "Full Screen"
        }
    }

    var helpText: String {
        switch self {
        case .close, .minimize:
            return accessibilityLabel
        case .zoom:
            return "Enter Full Screen. Option-click to zoom."
        }
    }
}

enum BrowserWindowTrafficLightMetrics {
    static var buttonDiameter: CGFloat {
        if #available(macOS 26.0, *) {
            return 14
        } else {
            return 12
        }
    }

    static let buttonSpacing: CGFloat = 9
    static let clusterHeight: CGFloat = 30
    static let clusterTrailingInset: CGFloat = 8

    static var sidebarReservedWidth: CGFloat {
        clusterWidth + clusterTrailingInset
    }

    static var clusterWidth: CGFloat {
        buttonDiameter * CGFloat(BrowserWindowTrafficLightKind.allCases.count)
            + buttonSpacing * CGFloat(BrowserWindowTrafficLightKind.allCases.count - 1)
    }
}

enum BrowserWindowTrafficLightAvailability {
    static func isEnabled(
        kind: BrowserWindowTrafficLightKind,
        window: NSWindow?
    ) -> Bool {
        guard let window,
              window.attachedSheet == nil
        else {
            return false
        }

        return isEnabled(kind: kind, styleMask: window.styleMask, hasAttachedSheet: false)
    }

    static func isEnabled(
        kind: BrowserWindowTrafficLightKind,
        styleMask: NSWindow.StyleMask,
        hasAttachedSheet: Bool
    ) -> Bool {
        guard hasAttachedSheet == false else {
            return false
        }

        switch kind {
        case .close:
            return styleMask.contains(.closable)
        case .minimize:
            return styleMask.contains(.miniaturizable)
                && styleMask.contains(.fullScreen) == false
        case .zoom:
            return styleMask.contains(.resizable)
        }
    }
}

struct BrowserWindowTrafficLights: View {
    let window: NSWindow?
    var isVisible: Bool = true

    @StateObject private var windowObserver = BrowserWindowTrafficLightWindowObserver()
    @StateObject private var zoomMenuPresenter = BrowserWindowZoomPopoverPresenter()
    @State private var isClusterHovered = false
    @State private var hoveredKinds: Set<BrowserWindowTrafficLightKind> = []

    var body: some View {
        let _ = windowObserver.revision
        let isFullScreen = window?.styleMask.contains(.fullScreen) ?? false
        let shouldShow = isVisible && isFullScreen == false
        let showsHoverGlyphs = isClusterHovered || hoveredKinds.isEmpty == false

        HStack(spacing: BrowserWindowTrafficLightMetrics.buttonSpacing) {
            ForEach(BrowserWindowTrafficLightKind.allCases) { kind in
                BrowserWindowTrafficLightButton(
                    kind: kind,
                    isClusterHovered: showsHoverGlyphs,
                    isWindowActive: windowObserver.isWindowActive,
                    isEnabled: BrowserWindowTrafficLightAvailability.isEnabled(
                        kind: kind,
                        window: window
                    ),
                    action: {
                        guard let window else { return }
                        BrowserWindowTrafficLightActionRouter.perform(kind, window: window, sender: nil)
                        windowObserver.refresh()
                    },
                    hoverChanged: { hovering, anchorView in
                        handleHover(kind: kind, hovering: hovering, anchorView: anchorView)
                    }
                )
            }
        }
        .frame(
            width: BrowserWindowTrafficLightMetrics.clusterWidth,
            height: BrowserWindowTrafficLightMetrics.clusterHeight,
            alignment: .center
        )
        .padding(.trailing, BrowserWindowTrafficLightMetrics.clusterTrailingInset)
        .frame(
            width: BrowserWindowTrafficLightMetrics.sidebarReservedWidth,
            height: BrowserWindowTrafficLightMetrics.clusterHeight,
            alignment: .leading
        )
        .opacity(shouldShow ? 1 : 0)
        .allowsHitTesting(shouldShow)
        .accessibilityHidden(!shouldShow)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isClusterHovered = hovering
            }
            if hovering == false {
                hoveredKinds.removeAll()
                zoomMenuPresenter.cancelPendingShow()
            }
        }
        .onAppear {
            windowObserver.attach(to: window)
        }
        .onChange(of: window.map(ObjectIdentifier.init)) { _, _ in
            windowObserver.attach(to: window)
        }
        .onDisappear {
            zoomMenuPresenter.close()
        }
    }

    @MainActor
    private func handleHover(
        kind: BrowserWindowTrafficLightKind,
        hovering: Bool,
        anchorView: NSView
    ) {
        withAnimation(.easeInOut(duration: 0.1)) {
            if hovering {
                hoveredKinds.insert(kind)
            } else {
                hoveredKinds.remove(kind)
            }
        }

        guard kind == .zoom else { return }

        if hovering,
           let window,
           BrowserWindowTrafficLightAvailability.isEnabled(kind: .zoom, window: window) {
            zoomMenuPresenter.scheduleShow(window: window, anchorView: anchorView)
        } else {
            zoomMenuPresenter.cancelPendingShow()
        }
    }
}

@MainActor
final class BrowserWindowTrafficLightWindowObserver: ObservableObject {
    @Published private(set) var revision: UInt = 0

    private weak var observedWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []

    var isWindowActive: Bool {
        guard let observedWindow else { return false }
        return NSApp.isActive && (observedWindow.isKeyWindow || observedWindow.isMainWindow)
    }

    func attach(to window: NSWindow?) {
        guard observedWindow !== window else {
            refresh()
            return
        }

        resetObservers()
        observedWindow = window
        installObservers(for: window)
        refresh()
    }

    func refresh() {
        revision &+= 1
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func installObservers(for window: NSWindow?) {
        let appNotifications: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification,
        ]

        for name in appNotifications {
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: name,
                    object: NSApp,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.refresh()
                    }
                }
            )
        }

        guard let window else { return }

        let windowNotifications: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.willBeginSheetNotification,
            NSWindow.didEndSheetNotification,
        ]

        for name in windowNotifications {
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: name,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.refresh()
                    }
                }
            )
        }
    }

    private func resetObservers() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }
}

@MainActor
enum BrowserWindowTrafficLightActionRouter {
    static func perform(_ kind: BrowserWindowTrafficLightKind, window: NSWindow, sender: Any?) {
        switch kind {
        case .close:
            window.close()
        case .minimize:
            window.performMiniaturize(sender)
        case .zoom:
            let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            if flags.contains(.option) {
                window.performZoom(sender)
            } else {
                window.toggleFullScreen(sender)
            }
        }
    }

    static func performMenuAction(
        _ action: BrowserWindowTrafficLightMenuAction,
        window: NSWindow,
        sender: Any? = nil
    ) {
        switch action {
        case .fullScreen:
            window.toggleFullScreen(sender)
        case .leftHalf,
             .rightHalf,
             .topHalf,
             .bottomHalf,
             .fill,
             .center,
             .leftThird,
             .rightThird:
            guard let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else {
                return
            }

            let targetFrame = BrowserWindowTrafficLightFrameCalculator.frame(
                for: action,
                visibleFrame: visibleFrame,
                currentFrame: window.frame
            )
            window.setFrame(targetFrame, display: true, animate: true)
        }
    }
}

enum BrowserWindowTrafficLightMenuAction: CaseIterable, Identifiable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case fill
    case center
    case leftThird
    case rightThird
    case fullScreen

    var id: Self { self }

    var title: String {
        switch self {
        case .leftHalf:
            return "Left Half"
        case .rightHalf:
            return "Right Half"
        case .topHalf:
            return "Top Half"
        case .bottomHalf:
            return "Bottom Half"
        case .fill:
            return "Fill"
        case .center:
            return "Center"
        case .leftThird:
            return "Left Third"
        case .rightThird:
            return "Right Third"
        case .fullScreen:
            return "Full Screen"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .leftHalf:
            return BrowserWindowControlsAccessibilityIdentifiers.leftHalfMenuItem
        case .rightHalf:
            return BrowserWindowControlsAccessibilityIdentifiers.rightHalfMenuItem
        case .topHalf:
            return BrowserWindowControlsAccessibilityIdentifiers.topHalfMenuItem
        case .bottomHalf:
            return BrowserWindowControlsAccessibilityIdentifiers.bottomHalfMenuItem
        case .fill:
            return BrowserWindowControlsAccessibilityIdentifiers.fillMenuItem
        case .center:
            return BrowserWindowControlsAccessibilityIdentifiers.centerMenuItem
        case .leftThird:
            return BrowserWindowControlsAccessibilityIdentifiers.leftThirdMenuItem
        case .rightThird:
            return BrowserWindowControlsAccessibilityIdentifiers.rightThirdMenuItem
        case .fullScreen:
            return BrowserWindowControlsAccessibilityIdentifiers.fullScreenMenuItem
        }
    }
}

enum BrowserWindowTrafficLightFrameCalculator {
    static func frame(
        for action: BrowserWindowTrafficLightMenuAction,
        visibleFrame: NSRect,
        currentFrame: NSRect
    ) -> NSRect {
        let frame = visibleFrame.standardized

        switch action {
        case .leftHalf:
            return NSRect(
                x: frame.minX,
                y: frame.minY,
                width: frame.width / 2,
                height: frame.height
            )
        case .rightHalf:
            return NSRect(
                x: frame.midX,
                y: frame.minY,
                width: frame.width / 2,
                height: frame.height
            )
        case .topHalf:
            return NSRect(
                x: frame.minX,
                y: frame.midY,
                width: frame.width,
                height: frame.height / 2
            )
        case .bottomHalf:
            return NSRect(
                x: frame.minX,
                y: frame.minY,
                width: frame.width,
                height: frame.height / 2
            )
        case .fill:
            return frame
        case .center:
            let centeredSize = NSSize(
                width: min(currentFrame.width, frame.width),
                height: min(currentFrame.height, frame.height)
            )
            return NSRect(
                x: frame.midX - centeredSize.width / 2,
                y: frame.midY - centeredSize.height / 2,
                width: centeredSize.width,
                height: centeredSize.height
            )
        case .leftThird:
            return NSRect(
                x: frame.minX,
                y: frame.minY,
                width: frame.width / 3,
                height: frame.height
            )
        case .rightThird:
            return NSRect(
                x: frame.minX + frame.width * 2 / 3,
                y: frame.minY,
                width: frame.width / 3,
                height: frame.height
            )
        case .fullScreen:
            return currentFrame
        }
    }
}

@MainActor
final class BrowserWindowZoomPopoverPresenter: ObservableObject {
    static let contentSize = NSSize(width: 254, height: 204)

    private var popover: NSPopover?
    private var pendingShowTask: Task<Void, Never>?

    func scheduleShow(window: NSWindow, anchorView: NSView) {
        cancelPendingShow()

        pendingShowTask = Task { @MainActor [weak self, weak window, weak anchorView] in
            try? await Task.sleep(nanoseconds: 320_000_000)

            guard !Task.isCancelled,
                  let self,
                  let window,
                  let anchorView,
                  anchorView.window != nil
            else {
                return
            }

            self.show(window: window, anchorView: anchorView)
        }
    }

    func cancelPendingShow() {
        pendingShowTask?.cancel()
        pendingShowTask = nil
    }

    func close() {
        cancelPendingShow()
        popover?.performClose(nil)
        popover = nil
    }

    private func show(window: NSWindow, anchorView: NSView) {
        if popover?.isShown == true {
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = Self.contentSize
        popover.contentViewController = NSHostingController(
            rootView: BrowserWindowZoomMenuView(
                isFullScreen: window.styleMask.contains(.fullScreen),
                onSelect: { [weak self, weak window] action in
                    guard let window else { return }
                    BrowserWindowTrafficLightActionRouter.performMenuAction(action, window: window)
                    self?.close()
                }
            )
        )

        self.popover = popover
        popover.show(
            relativeTo: anchorView.bounds,
            of: anchorView,
            preferredEdge: .minY
        )
    }
}

struct BrowserWindowTrafficLightButton: View {
    let kind: BrowserWindowTrafficLightKind
    let isClusterHovered: Bool
    let isWindowActive: Bool
    let isEnabled: Bool
    let action: () -> Void
    let hoverChanged: (Bool, NSView) -> Void

    private var diameter: CGFloat {
        BrowserWindowTrafficLightMetrics.buttonDiameter
    }

    var body: some View {
        ZStack {
            BrowserWindowTrafficLightFace(
                kind: kind,
                showsGlyph: isClusterHovered && isWindowActive && isEnabled,
                isActive: isWindowActive && isEnabled
            )
            .frame(width: diameter, height: diameter)

            BrowserWindowTrafficLightClickTarget(
                kind: kind,
                isEnabled: isEnabled,
                action: action,
                hoverChanged: hoverChanged
            )
            .frame(width: diameter, height: diameter)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .help(kind.helpText)
    }
}

private struct BrowserWindowTrafficLightClickTarget: NSViewRepresentable {
    let kind: BrowserWindowTrafficLightKind
    let isEnabled: Bool
    let action: () -> Void
    let hoverChanged: (Bool, NSView) -> Void

    func makeNSView(context: Context) -> BrowserWindowTrafficLightClickTargetView {
        let view = BrowserWindowTrafficLightClickTargetView(kind: kind)
        view.isTrafficLightEnabled = isEnabled
        view.action = action
        view.hoverChanged = hoverChanged
        return view
    }

    func updateNSView(_ nsView: BrowserWindowTrafficLightClickTargetView, context: Context) {
        nsView.isTrafficLightEnabled = isEnabled
        nsView.action = action
        nsView.hoverChanged = hoverChanged
    }
}

@MainActor
private final class BrowserWindowTrafficLightClickTargetView: NSView {
    let kind: BrowserWindowTrafficLightKind
    var action: (() -> Void)?
    var hoverChanged: ((Bool, NSView) -> Void)?
    private var trackingArea: NSTrackingArea?
    var isTrafficLightEnabled = true {
        didSet {
            setAccessibilityEnabled(isTrafficLightEnabled)
        }
    }

    init(kind: BrowserWindowTrafficLightKind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = false
        setAccessibilityElement(true)
        setAccessibilityIdentifier(kind.accessibilityIdentifier)
        setAccessibilityLabel(kind.accessibilityLabel)
        setAccessibilityHelp(kind.helpText)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area

        super.updateTrackingAreas()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isHidden == false,
              alphaValue > 0,
              bounds.contains(point)
        else {
            return nil
        }

        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard isTrafficLightEnabled else { return }
        action?()
    }

    override func mouseEntered(with event: NSEvent) {
        hoverChanged?(true, self)
    }

    override func mouseExited(with event: NSEvent) {
        hoverChanged?(false, self)
    }

    override func accessibilityPerformPress() -> Bool {
        guard isTrafficLightEnabled else { return false }
        action?()
        return true
    }
}

enum BrowserWindowTrafficLightAsset {
    static func name(
        for kind: BrowserWindowTrafficLightKind,
        showsGlyph: Bool,
        isActive: Bool
    ) -> String {
        guard isActive else {
            return "traffic-light-no-focus"
        }

        switch (kind, showsGlyph) {
        case (.close, false):
            return "traffic-light-close-normal"
        case (.close, true):
            return "traffic-light-close-hover"
        case (.minimize, false):
            return "traffic-light-minimize-normal"
        case (.minimize, true):
            return "traffic-light-minimize-hover"
        case (.zoom, false):
            return "traffic-light-zoom-normal"
        case (.zoom, true):
            return "traffic-light-zoom-hover"
        }
    }
}

struct BrowserWindowTrafficLightFace: View {
    let kind: BrowserWindowTrafficLightKind
    let showsGlyph: Bool
    let isActive: Bool

    private var diameter: CGFloat {
        BrowserWindowTrafficLightMetrics.buttonDiameter
    }

    var body: some View {
        Image(BrowserWindowTrafficLightAsset.name(
            for: kind,
            showsGlyph: showsGlyph,
            isActive: isActive
        ))
        .resizable()
        .interpolation(.high)
        .antialiased(true)
        .frame(width: diameter, height: diameter)
    }
}

enum BrowserWindowTrafficLightPalette {
    static func colors(
        for kind: BrowserWindowTrafficLightKind,
        isActive: Bool
    ) -> (outer: UInt32, inner: UInt32) {
        guard isActive else {
            return (0xD1D0D2, 0xC7C7C7)
        }

        switch kind {
        case .close:
            return (0xE24B41, 0xED6A5F)
        case .minimize:
            return (0xE1A73E, 0xF6BE50)
        case .zoom:
            return (0x2DAC2F, 0x61C555)
        }
    }
}

private struct BrowserWindowZoomMenuView: View {
    let isFullScreen: Bool
    let onSelect: (BrowserWindowTrafficLightMenuAction) -> Void

    private let moveActions: [BrowserWindowTrafficLightMenuAction] = [
        .leftHalf,
        .rightHalf,
        .topHalf,
        .bottomHalf,
    ]

    private let arrangeActions: [BrowserWindowTrafficLightMenuAction] = [
        .fill,
        .center,
        .leftThird,
        .rightThird,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrowserWindowZoomMenuSection(
                title: "Move & Resize",
                actions: moveActions,
                onSelect: onSelect
            )

            Divider()
                .padding(.vertical, 9)

            BrowserWindowZoomMenuSection(
                title: "Fill & Arrange",
                actions: arrangeActions,
                onSelect: onSelect
            )

            Divider()
                .padding(.top, 9)
                .padding(.bottom, 5)

            Button {
                onSelect(.fullScreen)
            } label: {
                HStack(spacing: 8) {
                    Text(isFullScreen ? "Exit Full Screen" : "Enter Full Screen")
                        .font(.system(size: 14, weight: .regular))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(BrowserWindowControlsAccessibilityIdentifiers.fullScreenMenuItem)
        }
        .padding(.top, 13)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .frame(
            width: BrowserWindowZoomPopoverPresenter.contentSize.width,
            height: BrowserWindowZoomPopoverPresenter.contentSize.height,
            alignment: .topLeading
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(BrowserWindowControlsAccessibilityIdentifiers.zoomMenu)
    }
}

private struct BrowserWindowZoomMenuSection: View {
    let title: String
    let actions: [BrowserWindowTrafficLightMenuAction]
    let onSelect: (BrowserWindowTrafficLightMenuAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                ForEach(actions) { action in
                    Button {
                        onSelect(action)
                    } label: {
                        BrowserWindowZoomMenuTileIcon(action: action)
                            .frame(width: 37, height: 29)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.title)
                    .accessibilityIdentifier(action.accessibilityIdentifier)
                    .help(action.title)
                }
            }
        }
    }
}

private struct BrowserWindowZoomMenuTileIcon: View {
    let action: BrowserWindowTrafficLightMenuAction

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let outer = bounds.insetBy(dx: 2, dy: 2)
            let inner = outer.insetBy(dx: 5, dy: 5)

            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.primary.opacity(0.82), lineWidth: 2.4)

                Path { path in
                    path.addRoundedRect(
                        in: fillRect(in: inner),
                        cornerSize: CGSize(width: 1.6, height: 1.6)
                    )
                }
                .fill(Color.primary.opacity(0.82))
            }
        }
    }

    private func fillRect(in rect: CGRect) -> CGRect {
        switch action {
        case .leftHalf:
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.42, height: rect.height)
        case .rightHalf:
            return CGRect(x: rect.maxX - rect.width * 0.42, y: rect.minY, width: rect.width * 0.42, height: rect.height)
        case .topHalf:
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.42)
        case .bottomHalf:
            return CGRect(x: rect.minX, y: rect.maxY - rect.height * 0.42, width: rect.width, height: rect.height * 0.42)
        case .fill:
            return rect
        case .center:
            return rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.22)
        case .leftThird:
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width / 3, height: rect.height)
        case .rightThird:
            return CGRect(x: rect.maxX - rect.width / 3, y: rect.minY, width: rect.width / 3, height: rect.height)
        case .fullScreen:
            return .zero
        }
    }
}

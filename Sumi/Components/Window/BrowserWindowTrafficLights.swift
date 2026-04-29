import AppKit
import SwiftUI

enum BrowserWindowControlsAccessibilityIdentifiers {
    static let closeButton = "browser-window-close-button"
    static let minimizeButton = "browser-window-minimize-button"
    static let zoomButton = "browser-window-zoom-button"
    static let miniBrowserWindow = "mini-browser-window"

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

    static let buttonSpacing: CGFloat = 6
    static let clusterHeight: CGFloat = 30
    static let clusterTrailingInset: CGFloat = 14

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

    var body: some View {
        let _ = windowObserver.revision
        let isFullScreen = window?.styleMask.contains(.fullScreen) ?? false
        let shouldShow = isVisible && isFullScreen == false

        BrowserWindowStandardTrafficLightsHost(
            window: window,
            isVisible: shouldShow
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
        .onAppear {
            windowObserver.attach(to: window)
        }
        .onChange(of: window.map(ObjectIdentifier.init)) { _, _ in
            windowObserver.attach(to: window)
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
    static func perform(
        _ kind: BrowserWindowTrafficLightKind,
        window: NSWindow,
        sender: Any?,
        modifierFlags: NSEvent.ModifierFlags? = nil
    ) {
        switch kind {
        case .close:
            close(window: window, sender: sender)
        case .minimize:
            minimize(window: window, sender: sender)
        case .zoom:
            let flags = (modifierFlags ?? NSApp.currentEvent?.modifierFlags ?? [])
                .intersection(.deviceIndependentFlagsMask)
            if flags.contains(.option) {
                optionZoom(window: window, sender: sender)
            } else {
                fullScreen(window: window, sender: sender)
            }
        }
    }

    static func close(window: NSWindow, sender: Any?) {
        window.performClose(sender)
    }

    static func minimize(window: NSWindow, sender: Any?) {
        window.miniaturize(sender)
    }

    static func fullScreen(window: NSWindow, sender: Any?) {
        window.toggleFullScreen(sender)
    }

    static func optionZoom(window: NSWindow, sender: Any?) {
        window.performZoom(sender)
    }
}

private struct BrowserWindowStandardTrafficLightsHost: NSViewRepresentable {
    let window: NSWindow?
    let isVisible: Bool

    func makeNSView(context: Context) -> BrowserWindowStandardTrafficLightsView {
        let view = BrowserWindowStandardTrafficLightsView()
        view.update(window: window, isVisible: isVisible)
        return view
    }

    func updateNSView(_ nsView: BrowserWindowStandardTrafficLightsView, context: Context) {
        nsView.update(window: window, isVisible: isVisible)
    }

    static func dismantleNSView(_ nsView: BrowserWindowStandardTrafficLightsView, coordinator: ()) {
        nsView.detachButtons()
    }
}

@MainActor
private final class BrowserWindowStandardTrafficLightsView: NSView {
    private weak var windowReference: NSWindow?
    private weak var observedWindow: NSWindow?
    private var isTrafficLightVisible = true
    private var isClusterHovered = false {
        didSet {
            guard isClusterHovered != oldValue else { return }
            needsDisplay = true
        }
    }
    private var trackingArea: NSTrackingArea?
    private var buttonTrackingAreas: [(view: NSView, trackingArea: NSTrackingArea)] = []
    private var observers: [NSObjectProtocol] = []
    private var hoverPollTimer: Timer?
    private let hoverTrackingView = TrafficLightsHoverTrackingView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        hoverTrackingView.onHoverChanged = { [weak self] hovering in
            self?.isClusterHovered = hovering
        }
        addSubview(hoverTrackingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        hoverPollTimer?.invalidate()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: BrowserWindowTrafficLightMetrics.clusterWidth,
            height: BrowserWindowTrafficLightMetrics.clusterHeight
        )
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window, windowReference == nil {
            updateWindowReference(window)
        }
        if isTrafficLightVisible {
            startHoverPolling()
        }
        refreshLayout()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
        updateTrackingAreas()
    }

    override func layout() {
        super.layout()
        layoutButtons()
        hoverTrackingView.frame = bounds
        if hoverTrackingView.superview === self {
            addSubview(hoverTrackingView, positioned: .above, relativeTo: nil)
        }
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea

        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        syncClusterHoverStateFromMouseLocation()
    }

    override func mouseExited(with event: NSEvent) {
        syncClusterHoverStateFromMouseLocation()
    }

    override func mouseMoved(with event: NSEvent) {
        syncClusterHoverStateFromMouseLocation()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawTrafficLightImages()
    }

    func update(window: NSWindow?, isVisible: Bool) {
        updateWindowReference(window ?? self.window)
        isTrafficLightVisible = isVisible
        if isVisible {
            startHoverPolling()
        } else {
            isClusterHovered = false
            stopHoverPolling()
        }
        refreshLayout()
        invalidateIntrinsicContentSize()
    }

    func detachButtons() {
        isClusterHovered = false
        hoverPollTimer?.invalidate()
        hoverPollTimer = nil
        removeButtonTrackingAreas()
        for kind in BrowserWindowTrafficLightKind.allCases {
            guard let button = windowReference?.standardWindowButton(kind.buttonType) else { continue }
            guard button.superview === self else { continue }
            button.removeFromSuperview()
            button.isHidden = true
            button.alphaValue = 0
            button.isEnabled = false
            button.setAccessibilityElement(false)
        }
        removeWindowObservers()
    }

    private func updateWindowReference(_ window: NSWindow?) {
        guard windowReference !== window else { return }
        windowReference = window
        window?.acceptsMouseMovedEvents = true
        installWindowObservers(for: window)
    }

    private func installWindowObservers(for window: NSWindow?) {
        guard observedWindow !== window else { return }

        removeWindowObservers()
        observedWindow = window

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
                        self?.refreshLayout()
                    }
                }
            )
        }

        guard let window else { return }

        let windowNotifications: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didResizeNotification,
            NSWindow.didEndLiveResizeNotification,
            NSWindow.didMoveNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
        ]

        for name in windowNotifications {
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: name,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.refreshLayout()
                        self?.refreshLayoutAfterWindowChromePass()
                    }
                }
            )
        }
    }

    private func removeWindowObservers() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        observedWindow = nil
    }

    private func refreshLayout() {
        needsLayout = true
        needsDisplay = true
        layoutSubtreeIfNeeded()
        layoutButtons()
    }

    private func refreshLayoutAfterWindowChromePass() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshLayout()
        }
    }

    private func layoutButtons() {
        guard let window = windowReference ?? self.window else { return }

        let containerHeight = bounds.height > 0
            ? bounds.height
            : BrowserWindowTrafficLightMetrics.clusterHeight
        var xOffset: CGFloat = 0
        removeButtonTrackingAreas()

        for kind in BrowserWindowTrafficLightKind.allCases {
            guard let button = window.standardWindowButton(kind.buttonType) else { continue }

            if button.superview !== self {
                button.removeFromSuperview()
                addSubview(button)
            }

            configure(button, kind: kind, window: window)

            let size = nativeButtonFrameSize(for: button)
            let yOffset = floor((containerHeight - size.height) / 2)
            button.frame = NSRect(
                x: xOffset,
                y: yOffset,
                width: size.width,
                height: size.height
            )
            button.updateTrackingAreas()
            installTrackingArea(on: button)
            xOffset += size.width + BrowserWindowTrafficLightMetrics.buttonSpacing
        }

        if hoverTrackingView.superview !== self {
            addSubview(hoverTrackingView)
        }
        hoverTrackingView.frame = bounds
        addSubview(hoverTrackingView, positioned: .above, relativeTo: nil)
    }

    private func installTrackingArea(on button: NSButton) {
        let trackingArea = NSTrackingArea(
            rect: button.bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        button.addTrackingArea(trackingArea)
        buttonTrackingAreas.append((button, trackingArea))
    }

    private func removeButtonTrackingAreas() {
        for item in buttonTrackingAreas {
            item.view.removeTrackingArea(item.trackingArea)
        }
        buttonTrackingAreas.removeAll()
    }

    private func syncClusterHoverStateFromMouseLocation() {
        isClusterHovered = isMouseCurrentlyInsideCluster()
    }

    private func startHoverPolling() {
        guard hoverPollTimer == nil else { return }

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.isTrafficLightVisible, (self.windowReference ?? self.window) != nil else {
                    self.isClusterHovered = false
                    self.stopHoverPolling()
                    return
                }
                self.syncClusterHoverStateFromMouseLocation()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverPollTimer = timer
    }

    private func stopHoverPolling() {
        hoverPollTimer?.invalidate()
        hoverPollTimer = nil
    }

    private func isMouseCurrentlyInsideCluster() -> Bool {
        guard isTrafficLightVisible else { return false }
        guard let window = windowReference ?? self.window else { return false }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return bounds.contains(point)
    }

    private func drawTrafficLightImages() {
        guard isTrafficLightVisible else { return }

        let window = windowReference ?? self.window
        let isHovered = isClusterHovered || isMouseCurrentlyInsideCluster()
        let isActive = window.map {
            (NSApp.isActive && ($0.isKeyWindow || $0.isMainWindow)) || isHovered
        } ?? isHovered
        let diameter = BrowserWindowTrafficLightMetrics.buttonDiameter
        let frameHeight = diameter + 2
        let yOffset = floor(((bounds.height > 0 ? bounds.height : BrowserWindowTrafficLightMetrics.clusterHeight) - frameHeight) / 2) + 1
        var xOffset: CGFloat = 0

        for kind in BrowserWindowTrafficLightKind.allCases {
            let isEnabled = window.map {
                BrowserWindowTrafficLightAvailability.isEnabled(kind: kind, window: $0)
            } ?? false
            let imageName = trafficLightAssetName(
                for: kind,
                isHovered: isHovered,
                isActive: isActive && isEnabled
            )

            if let image = NSImage(named: imageName) {
                image.draw(
                    in: NSRect(x: xOffset, y: yOffset, width: diameter, height: diameter),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: imageName == "traffic-light-no-focus" ? 0.25 : 1
                )
            }

            xOffset += diameter + BrowserWindowTrafficLightMetrics.buttonSpacing
        }
    }

    private func configure(_ button: NSButton, kind: BrowserWindowTrafficLightKind, window: NSWindow) {
        let isEnabled = isTrafficLightVisible
            && BrowserWindowTrafficLightAvailability.isEnabled(kind: kind, window: window)

        button.identifier = NSUserInterfaceItemIdentifier(kind.accessibilityIdentifier)
        button.setAccessibilityElement(isTrafficLightVisible)
        button.setAccessibilityIdentifier(kind.accessibilityIdentifier)
        button.setAccessibilityLabel(kind.accessibilityLabel)
        button.setAccessibilityHelp(kind.helpText)
        button.isHidden = !isTrafficLightVisible
        button.alphaValue = isTrafficLightVisible ? 0.01 : 0
        button.isEnabled = isEnabled
        button.cell?.controlView = button
        button.target = window
        button.isBordered = false
        button.translatesAutoresizingMaskIntoConstraints = true
        button.autoresizingMask = []
        button.needsDisplay = true
    }

    private func nativeButtonFrameSize(for button: NSButton) -> NSSize {
        let visualDiameter = BrowserWindowTrafficLightMetrics.buttonDiameter
        let intrinsic = button.intrinsicContentSize
        let alignmentRect = button.alignmentRect(
            forFrame: NSRect(
                origin: .zero,
                size: NSSize(width: visualDiameter, height: visualDiameter + 2)
            )
        )

        return NSSize(
            width: max(visualDiameter, intrinsic.width, alignmentRect.width),
            height: max(visualDiameter + 2, intrinsic.height + 2, alignmentRect.height + 2)
        )
    }

    private func trafficLightAssetName(
        for kind: BrowserWindowTrafficLightKind,
        isHovered: Bool,
        isActive: Bool
    ) -> String {
        guard isActive else {
            return "traffic-light-no-focus"
        }

        let state = isHovered ? "hover" : "normal"
        switch kind {
        case .close:
            return "traffic-light-close-\(state)"
        case .minimize:
            return "traffic-light-minimize-\(state)"
        case .zoom:
            return "traffic-light-zoom-\(state)"
        }
    }
}

@MainActor
private final class TrafficLightsHoverTrackingView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea

        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseMoved(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }
}

import AppKit

@MainActor
struct CollapsedSidebarPointerSuppressionEventMonitorClient {
    let addLocalMonitor: (
        NSEvent.EventTypeMask,
        @escaping (NSEvent) -> NSEvent?
    ) -> Any?
    let removeMonitor: (Any) -> Void

    static let live = CollapsedSidebarPointerSuppressionEventMonitorClient(
        addLocalMonitor: { mask, handler in
            NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
        },
        removeMonitor: { monitor in
            NSEvent.removeMonitor(monitor)
        }
    )
}

@MainActor
final class CollapsedSidebarPointerSuppressionController {
    static let monitoredEventTypes: NSEvent.EventTypeMask = [.mouseMoved, .cursorUpdate]

    private let eventMonitors: CollapsedSidebarPointerSuppressionEventMonitorClient
    private let setArrowCursor: () -> Void
    private let requiresKeyWindow: Bool

    private weak var window: NSWindow?
    private weak var observedWindow: NSWindow?
    private weak var panelView: NSView?
    private weak var hostedSidebarView: NSView?

    private var isCollapsedVisible = false
    private var isSidebarCollapsed = false
    private var isBrowserWindowActive = false
    private var localMonitor: Any?
    private var windowObservers: [NSObjectProtocol] = []
    private var isCursorCorrectionPending = false

    init(
        eventMonitors: CollapsedSidebarPointerSuppressionEventMonitorClient = .live,
        setArrowCursor: @escaping () -> Void = { NSCursor.arrow.set() },
        requiresKeyWindow: Bool = true
    ) {
        self.eventMonitors = eventMonitors
        self.setArrowCursor = setArrowCursor
        self.requiresKeyWindow = requiresKeyWindow
    }

    deinit {
        MainActor.assumeIsolated {
            teardown()
        }
    }

    var isMonitorInstalledForTesting: Bool {
        localMonitor != nil
    }

    var currentPanelRectForTesting: NSRect? {
        currentPanelRect()
    }

    func update(
        window: NSWindow?,
        panelView: NSView?,
        hostedSidebarView: NSView?,
        isCollapsedVisible: Bool,
        isSidebarCollapsed: Bool,
        isBrowserWindowActive: Bool
    ) {
        self.window = window
        self.panelView = panelView
        self.hostedSidebarView = hostedSidebarView
        self.isCollapsedVisible = isCollapsedVisible
        self.isSidebarCollapsed = isSidebarCollapsed
        self.isBrowserWindowActive = isBrowserWindowActive

        bindWindow(window)
        refreshMonitoring()
    }

    func refreshPanelRect() {
        refreshMonitoring()
    }

    func teardown() {
        uninstallMonitor()
        unbindWindow()
        window = nil
        panelView = nil
        hostedSidebarView = nil
        isCollapsedVisible = false
        isSidebarCollapsed = false
        isBrowserWindowActive = false
        isCursorCorrectionPending = false
    }

    private func bindWindow(_ nextWindow: NSWindow?) {
        guard observedWindow !== nextWindow else { return }
        unbindWindow()
        guard let nextWindow else { return }

        observedWindow = nextWindow
        let center = NotificationCenter.default
        windowObservers = [
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nextWindow,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshMonitoring()
                }
            },
            center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: nextWindow,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.uninstallMonitor()
                }
            },
            center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: nextWindow,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.teardown()
                }
            },
            center.addObserver(
                forName: NSWindow.didResizeNotification,
                object: nextWindow,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshMonitoring()
                }
            },
        ]
    }

    private func unbindWindow() {
        let center = NotificationCenter.default
        windowObservers.forEach(center.removeObserver)
        windowObservers.removeAll()
        observedWindow = nil
    }

    private func refreshMonitoring() {
        guard shouldInstallMonitor else {
            uninstallMonitor()
            return
        }

        installMonitorIfNeeded()
    }

    private var shouldInstallMonitor: Bool {
        guard isCollapsedVisible,
              isSidebarCollapsed,
              isBrowserWindowActive,
              let window,
              let panelView,
              panelView.window === window,
              currentPanelRect().map(Self.isUsablePanelRect) == true
        else {
            return false
        }

        return !requiresKeyWindow || window.isKeyWindow
    }

    private func installMonitorIfNeeded() {
        guard localMonitor == nil else { return }

        localMonitor = eventMonitors.addLocalMonitor(
            Self.monitoredEventTypes
        ) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                return self.handle(event)
            }
        }
    }

    private func uninstallMonitor() {
        guard let localMonitor else { return }
        eventMonitors.removeMonitor(localMonitor)
        self.localMonitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.type == .mouseMoved || event.type == .cursorUpdate,
              let window,
              let panelRect = currentPanelRect(),
              Self.isUsablePanelRect(panelRect),
              let windowPoint = pointInBrowserWindow(for: event, window: window),
              panelRect.contains(windowPoint)
        else {
            return event
        }

        switch sidebarHitClassification(at: windowPoint) {
        case .textInput:
            return event
        case .interactive:
            guard event.type == .cursorUpdate else {
                return event
            }
            setArrowCursor()
            schedulePostDispatchCursorCorrection()
            return nil
        case .background:
            setArrowCursor()
            schedulePostDispatchCursorCorrection()
            return nil
        }
    }

    private func pointInBrowserWindow(for event: NSEvent, window: NSWindow) -> NSPoint? {
        guard let eventWindow = event.window else {
            return event.locationInWindow
        }

        guard eventWindow === window || eventWindow.windowNumber == window.windowNumber else {
            return nil
        }

        return event.locationInWindow
    }

    private func currentPanelRect() -> NSRect? {
        guard let panelView,
              panelView.window === window
        else {
            return nil
        }

        return panelView.convert(panelView.bounds, to: nil)
    }

    private static func isUsablePanelRect(_ rect: NSRect) -> Bool {
        !rect.isEmpty && !rect.isNull && rect.width > 0 && rect.height > 0
    }

    private enum SidebarHitClassification {
        case background
        case interactive
        case textInput
    }

    private func sidebarHitClassification(at windowPoint: NSPoint) -> SidebarHitClassification {
        guard let panelView else { return .background }

        let panelPoint = panelView.convert(windowPoint, from: nil)
        guard let hitView = panelView.hitTest(panelPoint) else { return .background }

        if hitView === panelView || hitView === hostedSidebarView {
            return .background
        }

        if hitView.nearestPointerSuppressionAncestor(of: NSTextView.self) != nil {
            return .textInput
        }

        if let textField = hitView.nearestPointerSuppressionAncestor(of: NSTextField.self),
           textField.isEditable || textField.isSelectable
        {
            return .textInput
        }

        if hitView.nearestPointerSuppressionAncestor(of: SidebarInteractiveItemView.self) != nil {
            return .interactive
        }

        guard let hostedSidebarView else {
            return .background
        }

        if let control = hitView.nearestPointerSuppressionAncestor(of: NSControl.self),
           control.isDescendant(of: hostedSidebarView)
        {
            return .interactive
        }

        return .background
    }

    private func schedulePostDispatchCursorCorrection() {
        guard !isCursorCorrectionPending else { return }
        isCursorCorrectionPending = true

        Task { @MainActor [weak self, weak window] in
            guard let self else { return }
            self.isCursorCorrectionPending = false

            guard self.shouldInstallMonitor,
                  let window,
                  let panelRect = self.currentPanelRect(),
                  Self.isUsablePanelRect(panelRect)
            else {
                return
            }

            let screenPoint = NSEvent.mouseLocation
            let windowPoint = window.convertPoint(fromScreen: screenPoint)
            guard panelRect.contains(windowPoint),
                  self.sidebarHitClassification(at: windowPoint) != .textInput
            else {
                return
            }

            self.setArrowCursor()
        }
    }
}

private extension NSView {
    func nearestPointerSuppressionAncestor<T: NSView>(of type: T.Type) -> T? {
        var current: NSView? = self
        while let view = current {
            if let match = view as? T {
                return match
            }
            current = view.superview
        }
        return nil
    }
}

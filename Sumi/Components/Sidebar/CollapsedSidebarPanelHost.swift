import AppKit
import SwiftUI

final class CollapsedSidebarPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum CollapsedSidebarPanelFrameResolver {
    static func panelFrame(
        parentContentScreenFrame: NSRect,
        sidebarWidth: CGFloat,
        sidebarPosition: SidebarPosition
    ) -> NSRect {
        let width = min(max(sidebarWidth, 0), parentContentScreenFrame.width)
        let originX = sidebarPosition.shellEdge.isLeft
            ? parentContentScreenFrame.minX
            : parentContentScreenFrame.maxX - width

        return NSRect(
            x: originX,
            y: parentContentScreenFrame.minY,
            width: width,
            height: parentContentScreenFrame.height
        )
    }

    static func parentContentScreenFrame(in parentWindow: NSWindow) -> NSRect? {
        guard let contentView = parentWindow.contentView else { return nil }
        let contentWindowFrame = contentView.convert(contentView.bounds, to: nil)
        return parentWindow.convertToScreen(contentWindowFrame)
    }

    static func panelFrame(
        in parentWindow: NSWindow,
        sidebarWidth: CGFloat,
        sidebarPosition: SidebarPosition
    ) -> NSRect? {
        guard let contentScreenFrame = parentContentScreenFrame(in: parentWindow) else {
            return nil
        }
        return panelFrame(
            parentContentScreenFrame: contentScreenFrame,
            sidebarWidth: sidebarWidth,
            sidebarPosition: sidebarPosition
        )
    }
}

@MainActor
final class CollapsedSidebarPanelController {
    private var panelWindow: CollapsedSidebarPanelWindow?
    private let sidebarController = SidebarColumnViewController(usesCollapsedPanelRoot: true)
    private weak var attachedParentWindow: NSWindow?
    private weak var observedParentWindow: NSWindow?
    private weak var observedContentView: NSView?
    private var observers: [NSObjectProtocol] = []
    private var currentSidebarWidth: CGFloat = BrowserWindowState.sidebarDefaultWidth
    private var currentSidebarPosition: SidebarPosition = .left

    var panelWindowForTesting: CollapsedSidebarPanelWindow? {
        panelWindow
    }

    var attachedParentWindowForTesting: NSWindow? {
        attachedParentWindow
    }

    var isPanelAttachedForTesting: Bool {
        guard let panelWindow, let attachedParentWindow else { return false }
        return attachedParentWindow.childWindows?.contains(panelWindow) == true
    }

    func update<Content: View>(
        parentWindow: NSWindow?,
        root: Content,
        width: CGFloat,
        presentationContext: SidebarPresentationContext,
        contextMenuController: SidebarContextMenuController?,
        isHostRequested: Bool
    ) {
        currentSidebarWidth = width
        currentSidebarPosition = presentationContext.sidebarPosition

        guard isHostRequested,
              presentationContext.isCollapsedOverlay,
              let parentWindow
        else {
            orderOutAndDetach(teardownHostedContent: true, destroyWindow: true)
            return
        }

        let panel = ensurePanelWindow()
        bindParentWindow(parentWindow)
        configure(panel, for: parentWindow)

        if panel.contentViewController !== sidebarController {
            panel.contentViewController = sidebarController
        }

        sidebarController.updateHostedSidebar(
            root: root,
            width: width,
            contextMenuController: contextMenuController,
            capturesPanelBackgroundPointerEvents: presentationContext.capturesPanelBackgroundPointerEvents,
            isCollapsedPanelHitTestingEnabled: presentationContext.mode == .collapsedVisible
        )

        syncFrame()

        #if DEBUG
        SidebarDebugMetrics.recordCollapsedSidebarHost(
            controller: sidebarController,
            presentationMode: presentationContext.mode,
            isMounted: true
        )
        #endif

        if presentationContext.mode == .collapsedVisible {
            attachAndShow(panel, to: parentWindow)
        } else {
            orderOutAndDetach(teardownHostedContent: false, destroyWindow: false)
        }
    }

    func syncFrame() {
        guard let panelWindow,
              let parentWindow = observedParentWindow ?? attachedParentWindow,
              let frame = CollapsedSidebarPanelFrameResolver.panelFrame(
                in: parentWindow,
                sidebarWidth: currentSidebarWidth,
                sidebarPosition: currentSidebarPosition
              )
        else { return }

        panelWindow.setFrame(frame, display: panelWindow.isVisible)
    }

    func teardown() {
        orderOutAndDetach(teardownHostedContent: true, destroyWindow: true)
        unbindParentWindow()
    }

    deinit {
        MainActor.assumeIsolated {
            teardown()
        }
    }

    private func ensurePanelWindow() -> CollapsedSidebarPanelWindow {
        if let panelWindow {
            return panelWindow
        }

        let panel = CollapsedSidebarPanelWindow(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.worksWhenModal = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .fullScreenAuxiliary,
            .moveToActiveSpace,
            .ignoresCycle,
        ]
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panelWindow = panel
        return panel
    }

    private func configure(
        _ panel: CollapsedSidebarPanelWindow,
        for parentWindow: NSWindow
    ) {
        panel.level = parentWindow.level
        panel.appearance = parentWindow.effectiveAppearance
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
    }

    private func attachAndShow(
        _ panel: CollapsedSidebarPanelWindow,
        to parentWindow: NSWindow
    ) {
        if attachedParentWindow !== parentWindow {
            detachFromParent()
        }

        if parentWindow.childWindows?.contains(panel) != true {
            parentWindow.addChildWindow(panel, ordered: .above)
        }

        attachedParentWindow = parentWindow
        panel.orderFront(nil)
    }

    private func orderOutAndDetach(
        teardownHostedContent: Bool,
        destroyWindow: Bool
    ) {
        detachFromParent()
        panelWindow?.orderOut(nil)

        if teardownHostedContent {
            sidebarController.teardownSidebarHosting()
            #if DEBUG
            SidebarDebugMetrics.recordCollapsedSidebarHost(
                controller: sidebarController,
                presentationMode: .collapsedHidden,
                isMounted: false
            )
            #endif
        }

        if destroyWindow {
            panelWindow?.contentViewController = nil
            panelWindow = nil
        }
    }

    private func detachFromParent() {
        guard let panelWindow,
              let attachedParentWindow
        else {
            self.attachedParentWindow = nil
            return
        }

        if attachedParentWindow.childWindows?.contains(panelWindow) == true {
            attachedParentWindow.removeChildWindow(panelWindow)
        }
        self.attachedParentWindow = nil
    }

    private func bindParentWindow(_ parentWindow: NSWindow) {
        guard observedParentWindow !== parentWindow else { return }
        unbindParentWindow()
        observedParentWindow = parentWindow

        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
        ]

        observers = names.map { name in
            center.addObserver(
                forName: name,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.syncFrame()
                }
            }
        }

        observers.append(
            center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.teardown()
                }
            }
        )

        if let contentView = parentWindow.contentView {
            contentView.postsFrameChangedNotifications = true
            observedContentView = contentView
            observers.append(
                center.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: contentView,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.syncFrame()
                    }
                }
            )
        }
    }

    private func unbindParentWindow() {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers = []
        observedParentWindow = nil
        observedContentView = nil
    }
}

final class CollapsedSidebarPanelAnchorView: NSView {
    var onWindowChanged: ((NSWindow?) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChanged?(window)
    }
}

struct CollapsedSidebarPanelHost: NSViewRepresentable {
    @ObservedObject var browserManager: BrowserManager
    var windowState: BrowserWindowState
    var windowRegistry: WindowRegistry
    var commandPalette: CommandPalette
    var sumiSettings: SumiSettingsService
    var resolvedThemeContext: ResolvedThemeContext
    var trafficLightRenderState: BrowserWindowTrafficLightRenderState
    var presentationContext: SidebarPresentationContext
    var isHostRequested: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> CollapsedSidebarPanelAnchorView {
        let view = CollapsedSidebarPanelAnchorView(frame: .zero)
        view.onWindowChanged = { [weak controller = context.coordinator.controller] _ in
            Task { @MainActor [weak controller] in
                controller?.syncFrame()
            }
        }
        return view
    }

    func updateNSView(_ nsView: CollapsedSidebarPanelAnchorView, context: Context) {
        guard isHostRequested else {
            context.coordinator.controller.update(
                parentWindow: nsView.window ?? windowState.window,
                root: EmptyView(),
                width: presentationContext.sidebarWidth,
                presentationContext: presentationContext,
                contextMenuController: nil,
                isHostRequested: false
            )
            return
        }

        let root = SidebarColumnHostedRoot.view(
            browserManager: browserManager,
            windowState: windowState,
            windowRegistry: windowRegistry,
            commandPalette: commandPalette,
            sumiSettings: sumiSettings,
            resolvedThemeContext: resolvedThemeContext,
            trafficLightRenderState: trafficLightRenderState,
            presentationContext: presentationContext
        )

        context.coordinator.controller.update(
            parentWindow: nsView.window ?? windowState.window,
            root: root,
            width: presentationContext.sidebarWidth,
            presentationContext: presentationContext,
            contextMenuController: windowState.sidebarContextMenuController,
            isHostRequested: isHostRequested
        )
    }

    static func dismantleNSView(_ nsView: CollapsedSidebarPanelAnchorView, coordinator: Coordinator) {
        nsView.onWindowChanged = nil
        coordinator.controller.teardown()
    }

    @MainActor
    final class Coordinator {
        let controller = CollapsedSidebarPanelController()
    }
}

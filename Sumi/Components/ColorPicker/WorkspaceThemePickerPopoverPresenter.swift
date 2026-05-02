import AppKit
import SwiftUI

@MainActor
final class WorkspaceThemePickerPopoverPresenter: NSObject, NSPopoverDelegate {
    enum Metrics {
        @MainActor
        static var contentSize: NSSize {
            NSSize(width: GradientEditorView.panelWidth, height: 526)
        }
        static let closeAnimationFallbackDelay: UInt64 = 350_000_000
    }

    enum CloseDisposition {
        case commit
        case discard
    }

    private final class ActiveSession {
        let session: WorkspaceThemePickerSession
        let popover: NSPopover
        let hostingController: WorkspaceThemePickerPopoverHostingController
        weak var windowState: BrowserWindowState?
        weak var browserManager: BrowserManager?
        weak var transientCoordinator: SidebarTransientSessionCoordinator?
        let transientSessionToken: SidebarTransientSessionToken?
        var closeDisposition: CloseDisposition = .commit
        var closeFallbackTask: Task<Void, Never>?
        var isClosing = false

        init(
            session: WorkspaceThemePickerSession,
            popover: NSPopover,
            hostingController: WorkspaceThemePickerPopoverHostingController,
            windowState: BrowserWindowState,
            browserManager: BrowserManager,
            transientCoordinator: SidebarTransientSessionCoordinator?,
            transientSessionToken: SidebarTransientSessionToken?
        ) {
            self.session = session
            self.popover = popover
            self.hostingController = hostingController
            self.windowState = windowState
            self.browserManager = browserManager
            self.transientCoordinator = transientCoordinator
            self.transientSessionToken = transientSessionToken
        }

        deinit {
            closeFallbackTask?.cancel()
        }
    }

    private var activeSession: ActiveSession?
    private var observesDismissNotifications = false
    private var localMouseDownMonitor: Any?

    var hasActiveSession: Bool {
        activeSession != nil
    }

    func present(
        _ session: WorkspaceThemePickerSession,
        in windowState: BrowserWindowState,
        browserManager: BrowserManager
    ) {
        if activeSession != nil {
            closeActive(committing: true)
            return
        }

        session.commitsOnDismiss = true

        guard let resolvedAnchor = resolvedPresentationAnchor(
            for: session,
            in: windowState,
            sidebarPosition: browserManager.sumiSettings?.sidebarPosition ?? .left
        ) else {
            finishWithoutPopover(
                session,
                windowState: windowState,
                browserManager: browserManager,
                reason: "WorkspaceThemePickerPopoverPresenter.anchorUnavailable"
            )
            return
        }

        let hostingController = WorkspaceThemePickerPopoverHostingController(
            rootView: rootView(
                session: session,
                windowState: windowState,
                browserManager: browserManager
            ),
            contentSize: Self.Metrics.contentSize
        )

        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = hostingController
        popover.contentSize = Self.Metrics.contentSize
        popover.appearance = resolvedAnchor.view.window?.effectiveAppearance
            ?? windowState.window?.effectiveAppearance
            ?? NSApplication.shared.effectiveAppearance

        activeSession = ActiveSession(
            session: session,
            popover: popover,
            hostingController: hostingController,
            windowState: windowState,
            browserManager: browserManager,
            transientCoordinator: session.presentationSource?.coordinator,
            transientSessionToken: session.transientSessionToken
        )
        startObservingDismissNotifications()

        windowState.window?.makeKeyAndOrderFront(nil)
        popover.show(
            relativeTo: resolvedAnchor.rect,
            of: resolvedAnchor.view,
            preferredEdge: resolvedAnchor.preferredEdge
        )
    }

    func close(sessionID: UUID, committing: Bool) {
        guard let activeSession,
              activeSession.session.id == sessionID
        else { return }

        activeSession.closeDisposition = committing ? .commit : .discard
        activeSession.session.commitsOnDismiss = committing
        closeActiveSession(activeSession)
    }

    func closeActive(committing: Bool) {
        guard let activeSession else { return }
        close(sessionID: activeSession.session.id, committing: committing)
    }

    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover,
              let activeSession,
              activeSession.popover === popover
        else { return }

        finishClosedSession(
            activeSession,
            reason: "WorkspaceThemePickerPopoverPresenter.popoverDidClose"
        )
    }

    nonisolated static func fallbackAnchorRect(
        in bounds: NSRect,
        isSidebarVisible: Bool,
        sidebarWidth: CGFloat,
        savedSidebarWidth: CGFloat,
        sidebarPosition: SidebarPosition = .left
    ) -> NSRect {
        let rawSidebarWidth = isSidebarVisible
            ? sidebarWidth
            : SidebarPresentationContext.collapsedSidebarWidth(
                sidebarWidth: sidebarWidth,
                savedSidebarWidth: savedSidebarWidth
            )
        let x = sidebarPosition.shellEdge.sidebarBoundaryAnchorX(
            in: bounds,
            presentationWidth: rawSidebarWidth
        )
        let minY = bounds.minY + 1
        let maxY = max(minY, bounds.maxY - 1)
        let y = min(max(bounds.midY, minY), maxY)
        return NSRect(x: x, y: y, width: 1, height: 1)
    }

    nonisolated static func sidebarDismissRect(
        in bounds: NSRect,
        isSidebarVisible: Bool,
        sidebarWidth: CGFloat,
        savedSidebarWidth: CGFloat,
        sidebarPosition: SidebarPosition = .left
    ) -> NSRect {
        let width = isSidebarVisible
            ? sidebarWidth
            : SidebarPresentationContext.collapsedSidebarWidth(
                sidebarWidth: sidebarWidth,
                savedSidebarWidth: savedSidebarWidth
            )
        return sidebarPosition.shellEdge.sidebarDismissRect(
            in: bounds,
            presentationWidth: width
        )
    }

    static func performDismissRecovery(
        in window: NSWindow?,
        anchor: NSView?,
        using coordinator: SidebarHostRecoveryHandling
    ) {
        coordinator.recover(in: window)
        coordinator.recover(anchor: anchor)
    }

    static func performUncoordinatedSidebarDismissRecovery(
        windowState: BrowserWindowState?,
        source: SidebarTransientPresentationSource?,
        anchor: NSView?,
        using coordinator: SidebarHostRecoveryHandling
    ) {
        let window = source?.window ?? windowState?.window
        performDismissRecovery(
            in: window,
            anchor: anchor,
            using: coordinator
        )

        guard let windowState else { return }

        let recoveryResult = windowState.sidebarContextMenuController.recoverInteractiveOwners(
            in: window,
            source: source
        )
        if source?.interactiveOwnerRecoveryMetadata != nil,
           !recoveryResult.sourceOwnerResolved
        {
            windowState.scheduleSidebarInputRehydrate(
                reason: .ownerUnresolvedAfterSoftRecovery
            )
        }
    }

    private func rootView(
        session: WorkspaceThemePickerSession,
        windowState: BrowserWindowState,
        browserManager: BrowserManager
    ) -> AnyView {
        AnyView(
            WorkspaceThemePickerPopoverContent(session: session)
                .environmentObject(browserManager)
                .environment(windowState)
                .environment(\.sumiSettings, browserManager.sumiSettings ?? SumiSettingsService())
                .frame(
                    width: Self.Metrics.contentSize.width,
                    height: Self.Metrics.contentSize.height
                )
        )
    }

    private func resolvedPresentationAnchor(
        for session: WorkspaceThemePickerSession,
        in windowState: BrowserWindowState,
        sidebarPosition: SidebarPosition
    ) -> (view: NSView, rect: NSRect, preferredEdge: NSRectEdge)? {
        let preferredEdge = Self.preferredPopoverEdge(for: sidebarPosition)

        if let ownerView = session.presentationSource?.originOwnerView,
           ownerView.window != nil,
           ownerView.superview != nil,
           !ownerView.isHiddenOrHasHiddenAncestor,
           ownerView.alphaValue > 0
        {
            return (ownerView, ownerView.bounds, preferredEdge)
        }

        guard let contentView = windowState.window?.contentView
            ?? session.presentationSource?.window?.contentView
        else { return nil }

        return (
            contentView,
            Self.fallbackAnchorRect(
                in: contentView.bounds,
                isSidebarVisible: windowState.isSidebarVisible,
                sidebarWidth: windowState.sidebarWidth,
                savedSidebarWidth: windowState.savedSidebarWidth,
                sidebarPosition: sidebarPosition
            ),
            preferredEdge
        )
    }

    private nonisolated static func preferredPopoverEdge(for sidebarPosition: SidebarPosition) -> NSRectEdge {
        sidebarPosition == .left ? .maxX : .minX
    }

    private func closeActiveSession(_ activeSession: ActiveSession) {
        guard !activeSession.isClosing else { return }

        activeSession.isClosing = true
        if activeSession.popover.isShown {
            activeSession.popover.close()
            activeSession.closeFallbackTask = Task { @MainActor [weak self, weak activeSession] in
                try? await Task.sleep(nanoseconds: Self.Metrics.closeAnimationFallbackDelay)
                guard let self,
                      let activeSession,
                      self.activeSession === activeSession
                else { return }

                self.finishClosedSession(
                    activeSession,
                    reason: "WorkspaceThemePickerPopoverPresenter.closeFallback"
                )
            }
        } else {
            finishClosedSession(
                activeSession,
                reason: "WorkspaceThemePickerPopoverPresenter.closeNotShown"
            )
        }
    }

    private func finishClosedSession(
        _ closedSession: ActiveSession,
        reason: String
    ) {
        guard activeSession === closedSession else { return }

        stopObservingDismissNotifications()
        activeSession = nil
        closedSession.closeFallbackTask?.cancel()
        closedSession.session.commitsOnDismiss = closedSession.closeDisposition == .commit

        let finalize: () -> Void = { [weak browserManager = closedSession.browserManager] in
            guard let browserManager else { return }
            browserManager.finalizeWorkspaceThemePickerDismiss(closedSession.session)
        }

        if let coordinator = closedSession.transientCoordinator,
           let transientSessionToken = closedSession.transientSessionToken
        {
            coordinator.finishSession(
                transientSessionToken,
                reason: reason,
                teardown: finalize
            )
        } else {
            finalize()
            Self.performUncoordinatedSidebarDismissRecovery(
                windowState: closedSession.windowState,
                source: closedSession.session.presentationSource,
                anchor: closedSession.session.presentationSource?.originOwnerView,
                using: SidebarHostRecoveryCoordinator.shared
            )
        }
    }

    private func finishWithoutPopover(
        _ session: WorkspaceThemePickerSession,
        windowState: BrowserWindowState,
        browserManager: BrowserManager,
        reason: String
    ) {
        session.commitsOnDismiss = false

        let finalize: () -> Void = { [weak browserManager] in
            guard let browserManager else { return }
            browserManager.finalizeWorkspaceThemePickerDismiss(session)
        }

        if let coordinator = session.presentationSource?.coordinator,
           let transientSessionToken = session.transientSessionToken
        {
            coordinator.finishSession(
                transientSessionToken,
                reason: reason,
                teardown: finalize
            )
        } else {
            finalize()
            Self.performUncoordinatedSidebarDismissRecovery(
                windowState: windowState,
                source: session.presentationSource,
                anchor: session.presentationSource?.originOwnerView,
                using: SidebarHostRecoveryCoordinator.shared
            )
        }
    }

    private func startObservingDismissNotifications() {
        guard !observesDismissNotifications else { return }
        observesDismissNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive(_:)),
            name: NSApplication.willResignActiveNotification,
            object: nil
        )
        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleLocalMouseDown(event)
            }
            return event
        }
    }

    private func stopObservingDismissNotifications() {
        guard observesDismissNotifications else { return }
        observesDismissNotifications = false
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.willResignActiveNotification,
            object: nil
        )
        if let localMouseDownMonitor {
            NSEvent.removeMonitor(localMouseDownMonitor)
            self.localMouseDownMonitor = nil
        }
    }

    @MainActor @objc private func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let activeSession,
              window === activeSession.windowState?.window
        else { return }

        if activeSession.popover.contentViewController?.view.window === NSApp.keyWindow {
            return
        }

        close(sessionID: activeSession.session.id, committing: false)
    }

    @MainActor @objc private func applicationWillResignActive(_: Notification) {
        closeActive(committing: false)
    }

    private func handleLocalMouseDown(_ event: NSEvent) {
        guard let activeSession,
              !activeSession.isClosing,
              let windowState = activeSession.windowState,
              let window = windowState.window,
              let contentView = window.contentView,
              event.window === window
        else { return }

        let pointInContentView = contentView.convert(event.locationInWindow, from: nil)
        let sidebarRect = Self.sidebarDismissRect(
            in: contentView.bounds,
            isSidebarVisible: windowState.isSidebarVisible,
            sidebarWidth: windowState.sidebarWidth,
            savedSidebarWidth: windowState.savedSidebarWidth,
            sidebarPosition: activeSession.browserManager?.sumiSettings?.sidebarPosition ?? .left
        )

        guard sidebarRect.contains(pointInContentView) else { return }
        close(sessionID: activeSession.session.id, committing: true)
    }
}

private struct WorkspaceThemePickerPopoverContent: View {
    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @ObservedObject var session: WorkspaceThemePickerSession

    var body: some View {
        GradientEditorView(
            workspaceTheme: Binding(
                get: { session.draftTheme },
                set: { session.draftTheme = $0 }
            ),
            onThemeChange: { _ in
                browserManager.previewWorkspaceThemePickerDraft(sessionID: session.id)
            }
        )
        .environment(\.resolvedThemeContext, resolvedThemeContext)
        .preferredColorScheme(globalColorScheme)
    }

    private var resolvedThemeContext: ResolvedThemeContext {
        windowState.resolvedThemeContext(
            global: globalColorScheme,
            settings: sumiSettings
        )
    }

    private var globalColorScheme: ColorScheme {
        switch sumiSettings.windowSchemeMode {
        case .auto:
            return ColorScheme(workspaceThemePopoverAppearance: appKitAppearance)
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private var appKitAppearance: NSAppearance {
        windowState.window?.effectiveAppearance ?? NSApplication.shared.effectiveAppearance
    }
}

private final class WorkspaceThemePickerPopoverHostingController: NSViewController {
    private let popoverView: WorkspaceThemePickerPopoverContentView

    init(rootView: AnyView, contentSize: NSSize) {
        self.popoverView = WorkspaceThemePickerPopoverContentView(
            rootView: rootView,
            contentSize: contentSize
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = popoverView
    }
}

private final class WorkspaceThemePickerPopoverContentView: NSView {
    private let hostingView: NSHostingView<AnyView>

    init(rootView: AnyView, contentSize: NSSize) {
        self.hostingView = NSHostingView(rootView: rootView)
        super.init(frame: NSRect(origin: .zero, size: contentSize))
        commonInit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        hostingView.fittingSize
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

private extension ColorScheme {
    init(workspaceThemePopoverAppearance appearance: NSAppearance) {
        let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
        self = bestMatch == .darkAqua ? .dark : .light
    }
}

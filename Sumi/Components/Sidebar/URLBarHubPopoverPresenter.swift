import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class URLBarHubPopoverPresenter: NSObject, NSPopoverDelegate {
    private enum Metrics {
        static let fallbackControlsSize = NSSize(width: 234, height: 250)
        static let maximumHeight: CGFloat = 560
        static let resizeAnimationDuration: TimeInterval = 0.18
        static let closeAnimationFallbackDelay: UInt64 = 350_000_000
    }

    private final class AnchorRegistration {
        weak var view: NSView?
        weak var windowState: BrowserWindowState?
        weak var browserManager: BrowserManager?
        weak var settings: SumiSettingsService?
        var themeContext: ResolvedThemeContext
        var currentTab: Tab?
        var profile: Profile?
        var profileId: UUID?

        init(
            view: NSView,
            windowState: BrowserWindowState,
            browserManager: BrowserManager,
            settings: SumiSettingsService,
            themeContext: ResolvedThemeContext,
            currentTab: Tab?,
            profile: Profile?,
            profileId: UUID?
        ) {
            self.view = view
            self.windowState = windowState
            self.browserManager = browserManager
            self.settings = settings
            self.themeContext = themeContext
            self.currentTab = currentTab
            self.profile = profile
            self.profileId = profileId
        }
    }

    private final class ActiveSession {
        let popover: NSPopover
        let hostingController: NSHostingController<AnyView>
        weak var windowState: BrowserWindowState?
        weak var browserManager: BrowserManager?
        weak var transientCoordinator: SidebarTransientSessionCoordinator?
        let transientSessionToken: SidebarTransientSessionToken?
        var initialMode: URLBarHubInitialMode
        var modeRequestNonce: Int
        var contentSize: NSSize
        var resizeAnimationTask: Task<Void, Never>?
        var closeFallbackTask: Task<Void, Never>?
        var isClosing = false

        init(
            popover: NSPopover,
            hostingController: NSHostingController<AnyView>,
            windowState: BrowserWindowState,
            browserManager: BrowserManager,
            transientCoordinator: SidebarTransientSessionCoordinator?,
            transientSessionToken: SidebarTransientSessionToken?,
            initialMode: URLBarHubInitialMode,
            modeRequestNonce: Int,
            contentSize: NSSize
        ) {
            self.popover = popover
            self.hostingController = hostingController
            self.windowState = windowState
            self.browserManager = browserManager
            self.transientCoordinator = transientCoordinator
            self.transientSessionToken = transientSessionToken
            self.initialMode = initialMode
            self.modeRequestNonce = modeRequestNonce
            self.contentSize = contentSize
        }

        deinit {
            resizeAnimationTask?.cancel()
            closeFallbackTask?.cancel()
        }
    }

    private struct PendingTransientSession {
        let token: SidebarTransientSessionToken
        let source: SidebarTransientPresentationSource
    }

    private var anchors: [UUID: AnchorRegistration] = [:]
    private var activeSessions: [UUID: ActiveSession] = [:]
    private var pendingTransientSessions: [UUID: PendingTransientSession] = [:]
    private var pendingContentSizes: [UUID: NSSize] = [:]
    private var nextModeRequestNonce: Int = 0

    func registerAnchor(
        _ view: NSView,
        windowState: BrowserWindowState,
        browserManager: BrowserManager,
        settings: SumiSettingsService,
        themeContext: ResolvedThemeContext,
        currentTab: Tab?,
        profile: Profile?,
        profileId: UUID?
    ) {
        let registration = AnchorRegistration(
            view: view,
            windowState: windowState,
            browserManager: browserManager,
            settings: settings,
            themeContext: themeContext,
            currentTab: currentTab,
            profile: profile,
            profileId: profileId
        )
        anchors[windowState.id] = registration

        if let session = activeSessions[windowState.id] {
            update(session, using: registration)
        }
    }

    func unregisterAnchor(_ view: NSView, windowID: UUID) {
        guard anchors[windowID]?.view === view else { return }
        close(windowID: windowID)
        anchors[windowID] = nil
        pendingContentSizes[windowID] = nil
    }

    func toggle(
        in windowState: BrowserWindowState,
        browserManager: BrowserManager,
        initialMode: URLBarHubInitialMode = .controls
    ) {
        if activeSessions[windowState.id]?.popover.isShown == true {
            close(in: windowState)
            return
        }

        present(
            in: windowState,
            browserManager: browserManager,
            initialMode: initialMode
        )
    }

    func present(
        in windowState: BrowserWindowState,
        browserManager: BrowserManager,
        initialMode: URLBarHubInitialMode = .controls
    ) {
        if let session = activeSessions[windowState.id],
           let registration = anchors[windowState.id]
        {
            route(session, to: initialMode, using: registration)
            return
        }

        presentOrRetry(
            in: windowState,
            browserManager: browserManager,
            initialMode: initialMode,
            allowRetry: true
        )
    }

    func close(in windowState: BrowserWindowState) {
        close(windowID: windowState.id)
    }

    func isPresented(in windowState: BrowserWindowState) -> Bool {
        activeSessions[windowState.id]?.popover.isShown == true
    }

    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover,
              let windowID = activeSessions.first(where: { $0.value.popover === popover })?.key
        else { return }

        finishClosedSession(windowID: windowID, session: activeSessions[windowID])
    }

    private func presentOrRetry(
        in windowState: BrowserWindowState,
        browserManager: BrowserManager,
        initialMode: URLBarHubInitialMode,
        allowRetry: Bool
    ) {
        guard let registration = anchors[windowState.id],
              let anchorView = registration.view,
              anchorView.window != nil,
              !anchorView.isHiddenOrHasHiddenAncestor,
              anchorView.alphaValue > 0
        else {
            if allowRetry {
                beginPendingTransientSessionIfNeeded(in: windowState)
                Task { @MainActor [weak self, weak windowState, weak browserManager] in
                    await Task.yield()
                    await Task.yield()
                    guard let self, let windowState, let browserManager else { return }
                    self.presentOrRetry(
                        in: windowState,
                        browserManager: browserManager,
                        initialMode: initialMode,
                        allowRetry: false
                    )
                }
            } else {
                finishPendingTransientSession(
                    windowID: windowState.id,
                    reason: "URLBarHubPopoverPresenter.anchorUnavailable"
                )
            }
            return
        }

        nextModeRequestNonce += 1
        let modeRequestNonce = nextModeRequestNonce
        let hostingController = makeHostingController(
            registration: registration,
            initialMode: initialMode,
            modeRequestNonce: modeRequestNonce,
            windowID: windowState.id
        )
        let initialSize = measuredContentSize(
            for: hostingController,
            fallback: fallbackContentSize(for: initialMode)
        )

        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = hostingController
        popover.contentSize = initialSize
        popover.appearance = popoverAppearance(for: registration)
        hostingController.view.frame = NSRect(origin: .zero, size: initialSize)

        let transientSessionToken = takeTransientSession(
            in: windowState,
            anchorView: anchorView
        )

        let session = ActiveSession(
            popover: popover,
            hostingController: hostingController,
            windowState: windowState,
            browserManager: browserManager,
            transientCoordinator: windowState.sidebarTransientSessionCoordinator,
            transientSessionToken: transientSessionToken,
            initialMode: initialMode,
            modeRequestNonce: modeRequestNonce,
            contentSize: initialSize
        )
        activeSessions[windowState.id] = session

        windowState.window?.makeKeyAndOrderFront(nil)
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)

        if let pendingSize = pendingContentSizes.removeValue(forKey: windowState.id) {
            applyContentSize(pendingSize, to: session, animated: false)
        }
    }

    private func close(windowID: UUID) {
        guard let session = activeSessions[windowID] else {
            finishPendingTransientSession(
                windowID: windowID,
                reason: "URLBarHubPopoverPresenter.closePending"
            )
            return
        }

        guard !session.isClosing else { return }

        session.isClosing = true
        session.popover.close()
        session.closeFallbackTask = Task { @MainActor [weak self, weak session] in
            try? await Task.sleep(nanoseconds: Metrics.closeAnimationFallbackDelay)
            guard let self,
                  let session,
                  self.activeSessions[windowID] === session
            else { return }

            self.finishClosedSession(windowID: windowID, session: session)
        }
    }

    private func finishClosedSession(windowID: UUID, session: ActiveSession?) {
        let session = session ?? activeSessions[windowID]
        activeSessions[windowID] = nil
        pendingContentSizes[windowID] = nil

        session?.transientCoordinator?.finishSession(
            session?.transientSessionToken,
            reason: "URLBarHubPopoverPresenter.popoverDidClose"
        )
        finishPendingTransientSession(
            windowID: windowID,
            reason: "URLBarHubPopoverPresenter.finishClosedPending"
        )

        let anchor = anchors[windowID]?.view
        let window = anchor?.window ?? session?.windowState?.window
        SidebarHostRecoveryCoordinator.shared.recover(in: window)
        SidebarHostRecoveryCoordinator.shared.recover(anchor: anchor)
    }

    private func route(
        _ session: ActiveSession,
        to initialMode: URLBarHubInitialMode,
        using registration: AnchorRegistration
    ) {
        nextModeRequestNonce += 1
        session.initialMode = initialMode
        session.modeRequestNonce = nextModeRequestNonce
        update(session, using: registration)
    }

    private func update(
        _ session: ActiveSession,
        using registration: AnchorRegistration
    ) {
        session.popover.appearance = popoverAppearance(for: registration)
        session.hostingController.rootView = rootView(
            registration: registration,
            initialMode: session.initialMode,
            modeRequestNonce: session.modeRequestNonce,
            windowID: registration.windowState?.id
        )
        session.hostingController.view.frame.size = session.contentSize
    }

    private func makeHostingController(
        registration: AnchorRegistration,
        initialMode: URLBarHubInitialMode,
        modeRequestNonce: Int,
        windowID: UUID
    ) -> NSHostingController<AnyView> {
        NSHostingController(
            rootView: rootView(
                registration: registration,
                initialMode: initialMode,
                modeRequestNonce: modeRequestNonce,
                windowID: windowID
            )
        )
    }

    private func rootView(
        registration: AnchorRegistration,
        initialMode: URLBarHubInitialMode,
        modeRequestNonce: Int,
        windowID: UUID?
    ) -> AnyView {
        guard let browserManager = registration.browserManager,
              let windowState = registration.windowState
        else {
            return AnyView(EmptyView())
        }

        let settings = registration.settings ?? SumiSettingsService()
        let colorScheme = popoverColorScheme(for: registration)
        let view = URLBarHubPopover(
            bookmarkManager: browserManager.bookmarkManager,
            bookmarkPresentationRequest: browserManager.bookmarkEditorPresentationRequest,
            currentTab: registration.currentTab,
            profile: registration.profile,
            profileId: registration.profileId,
            initialMode: initialMode,
            modeRequestNonce: modeRequestNonce,
            onClose: { [weak self] in
                guard let windowID else { return }
                self?.close(windowID: windowID)
            },
            onContentSizeChange: { [weak self] size in
                guard let windowID else { return }
                self?.handleContentSizeChange(size, windowID: windowID)
            }
        )
        .environmentObject(browserManager)
        .environmentObject(browserManager.extensionSurfaceStore)
        .environment(windowState)
        .environment(\.sumiSettings, settings)
        .environment(\.resolvedThemeContext, popoverThemeContext(for: registration, colorScheme: colorScheme))
        .environment(\.colorScheme, colorScheme)
        .preferredColorScheme(colorScheme)
        return AnyView(view)
    }

    private func handleContentSizeChange(_ size: CGSize, windowID: UUID) {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 1,
              size.height > 1
        else { return }

        let targetSize = clampedContentSize(NSSize(width: size.width, height: size.height))
        guard let session = activeSessions[windowID] else {
            pendingContentSizes[windowID] = targetSize
            return
        }

        applyContentSize(targetSize, to: session, animated: true)
    }

    private func applyContentSize(
        _ targetSize: NSSize,
        to session: ActiveSession,
        animated: Bool
    ) {
        guard contentSize(session.contentSize, differsFrom: targetSize) else { return }

        session.contentSize = targetSize
        session.hostingController.view.frame.size = targetSize

        guard animated else {
            session.resizeAnimationTask?.cancel()
            session.popover.contentSize = targetSize
            return
        }

        animateContentSizeIfNeeded(session, to: targetSize)
    }

    private func measuredContentSize(
        for controller: NSHostingController<AnyView>,
        fallback: NSSize
    ) -> NSSize {
        let fittingSize = controller.view.fittingSize
        guard fittingSize.width.isFinite,
              fittingSize.height.isFinite,
              fittingSize.width > 1,
              fittingSize.height > 1
        else {
            return fallback
        }

        return clampedContentSize(fittingSize)
    }

    private func fallbackContentSize(for initialMode: URLBarHubInitialMode) -> NSSize {
        switch initialMode {
        case .controls:
            return Metrics.fallbackControlsSize
        }
    }

    private func clampedContentSize(_ size: NSSize) -> NSSize {
        NSSize(
            width: ceil(size.width),
            height: min(ceil(size.height), Metrics.maximumHeight)
        )
    }

    private func contentSize(_ lhs: NSSize, differsFrom rhs: NSSize) -> Bool {
        abs(lhs.width - rhs.width) > 0.5 || abs(lhs.height - rhs.height) > 0.5
    }

    private func animateContentSizeIfNeeded(_ session: ActiveSession, to targetSize: NSSize) {
        let popover = session.popover
        guard contentSize(popover.contentSize, differsFrom: targetSize) else { return }

        session.resizeAnimationTask?.cancel()

        let startSize = popover.contentSize
        session.resizeAnimationTask = Task { @MainActor [weak session, weak popover] in
            let startTime = CACurrentMediaTime()
            let duration = Metrics.resizeAnimationDuration

            while !Task.isCancelled {
                guard let session, let popover else { return }

                let elapsed = CACurrentMediaTime() - startTime
                let rawProgress = min(max(elapsed / duration, 0), 1)
                let easedProgress = rawProgress * rawProgress * (3 - 2 * rawProgress)
                popover.contentSize = NSSize(
                    width: startSize.width + (targetSize.width - startSize.width) * easedProgress,
                    height: startSize.height + (targetSize.height - startSize.height) * easedProgress
                )

                guard rawProgress < 1 else {
                    popover.contentSize = targetSize
                    session.resizeAnimationTask = nil
                    return
                }

                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    private func popoverAppearance(for registration: AnchorRegistration) -> NSAppearance {
        let windowAppearance = registration.view?.window?.effectiveAppearance
            ?? registration.windowState?.window?.effectiveAppearance
            ?? NSApplication.shared.effectiveAppearance
        let windowScheme = ColorScheme(urlHubPopoverAppearance: windowAppearance)
        let preferredScheme = popoverColorScheme(for: registration)

        if windowScheme == preferredScheme {
            return windowAppearance
        }

        let preferredName: NSAppearance.Name = preferredScheme == .dark ? .darkAqua : .aqua
        return NSAppearance(named: preferredName) ?? windowAppearance
    }

    private func popoverColorScheme(for registration: AnchorRegistration) -> ColorScheme {
        registration.themeContext.nativeSurfaceColorScheme
    }

    private func popoverThemeContext(
        for registration: AnchorRegistration,
        colorScheme: ColorScheme
    ) -> ResolvedThemeContext {
        var context = registration.themeContext
        context.globalColorScheme = colorScheme
        context.chromeColorScheme = colorScheme
        context.sourceChromeColorScheme = colorScheme
        context.targetChromeColorScheme = colorScheme
        context.sourceWorkspaceTheme = context.workspaceTheme
        context.targetWorkspaceTheme = context.workspaceTheme
        context.isInteractiveTransition = false
        context.transitionProgress = 1.0
        return context
    }

    private func beginPendingTransientSessionIfNeeded(in windowState: BrowserWindowState) {
        let windowID = windowState.id
        guard pendingTransientSessions[windowID] == nil,
              activeSessions[windowID]?.transientSessionToken == nil
        else { return }

        let source = windowState.sidebarTransientSessionCoordinator.preparedPresentationSource(
            window: windowState.window
        )
        let token = windowState.sidebarTransientSessionCoordinator.beginSession(
            kind: .urlHubPopover,
            source: source,
            path: "URLBarHubPopoverPresenter.waitForAnchor"
        )
        pendingTransientSessions[windowID] = PendingTransientSession(
            token: token,
            source: source
        )
    }

    private func takeTransientSession(
        in windowState: BrowserWindowState,
        anchorView: NSView
    ) -> SidebarTransientSessionToken {
        let windowID = windowState.id
        if let pendingSession = pendingTransientSessions.removeValue(forKey: windowID) {
            pendingSession.source.refresh(
                window: anchorView.window ?? windowState.window,
                originOwnerView: anchorView
            )
            return pendingSession.token
        }

        let source = windowState.sidebarTransientSessionCoordinator.preparedPresentationSource(
            window: anchorView.window ?? windowState.window,
            ownerView: anchorView
        )
        return windowState.sidebarTransientSessionCoordinator.beginSession(
            kind: .urlHubPopover,
            source: source,
            path: "URLBarHubPopoverPresenter.present"
        )
    }

    private func finishPendingTransientSession(windowID: UUID, reason: String) {
        guard let pendingSession = pendingTransientSessions.removeValue(forKey: windowID) else { return }
        pendingSession.source.coordinator?.finishSession(
            pendingSession.token,
            reason: reason
        )
    }
}

struct URLBarHubPopoverAnchorView: NSViewRepresentable {
    let browserManager: BrowserManager
    let windowState: BrowserWindowState
    let settings: SumiSettingsService
    let themeContext: ResolvedThemeContext
    let currentTab: Tab?
    let profile: Profile?
    let profileId: UUID?

    func makeCoordinator() -> Coordinator {
        Coordinator(browserManager: browserManager, windowID: windowState.id)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        register(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.browserManager = browserManager
        context.coordinator.windowID = windowState.id
        register(nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.browserManager?.urlBarHubPopoverPresenter.unregisterAnchor(
            nsView,
            windowID: coordinator.windowID
        )
    }

    private func register(_ view: NSView, coordinator: Coordinator) {
        coordinator.browserManager = browserManager
        coordinator.windowID = windowState.id
        browserManager.urlBarHubPopoverPresenter.registerAnchor(
            view,
            windowState: windowState,
            browserManager: browserManager,
            settings: settings,
            themeContext: themeContext,
            currentTab: currentTab,
            profile: profile,
            profileId: profileId
        )
    }

    final class Coordinator {
        weak var browserManager: BrowserManager?
        var windowID: UUID

        init(browserManager: BrowserManager, windowID: UUID) {
            self.browserManager = browserManager
            self.windowID = windowID
        }
    }
}

private extension ColorScheme {
    init(urlHubPopoverAppearance appearance: NSAppearance) {
        let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
        self = bestMatch == .darkAqua ? .dark : .light
    }
}

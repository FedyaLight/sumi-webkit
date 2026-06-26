import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class URLBarHubPopoverPresenter: NSObject, NSPopoverDelegate {
    private enum Metrics {
        static let fallbackControlsSize = NSSize(width: 234, height: 250)
        static let maximumHeight: CGFloat = 560
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
        let hostingController: NSHostingController<URLBarHubPopoverRootView>
        weak var windowState: BrowserWindowState?
        weak var browserManager: BrowserManager?
        weak var transientCoordinator: SidebarTransientSessionCoordinator?
        let transientSessionToken: SidebarTransientSessionToken?
        var contentSize: NSSize
        var closeFallbackTask: Task<Void, Never>?
        var isClosing = false

        init(
            popover: NSPopover,
            hostingController: NSHostingController<URLBarHubPopoverRootView>,
            windowState: BrowserWindowState,
            browserManager: BrowserManager,
            transientCoordinator: SidebarTransientSessionCoordinator?,
            transientSessionToken: SidebarTransientSessionToken?,
            contentSize: NSSize
        ) {
            self.popover = popover
            self.hostingController = hostingController
            self.windowState = windowState
            self.browserManager = browserManager
            self.transientCoordinator = transientCoordinator
            self.transientSessionToken = transientSessionToken
            self.contentSize = contentSize
        }

        deinit {
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

    func toggle(in windowState: BrowserWindowState, browserManager: BrowserManager) {
        if activeSessions[windowState.id]?.popover.isShown == true {
            close(in: windowState)
            return
        }

        present(
            in: windowState,
            browserManager: browserManager
        )
    }

    func present(in windowState: BrowserWindowState, browserManager: BrowserManager) {
        if let session = activeSessions[windowState.id],
           let registration = anchors[windowState.id]
        {
            update(session, using: registration)
            return
        }

        presentOrRetry(
            in: windowState,
            browserManager: browserManager,
            allowRetry: true
        )
    }

    func close(in windowState: BrowserWindowState) {
        close(windowID: windowState.id)
    }

    func isPresented(in windowState: BrowserWindowState) -> Bool {
        activeSessions[windowState.id]?.popover.isShown == true
    }

    /// URL-bar site-controls anchor used when an extension action button anchor is stale.
    func anchorView(for windowID: UUID) -> NSView? {
        guard let view = anchors[windowID]?.view,
              PopoverPresenterChromeSupport.isAnchorViewReady(
                  view,
                  checkHiddenAncestors: true
              )
        else {
            return nil
        }
        return view
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
        allowRetry: Bool
    ) {
        guard let registration = anchors[windowState.id],
              let anchorView = registration.view,
              PopoverPresenterChromeSupport.isAnchorViewReady(
                  anchorView,
                  checkHiddenAncestors: true
              )
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

        let hostingController = makeHostingController(
            registration: registration,
            windowID: windowState.id
        )
        let initialSize = measuredContentSize(
            for: hostingController,
            fallback: Metrics.fallbackControlsSize
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
        PopoverPresenterChromeSupport.scheduleCloseFallback(task: &session.closeFallbackTask) { [weak self, weak session] in
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

    private func update(
        _ session: ActiveSession,
        using registration: AnchorRegistration
    ) {
        session.popover.appearance = popoverAppearance(for: registration)
        session.hostingController.rootView = rootView(
            registration: registration,
            windowID: registration.windowState?.id
        )
        session.hostingController.view.frame.size = session.contentSize
    }

    private func makeHostingController(
        registration: AnchorRegistration,
        windowID: UUID
    ) -> NSHostingController<URLBarHubPopoverRootView> {
        NSHostingController(
            rootView: rootView(
                registration: registration,
                windowID: windowID
            )
        )
    }

    private func rootView(
        registration: AnchorRegistration,
        windowID: UUID?
    ) -> URLBarHubPopoverRootView {
        let colorScheme = popoverColorScheme(for: registration)
        return URLBarHubPopoverRootView(
            browserManager: registration.browserManager,
            windowState: registration.windowState,
            settings: registration.settings ?? SumiSettingsService(),
            themeContext: popoverThemeContext(for: registration, colorScheme: colorScheme),
            colorScheme: colorScheme,
            currentTab: registration.currentTab,
            profile: registration.profile,
            profileId: registration.profileId,
            onClose: { [weak self] in
                guard let windowID else { return }
                self?.close(windowID: windowID)
            },
            onContentSizeChange: { [weak self] size in
                guard let windowID else { return }
                self?.handleContentSizeChange(size, windowID: windowID)
            }
        )
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
            session.popover.contentSize = targetSize
            return
        }

        animateContentSizeIfNeeded(session, to: targetSize)
    }

    private func measuredContentSize(
        for controller: NSHostingController<URLBarHubPopoverRootView>,
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

        PopoverPresenterChromeSupport.animateContentSize(
            popover: popover,
            to: targetSize
        )
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
        PopoverPresenterChromeSupport.themeContext(registration.themeContext, colorScheme: colorScheme)
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

private struct URLBarHubPopoverRootView: View {
    let browserManager: BrowserManager?
    let windowState: BrowserWindowState?
    let settings: SumiSettingsService
    let themeContext: ResolvedThemeContext
    let colorScheme: ColorScheme
    let currentTab: Tab?
    let profile: Profile?
    let profileId: UUID?
    let onClose: () -> Void
    let onContentSizeChange: (CGSize) -> Void

    var body: some View {
        if let browserManager, let windowState {
            URLBarHubPopover(
                bookmarkManager: browserManager.bookmarkManager,
                bookmarkPresentationRequest: browserManager.bookmarkEditorPresentationRequest,
                currentTab: currentTab,
                profile: profile,
                profileId: profileId,
                onClose: onClose,
                onContentSizeChange: onContentSizeChange
            )
            .environmentObject(browserManager)
            .environmentObject(browserManager.extensionSurfaceStore)
            .environment(windowState)
            .environment(\.sumiSettings, settings)
            .environment(\.resolvedThemeContext, themeContext)
            .environment(\.colorScheme, colorScheme)
            .preferredColorScheme(colorScheme)
        } else {
            EmptyView()
        }
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

import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class DownloadsPopoverPresenter: NSObject, NSPopoverDelegate {
    private enum Metrics {
        static let width: CGFloat = 360
        static let rowHeight: CGFloat = 52
        static let rowAreaPadding: CGFloat = 18
        static let singleSlotRowArea: CGFloat = rowHeight + rowAreaPadding
        static let maximumRowsHeight: CGFloat = 330
        static let footerHeight: CGFloat = 52
        static let maximumHeight: CGFloat = 390
        static let resizeAnimationDuration: TimeInterval = 0.18
        static let closeAnimationFallbackDelay: UInt64 = 350_000_000
    }

    private final class AnchorRegistration {
        weak var view: NSView?
        weak var windowState: BrowserWindowState?
        weak var browserManager: BrowserManager?
        weak var settings: SumiSettingsService?
        var themeContext: ResolvedThemeContext

        init(
            view: NSView,
            windowState: BrowserWindowState,
            browserManager: BrowserManager,
            settings: SumiSettingsService,
            themeContext: ResolvedThemeContext
        ) {
            self.view = view
            self.windowState = windowState
            self.browserManager = browserManager
            self.settings = settings
            self.themeContext = themeContext
        }
    }

    private final class ActiveSession {
        let popover: NSPopover
        let hostingController: NSHostingController<AnyView>
        weak var windowState: BrowserWindowState?
        weak var transientCoordinator: SidebarTransientSessionCoordinator?
        let transientSessionToken: SidebarTransientSessionToken?
        var cancellables = Set<AnyCancellable>()
        var resizeAnimationTask: Task<Void, Never>?
        var closeFallbackTask: Task<Void, Never>?
        var isClosing = false

        init(
            popover: NSPopover,
            hostingController: NSHostingController<AnyView>,
            windowState: BrowserWindowState,
            transientCoordinator: SidebarTransientSessionCoordinator?,
            transientSessionToken: SidebarTransientSessionToken?
        ) {
            self.popover = popover
            self.hostingController = hostingController
            self.windowState = windowState
            self.transientCoordinator = transientCoordinator
            self.transientSessionToken = transientSessionToken
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

    func registerAnchor(
        _ view: NSView,
        windowState: BrowserWindowState,
        browserManager: BrowserManager,
        settings: SumiSettingsService,
        themeContext: ResolvedThemeContext
    ) {
        let registration = AnchorRegistration(
            view: view,
            windowState: windowState,
            browserManager: browserManager,
            settings: settings,
            themeContext: themeContext
        )
        anchors[windowState.id] = registration

        if let session = activeSessions[windowState.id] {
            let size = contentSize(for: browserManager.downloadManager)
            update(
                session,
                using: registration,
                downloadManager: browserManager.downloadManager,
                contentSize: size
            )
        }
    }

    func unregisterAnchor(_ view: NSView, windowID: UUID) {
        guard anchors[windowID]?.view === view else { return }
        close(windowID: windowID)
        anchors[windowID] = nil
    }

    func toggle(in windowState: BrowserWindowState, browserManager: BrowserManager) {
        if activeSessions[windowState.id]?.popover.isShown == true {
            close(in: windowState)
            return
        }

        presentOrRetry(in: windowState, browserManager: browserManager, allowRetry: true)
    }

    func close(in windowState: BrowserWindowState) {
        close(windowID: windowState.id)
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
              anchorView.window != nil,
              !anchorView.isHidden,
              anchorView.alphaValue > 0
        else {
            if allowRetry {
                beginPendingTransientSessionIfNeeded(in: windowState)
                windowState.isDownloadsPopoverPresented = true
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
                finishPendingTransientSession(windowID: windowState.id, reason: "DownloadsPopoverPresenter.anchorUnavailable")
                windowState.isDownloadsPopoverPresented = false
            }
            return
        }

        let hostingController = makeHostingController(
            registration: registration,
            downloadManager: browserManager.downloadManager
        )
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = hostingController
        popover.contentSize = contentSize(for: browserManager.downloadManager)
        popover.appearance = popoverAppearance(for: registration)
        let transientSessionToken = takeTransientSession(
            in: windowState,
            anchorView: anchorView
        )

        let session = ActiveSession(
            popover: popover,
            hostingController: hostingController,
            windowState: windowState,
            transientCoordinator: windowState.sidebarTransientSessionCoordinator,
            transientSessionToken: transientSessionToken
        )
        session.cancellables.insert(
            browserManager.downloadManager.$items.sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshContentSize(for: windowState.id)
                }
            }
        )
        activeSessions[windowState.id] = session

        windowState.isDownloadsPopoverPresented = true
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)
    }

    private func close(windowID: UUID) {
        guard let session = activeSessions[windowID] else {
            finishPendingTransientSession(windowID: windowID, reason: "DownloadsPopoverPresenter.closePending")
            anchors[windowID]?.windowState?.isDownloadsPopoverPresented = false
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

        session?.transientCoordinator?.finishSession(
            session?.transientSessionToken,
            reason: "DownloadsPopoverPresenter.popoverDidClose"
        )
        finishPendingTransientSession(windowID: windowID, reason: "DownloadsPopoverPresenter.finishClosedPending")

        session?.windowState?.isDownloadsPopoverPresented = false
        anchors[windowID]?.windowState?.isDownloadsPopoverPresented = false

        let anchor = anchors[windowID]?.view
        let window = anchor?.window ?? session?.windowState?.window
        SidebarHostRecoveryCoordinator.shared.recover(in: window)
        SidebarHostRecoveryCoordinator.shared.recover(anchor: anchor)
    }

    private func refreshContentSize(for windowID: UUID) {
        guard let session = activeSessions[windowID],
              let registration = anchors[windowID],
              let browserManager = registration.browserManager
        else { return }

        let targetSize = contentSize(for: browserManager.downloadManager)
        update(
            session,
            using: registration,
            downloadManager: browserManager.downloadManager,
            contentSize: targetSize
        )
        animateContentSizeIfNeeded(session, to: targetSize)
    }

    private func update(
        _ session: ActiveSession,
        using registration: AnchorRegistration,
        downloadManager: DownloadManager,
        contentSize: NSSize
    ) {
        session.popover.appearance = popoverAppearance(for: registration)
        session.hostingController.rootView = rootView(
            registration: registration,
            downloadManager: downloadManager,
            contentSize: contentSize
        )
        session.hostingController.view.frame.size = contentSize
    }

    private func makeHostingController(
        registration: AnchorRegistration,
        downloadManager: DownloadManager
    ) -> NSHostingController<AnyView> {
        let contentSize = contentSize(for: downloadManager)
        let controller = NSHostingController(
            rootView: rootView(
                registration: registration,
                downloadManager: downloadManager,
                contentSize: contentSize
            )
        )
        controller.view.frame = NSRect(origin: .zero, size: contentSize)
        return controller
    }

    private func rootView(
        registration: AnchorRegistration,
        downloadManager: DownloadManager,
        contentSize: NSSize
    ) -> AnyView {
        let settings = registration.settings ?? SumiSettingsService()
        let colorScheme = popoverColorScheme(for: registration)
        return AnyView(
            DownloadsPopoverView(downloadManager: downloadManager)
                .environment(\.sumiSettings, settings)
                .environment(\.resolvedThemeContext, popoverThemeContext(for: registration, colorScheme: colorScheme))
                .environment(\.colorScheme, colorScheme)
                .frame(width: Metrics.width, height: contentSize.height)
        )
    }

    private func popoverAppearance(for registration: AnchorRegistration) -> NSAppearance {
        registration.view?.window?.effectiveAppearance ?? NSApplication.shared.effectiveAppearance
    }

    private func popoverColorScheme(for registration: AnchorRegistration) -> ColorScheme {
        ColorScheme(downloadsPopoverAppearance: popoverAppearance(for: registration))
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

    func contentSize(for downloadManager: DownloadManager) -> NSSize {
        let rowArea: CGFloat
        if downloadManager.items.isEmpty {
            rowArea = Metrics.singleSlotRowArea
        } else {
            rowArea = min(
                CGFloat(downloadManager.items.count) * Metrics.rowHeight + Metrics.rowAreaPadding,
                Metrics.maximumRowsHeight
            )
        }

        let height = min(rowArea + Metrics.footerHeight, Metrics.maximumHeight)
        return NSSize(width: Metrics.width, height: height)
    }

    private func animateContentSizeIfNeeded(_ session: ActiveSession, to targetSize: NSSize) {
        let popover = session.popover
        guard popover.contentSize != targetSize else { return }

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

    private func beginPendingTransientSessionIfNeeded(in windowState: BrowserWindowState) {
        let windowID = windowState.id
        guard pendingTransientSessions[windowID] == nil,
              activeSessions[windowID]?.transientSessionToken == nil
        else { return }

        let source = windowState.sidebarTransientSessionCoordinator.preparedPresentationSource(
            window: windowState.window
        )
        let token = windowState.sidebarTransientSessionCoordinator.beginSession(
            kind: .downloadsPopover,
            source: source,
            path: "DownloadsPopoverPresenter.waitForAnchor"
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
            kind: .downloadsPopover,
            source: source,
            path: "DownloadsPopoverPresenter.present"
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

private extension ColorScheme {
    init(downloadsPopoverAppearance appearance: NSAppearance) {
        let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
        self = bestMatch == .darkAqua ? .dark : .light
    }
}

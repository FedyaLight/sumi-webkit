import AppKit
import SwiftUI

struct FolderSearchPopoverRequest {
    let folderID: UUID
    let folderName: String
    let candidates: [FolderSearchCandidate]
}

struct FolderSearchPopoverPresentationContext {
    let sidebarPosition: SidebarPosition
    let settings: SumiSettingsService
}

@MainActor
final class FolderSearchPopoverPresenter: NSObject, NSPopoverDelegate {
    private final class ActiveSession {
        let id = UUID()
        let folderID: UUID
        let windowID: UUID
        let popover: NSPopover
        let windowState: BrowserWindowState
        let source: SidebarTransientPresentationSource
        let anchorScreenFrame: NSRect?
        let transientSessionToken: SidebarTransientSessionToken?
        var anchorHovered = true
        var popoverHovered = false
        var isClosing = false
        var closeGraceTask: Task<Void, Never>?
        var closeFallbackTask: Task<Void, Never>?
        var notificationObservers: [NSObjectProtocol] = []

        init(
            folderID: UUID,
            windowID: UUID,
            popover: NSPopover,
            windowState: BrowserWindowState,
            source: SidebarTransientPresentationSource,
            anchorScreenFrame: NSRect?,
            transientSessionToken: SidebarTransientSessionToken?
        ) {
            self.folderID = folderID
            self.windowID = windowID
            self.popover = popover
            self.windowState = windowState
            self.source = source
            self.anchorScreenFrame = anchorScreenFrame
            self.transientSessionToken = transientSessionToken
        }
    }

    private var activeSession: ActiveSession?

    func present(
        request: FolderSearchPopoverRequest,
        in windowState: BrowserWindowState,
        themeContext: ResolvedThemeContext,
        presentationContext: FolderSearchPopoverPresentationContext,
        source: SidebarTransientPresentationSource
    ) {
        guard !request.candidates.isEmpty,
              let anchor = resolvedPresentationAnchor(
                source: source,
                in: windowState,
                sidebarPosition: presentationContext.sidebarPosition
              )
        else { return }

        if let activeSession,
           activeSession.folderID == request.folderID,
           activeSession.windowID == windowState.id {
            activeSession.anchorHovered = true
            activeSession.closeGraceTask?.cancel()
            return
        }

        dismissActiveImmediately(reason: "FolderSearchPopoverPresenter.replaceActive")

        let surfaceColorScheme = themeContext.chromeColorScheme
        let surfaceThemeContext = PopoverPresenterChromeSupport.themeContext(
            themeContext,
            colorScheme: surfaceColorScheme
        )
        let contentSize = NSSize(
            width: FolderSearchPopoverMetrics.width,
            height: FolderSearchPopoverMetrics.contentHeight(candidateCount: request.candidates.count)
        )

        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = contentSize
        popover.appearance = PopoverPresenterChromeSupport.appearance(
            for: surfaceColorScheme,
            fallback: anchor.view.window?.effectiveAppearance ?? windowState.window?.effectiveAppearance
        )
        popover.contentViewController = NSHostingController(
            rootView: FolderSearchPopoverView(
                folderName: request.folderName,
                candidates: request.candidates,
                onHoverChanged: { [weak self] hovering in
                    self?.setPopoverHovered(
                        folderID: request.folderID,
                        windowID: windowState.id,
                        hovering: hovering
                    )
                },
                onClose: { [weak self] in
                    self?.closeActive(
                        folderID: request.folderID,
                        windowID: windowState.id
                    )
                }
            )
            .environment(windowState)
            .environment(\.sumiSettings, presentationContext.settings)
            .environment(\.resolvedThemeContext, surfaceThemeContext)
            .environment(\.colorScheme, surfaceColorScheme)
            .preferredColorScheme(surfaceColorScheme)
        )

        let token = source.coordinator?.beginSession(
            kind: .folderSearchPopover,
            source: source,
            path: "FolderSearchPopoverPresenter.present",
            conflictDismiss: { [weak self] in
                self?.closeActive(
                    folderID: request.folderID,
                    windowID: windowState.id
                )
            }
        )

        let session = ActiveSession(
            folderID: request.folderID,
            windowID: windowState.id,
            popover: popover,
            windowState: windowState,
            source: source,
            anchorScreenFrame: screenFrame(for: anchor),
            transientSessionToken: token
        )
        activeSession = session
        installDismissalObservers(for: session)

        windowState.window?.makeKeyAndOrderFront(nil)
        popover.show(
            relativeTo: anchor.rect,
            of: anchor.view,
            preferredEdge: anchor.preferredEdge
        )
    }

    func setAnchorHovered(
        folderID: UUID,
        in windowState: BrowserWindowState,
        hovering: Bool
    ) {
        guard let activeSession,
              activeSession.folderID == folderID,
              activeSession.windowID == windowState.id
        else { return }

        activeSession.anchorHovered = hovering
        if hovering {
            activeSession.closeGraceTask?.cancel()
        } else {
            scheduleCloseIfNeeded(activeSession)
        }
    }

    func closeActive(
        folderID: UUID,
        windowID: UUID
    ) {
        guard let activeSession,
              activeSession.folderID == folderID,
              activeSession.windowID == windowID
        else { return }
        closeActiveSession(activeSession, reason: "FolderSearchPopoverPresenter.closeActive")
    }

    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover,
              let activeSession,
              activeSession.popover === popover
        else { return }

        finishClosedSession(activeSession, reason: "FolderSearchPopoverPresenter.popoverDidClose")
    }

    private func setPopoverHovered(
        folderID: UUID,
        windowID: UUID,
        hovering: Bool
    ) {
        guard let activeSession,
              activeSession.folderID == folderID,
              activeSession.windowID == windowID
        else { return }

        activeSession.popoverHovered = hovering
        if hovering {
            activeSession.closeGraceTask?.cancel()
        } else {
            scheduleCloseIfNeeded(activeSession)
        }
    }

    private func scheduleCloseIfNeeded(_ activeSession: ActiveSession) {
        activeSession.closeGraceTask?.cancel()
        activeSession.closeGraceTask = Task { @MainActor [weak self, weak activeSession] in
            try? await Task.sleep(nanoseconds: FolderSearchPopoverPolicy.closeGraceNanoseconds)
            guard let self,
                  let activeSession,
                  self.activeSession === activeSession
            else { return }

            let currentHoverState = self.currentPointerHoverState(for: activeSession)
            activeSession.anchorHovered = currentHoverState.anchor
            activeSession.popoverHovered = currentHoverState.popover

            guard !currentHoverState.anchor,
                  !currentHoverState.popover
            else { return }

            self.closeActiveSession(
                activeSession,
                reason: "FolderSearchPopoverPresenter.closeGrace"
            )
        }
    }

    private func currentPointerHoverState(
        for activeSession: ActiveSession
    ) -> (anchor: Bool, popover: Bool) {
        (
            anchor: viewContainsCurrentPointer(activeSession.source.originOwnerView)
                || screenFrameContainsCurrentPointer(activeSession.anchorScreenFrame),
            popover: popoverContainsCurrentPointer(activeSession.popover)
        )
    }

    private func screenFrameContainsCurrentPointer(_ screenFrame: NSRect?) -> Bool {
        guard let screenFrame else { return false }
        return screenFrame.contains(NSEvent.mouseLocation)
    }

    private func popoverContainsCurrentPointer(_ popover: NSPopover) -> Bool {
        guard let view = popover.contentViewController?.view,
              let window = view.window,
              PopoverPresenterChromeSupport.isAnchorViewReady(view, checkHiddenAncestors: true)
        else { return false }

        if window.frame.contains(NSEvent.mouseLocation) {
            return true
        }

        let localPoint = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return view.bounds.contains(localPoint)
    }

    private func viewContainsCurrentPointer(_ view: NSView?) -> Bool {
        guard let view,
              let window = view.window,
              PopoverPresenterChromeSupport.isAnchorViewReady(view, checkHiddenAncestors: true)
        else { return false }

        let localPoint = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return view.bounds.contains(localPoint)
    }

    private func screenFrame(
        for anchor: (view: NSView, rect: NSRect, preferredEdge: NSRectEdge)
    ) -> NSRect? {
        guard let window = anchor.view.window else { return nil }
        let windowRect = anchor.view.convert(anchor.rect, to: nil)
        return window.convertToScreen(windowRect)
    }

    private func closeActiveSession(
        _ activeSession: ActiveSession,
        reason: String
    ) {
        guard !activeSession.isClosing else { return }
        activeSession.isClosing = true
        activeSession.closeGraceTask?.cancel()

        PopoverPresenterChromeSupport.closePopoverWithFallback(
            popover: activeSession.popover,
            closeFallbackTask: &activeSession.closeFallbackTask,
            onFallback: { [weak self, weak activeSession] in
                guard let self,
                      let activeSession,
                      self.activeSession === activeSession
                else { return }

                self.finishClosedSession(
                    activeSession,
                    reason: "\(reason).fallback"
                )
            },
            onNotShown: { [weak self, weak activeSession] in
                guard let self,
                      let activeSession
                else { return }
                self.finishClosedSession(activeSession, reason: "\(reason).notShown")
            }
        )
    }

    private func dismissActiveImmediately(reason: String) {
        guard let activeSession else { return }
        self.activeSession = nil
        removeNotificationObservers(for: activeSession)
        activeSession.closeGraceTask?.cancel()
        activeSession.closeFallbackTask?.cancel()
        if activeSession.popover.isShown {
            activeSession.popover.close()
        }
        finishSession(activeSession, reason: reason)
    }

    private func finishClosedSession(
        _ closedSession: ActiveSession,
        reason: String
    ) {
        guard activeSession === closedSession else { return }

        activeSession = nil
        removeNotificationObservers(for: closedSession)
        closedSession.closeGraceTask?.cancel()
        closedSession.closeFallbackTask?.cancel()
        finishSession(closedSession, reason: reason)
    }

    private func installDismissalObservers(for activeSession: ActiveSession) {
        let center = NotificationCenter.default
        var observers: [NSObjectProtocol] = []
        let sessionID = activeSession.id

        observers.append(
            center.addObserver(
                forName: .sumiShouldHideCollapsedSidebarOverlay,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.closeIfActive(
                        sessionID: sessionID,
                        reason: "FolderSearchPopoverPresenter.collapsedSidebarOverlayHidden"
                    )
                }
            }
        )
        observers.append(
            center.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: NSApp,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.closeIfActive(
                        sessionID: sessionID,
                        reason: "FolderSearchPopoverPresenter.applicationResignedActive"
                    )
                }
            }
        )
        observers.append(
            center.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: NSApp,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.closeIfActive(
                        sessionID: sessionID,
                        reason: "FolderSearchPopoverPresenter.applicationWillTerminate"
                    )
                }
            }
        )
        if let window = activeSession.windowState.window ?? activeSession.source.window {
            observers.append(
                center.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: nil
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.closeIfActive(
                            sessionID: sessionID,
                            reason: "FolderSearchPopoverPresenter.windowWillClose"
                        )
                    }
                }
            )
        }

        activeSession.notificationObservers = observers
    }

    private func removeNotificationObservers(for activeSession: ActiveSession) {
        let observers = activeSession.notificationObservers
        activeSession.notificationObservers = []
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private func closeIfActive(
        sessionID: UUID,
        reason: String
    ) {
        guard let activeSession,
              activeSession.id == sessionID
        else { return }

        closeActiveSession(activeSession, reason: reason)
    }

    private func finishSession(
        _ session: ActiveSession,
        reason: String
    ) {
        if let coordinator = session.source.coordinator {
            coordinator.finishSession(
                session.transientSessionToken,
                reason: reason
            )
        } else {
            WorkspaceThemePickerPopoverPresenter.performUncoordinatedSidebarDismissRecovery(
                windowState: session.windowState,
                source: session.source,
                anchor: session.source.originOwnerView,
                using: SidebarHostRecoveryCoordinator.shared
            )
        }
    }

    private func resolvedPresentationAnchor(
        source: SidebarTransientPresentationSource,
        in windowState: BrowserWindowState,
        sidebarPosition: SidebarPosition
    ) -> (view: NSView, rect: NSRect, preferredEdge: NSRectEdge)? {
        let preferredEdge: NSRectEdge = sidebarPosition == .left ? .maxX : .minX

        if let ownerView = source.originOwnerView,
           PopoverPresenterChromeSupport.isAnchorViewReady(ownerView, checkHiddenAncestors: true) {
            return (ownerView, ownerView.bounds, preferredEdge)
        }

        guard let contentView = windowState.window?.contentView ?? source.window?.contentView else {
            return nil
        }

        return (
            contentView,
            WorkspaceThemePickerPopoverPresenter.fallbackAnchorRect(
                in: contentView.bounds,
                isSidebarVisible: windowState.isSidebarVisible,
                sidebarWidth: windowState.sidebarWidth,
                savedSidebarWidth: windowState.savedSidebarWidth,
                sidebarPosition: sidebarPosition
            ),
            preferredEdge
        )
    }
}

import AppKit
import SwiftUI

@MainActor
final class ShortcutEditorPopoverPresenter: NSObject, NSPopoverDelegate {
    enum Metrics {
        static let contentSize = NSSize(width: 360, height: 156)
    }

    private final class ActiveSession {
        let editorSession: ShortcutLinkEditorSession
        let popover: NSPopover
        weak var windowState: BrowserWindowState?
        weak var browserManager: BrowserManager?
        let source: SidebarTransientPresentationSource
        let transientSessionToken: SidebarTransientSessionToken?
        var closeFallbackTask: Task<Void, Never>?
        var isClosing = false

        init(
            editorSession: ShortcutLinkEditorSession,
            popover: NSPopover,
            windowState: BrowserWindowState,
            browserManager: BrowserManager,
            source: SidebarTransientPresentationSource,
            transientSessionToken: SidebarTransientSessionToken?
        ) {
            self.editorSession = editorSession
            self.popover = popover
            self.windowState = windowState
            self.browserManager = browserManager
            self.source = source
            self.transientSessionToken = transientSessionToken
        }

        deinit {
            closeFallbackTask?.cancel()
        }
    }

    private var activeSession: ActiveSession?

    func present(
        pin: ShortcutPin,
        in windowState: BrowserWindowState,
        browserManager: BrowserManager,
        themeContext: ResolvedThemeContext,
        source: SidebarTransientPresentationSource
    ) {
        if activeSession != nil {
            closeActive(committing: true)
            return
        }

        guard let anchor = resolvedPresentationAnchor(
            source: source,
            in: windowState,
            sidebarPosition: browserManager.sumiSettings?.sidebarPosition ?? .left
        ) else {
            return
        }

        let editorSession = ShortcutLinkEditorSession(pin: pin)
        let surfaceThemeContext = themeContext.nativeSurfaceThemeContext
        let surfaceColorScheme = surfaceThemeContext.nativeSurfaceColorScheme
        let hostingController = NSHostingController(
            rootView: ShortcutLinkEditorSheet(
                session: editorSession,
                onDone: { [weak self] in
                    self?.closeActive(committing: true)
                },
                onCancel: { [weak self, weak editorSession] in
                    editorSession?.cancelsOnDismiss = true
                    self?.closeActive(committing: false)
                }
            )
            .environment(windowState)
            .environment(\.sumiSettings, browserManager.sumiSettings ?? SumiSettingsService())
            .environment(\.resolvedThemeContext, surfaceThemeContext)
            .environment(\.colorScheme, surfaceColorScheme)
            .preferredColorScheme(surfaceColorScheme)
            .frame(
                width: Self.Metrics.contentSize.width,
                height: Self.Metrics.contentSize.height
            )
        )

        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = hostingController
        popover.contentSize = Self.Metrics.contentSize
        popover.appearance = PopoverPresenterChromeSupport.appearance(
            for: surfaceColorScheme,
            fallback: anchor.view.window?.effectiveAppearance ?? windowState.window?.effectiveAppearance
        )

        let token = source.coordinator?.beginSession(
            kind: .shortcutEditorPopover,
            source: source,
            path: "ShortcutEditorPopoverPresenter.present"
        )

        activeSession = ActiveSession(
            editorSession: editorSession,
            popover: popover,
            windowState: windowState,
            browserManager: browserManager,
            source: source,
            transientSessionToken: token
        )

        windowState.window?.makeKeyAndOrderFront(nil)
        popover.show(
            relativeTo: anchor.rect,
            of: anchor.view,
            preferredEdge: anchor.preferredEdge
        )
    }

    func closeActive(committing: Bool) {
        guard let activeSession else { return }
        activeSession.editorSession.cancelsOnDismiss = !committing
        closeActiveSession(activeSession)
    }

    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover,
              let activeSession,
              activeSession.popover === popover
        else { return }

        finishClosedSession(activeSession, reason: "ShortcutEditorPopoverPresenter.popoverDidClose")
    }

    private func closeActiveSession(_ activeSession: ActiveSession) {
        guard !activeSession.isClosing else { return }
        activeSession.isClosing = true

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
                    reason: "ShortcutEditorPopoverPresenter.closeFallback"
                )
            },
            onNotShown: { [weak self, weak activeSession] in
                guard let self, let activeSession else { return }
                self.finishClosedSession(activeSession, reason: "ShortcutEditorPopoverPresenter.closeNotShown")
            }
        )
    }

    private func finishClosedSession(
        _ closedSession: ActiveSession,
        reason: String
    ) {
        guard activeSession === closedSession else { return }

        activeSession = nil
        closedSession.closeFallbackTask?.cancel()

        let finalize: () -> Void = { [weak browserManager = closedSession.browserManager] in
            guard let browserManager else { return }
            if !closedSession.editorSession.cancelsOnDismiss {
                browserManager.commitShortcutEditorSession(closedSession.editorSession)
            }
        }

        if let coordinator = closedSession.source.coordinator {
            coordinator.finishSession(
                closedSession.transientSessionToken,
                reason: reason,
                teardown: finalize
            )
        } else {
            finalize()
            WorkspaceThemePickerPopoverPresenter.performUncoordinatedSidebarDismissRecovery(
                windowState: closedSession.windowState,
                source: closedSession.source,
                anchor: closedSession.source.originOwnerView,
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
           ownerView.window != nil,
           ownerView.superview != nil,
           !ownerView.isHiddenOrHasHiddenAncestor,
           ownerView.alphaValue > 0 {
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

@MainActor
extension BrowserManager {
    func showShortcutEditor(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState,
        themeContext: ResolvedThemeContext,
        source: SidebarTransientPresentationSource
    ) {
        shortcutEditorPopoverPresenter.present(
            pin: pin,
            in: windowState,
            browserManager: self,
            themeContext: themeContext,
            source: source
        )
    }

    func commitShortcutEditorSession(_ session: ShortcutLinkEditorSession) {
        guard session.hasChanges,
              let launchURL = session.normalizedURL
        else { return }

        _ = tabManager.updateShortcutPin(
            session.pin,
            title: session.effectiveTitle,
            launchURL: launchURL,
            iconAsset: .some(session.iconAsset)
        )
    }
}

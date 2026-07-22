//
//  SidebarContextMenuController.swift
//  Sumi
//

import AppKit
import SwiftUI

enum SidebarContextMenuPopupReturnPolicy {
    static func finalizationReason(
        didBecomeVisible: Bool,
        didClose: Bool
    ) -> String? {
        if didClose {
            return "popup-return-after-close"
        }

        if !didBecomeVisible {
            return "popup-return-before-open"
        }

        return nil
    }
}

@MainActor
final class SidebarContextMenuController {
    let interactionState: SidebarInteractionState
    let transientSessionCoordinator: SidebarTransientSessionCoordinator
    let sidebarRecoveryCoordinator: SidebarHostRecoveryHandling
    weak var windowState: BrowserWindowState?
    weak var settings: SumiSettingsService?

    private weak var activeOwnerView: NSView?
    private weak var observedWindow: NSWindow?
    private var windowObservers: [NSObjectProtocol] = []
    private var activeRootMenu: NSMenu?
    private var menuEndTrackingObserver: NSObjectProtocol?

    private var activeSessionID: UUID?
    private var activeInteractionToken: SidebarTransientSessionToken?
    private var activeMenuBuilder: SidebarContextMenuBuilder?
    private var activeSessionDidBecomeVisible = false
    private var activeSessionDidClose = false
    private var activeMenuVisibilityChanged: (Bool) -> Void = { _ in }
    private var backgroundEntriesProvider: () -> [SidebarContextMenuEntry] = { [] }
    private var backgroundMenuVisibilityChanged: (Bool) -> Void = { _ in }

    init(
        interactionState: SidebarInteractionState,
        transientSessionCoordinator: SidebarTransientSessionCoordinator,
        sidebarRecoveryCoordinator: SidebarHostRecoveryHandling = SidebarHostRecoveryCoordinator()
    ) {
        self.interactionState = interactionState
        self.transientSessionCoordinator = transientSessionCoordinator
        self.sidebarRecoveryCoordinator = sidebarRecoveryCoordinator
    }

    isolated deinit {
        let center = NotificationCenter.default
        windowObservers.forEach(center.removeObserver)
        if let menuEndTrackingObserver {
            center.removeObserver(menuEndTrackingObserver)
        }
    }

    func configureBackgroundMenu(
        entriesProvider: @escaping () -> [SidebarContextMenuEntry],
        onMenuVisibilityChanged: @escaping (Bool) -> Void
    ) {
        backgroundEntriesProvider = entriesProvider
        backgroundMenuVisibilityChanged = onMenuVisibilityChanged
    }

    func registerInteractiveOwner(_ ownerView: SidebarInteractiveItemView) {
        interactionState.registerInteractiveOwner(ownerView)
    }

    func unregisterInteractiveOwner(_ ownerView: SidebarInteractiveItemView) {
        interactionState.unregisterInteractiveOwner(ownerView)
    }

    func recoverInteractiveOwners(
        in window: NSWindow?,
        source: SidebarTransientPresentationSource?
    ) -> SidebarInteractiveOwnerRecoveryResult {
        let sourceMetadata = source?.interactiveOwnerRecoveryMetadata
        let result = interactionState.recoverInteractiveOwners(
            in: window,
            sourceMetadata: sourceMetadata
        )
        return result
    }

    func ownerViewDidAttach(_ ownerView: NSView) {
        if let ownerView = ownerView as? SidebarInteractiveItemView {
            registerInteractiveOwner(ownerView)
        }
        guard activeOwnerView === ownerView else { return }
        rebindWindow(ownerView.window)
    }

    func ownerViewDidDetach(_ ownerView: NSView) {
        if let ownerView = ownerView as? SidebarInteractiveItemView {
            ownerView.cancelPrimaryMouseTracking()
            unregisterInteractiveOwner(ownerView)
        }
        guard activeOwnerView === ownerView else { return }
        forceCloseActiveSession()
        rebindWindow(nil)
    }

    func presentMenu(
        _ target: SidebarContextMenuResolvedTarget,
        trigger: SidebarContextMenuMouseTrigger,
        event: NSEvent,
        in ownerView: NSView
    ) {
        forceCloseActiveSession()
        activeOwnerView = ownerView
        rebindWindow(ownerView.window)

        let sessionID = UUID()
        activeSessionID = sessionID
        activeMenuVisibilityChanged = target.onMenuVisibilityChanged
        activeSessionDidBecomeVisible = false
        activeSessionDidClose = false
        // Own recovery before entering AppKit menu tracking so pre-open interruptions
        // still unwind through the transient sidebar session coordinator.
        startMenuSession(sessionID: sessionID)

        let builder = SidebarContextMenuBuilder(
            entries: target.entries,
            onMenuWillOpen: { [weak self] in
                self?.markMenuVisible(sessionID: sessionID)
            },
            onMenuDidClose: { [weak self] in
                self?.markMenuClosed(sessionID: sessionID)
            },
            onActionWillDispatch: { [weak self] title, classification in
                self?.transientSessionCoordinator.beginMenuActionDispatch(
                    path: "SidebarContextMenuActionTarget.performAction:\(title)",
                    classification: classification
                )
            },
            onActionDidDrain: { [weak self] title, classification in
                self?.transientSessionCoordinator.finishMenuActionDispatch(
                    path: "SidebarContextMenuActionTarget.performAction:\(title)",
                    classification: classification
                )
            }
        )
        activeMenuBuilder = builder

        let menu = builder.buildMenu()
        if let windowState,
           let window = ownerView.window {
            let globalScheme: ColorScheme = window.effectiveAppearance.name == .darkAqua ? .dark : .light
            if let settings {
                let themeContext = windowState.resolvedThemeContext(global: globalScheme, settings: settings)
                let colorScheme = themeContext.nativeSurfaceColorScheme
                let appearance = NSAppearance.sumiChromeAppearance(
                    for: colorScheme,
                    fallback: window.effectiveAppearance
                )
                menu.sumiApplyAppearance(appearance)
            }
        }
        observeMenuEndTracking(for: menu, sessionID: sessionID)
        let point = ownerView.convert(event.locationInWindow, from: nil)
        switch SidebarContextMenuRoutingPolicy.presentationStyle(for: trigger) {
        case .contextualEvent:
            NSMenu.popUpContextMenu(menu, with: event, for: ownerView)
        case .anchoredPopup:
            menu.popUp(positioning: nil, at: point, in: ownerView)
        }

        builder.forceCloseLifecycleIfNeeded()

        finalizeReturnedMenuSessionIfNeeded(sessionID: sessionID)
    }

    @discardableResult
    func presentTransientMenu(
        entries: [SidebarContextMenuEntry],
        onMenuVisibilityChanged: @escaping (Bool) -> Void = { _ in },
        trigger: SidebarContextMenuMouseTrigger,
        event: NSEvent,
        in ownerView: NSView
    ) -> Bool {
        guard entries.isEmpty == false else { return false }

        presentMenu(
            SidebarContextMenuResolvedTarget(
                entries: entries,
                onMenuVisibilityChanged: onMenuVisibilityChanged
            ),
            trigger: trigger,
            event: event,
            in: ownerView
        )
        return true
    }

    func presentBackgroundMenu(
        trigger: SidebarContextMenuMouseTrigger,
        event: NSEvent,
        in ownerView: NSView
    ) -> Bool {
        let entries = backgroundEntriesProvider()
        guard entries.isEmpty == false else { return false }

        presentMenu(
            SidebarContextMenuResolvedTarget(
                entries: entries,
                onMenuVisibilityChanged: backgroundMenuVisibilityChanged
            ),
            trigger: trigger,
            event: event,
            in: ownerView
        )
        return true
    }

    private func startMenuSession(sessionID: UUID) {
        guard activeSessionID == sessionID, activeInteractionToken == nil else { return }
        transientSessionCoordinator.prepareMenuPresentationSource(ownerView: activeOwnerView)
        activeInteractionToken = transientSessionCoordinator.beginSession(
            kind: .contextMenu,
            source: transientSessionCoordinator.preparedPresentationSource(
                window: activeOwnerView?.window,
                ownerView: activeOwnerView
            ),
            path: "SidebarContextMenuController.startMenuSession",
            preservePendingSource: true
        )
    }

    private func markMenuVisible(sessionID: UUID) {
        guard activeSessionID == sessionID,
              activeInteractionToken != nil,
              !activeSessionDidBecomeVisible
        else { return }

        activeSessionDidBecomeVisible = true
    }

    private func markMenuClosed(sessionID: UUID) {
        guard activeSessionID == sessionID else { return }
        guard activeInteractionToken != nil else { return }
        guard !activeSessionDidClose else { return }

        activeSessionDidClose = true
    }

    private func observeMenuEndTracking(
        for menu: NSMenu,
        sessionID: UUID
    ) {
        removeMenuEndTrackingObserver()
        activeRootMenu = menu

        let center = NotificationCenter.default
        let observedMenuID = ObjectIdentifier(menu)
        menuEndTrackingObserver = center.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: menu,
            queue: .main
        ) { [weak self] notification in
            guard let notifiedMenu = notification.object as AnyObject?,
                  ObjectIdentifier(notifiedMenu) == observedMenuID
            else { return }
            Task { @MainActor [weak self] in
                self?.handleMenuDidEndTracking(sessionID: sessionID)
            }
        }
    }

    private func handleMenuDidEndTracking(sessionID: UUID) {
        guard activeSessionID == sessionID,
              activeRootMenu != nil
        else { return }

        finalizeMenuSession(
            sessionID: sessionID,
            reason: "didEndTracking"
        )
    }

    private func finalizeReturnedMenuSessionIfNeeded(sessionID: UUID) {
        guard activeSessionID == sessionID else { return }
        guard let reason = SidebarContextMenuPopupReturnPolicy.finalizationReason(
            didBecomeVisible: activeSessionDidBecomeVisible,
            didClose: activeSessionDidClose
        ) else { return }

        finalizeMenuSession(
            sessionID: sessionID,
            reason: reason
        )
    }

    private func finalizeMenuSession(
        sessionID: UUID,
        reason _: String
    ) {
        guard activeSessionID == sessionID else { return }

        let visibilityChanged = activeMenuVisibilityChanged
        let shouldNotifyVisibility = activeSessionDidBecomeVisible

        removeMenuEndTrackingObserver()
        transientSessionCoordinator.endSession(activeInteractionToken)
        activeInteractionToken = nil

        if shouldNotifyVisibility {
            scheduleDeferredMenuVisibilityCallbacks(
                visibilityChanged,
                sessionID: sessionID
            )
        }

        clearActiveSession()
    }

    private func scheduleDeferredMenuVisibilityCallbacks(
        _ visibilityChanged: @escaping (Bool) -> Void,
        sessionID _: UUID
    ) {
        // Never mutate SwiftUI row state from NSMenu's tracking loop. AppKit returns
        // from popUp before this runs, so rows can clean up hover visuals without
        // tearing down the menu owner while the menu still tracks events.
        DispatchQueue.main.async {
            visibilityChanged(true)
            visibilityChanged(false)
        }
    }

    private func forceCloseActiveSession() {
        guard let sessionID = activeSessionID else { return }
        activeMenuBuilder?.forceCloseLifecycleIfNeeded()
        finalizeMenuSession(
            sessionID: sessionID,
            reason: "force-close"
        )
    }

    private func clearActiveSession() {
        activeSessionID = nil
        activeOwnerView = nil
        activeMenuBuilder = nil
        activeRootMenu = nil
        activeSessionDidBecomeVisible = false
        activeSessionDidClose = false
        activeInteractionToken = nil
        activeMenuVisibilityChanged = { _ in }
    }

    private func rebindWindow(_ window: NSWindow?) {
        guard observedWindow !== window else { return }

        if observedWindow != nil || window != nil {
            forceCloseActiveSession()
        }

        removeWindowObservers()
        observedWindow = window

        guard let window else { return }

        let center = NotificationCenter.default
        windowObservers = [
            center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleWindowTeardown()
                }
            },
        ]
    }

    private func removeWindowObservers() {
        let center = NotificationCenter.default
        windowObservers.forEach(center.removeObserver)
        windowObservers.removeAll()
    }

    private func removeMenuEndTrackingObserver() {
        if let menuEndTrackingObserver {
            NotificationCenter.default.removeObserver(menuEndTrackingObserver)
            self.menuEndTrackingObserver = nil
        }
        activeRootMenu = nil
    }

    private func handleWindowTeardown() {
        let ownerView = activeOwnerView
        forceCloseActiveSession()
        if let ownerView {
            sidebarRecoveryCoordinator.recover(anchor: ownerView)
        }
    }
}

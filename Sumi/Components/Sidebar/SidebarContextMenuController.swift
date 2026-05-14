//
//  SidebarContextMenuController.swift
//  Sumi
//

import AppKit
import SwiftUI

@MainActor
@Observable
final class SidebarInteractionState {
    private var activeSessionTokenIDsByKind: [SidebarTransientUIKind: Set<UUID>] = [:]
    private var dragTokenID: UUID?
    private(set) var activePressedSourceID: String?

    var isContextMenuPresented: Bool {
        isKindActive(.contextMenu)
    }

    var freezesSidebarHoverState: Bool {
        activeKinds.contains(where: \.pinsCollapsedSidebar)
    }

    var allowsSidebarSwipeCapture: Bool {
        activeKinds.isEmpty
    }

    var allowsSidebarDragSourceHitTesting: Bool {
        activeKinds.contains(where: \.blocksSidebarDragSources) == false
    }

    var activeKindsDescription: String {
        let values = activeKinds.map(\.rawValue).sorted()
        return values.isEmpty ? "none" : values.joined(separator: ",")
    }

    func beginPressedSource(_ sourceID: String?) {
        guard let sourceID else { return }
        activePressedSourceID = sourceID
    }

    func endPressedSource(_ sourceID: String?) {
        guard activePressedSourceID != nil else { return }
        if let sourceID, activePressedSourceID != sourceID {
            return
        }
        activePressedSourceID = nil
    }

    func beginSession(kind: SidebarTransientUIKind, tokenID: UUID) {
        var tokens = activeSessionTokenIDsByKind[kind] ?? []
        tokens.insert(tokenID)
        activeSessionTokenIDsByKind[kind] = tokens
    }

    func endSession(kind: SidebarTransientUIKind, tokenID: UUID) {
        guard var tokens = activeSessionTokenIDsByKind[kind] else { return }
        tokens.remove(tokenID)
        if tokens.isEmpty {
            activeSessionTokenIDsByKind.removeValue(forKey: kind)
        } else {
            activeSessionTokenIDsByKind[kind] = tokens
        }
    }

    func syncSidebarItemDrag(_ isDragging: Bool) {
        if isDragging {
            guard dragTokenID == nil else { return }
            activePressedSourceID = nil
            let tokenID = UUID()
            dragTokenID = tokenID
            beginSession(kind: .drag, tokenID: tokenID)
            return
        }

        guard let dragTokenID else { return }
        endSession(kind: .drag, tokenID: dragTokenID)
        self.dragTokenID = nil
    }

    func reconcileSessions(_ activeTokenIDsByKind: [SidebarTransientUIKind: Set<UUID>]) {
        activeSessionTokenIDsByKind = activeTokenIDsByKind.filter { !$0.value.isEmpty }
        if let dragTokenID,
           activeSessionTokenIDsByKind[.drag]?.contains(dragTokenID) != true
        {
            self.dragTokenID = nil
        }
        if freezesSidebarHoverState {
            activePressedSourceID = nil
        }
    }

    private var activeKinds: Set<SidebarTransientUIKind> {
        Set(activeSessionTokenIDsByKind.keys)
    }

    private func isKindActive(_ kind: SidebarTransientUIKind) -> Bool {
        activeSessionTokenIDsByKind[kind]?.isEmpty == false
    }
}

@MainActor
final class SidebarInteractiveOwnerRegistry {
    private struct WeakOwner {
        weak var view: SidebarInteractiveItemView?
    }

    private var ownersByID: [ObjectIdentifier: WeakOwner] = [:]
    private var ownerOrder: [ObjectIdentifier] = []

    func register(_ owner: SidebarInteractiveItemView) {
        let id = ObjectIdentifier(owner)
        ownersByID[id] = WeakOwner(view: owner)
        ownerOrder.removeAll { $0 == id }
        ownerOrder.append(id)
        pruneStaleOwners()
    }

    func unregister(_ owner: SidebarInteractiveItemView) {
        let id = ObjectIdentifier(owner)
        ownersByID[id] = nil
        ownerOrder.removeAll { $0 == id }
    }

    func owner(
        at windowPoint: NSPoint,
        in window: NSWindow?,
        eventType: NSEvent.EventType?,
        hostedSidebarView: NSView? = nil
    ) -> SidebarInteractiveItemView? {
        pruneStaleOwners()

        var bestCandidate: (
            owner: SidebarInteractiveItemView,
            priority: Int,
            depth: Int,
            orderIndex: Int
        )?

        for (orderIndex, id) in ownerOrder.enumerated() {
            guard let owner = ownersByID[id]?.view,
                  isLive(owner, in: window, hostedSidebarView: hostedSidebarView)
            else { continue }

            let localPoint = owner.convert(windowPoint, from: nil)
            guard owner.bounds.contains(localPoint),
                  owner.shouldCaptureInteraction(at: localPoint, eventType: eventType)
            else { continue }

            let priority = owner.routingPriority(at: localPoint, eventType: eventType)
            let depth = owner.sidebarOwnerHierarchyDepth
            if let current = bestCandidate {
                if priority > current.priority
                    || (priority == current.priority && depth > current.depth)
                    || (priority == current.priority && depth == current.depth && orderIndex > current.orderIndex)
                {
                    bestCandidate = (owner, priority, depth, orderIndex)
                }
            } else {
                bestCandidate = (owner, priority, depth, orderIndex)
            }
        }

        return bestCandidate?.owner
    }

    @discardableResult
    func recoverOwners(
        in window: NSWindow?,
        sourceMetadata: SidebarInteractiveOwnerRecoveryMetadata? = nil
    ) -> SidebarInteractiveOwnerRecoveryResult {
        pruneStaleOwners()

        var recoveredCount = 0
        var sourceOwnerResolved = false
        var resolvedOwnerDescription: String?
        var resolutionReason: String?
        for id in ownerOrder {
            guard let owner = ownersByID[id]?.view,
                  isLive(owner, in: window)
            else { continue }

            owner.cancelPrimaryMouseTracking()
            owner.setTransientInteractionEnabled(true)
            SidebarTransientUIHitTestingRecovery.invalidateLayoutChain(from: owner)
            recoveredCount += 1

            if !sourceOwnerResolved,
               let sourceMetadata,
               let resolvedBy = owner.recoveryResolutionReason(matching: sourceMetadata)
            {
                sourceOwnerResolved = true
                resolvedOwnerDescription = owner.recoveryDebugDescription
                resolutionReason = resolvedBy
            }
        }

        return SidebarInteractiveOwnerRecoveryResult(
            recoveredOwnerCount: recoveredCount,
            sourceOwnerResolved: sourceOwnerResolved,
            resolvedOwnerDescription: resolvedOwnerDescription,
            resolutionReason: resolutionReason
        )
    }

    private func pruneStaleOwners() {
        ownerOrder.removeAll { id in
            guard let owner = ownersByID[id]?.view,
                  owner.window != nil,
                  owner.superview != nil
            else {
                ownersByID[id] = nil
                return true
            }
            return false
        }
    }

    private func isLive(
        _ owner: SidebarInteractiveItemView,
        in window: NSWindow?,
        hostedSidebarView: NSView? = nil
    ) -> Bool {
        guard owner.window != nil,
              owner.window === window,
              owner.superview != nil,
              !owner.isHiddenOrHasHiddenAncestor
        else {
            return false
        }
        if let hostedSidebarView,
           owner.isDescendant(of: hostedSidebarView) != true
        {
            return false
        }
        return true
    }
}

private extension NSView {
    var sidebarOwnerHierarchyDepth: Int {
        var depth = 0
        var current = superview
        while let view = current {
            depth += 1
            current = view.superview
        }
        return depth
    }
}

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
    var sidebarRecoveryCoordinator: SidebarHostRecoveryHandling = SidebarHostRecoveryCoordinator.shared

    private let interactiveOwnerRegistry = SidebarInteractiveOwnerRegistry()
    private weak var activeOwnerView: NSView?
    private weak var activePrimaryMouseTrackingOwner: SidebarInteractiveItemView?
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
        transientSessionCoordinator: SidebarTransientSessionCoordinator
    ) {
        self.interactionState = interactionState
        self.transientSessionCoordinator = transientSessionCoordinator
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
        interactiveOwnerRegistry.register(ownerView)
    }

    func unregisterInteractiveOwner(_ ownerView: SidebarInteractiveItemView) {
        endPrimaryMouseTracking(ownerView)
        interactiveOwnerRegistry.unregister(ownerView)
    }

    func interactiveOwner(
        at windowPoint: NSPoint,
        in window: NSWindow?,
        eventType: NSEvent.EventType?,
        hostedSidebarView: NSView? = nil
    ) -> SidebarInteractiveItemView? {
        interactiveOwnerRegistry.owner(
            at: windowPoint,
            in: window,
            eventType: eventType,
            hostedSidebarView: hostedSidebarView
        )
    }

    func prefersOriginalHitOwner(
        _ ownerView: SidebarInteractiveItemView,
        at windowPoint: NSPoint,
        in window: NSWindow?,
        eventType: NSEvent.EventType?,
        hostedSidebarView: NSView? = nil
    ) -> Bool {
        guard ownerView.window === window,
              ownerView.superview != nil,
              !ownerView.isHiddenOrHasHiddenAncestor
        else {
            return false
        }
        if let hostedSidebarView,
           ownerView.isDescendant(of: hostedSidebarView) != true
        {
            return false
        }

        let localPoint = ownerView.convert(windowPoint, from: nil)
        guard ownerView.bounds.contains(localPoint),
              ownerView.shouldCaptureInteraction(at: localPoint, eventType: eventType)
        else {
            return false
        }
        return true
    }

    func recoverInteractiveOwners(
        in window: NSWindow?,
        source: SidebarTransientPresentationSource?
    ) -> SidebarInteractiveOwnerRecoveryResult {
        if let owner = primaryMouseTrackingOwner(in: window) {
            owner.cancelPrimaryMouseTracking()
        }
        let sourceMetadata = source?.interactiveOwnerRecoveryMetadata
        let result = interactiveOwnerRegistry.recoverOwners(
            in: window,
            sourceMetadata: sourceMetadata
        )
        return result
    }

    func beginPrimaryMouseTracking(_ ownerView: SidebarInteractiveItemView) {
        activePrimaryMouseTrackingOwner = ownerView
    }

    func endPrimaryMouseTracking(_ ownerView: SidebarInteractiveItemView) {
        guard activePrimaryMouseTrackingOwner === ownerView else { return }
        activePrimaryMouseTrackingOwner = nil
    }

    func primaryMouseTrackingOwner(in window: NSWindow?) -> SidebarInteractiveItemView? {
        guard let owner = activePrimaryMouseTrackingOwner,
              owner.window != nil,
              owner.window === window,
              owner.superview != nil,
              !owner.isHiddenOrHasHiddenAncestor
        else {
            return nil
        }
        return owner
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

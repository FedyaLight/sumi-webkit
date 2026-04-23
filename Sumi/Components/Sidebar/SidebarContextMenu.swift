//
//  SpaceContextMenu.swift
//  Sumi
//
//  Created by Aether on 15/11/2025.
//

import AppKit
import SwiftUI

enum SidebarContextMenuRole {
    case normal
    case destructive
}

enum SidebarUITestDragMarker {
    private static let argumentPrefix = "--uitest-sidebar-drag-marker="

    static var markerURL: URL? {
        #if DEBUG
        ProcessInfo.processInfo.arguments.lazy.compactMap { argument -> URL? in
            guard argument.hasPrefix(argumentPrefix) else { return nil }
            let path = String(argument.dropFirst(argumentPrefix.count))
            guard path.isEmpty == false else { return nil }
            return URL(fileURLWithPath: path)
        }.first
        #else
        nil
        #endif
    }

    static func recordDragStart(
        itemID: UUID,
        sourceDescription: @autoclosure () -> String,
        ownerDescription: @autoclosure () -> String,
        sourceID: @autoclosure () -> String? = nil,
        viewDescription: @autoclosure () -> String? = nil
    ) {
        #if DEBUG
            append(
                [
                    "event=startDrag",
                    "item=\(itemID.uuidString)",
                    "sourceID=\(sourceID() ?? "nil")",
                    "source=\(sourceDescription())",
                    "view=\(viewDescription() ?? "nil")",
                    "owner=\(ownerDescription())",
                    "timestamp=\(Date().timeIntervalSince1970)",
                ]
            )
        #else
            _ = itemID
            _ = sourceDescription
            _ = ownerDescription
            _ = sourceID
            _ = viewDescription
        #endif
    }

    static func recordEvent(
        _ name: String,
        dragItemID: UUID?,
        ownerDescription: String,
        sourceID: String? = nil,
        viewDescription: String? = nil,
        details: @autoclosure () -> String
    ) {
        #if DEBUG
            append(
                [
                    "event=\(name)",
                    "dragItem=\(dragItemID?.uuidString ?? "nil")",
                    "sourceID=\(sourceID ?? "nil")",
                    "view=\(viewDescription ?? "nil")",
                    "owner=\(ownerDescription)",
                    "details=\(details())",
                    "timestamp=\(Date().timeIntervalSince1970)",
                ]
            )
        #else
            _ = name
            _ = dragItemID
            _ = ownerDescription
            _ = sourceID
            _ = viewDescription
            _ = details
        #endif
    }

    private static func append(_ fields: [String]) {
        guard let markerURL else { return }
        let message = fields.joined(separator: " ") + "\n"
        if let data = message.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: markerURL)
        {
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
            _ = try? handle.close()
            return
        }
        try? message.write(to: markerURL, atomically: true, encoding: String.Encoding.utf8)
    }
}

func sidebarObjectDebugDescription(_ object: AnyObject?) -> String {
    guard let object else { return "nil" }
    let pointer = Unmanaged.passUnretained(object).toOpaque()
    return "\(String(describing: type(of: object)))@\(pointer)"
}

func sidebarViewDebugDescription(_ view: NSView?) -> String {
    guard let view else { return "nil" }
    return sidebarObjectDebugDescription(view)
}

func sidebarHostedSidebarRoot(from view: NSView?) -> NSView? {
    var current = view
    while let candidate = current {
        if let superview = candidate.superview,
           String(describing: type(of: superview)) == "SidebarColumnContainerView"
        {
            return candidate
        }
        current = candidate.superview
    }
    return nil
}

enum SidebarContextMenuActionClassification: String {
    case presentationOnly
    case stateMutationNonStructural
    case structuralMutation

    var recoveryTier: SidebarRecoveryTier {
        switch self {
        case .presentationOnly, .stateMutationNonStructural:
            return .soft
        case .structuralMutation:
            return .hardRehydrate
        }
    }
}

struct SidebarContextMenuChoice: Identifiable, Equatable {
    let id: UUID
    let title: String
    var isSelected: Bool = false
}

struct SidebarContextMenuAction {
    let title: String
    let systemImage: String?
    let isEnabled: Bool
    let state: NSControl.StateValue
    let role: SidebarContextMenuRole
    let classification: SidebarContextMenuActionClassification
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        isEnabled: Bool = true,
        state: NSControl.StateValue = .off,
        role: SidebarContextMenuRole = .normal,
        classification: SidebarContextMenuActionClassification = .stateMutationNonStructural,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.state = state
        self.role = role
        self.classification = classification
        self.action = action
    }
}

indirect enum SidebarContextMenuEntry {
    case action(SidebarContextMenuAction)
    case submenu(title: String, systemImage: String? = nil, children: [SidebarContextMenuEntry])
    case separator
}

enum SidebarContextMenuSurfaceKind: Equatable {
    case row
    case button
    case background
}

func sidebarContextMenuSurfaceDebugDescription(_ surfaceKind: SidebarContextMenuSurfaceKind) -> String {
    switch surfaceKind {
    case .row:
        return "row"
    case .button:
        return "button"
    case .background:
        return "background"
    }
}

func sidebarPresentationModeDebugDescription(_ mode: SidebarPresentationMode) -> String {
    switch mode {
    case .docked:
        return "docked"
    case .collapsedHidden:
        return "collapsedHidden"
    case .collapsedVisible:
        return "collapsedVisible"
    }
}

struct SidebarContextMenuTriggers: OptionSet {
    let rawValue: Int

    static let leftClick = SidebarContextMenuTriggers(rawValue: 1 << 0)
    static let rightClick = SidebarContextMenuTriggers(rawValue: 1 << 1)
}

enum SidebarContextMenuMouseTrigger {
    case leftMouseDown
    case rightMouseDown
}

enum SidebarContextMenuPresentationStyle: Equatable {
    case contextualEvent
    case anchoredPopup
}

enum SidebarContextMenuRoutingPolicy {
    static func presentationStyle(
        for trigger: SidebarContextMenuMouseTrigger
    ) -> SidebarContextMenuPresentationStyle {
        switch trigger {
        case .rightMouseDown:
            return .contextualEvent
        case .leftMouseDown:
            return .anchoredPopup
        }
    }

    static func shouldIntercept(
        _ trigger: SidebarContextMenuMouseTrigger,
        triggers: SidebarContextMenuTriggers
    ) -> Bool {
        switch trigger {
        case .leftMouseDown:
            triggers.contains(.leftClick)
        case .rightMouseDown:
            triggers.contains(.rightClick)
        }
    }
}

final class SidebarContextMenuBuilder: NSObject, NSMenuDelegate {
    private let entries: [SidebarContextMenuEntry]
    private let onMenuWillOpen: () -> Void
    private let onMenuDidClose: () -> Void
    private let onActionWillDispatch: (String, SidebarContextMenuActionClassification) -> Void
    private let onActionDidDrain: (String, SidebarContextMenuActionClassification) -> Void
    private var actionTargets: [SidebarContextMenuActionTarget] = []
    private var didOpenMenu = false
    private var didCloseMenu = false

    init(
        entries: [SidebarContextMenuEntry],
        onMenuWillOpen: @escaping () -> Void = {},
        onMenuDidClose: @escaping () -> Void = {},
        onActionWillDispatch: @escaping (String, SidebarContextMenuActionClassification) -> Void = { _, _ in },
        onActionDidDrain: @escaping (String, SidebarContextMenuActionClassification) -> Void = { _, _ in }
    ) {
        self.entries = entries
        self.onMenuWillOpen = onMenuWillOpen
        self.onMenuDidClose = onMenuDidClose
        self.onActionWillDispatch = onActionWillDispatch
        self.onActionDidDrain = onActionDidDrain
    }

    func buildMenu() -> NSMenu {
        actionTargets.removeAll()
        didOpenMenu = false
        didCloseMenu = false

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        append(entries, to: menu)

        while menu.items.last?.isSeparatorItem == true {
            menu.removeItem(at: menu.items.count - 1)
        }

        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard !didOpenMenu else { return }
        didOpenMenu = true
        onMenuWillOpen()
    }

    func menuDidClose(_ menu: NSMenu) {
        forceCloseLifecycleIfNeeded()
    }

    func forceCloseLifecycleIfNeeded() {
        guard didOpenMenu, !didCloseMenu else { return }
        didCloseMenu = true
        onMenuDidClose()
    }

    private func append(_ entries: [SidebarContextMenuEntry], to menu: NSMenu) {
        for entry in entries {
            switch entry {
            case .separator:
                guard !menu.items.isEmpty, menu.items.last?.isSeparatorItem == false else { continue }
                menu.addItem(.separator())

            case .submenu(let title, let systemImage, let children):
                let submenu = NSMenu(title: title)
                submenu.autoenablesItems = false
                append(children, to: submenu)
                while submenu.items.last?.isSeparatorItem == true {
                    submenu.removeItem(at: submenu.items.count - 1)
                }
                guard !submenu.items.isEmpty else { continue }

                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.submenu = submenu
                if let systemImage {
                    item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
                }
                menu.addItem(item)

            case .action(let action):
                let target = SidebarContextMenuActionTarget(
                    title: action.title,
                    classification: action.classification,
                    action: action.action,
                    onActionWillDispatch: onActionWillDispatch,
                    onActionDidDrain: onActionDidDrain
                )
                actionTargets.append(target)

                let item = NSMenuItem(
                    title: action.title,
                    action: #selector(SidebarContextMenuActionTarget.performAction),
                    keyEquivalent: ""
                )
                item.target = target
                item.isEnabled = action.isEnabled
                item.state = action.state
                if let systemImage = action.systemImage {
                    item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: action.title)
                }
                if action.role == .destructive {
                    item.attributedTitle = NSAttributedString(
                        string: action.title,
                        attributes: [.foregroundColor: NSColor.systemRed]
                    )
                }
                menu.addItem(item)
            }
        }
    }
}

private final class SidebarContextMenuActionTarget: NSObject {
    private let title: String
    private let classification: SidebarContextMenuActionClassification
    private let action: () -> Void
    private let onActionWillDispatch: (String, SidebarContextMenuActionClassification) -> Void
    private let onActionDidDrain: (String, SidebarContextMenuActionClassification) -> Void

    init(
        title: String,
        classification: SidebarContextMenuActionClassification,
        action: @escaping () -> Void,
        onActionWillDispatch: @escaping (String, SidebarContextMenuActionClassification) -> Void,
        onActionDidDrain: @escaping (String, SidebarContextMenuActionClassification) -> Void
    ) {
        self.title = title
        self.classification = classification
        self.action = action
        self.onActionWillDispatch = onActionWillDispatch
        self.onActionDidDrain = onActionDidDrain
    }

    @objc func performAction() {
        onActionWillDispatch(title, classification)
        DispatchQueue.main.async { [classification, title, action, onActionDidDrain] in
            action()
            DispatchQueue.main.async {
                onActionDidDrain(title, classification)
            }
        }
    }
}

@MainActor
@Observable
final class SidebarInteractionState {
    private var activeSessionTokenIDsByKind: [SidebarTransientUIKind: Set<UUID>] = [:]
    private var dragTokenID: UUID?

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
    private weak var activeRootMenu: NSMenu?
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

    deinit {
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
        RuntimeDiagnostics.emit(
            "🧭 Sidebar interactive owners recovered window=\(window.map { "\($0.windowNumber)" } ?? "nil") expected=\(sourceMetadata?.description ?? "none") count=\(result.recoveredOwnerCount) sourceResolved=\(result.sourceOwnerResolved) resolvedOwner=\(result.resolvedOwnerDescription ?? "nil") resolution=\(result.resolutionReason ?? "none")"
        )
        return result
    }

    func beginPrimaryMouseTracking(_ ownerView: SidebarInteractiveItemView) {
        activePrimaryMouseTrackingOwner = ownerView
        RuntimeDiagnostics.emit(
            "🧭 Sidebar primary tracking began owner=\(ownerView.recoveryDebugDescription) window=\(ownerView.window.map { "\($0.windowNumber)" } ?? "nil")"
        )
    }

    func endPrimaryMouseTracking(_ ownerView: SidebarInteractiveItemView) {
        guard activePrimaryMouseTrackingOwner === ownerView else { return }
        activePrimaryMouseTrackingOwner = nil
        RuntimeDiagnostics.emit(
            "🧭 Sidebar primary tracking ended owner=\(ownerView.recoveryDebugDescription)"
        )
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

    fileprivate func ownerViewDidAttach(_ ownerView: NSView) {
        if let ownerView = ownerView as? SidebarInteractiveItemView {
            registerInteractiveOwner(ownerView)
        }
        guard activeOwnerView === ownerView else { return }
        rebindWindow(ownerView.window)
    }

    fileprivate func ownerViewDidDetach(_ ownerView: NSView) {
        if let ownerView = ownerView as? SidebarInteractiveItemView {
            ownerView.cancelPrimaryMouseTracking()
            unregisterInteractiveOwner(ownerView)
        }
        guard activeOwnerView === ownerView else { return }
        forceCloseActiveSession()
        rebindWindow(nil)
    }

    fileprivate func presentMenu(
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

        // If AppKit never opened the menu, `didEndTracking` will not arrive and the
        // eager session must still unwind immediately.
        if activeSessionID == sessionID,
           !activeSessionDidBecomeVisible
        {
            finalizeMenuSession(
                sessionID: sessionID,
                reason: "popup-return-before-open"
            )
        }
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
        RuntimeDiagnostics.emit(
            "🧭 Sidebar context menu session started id=\(sessionID.uuidString) owner=\(activeOwnerViewDebugDescription)"
        )
    }

    private func markMenuVisible(sessionID: UUID) {
        guard activeSessionID == sessionID,
              activeInteractionToken != nil,
              !activeSessionDidBecomeVisible
        else { return }

        activeSessionDidBecomeVisible = true
        RuntimeDiagnostics.emit(
            "🧭 Sidebar context menu session became visible id=\(sessionID.uuidString) owner=\(activeOwnerViewDebugDescription)"
        )
    }

    private func markMenuClosed(sessionID: UUID) {
        guard activeSessionID == sessionID else { return }
        guard activeInteractionToken != nil else { return }
        guard !activeSessionDidClose else { return }

        activeSessionDidClose = true
        RuntimeDiagnostics.emit(
            "🧭 Sidebar context menu session closed id=\(sessionID.uuidString) owner=\(activeOwnerViewDebugDescription)"
        )
    }

    private func observeMenuEndTracking(
        for menu: NSMenu,
        sessionID: UUID
    ) {
        removeMenuEndTrackingObserver()
        activeRootMenu = menu

        let center = NotificationCenter.default
        menuEndTrackingObserver = center.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: menu,
            queue: .main
        ) { [weak self] notification in
            guard let menu = notification.object as? NSMenu else { return }
            Task { @MainActor [weak self] in
                self?.handleMenuDidEndTracking(menu, sessionID: sessionID)
            }
        }
    }

    private func handleMenuDidEndTracking(
        _ menu: NSMenu,
        sessionID: UUID
    ) {
        guard activeSessionID == sessionID,
              activeRootMenu === menu
        else { return }

        finalizeMenuSession(
            sessionID: sessionID,
            reason: "didEndTracking"
        )
    }

    private func finalizeMenuSession(
        sessionID: UUID,
        reason: String
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

        RuntimeDiagnostics.emit(
            "🧭 Sidebar context menu session finalized id=\(sessionID.uuidString) reason=\(reason) visible=\(activeSessionDidBecomeVisible) closed=\(activeSessionDidClose) owner=\(activeOwnerViewDebugDescription)"
        )
        clearActiveSession()
    }

    private var activeOwnerViewDebugDescription: String {
        guard let activeOwnerView else { return "nil" }
        if let ownerView = activeOwnerView as? SidebarInteractiveItemView {
            return ownerView.recoveryDebugDescription
        }
        return String(describing: type(of: activeOwnerView))
    }

    private func scheduleDeferredMenuVisibilityCallbacks(
        _ visibilityChanged: @escaping (Bool) -> Void,
        sessionID: UUID
    ) {
        // Never mutate SwiftUI row state from NSMenu's tracking loop. AppKit returns
        // from popUp before this runs, so rows can clean up hover visuals without
        // tearing down the menu owner while the menu still tracks events.
        DispatchQueue.main.async {
            RuntimeDiagnostics.emit(
                "🧭 Sidebar context menu visibility callbacks deferred id=\(sessionID.uuidString)"
            )
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

struct SidebarContextMenuLeafConfiguration {
    let isEnabled: Bool
    let surfaceKind: SidebarContextMenuSurfaceKind
    let triggers: SidebarContextMenuTriggers
    let entries: () -> [SidebarContextMenuEntry]
    let onMenuVisibilityChanged: (Bool) -> Void
}

struct SidebarAppKitItemConfiguration {
    var isInteractionEnabled: Bool = true
    var menu: SidebarContextMenuLeafConfiguration? = nil
    var dragSource: SidebarDragSourceConfiguration? = nil
    var primaryAction: (() -> Void)? = nil
    var onMiddleClick: (() -> Void)? = nil
    var sourceID: String? = nil
    var presentationMode: SidebarPresentationMode = .docked

    var surfaceKind: SidebarContextMenuSurfaceKind {
        menu?.surfaceKind ?? .row
    }
}

private struct SidebarContextMenuResolvedTarget {
    let entries: [SidebarContextMenuEntry]
    let onMenuVisibilityChanged: (Bool) -> Void
}

@MainActor
final class SidebarInteractiveItemView: NSView, NSDraggingSource, SidebarTransientInteractionDisarmable {
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private let dragThreshold: CGFloat = 3

    weak var contextMenuController: SidebarContextMenuController? {
        didSet {
            guard oldValue !== contextMenuController else { return }
            oldValue?.ownerViewDidDetach(self)
            contextMenuController?.ownerViewDidAttach(self)
        }
    }

    private(set) var isInteractive = true
    private var itemConfiguration = SidebarAppKitItemConfiguration()
    private var mouseDownEvent: NSEvent?
    private var mouseDownPoint: CGPoint?
    private var mouseDownCanStartDrag = false
    private var didStartDrag = false
    private var isTrackingDragGesture = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        contextMenuController?.ownerViewDidAttach(self)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            contextMenuController?.ownerViewDidDetach(self)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func update(rootView: AnyView, configuration: SidebarAppKitItemConfiguration) {
        hostingView.rootView = rootView
        itemConfiguration = configuration
        identifier = configuration.sourceID.map { NSUserInterfaceItemIdentifier($0) }
        if !configuration.supportsPrimaryMouseTracking {
            resetMouseState()
        }
        setTransientInteractionEnabled(true)
        SidebarUITestDragMarker.recordEvent(
            "bridgeUpdate",
            dragItemID: itemConfiguration.dragSource?.item.tabId,
            ownerDescription: recoveryDebugDescription,
            sourceID: itemConfiguration.sourceID,
            viewDescription: debugViewDescription,
            details: "source=\(itemConfiguration.sourceID ?? "nil") surface=\(sidebarContextMenuSurfaceDebugDescription(itemConfiguration.surfaceKind)) mode=\(sidebarPresentationModeDebugDescription(itemConfiguration.presentationMode)) interactive=\(isInteractive) inputEnabled=\(itemConfiguration.isInteractionEnabled) view=\(debugViewDescription) hostedRoot=\(hostedSidebarRootDebugDescription) controller=\(contextMenuControllerDebugDescription)"
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isInteractive, bounds.contains(point) else { return nil }
        let eventType = window?.currentEvent?.type
        let captures = shouldCaptureInteraction(at: point, eventType: eventType)
        if eventType == .leftMouseDown || eventType == .rightMouseDown {
            SidebarUITestDragMarker.recordEvent(
                "hitTest",
                dragItemID: itemConfiguration.dragSource?.item.tabId,
                ownerDescription: recoveryDebugDescription,
                sourceID: itemConfiguration.sourceID,
                viewDescription: debugViewDescription,
                details: "source=\(itemConfiguration.sourceID ?? "nil") event=\(eventType.map(String.init(describing:)) ?? "nil") point=\(Int(point.x)),\(Int(point.y)) captures=\(captures) view=\(debugViewDescription) hostedRoot=\(hostedSidebarRootDebugDescription)"
            )
        }
        if captures {
            return self
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if shouldPresentMenu(trigger: .leftMouseDown, at: point) {
            RuntimeDiagnostics.emit(
                "🧭 Sidebar mouseDown presenting menu owner=\(recoveryDebugDescription) trigger=leftMouseDown point=\(Int(point.x)),\(Int(point.y))"
            )
            presentContextMenu(trigger: .leftMouseDown, event: event)
            return
        }

        let capturesPrimaryAction = shouldCapturePrimaryAction(at: point)
        let capturesDrag = shouldCaptureDrag(at: point)
        SidebarUITestDragMarker.recordEvent(
            "mouseDown",
            dragItemID: itemConfiguration.dragSource?.item.tabId,
            ownerDescription: recoveryDebugDescription,
            sourceID: itemConfiguration.sourceID,
            viewDescription: debugViewDescription,
            details: "source=\(itemConfiguration.sourceID ?? "nil") point=\(Int(point.x)),\(Int(point.y)) capturesPrimary=\(capturesPrimaryAction) capturesDrag=\(capturesDrag) allowsHitTesting=\(allowsTransientDragSourceHitTesting) activeKinds=\(contextMenuController?.interactionState.activeKindsDescription ?? "unknown") mode=\(sidebarPresentationModeDebugDescription(itemConfiguration.presentationMode)) surface=\(sidebarContextMenuSurfaceDebugDescription(itemConfiguration.surfaceKind)) view=\(debugViewDescription) hostedRoot=\(hostedSidebarRootDebugDescription) controller=\(contextMenuControllerDebugDescription)"
        )
        logLeftMouseCapture(
            point: point,
            capturesPrimaryAction: capturesPrimaryAction,
            capturesDrag: capturesDrag
        )

        if capturesPrimaryAction || capturesDrag {
            window?.makeFirstResponder(self)
            mouseDownEvent = event
            mouseDownPoint = point
            mouseDownCanStartDrag = capturesDrag
            didStartDrag = false
            isTrackingDragGesture = true
            contextMenuController?.beginPrimaryMouseTracking(self)
            trackPrimaryMouseEventsIfNeeded(after: event)
            return
        }

        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isInteractive,
              isTrackingDragGesture,
              !didStartDrag,
              let mouseDownPoint
        else {
            super.mouseDragged(with: event)
            return
        }
        guard mouseDownCanStartDrag else { return }

        let point = convert(event.locationInWindow, from: nil)
        let distance = hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y)
        SidebarUITestDragMarker.recordEvent(
            "mouseDragged",
            dragItemID: itemConfiguration.dragSource?.item.tabId,
            ownerDescription: recoveryDebugDescription,
            sourceID: itemConfiguration.sourceID,
            viewDescription: debugViewDescription,
            details: "source=\(itemConfiguration.sourceID ?? "nil") distance=\(String(format: "%.2f", distance)) canStart=\(mouseDownCanStartDrag) allowsHitTesting=\(allowsTransientDragSourceHitTesting) activeKinds=\(contextMenuController?.interactionState.activeKindsDescription ?? "unknown") view=\(debugViewDescription) hostedRoot=\(hostedSidebarRootDebugDescription)"
        )
        guard distance >= dragThreshold else { return }
        RuntimeDiagnostics.emit(
            "🧭 Sidebar mouseDragged starting drag owner=\(recoveryDebugDescription) distance=\(String(format: "%.2f", distance))"
        )
        startDrag(with: mouseDownEvent ?? event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isTrackingDragGesture else {
            super.mouseUp(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let primaryAction = itemConfiguration.primaryAction ?? itemConfiguration.dragSource?.onActivate
        let shouldInvokePrimaryAction = !didStartDrag && shouldCapturePrimaryAction(at: point)
        resetMouseState()
        if shouldInvokePrimaryAction {
            RuntimeDiagnostics.emit(
                "🧭 Sidebar primary click activated owner=\(String(describing: type(of: self)))"
            )
            primaryAction?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard shouldPresentMenu(trigger: .rightMouseDown, at: point) else {
            super.rightMouseDown(with: event)
            return
        }
        presentContextMenu(trigger: .rightMouseDown, event: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard shouldHandleMiddleClick(event, at: point) else {
            super.otherMouseUp(with: event)
            return
        }
        itemConfiguration.onMiddleClick?()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        SidebarDragState.shared.resetInteractionState()
        resetMouseState()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        movedTo screenPoint: NSPoint
    ) {
        guard didStartDrag,
              let location = currentGlobalLocation(fromScreenPoint: screenPoint) else { return }
        updateInternalDragState(at: location)
    }

    func setTransientInteractionEnabled(_ isEnabled: Bool) {
        guard isInteractive != isEnabled else { return }

        if !isEnabled,
           didStartDrag,
           !shouldPreserveSharedDragStateOnTeardown {
            SidebarDragState.shared.resetInteractionState()
        }

        isInteractive = isEnabled
        resetMouseState()
    }

    func cancelPrimaryMouseTracking() {
        resetMouseState()
    }

    func prepareForDismantle() {
        setTransientInteractionEnabled(false)
        itemConfiguration = SidebarAppKitItemConfiguration()
        contextMenuController = nil
        resetMouseState()
    }

    func shouldCaptureInteraction(
        at point: NSPoint,
        eventType: NSEvent.EventType?
    ) -> Bool {
        guard isInteractive, bounds.contains(point) else { return false }

        switch eventType {
        case .leftMouseDown?:
            if shouldPresentMenu(trigger: .leftMouseDown, at: point) {
                return true
            }
            return shouldCapturePrimaryAction(at: point) || shouldCaptureDrag(at: point)
        case .rightMouseDown?:
            return shouldPresentMenu(trigger: .rightMouseDown, at: point)
        case .otherMouseUp?:
            return itemConfiguration.onMiddleClick != nil
        default:
            return false
        }
    }

    func routingPriority(
        at point: NSPoint,
        eventType: NSEvent.EventType?
    ) -> Int {
        guard isInteractive, bounds.contains(point) else { return 0 }

        let inputBonus = itemConfiguration.isInteractionEnabled ? 100 : 0
        switch eventType {
        case .leftMouseDown?:
            if shouldCaptureDrag(at: point) {
                return inputBonus + 30
            }
            if shouldPresentMenu(trigger: .leftMouseDown, at: point) {
                return inputBonus + 20
            }
            if shouldCapturePrimaryAction(at: point) {
                return inputBonus + 10
            }
        case .rightMouseDown?:
            if shouldPresentMenu(trigger: .rightMouseDown, at: point) {
                return inputBonus + 20
            }
        case .otherMouseUp?:
            if itemConfiguration.onMiddleClick != nil {
                return inputBonus + 10
            }
        default:
            break
        }

        return 0
    }

    private func shouldPresentMenu(
        trigger: SidebarContextMenuMouseTrigger,
        at point: NSPoint
    ) -> Bool {
        guard bounds.contains(point),
              let menu = itemConfiguration.menu,
              menu.isEnabled,
              SidebarContextMenuRoutingPolicy.shouldIntercept(trigger, triggers: menu.triggers)
        else {
            return false
        }
        return menu.entries().isEmpty == false
    }

    private func shouldCaptureDrag(at point: NSPoint) -> Bool {
        guard let configuration = itemConfiguration.dragSource,
              configuration.isEnabled,
              allowsTransientDragSourceHitTesting,
              bounds.contains(point)
        else {
            return false
        }

        return !configuration.exclusionZones.contains { $0.contains(point, in: bounds) }
    }

    private func shouldCapturePrimaryAction(at point: NSPoint) -> Bool {
        guard itemConfiguration.primaryAction != nil || itemConfiguration.dragSource?.onActivate != nil,
              bounds.contains(point)
        else {
            return false
        }

        return !isInPrimaryActionExclusionZone(point)
    }

    private func isInPrimaryActionExclusionZone(_ point: NSPoint) -> Bool {
        guard let dragSource = itemConfiguration.dragSource else { return false }
        return dragSource.exclusionZones.contains { $0.contains(point, in: bounds) }
    }

    private func shouldHandleMiddleClick(_ event: NSEvent, at point: NSPoint) -> Bool {
        guard bounds.contains(point),
              event.buttonNumber == 2,
              itemConfiguration.onMiddleClick != nil
        else {
            return false
        }
        return true
    }

    private func presentContextMenu(
        trigger: SidebarContextMenuMouseTrigger,
        event: NSEvent
    ) {
        guard let menu = itemConfiguration.menu else { return }

        RuntimeDiagnostics.emit(
            "🧭 Sidebar present context menu owner=\(recoveryDebugDescription) trigger=\(String(describing: trigger))"
        )

        contextMenuController?.presentMenu(
            SidebarContextMenuResolvedTarget(
                entries: menu.entries(),
                onMenuVisibilityChanged: menu.onMenuVisibilityChanged
            ),
            trigger: trigger,
            event: event,
            in: self
        )
    }

    private func startDrag(with event: NSEvent) {
        guard let configuration = itemConfiguration.dragSource,
              isInteractive,
              configuration.isEnabled,
              allowsTransientDragSourceHitTesting
        else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        guard let previewSession = SidebarDragPreviewSessionFactory.make(
            configuration: configuration,
            sourceSize: bounds.size,
            sourceOffsetFromBottomLeading: point
        ) else { return }

        didStartDrag = true
        let dragLocation = currentGlobalLocation(for: point)
        SidebarDragState.shared.beginInternalDragSession(
            itemId: configuration.item.tabId,
            location: dragLocation,
            previewKind: configuration.previewKind,
            previewAssets: previewSession.previewAssets,
            previewModel: previewSession.previewModel
        )
        RuntimeDiagnostics.emit(
            "🧭 Sidebar drag started owner=\(recoveryDebugDescription) item=\(configuration.item.tabId.uuidString) source=\(sidebarDropZoneDebugDescription(configuration.sourceZone)) isDragging=\(SidebarDragState.shared.isDragging)"
        )
        SidebarUITestDragMarker.recordDragStart(
            itemID: configuration.item.tabId,
            sourceDescription: sidebarDropZoneDebugDescription(configuration.sourceZone),
            ownerDescription: recoveryDebugDescription,
            sourceID: itemConfiguration.sourceID,
            viewDescription: debugViewDescription
        )
        updateInternalDragState(at: dragLocation)

        let dragItem = NSDraggingItem(pasteboardWriter: configuration.item.pasteboardItem())
        let frame = NSRect(
            x: point.x - previewSession.primaryAsset.anchorOffset.x,
            y: point.y - previewSession.primaryAsset.anchorOffset.y,
            width: previewSession.primaryAsset.size.width,
            height: previewSession.primaryAsset.size.height
        )
        dragItem.setDraggingFrame(frame, contents: transparentImage(size: previewSession.primaryAsset.size))

        let session = beginDraggingSession(with: [dragItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    private func currentGlobalLocation(for localPoint: CGPoint) -> CGPoint {
        guard let window else { return localPoint }
        let pointInWindow = convert(localPoint, to: nil)
        let windowHeight = window.contentView?.bounds.height ?? window.frame.height
        return CGPoint(x: pointInWindow.x, y: windowHeight - pointInWindow.y)
    }

    private func currentGlobalLocation(fromScreenPoint screenPoint: NSPoint) -> CGPoint? {
        guard let window else { return nil }
        let pointInWindow = window.convertPoint(fromScreen: screenPoint)
        return currentGlobalLocation(for: convert(pointInWindow, from: nil))
    }

    private func updateInternalDragState(at location: CGPoint) {
        guard let configuration = itemConfiguration.dragSource else { return }
        SidebarDropResolver.updateState(
            location: location,
            state: SidebarDragState.shared,
            draggedItem: configuration.item
        )
    }

    private var shouldPreserveSharedDragStateOnTeardown: Bool {
        guard didStartDrag,
              let dragItemID = itemConfiguration.dragSource?.item.tabId else {
            return false
        }

        let state = SidebarDragState.shared
        return state.isDragging
            && state.isInternalDragSession
            && state.activeDragItemId == dragItemID
    }

    private var allowsTransientDragSourceHitTesting: Bool {
        contextMenuController?.interactionState.allowsSidebarDragSourceHitTesting ?? true
    }

    private func resetMouseState() {
        let hadMouseState = mouseDownEvent != nil
            || mouseDownPoint != nil
            || mouseDownCanStartDrag
            || didStartDrag
            || isTrackingDragGesture
        mouseDownEvent = nil
        mouseDownPoint = nil
        mouseDownCanStartDrag = false
        didStartDrag = false
        isTrackingDragGesture = false
        contextMenuController?.endPrimaryMouseTracking(self)
        if hadMouseState {
            SidebarUITestDragMarker.recordEvent(
                "resetMouseState",
                dragItemID: itemConfiguration.dragSource?.item.tabId,
                ownerDescription: recoveryDebugDescription,
                sourceID: itemConfiguration.sourceID,
                viewDescription: debugViewDescription,
                details: "source=\(itemConfiguration.sourceID ?? "nil") interactive=\(isInteractive) allowsHitTesting=\(allowsTransientDragSourceHitTesting) activeKinds=\(contextMenuController?.interactionState.activeKindsDescription ?? "unknown") view=\(debugViewDescription) hostedRoot=\(hostedSidebarRootDebugDescription) controller=\(contextMenuControllerDebugDescription)"
            )
        }
    }

    private func trackPrimaryMouseEventsIfNeeded(after event: NSEvent) {
        guard event.timestamp > 0,
              let trackingWindow = window,
              event.windowNumber == trackingWindow.windowNumber,
              contextMenuController?.interactionState.isContextMenuPresented != true
        else {
            return
        }

        RuntimeDiagnostics.emit(
            "🧭 Sidebar primary tracking loop started owner=\(String(describing: type(of: self))) window=\(trackingWindow.windowNumber)"
        )
        trackingWindow.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { [weak self, weak trackingWindow] trackedEvent, stop in
            guard let self,
                  let trackingWindow,
                  self.window === trackingWindow,
                  self.superview != nil,
                  self.isTrackingDragGesture,
                  let trackedEvent
            else {
                stop.pointee = true
                return
            }

            switch trackedEvent.type {
            case .leftMouseDragged:
                self.mouseDragged(with: trackedEvent)
                if self.didStartDrag {
                    stop.pointee = true
                }
            case .leftMouseUp:
                self.mouseUp(with: trackedEvent)
                stop.pointee = true
            default:
                break
            }
        }
    }

    private func logLeftMouseCapture(
        point: NSPoint,
        capturesPrimaryAction: Bool,
        capturesDrag: Bool
    ) {
        RuntimeDiagnostics.emit(
            "🧭 Sidebar left-click capture owner=\(recoveryDebugDescription) point=\(Int(point.x)),\(Int(point.y)) inputEnabled=\(itemConfiguration.isInteractionEnabled) primaryAction=\(itemConfiguration.primaryAction != nil) dragEnabled=\(itemConfiguration.dragSource?.isEnabled == true) capturesPrimary=\(capturesPrimaryAction) capturesDrag=\(capturesDrag) activeKinds=\(contextMenuController?.interactionState.activeKindsDescription ?? "unknown")"
        )
    }

    var recoveryMetadata: SidebarInteractiveOwnerRecoveryMetadata {
        SidebarInteractiveOwnerRecoveryMetadata(
            ownerObjectID: ObjectIdentifier(self),
            ownerTypeName: String(describing: type(of: self)),
            dragItemID: itemConfiguration.dragSource?.item.tabId,
            dragSourceZone: itemConfiguration.dragSource?.sourceZone
        )
    }

    var sourceID: String? {
        itemConfiguration.sourceID
    }

    var debugViewDescription: String {
        sidebarViewDebugDescription(self)
    }

    var hostedSidebarRootDebugDescription: String {
        sidebarViewDebugDescription(sidebarHostedSidebarRoot(from: self))
    }

    var contextMenuControllerDebugDescription: String {
        sidebarObjectDebugDescription(contextMenuController)
    }

    var recoveryDebugDescription: String {
        let sourceID = itemConfiguration.sourceID ?? "nil"
        let surface = sidebarContextMenuSurfaceDebugDescription(itemConfiguration.surfaceKind)
        let mode = sidebarPresentationModeDebugDescription(itemConfiguration.presentationMode)
        return "\(recoveryMetadata.description){source=\(sourceID),surface=\(surface),mode=\(mode)}"
    }

    func recoveryResolutionReason(
        matching metadata: SidebarInteractiveOwnerRecoveryMetadata
    ) -> String? {
        if metadata.ownerObjectID == ObjectIdentifier(self) {
            return "objectIdentity"
        }

        guard let dragSource = itemConfiguration.dragSource,
              metadata.dragItemID == dragSource.item.tabId,
              metadata.dragSourceZone == dragSource.sourceZone
        else {
            return nil
        }

        return "dragKey"
    }

}

private extension SidebarAppKitItemConfiguration {
    var supportsPrimaryMouseTracking: Bool {
        primaryAction != nil || dragSource?.isEnabled == true || dragSource?.onActivate != nil
    }
}

private struct SidebarAppKitItemBridge<Content: View>: NSViewRepresentable {
    let content: Content
    let controller: SidebarContextMenuController
    let configuration: SidebarAppKitItemConfiguration

    func makeNSView(context: Context) -> SidebarInteractiveItemView {
        let view = SidebarInteractiveItemView(frame: .zero)
        view.contextMenuController = controller
        view.update(rootView: AnyView(content), configuration: configuration)
        SidebarUITestDragMarker.recordEvent(
            "bridgeMake",
            dragItemID: configuration.dragSource?.item.tabId,
            ownerDescription: view.recoveryDebugDescription,
            sourceID: configuration.sourceID,
            viewDescription: view.debugViewDescription,
            details: "source=\(configuration.sourceID ?? "nil") inputEnabled=\(configuration.isInteractionEnabled) view=\(view.debugViewDescription) hostedRoot=\(view.hostedSidebarRootDebugDescription) controller=\(view.contextMenuControllerDebugDescription)"
        )
        return view
    }

    func updateNSView(_ nsView: SidebarInteractiveItemView, context: Context) {
        nsView.contextMenuController = controller
        nsView.update(rootView: AnyView(content), configuration: configuration)
    }

    static func dismantleNSView(_ nsView: SidebarInteractiveItemView, coordinator: ()) {
        SidebarUITestDragMarker.recordEvent(
            "bridgeDismantle",
            dragItemID: nsView.recoveryMetadata.dragItemID,
            ownerDescription: nsView.recoveryDebugDescription,
            sourceID: nsView.sourceID,
            viewDescription: nsView.debugViewDescription,
            details: "source=\(nsView.identifier?.rawValue ?? "nil") view=\(nsView.debugViewDescription) hostedRoot=\(nsView.hostedSidebarRootDebugDescription) controller=\(nsView.contextMenuControllerDebugDescription)"
        )
        nsView.prepareForDismantle()
    }
}

private struct SidebarAppKitItemModifier: ViewModifier {
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sidebarPresentationContext) private var presentationContext

    let menu: SidebarContextMenuLeafConfiguration
    let dragSource: SidebarDragSourceConfiguration?
    let primaryAction: (() -> Void)?
    let onMiddleClick: (() -> Void)?
    let sourceID: String?
    let isInteractionEnabled: Bool

    func body(content: Content) -> some View {
        SidebarAppKitItemBridge(
            content: content,
            controller: windowState.sidebarContextMenuController,
            configuration: SidebarAppKitItemConfiguration(
                isInteractionEnabled: isInteractionEnabled,
                menu: menu,
                dragSource: dragSource,
                primaryAction: primaryAction,
                onMiddleClick: onMiddleClick,
                sourceID: sourceID,
                presentationMode: presentationContext.mode
            )
        )
    }
}

private struct SidebarAppKitPrimaryActionModifier: ViewModifier {
    @Environment(BrowserWindowState.self) private var windowState

    let isEnabled: Bool
    let isInteractionEnabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        let primaryAction: (() -> Void)? = isEnabled ? action : nil
        return SidebarAppKitItemBridge(
            content: content,
            controller: windowState.sidebarContextMenuController,
            configuration: SidebarAppKitItemConfiguration(
                isInteractionEnabled: isInteractionEnabled,
                primaryAction: primaryAction
            )
        )
    }
}

private struct SidebarBackgroundMenuConfigurationBridge: NSViewRepresentable {
    let controller: SidebarContextMenuController
    let entries: () -> [SidebarContextMenuEntry]
    let onMenuVisibilityChanged: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        controller.configureBackgroundMenu(
            entriesProvider: entries,
            onMenuVisibilityChanged: onMenuVisibilityChanged
        )
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        controller.configureBackgroundMenu(
            entriesProvider: entries,
            onMenuVisibilityChanged: onMenuVisibilityChanged
        )
    }
}

@MainActor
final class SumiAppKitContextMenuHostView: NSView {
    weak var controller: SidebarContextMenuController?
    var isContextMenuEnabled = true
    var entriesProvider: () -> [SidebarContextMenuEntry] = { [] }
    var onMenuVisibilityChanged: (Bool) -> Void = { _ in }

    override var acceptsFirstResponder: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard canHandleContextMenu(for: window?.currentEvent, at: point) else {
            return nil
        }
        return self
    }

    override func rightMouseDown(with event: NSEvent) {
        presentContextMenu(trigger: .rightMouseDown, event: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.control) else {
            super.mouseDown(with: event)
            return
        }
        presentContextMenu(trigger: .rightMouseDown, event: event)
    }

    func reset() {
        controller = nil
        isContextMenuEnabled = false
        entriesProvider = { [] }
        onMenuVisibilityChanged = { _ in }
    }

    func canHandleContextMenu(for event: NSEvent?, at point: NSPoint) -> Bool {
        guard isContextMenuEnabled,
              bounds.contains(point),
              controller != nil,
              entriesProvider().isEmpty == false,
              let event
        else {
            return false
        }

        switch event.type {
        case .rightMouseDown:
            return true
        case .leftMouseDown:
            return event.modifierFlags.contains(.control)
        default:
            return false
        }
    }

    private func presentContextMenu(
        trigger: SidebarContextMenuMouseTrigger,
        event: NSEvent
    ) {
        controller?.presentTransientMenu(
            entries: entriesProvider(),
            onMenuVisibilityChanged: onMenuVisibilityChanged,
            trigger: trigger,
            event: event,
            in: self
        )
    }
}

private struct SumiAppKitContextMenuBridge: NSViewRepresentable {
    let controller: SidebarContextMenuController
    let isEnabled: Bool
    let entries: () -> [SidebarContextMenuEntry]
    let onMenuVisibilityChanged: (Bool) -> Void

    func makeNSView(context: Context) -> SumiAppKitContextMenuHostView {
        let view = SumiAppKitContextMenuHostView(frame: .zero)
        update(view)
        return view
    }

    func updateNSView(_ nsView: SumiAppKitContextMenuHostView, context: Context) {
        update(nsView)
    }

    static func dismantleNSView(_ nsView: SumiAppKitContextMenuHostView, coordinator: ()) {
        nsView.reset()
    }

    private func update(_ view: SumiAppKitContextMenuHostView) {
        view.controller = controller
        view.isContextMenuEnabled = isEnabled
        view.entriesProvider = entries
        view.onMenuVisibilityChanged = onMenuVisibilityChanged
    }
}

private struct SumiAppKitContextMenuModifier: ViewModifier {
    @Environment(BrowserWindowState.self) private var windowState

    let isEnabled: Bool
    let entries: () -> [SidebarContextMenuEntry]
    let onMenuVisibilityChanged: (Bool) -> Void

    func body(content: Content) -> some View {
        content.overlay {
            SumiAppKitContextMenuBridge(
                controller: windowState.sidebarContextMenuController,
                isEnabled: isEnabled,
                entries: entries,
                onMenuVisibilityChanged: onMenuVisibilityChanged
            )
        }
    }
}

extension View {
    func sidebarAppKitContextMenu(
        isEnabled: Bool = true,
        isInteractionEnabled: Bool = true,
        surfaceKind: SidebarContextMenuSurfaceKind = .row,
        triggers: SidebarContextMenuTriggers = [.rightClick],
        dragSource: SidebarDragSourceConfiguration? = nil,
        primaryAction: (() -> Void)? = nil,
        onMiddleClick: (() -> Void)? = nil,
        sourceID: String? = nil,
        entries: @escaping () -> [SidebarContextMenuEntry],
        onMenuVisibilityChanged: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        modifier(
            SidebarAppKitItemModifier(
                menu: SidebarContextMenuLeafConfiguration(
                    isEnabled: isEnabled,
                    surfaceKind: surfaceKind,
                    triggers: triggers,
                    entries: entries,
                    onMenuVisibilityChanged: onMenuVisibilityChanged
                ),
                dragSource: dragSource,
                primaryAction: primaryAction,
                onMiddleClick: onMiddleClick,
                sourceID: sourceID,
                isInteractionEnabled: isInteractionEnabled
            )
        )
    }

    func sidebarAppKitPrimaryAction(
        isEnabled: Bool = true,
        isInteractionEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        modifier(
            SidebarAppKitPrimaryActionModifier(
                isEnabled: isEnabled,
                isInteractionEnabled: isInteractionEnabled,
                action: action
            )
        )
    }

    func sidebarAppKitBackgroundContextMenu(
        controller: SidebarContextMenuController,
        entries: @escaping () -> [SidebarContextMenuEntry],
        onMenuVisibilityChanged: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        background(
            SidebarBackgroundMenuConfigurationBridge(
                controller: controller,
                entries: entries,
                onMenuVisibilityChanged: onMenuVisibilityChanged
            )
            .frame(width: 0, height: 0)
        )
    }

    func sumiAppKitContextMenu(
        isEnabled: Bool = true,
        entries: @escaping () -> [SidebarContextMenuEntry],
        onMenuVisibilityChanged: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        modifier(
            SumiAppKitContextMenuModifier(
                isEnabled: isEnabled,
                entries: entries,
                onMenuVisibilityChanged: onMenuVisibilityChanged
            )
        )
    }
}

private func transparentImage(size: CGSize) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.clear.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
    image.unlockFocus()
    return image
}

struct SidebarFolderHeaderMenuCallbacks {
    let onRename: () -> Void
    let onChangeIcon: () -> Void
    let onResetIcon: () -> Void
    let onAddTab: () -> Void
    let onAlphabetize: () -> Void
    let onDelete: () -> Void
}

struct SidebarRegularTabMenuCallbacks {
    let onAddToFolder: (UUID) -> Void
    let onAddToFavorites: () -> Void
    let onCopyLink: () -> Void
    let onShare: () -> Void
    let onRename: () -> Void
    let onSplitRight: () -> Void
    let onSplitLeft: () -> Void
    let onDuplicate: () -> Void
    let onMoveToSpace: (UUID) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onPinToSpace: () -> Void
    let onPinGlobally: () -> Void
    let onCloseAllBelow: () -> Void
    let onClose: () -> Void
}

struct SidebarLauncherMenuCallbacks {
    let onOpen: () -> Void
    let onSplitRight: () -> Void
    let onSplitLeft: () -> Void
    let onDuplicate: () -> Void
    let onResetToLaunchURL: (() -> Void)?
    let onReplaceLauncherURLWithCurrent: (() -> Void)?
    let onEditIcon: () -> Void
    let onEditLink: () -> Void
    let onUnpin: () -> Void
    let onMoveToRegularTabs: () -> Void
    let onPinGlobally: (() -> Void)?
    let onCloseCurrentPage: (() -> Void)?
}

struct SidebarEssentialsMenuCallbacks {
    let onOpen: () -> Void
    let onSplitRight: () -> Void
    let onSplitLeft: () -> Void
    let onCloseCurrentPage: (() -> Void)?
    let onRemoveFromEssentials: () -> Void
    let onMoveToRegularTabs: () -> Void
}

struct SidebarSpaceMenuCallbacks {
    let onSelectProfile: (UUID) -> Void
    let onRename: (() -> Void)?
    let onChangeIcon: (() -> Void)?
    let onChangeTheme: () -> Void
    let onOpenSettings: () -> Void
    let onDeleteSpace: (() -> Void)?
}

struct SidebarSpaceListMenuCallbacks {
    let onOpenSettings: () -> Void
    let onDeleteSpace: (() -> Void)?
}

struct SidebarShellMenuCallbacks {
    let onCreateSpace: () -> Void
    let onCreateFolder: () -> Void
    let onNewSplit: () -> Void
    let onNewTab: () -> Void
    let onReloadSelectedTab: () -> Void
    let onBookmarkSelectedTab: () -> Void
    let onReopenClosedTab: () -> Void
    let onToggleCompactMode: () -> Void
    let onEditTheme: () -> Void
    let onOpenLayout: () -> Void
}

private func joinSidebarMenuSections(_ sections: [[SidebarContextMenuEntry]]) -> [SidebarContextMenuEntry] {
    sections
        .filter { !$0.isEmpty }
        .enumerated()
        .flatMap { index, section in
            index == 0 ? section : [.separator] + section
        }
}

func makeFolderHeaderContextMenuEntries(
    hasCustomIcon: Bool,
    callbacks: SidebarFolderHeaderMenuCallbacks
) -> [SidebarContextMenuEntry] {
    joinSidebarMenuSections(
        [
            [
                .action(.init(title: "Rename Folder", onAction: callbacks.onRename)),
                .action(.init(title: "Change Folder Icon…", classification: .presentationOnly, onAction: callbacks.onChangeIcon)),
            ] + (hasCustomIcon
                ? [.action(.init(title: "Reset Folder Icon", onAction: callbacks.onResetIcon))]
                : []) + [
                    .action(.init(title: "Add Tab to Folder", classification: .structuralMutation, onAction: callbacks.onAddTab)),
                ],
            [
                .action(.init(title: "Alphabetize Tabs", classification: .structuralMutation, onAction: callbacks.onAlphabetize)),
            ],
            [
                .action(
                    .init(
                        title: "Delete Folder",
                        role: .destructive,
                        classification: .structuralMutation,
                        onAction: callbacks.onDelete
                    )
                ),
            ],
        ]
    )
}

func makeRegularTabContextMenuEntries(
    folders: [SidebarContextMenuChoice],
    spaces: [SidebarContextMenuChoice],
    showsAddToFavorites: Bool,
    canMoveUp: Bool,
    canMoveDown: Bool,
    showsCloseAllBelow: Bool,
    callbacks: SidebarRegularTabMenuCallbacks
) -> [SidebarContextMenuEntry] {
    let addSection: [SidebarContextMenuEntry] =
        (folders.isEmpty
            ? []
            : [
                .submenu(
                    title: "Add to Folder",
                    systemImage: "folder.badge.plus",
                    children: folders.map { folder in
                .action(
                            .init(
                                title: folder.title,
                                systemImage: "folder.fill",
                                classification: .structuralMutation,
                                onAction: { callbacks.onAddToFolder(folder.id) }
                            )
                        )
                    }
                ),
            ]) +
        (showsAddToFavorites
            ? [.action(.init(title: "Add to Favorites", systemImage: "star.fill", classification: .structuralMutation, onAction: callbacks.onAddToFavorites))]
            : [])

    let editSection: [SidebarContextMenuEntry] = [
        .action(.init(title: "Copy Link", systemImage: "link", classification: .presentationOnly, onAction: callbacks.onCopyLink)),
        .action(.init(title: "Share", systemImage: "square.and.arrow.up", classification: .presentationOnly, onAction: callbacks.onShare)),
        .action(.init(title: "Rename", systemImage: "character.cursor.ibeam", onAction: callbacks.onRename)),
    ]

    let moveToSpaceEntries = spaces.map { space in
        SidebarContextMenuEntry.action(
            .init(
                title: space.title,
                isEnabled: space.isSelected == false,
                classification: .structuralMutation,
                onAction: { callbacks.onMoveToSpace(space.id) }
            )
        )
    }

    let actionSection: [SidebarContextMenuEntry] = [
        .submenu(
            title: "Open in Split",
            systemImage: "rectangle.split.2x1",
            children: [
                .action(.init(title: "Right", systemImage: "rectangle.righthalf.filled", onAction: callbacks.onSplitRight)),
                .action(.init(title: "Left", systemImage: "rectangle.lefthalf.filled", onAction: callbacks.onSplitLeft)),
            ]
        ),
        .action(.init(title: "Duplicate", systemImage: "plus.square.on.square", classification: .structuralMutation, onAction: callbacks.onDuplicate)),
        .submenu(title: "Move to Space", systemImage: "square.grid.2x2", children: moveToSpaceEntries),
        .action(.init(title: "Move Up", systemImage: "arrow.up", isEnabled: canMoveUp, classification: .structuralMutation, onAction: callbacks.onMoveUp)),
        .action(.init(title: "Move Down", systemImage: "arrow.down", isEnabled: canMoveDown, classification: .structuralMutation, onAction: callbacks.onMoveDown)),
        .action(.init(title: "Pin to Space", systemImage: "pin", classification: .structuralMutation, onAction: callbacks.onPinToSpace)),
        .action(.init(title: "Pin Globally", systemImage: "pin.circle", classification: .structuralMutation, onAction: callbacks.onPinGlobally)),
    ]

    let closeSection: [SidebarContextMenuEntry] =
        (showsCloseAllBelow
            ? [.action(.init(title: "Close All Below", systemImage: "arrow.down.to.line", classification: .structuralMutation, onAction: callbacks.onCloseAllBelow))]
            : []) + [
                .action(
                    .init(
                        title: "Close",
                        systemImage: "xmark",
                        role: .destructive,
                        classification: .structuralMutation,
                        onAction: callbacks.onClose
                    )
                ),
            ]

    return joinSidebarMenuSections([addSection, editSection, actionSection, closeSection])
}

func makeSpacePinnedLauncherContextMenuEntries(
    hasRuntimeResetActions: Bool,
    showsCloseCurrentPage: Bool,
    callbacks: SidebarLauncherMenuCallbacks
) -> [SidebarContextMenuEntry] {
    var sections: [[SidebarContextMenuEntry]] = [
        [
            .action(.init(title: "Open", systemImage: "arrow.up.forward.app", onAction: callbacks.onOpen)),
            .action(.init(title: "Open in Split (Right)", systemImage: "rectangle.split.2x1", onAction: callbacks.onSplitRight)),
            .action(.init(title: "Open in Split (Left)", systemImage: "rectangle.split.2x1", onAction: callbacks.onSplitLeft)),
        ],
    ]

    if hasRuntimeResetActions, let onResetToLaunchURL = callbacks.onResetToLaunchURL, let onReplace = callbacks.onReplaceLauncherURLWithCurrent {
        sections.append(
            [
                .action(.init(title: "Reset to Launcher URL", systemImage: "arrow.counterclockwise", onAction: onResetToLaunchURL)),
                .action(.init(title: "Replace Launcher URL with Current", systemImage: "arrow.triangle.2.circlepath", onAction: onReplace)),
            ]
        )
    }

    var managementSection: [SidebarContextMenuEntry] = [
        .action(.init(title: "Edit Icon", systemImage: "photo", classification: .presentationOnly, onAction: callbacks.onEditIcon)),
        .action(.init(title: "Edit Link…", systemImage: "link.badge.plus", classification: .presentationOnly, onAction: callbacks.onEditLink)),
        .action(.init(title: "Unpin from Space", systemImage: "pin.slash", classification: .structuralMutation, onAction: callbacks.onUnpin)),
        .action(.init(title: "Move to Regular Tabs", systemImage: "pin.slash.fill", classification: .structuralMutation, onAction: callbacks.onMoveToRegularTabs)),
    ]
    if let onPinGlobally = callbacks.onPinGlobally {
        managementSection.append(.action(.init(title: "Pin Globally", systemImage: "pin.circle", classification: .structuralMutation, onAction: onPinGlobally)))
    }
    sections.append(managementSection)

    if showsCloseCurrentPage, let onCloseCurrentPage = callbacks.onCloseCurrentPage {
        sections.append(
            [
                .action(.init(title: "Close current page", systemImage: "xmark.circle", onAction: onCloseCurrentPage)),
            ]
        )
    }

    return joinSidebarMenuSections(sections)
}

func makeFolderLauncherContextMenuEntries(
    hasRuntimeResetActions: Bool,
    showsCloseCurrentPage: Bool,
    callbacks: SidebarLauncherMenuCallbacks
) -> [SidebarContextMenuEntry] {
    var sections: [[SidebarContextMenuEntry]] = [
        [
            .action(.init(title: "Open", systemImage: "arrow.up.forward.app", onAction: callbacks.onOpen)),
            .action(.init(title: "Open in Split (Right)", systemImage: "rectangle.split.2x1", onAction: callbacks.onSplitRight)),
            .action(.init(title: "Open in Split (Left)", systemImage: "rectangle.split.2x1", onAction: callbacks.onSplitLeft)),
            .action(.init(title: "Duplicate Tab", systemImage: "doc.on.doc", classification: .structuralMutation, onAction: callbacks.onDuplicate)),
        ],
    ]

    if hasRuntimeResetActions, let onResetToLaunchURL = callbacks.onResetToLaunchURL, let onReplace = callbacks.onReplaceLauncherURLWithCurrent {
        sections.append(
            [
                .action(.init(title: "Reset to Launcher URL", systemImage: "arrow.counterclockwise", onAction: onResetToLaunchURL)),
                .action(.init(title: "Replace Launcher URL with Current", systemImage: "arrow.triangle.2.circlepath", onAction: onReplace)),
            ]
        )
    }

    sections.append(
        [
            .action(.init(title: "Edit Icon", systemImage: "photo", classification: .presentationOnly, onAction: callbacks.onEditIcon)),
            .action(.init(title: "Edit Link…", systemImage: "link.badge.plus", classification: .presentationOnly, onAction: callbacks.onEditLink)),
            .action(.init(title: "Unpin from Folder", systemImage: "pin.slash", classification: .structuralMutation, onAction: callbacks.onUnpin)),
            .action(.init(title: "Move to Regular Tabs", systemImage: "pin.slash.fill", classification: .structuralMutation, onAction: callbacks.onMoveToRegularTabs)),
        ]
    )

    if showsCloseCurrentPage, let onCloseCurrentPage = callbacks.onCloseCurrentPage {
        sections.append(
            [
                .action(.init(title: "Close current page", systemImage: "xmark.circle", onAction: onCloseCurrentPage)),
            ]
        )
    }

    return joinSidebarMenuSections(sections)
}

func makeEssentialsContextMenuEntries(
    showsCloseCurrentPage: Bool,
    callbacks: SidebarEssentialsMenuCallbacks
) -> [SidebarContextMenuEntry] {
    var sections: [[SidebarContextMenuEntry]] = [
        [
            .action(.init(title: "Open", systemImage: "arrow.up.forward.app", onAction: callbacks.onOpen)),
            .action(.init(title: "Open in Split (Right)", systemImage: "rectangle.split.2x1", onAction: callbacks.onSplitRight)),
            .action(.init(title: "Open in Split (Left)", systemImage: "rectangle.split.2x1", onAction: callbacks.onSplitLeft)),
        ],
    ]

    if showsCloseCurrentPage, let onCloseCurrentPage = callbacks.onCloseCurrentPage {
        sections.append(
            [
                .action(.init(title: "Close current page", systemImage: "xmark", role: .destructive, onAction: onCloseCurrentPage)),
            ]
        )
    }

    sections.append(
        [
            .action(.init(title: "Remove from Essentials", systemImage: "pin.slash", classification: .structuralMutation, onAction: callbacks.onRemoveFromEssentials)),
            .action(.init(title: "Move to Regular Tabs", systemImage: "pin.slash.fill", classification: .structuralMutation, onAction: callbacks.onMoveToRegularTabs)),
        ]
    )

    return joinSidebarMenuSections(sections)
}

func makeSpaceContextMenuEntries(
    profiles: [SidebarContextMenuChoice],
    canRename: Bool,
    canChangeIcon: Bool,
    canDelete: Bool,
    callbacks: SidebarSpaceMenuCallbacks
) -> [SidebarContextMenuEntry] {
    let profileEntries = profiles.map { profile in
        SidebarContextMenuEntry.action(
            .init(
                title: profile.title,
                state: profile.isSelected ? .on : .off,
                onAction: { callbacks.onSelectProfile(profile.id) }
            )
        )
    }

    var editSection: [SidebarContextMenuEntry] = []
    if canRename, let onRename = callbacks.onRename {
        editSection.append(.action(.init(title: "Rename", systemImage: "textformat", onAction: onRename)))
    }
    if canChangeIcon, let onChangeIcon = callbacks.onChangeIcon {
        editSection.append(.action(.init(title: "Change Icon", systemImage: "face.smiling", classification: .presentationOnly, onAction: onChangeIcon)))
    }
    editSection.append(.action(.init(title: "Change Theme", systemImage: "paintpalette", classification: .presentationOnly, onAction: callbacks.onChangeTheme)))

    var settingsSection: [SidebarContextMenuEntry] = [
        .action(.init(title: "Space Settings", systemImage: "gear", classification: .presentationOnly, onAction: callbacks.onOpenSettings)),
    ]
    if canDelete, let onDeleteSpace = callbacks.onDeleteSpace {
        settingsSection.append(
            .action(.init(title: "Delete Space", systemImage: "trash", role: .destructive, classification: .structuralMutation, onAction: onDeleteSpace))
        )
    }

    return joinSidebarMenuSections(
        [
            [
                .submenu(title: "Profile", systemImage: "person.crop.circle", children: profileEntries),
            ],
            editSection,
            settingsSection,
        ]
    )
}

func makeSpaceListContextMenuEntries(
    canDelete: Bool,
    callbacks: SidebarSpaceListMenuCallbacks
) -> [SidebarContextMenuEntry] {
    joinSidebarMenuSections(
        [
        [
            .action(.init(title: "Space Settings", systemImage: "gear", classification: .presentationOnly, onAction: callbacks.onOpenSettings)),
        ],
        canDelete && callbacks.onDeleteSpace != nil
            ? [
                .action(
                    .init(
                        title: "Delete Space",
                        systemImage: "trash",
                        role: .destructive,
                        classification: .structuralMutation,
                        onAction: callbacks.onDeleteSpace ?? {}
                    )
                ),
            ]
                : [],
        ]
    )
}

func makeSidebarShellContextMenuEntries(
    hasSelectedTab: Bool,
    isCompactModeEnabled: Bool,
    callbacks: SidebarShellMenuCallbacks
) -> [SidebarContextMenuEntry] {
    joinSidebarMenuSections(
        [
            [
                .action(.init(title: "Create Space", systemImage: "square.grid.2x2", classification: .structuralMutation, onAction: callbacks.onCreateSpace)),
                .action(.init(title: "Create Folder", systemImage: "folder.badge.plus", classification: .structuralMutation, onAction: callbacks.onCreateFolder)),
                .action(.init(title: "New Split", systemImage: "rectangle.split.2x1", onAction: callbacks.onNewSplit)),
                .action(.init(title: "New Tab", systemImage: "plus", classification: .structuralMutation, onAction: callbacks.onNewTab)),
            ],
            [
                .action(
                    .init(
                        title: "Reload Selected Tab",
                        systemImage: "arrow.clockwise",
                        isEnabled: hasSelectedTab,
                        onAction: callbacks.onReloadSelectedTab
                    )
                ),
                .action(
                    .init(
                        title: "Bookmark Selected Tab…",
                        systemImage: "bookmark",
                        isEnabled: hasSelectedTab,
                        classification: .presentationOnly,
                        onAction: callbacks.onBookmarkSelectedTab
                    )
                ),
                .action(
                    .init(
                        title: "Reopen Closed Tab",
                        systemImage: "arrow.uturn.backward",
                        classification: .structuralMutation,
                        onAction: callbacks.onReopenClosedTab
                    )
                ),
            ],
            [
                .action(
                    .init(
                        title: "Enable compact mode",
                        systemImage: "circle.grid.2x2",
                        state: isCompactModeEnabled ? .on : .off,
                        onAction: callbacks.onToggleCompactMode
                    )
                ),
            ],
            [
                .action(.init(title: "Edit Theme", systemImage: "paintpalette", classification: .presentationOnly, onAction: callbacks.onEditTheme)),
                .action(.init(title: "Sumi Layout…", systemImage: "slider.horizontal.3", classification: .presentationOnly, onAction: callbacks.onOpenLayout)),
            ],
        ]
    )
}

extension SidebarContextMenuAction {
    init(
        title: String,
        systemImage: String? = nil,
        isEnabled: Bool = true,
        state: NSControl.StateValue = .off,
        role: SidebarContextMenuRole = .normal,
        classification: SidebarContextMenuActionClassification = .stateMutationNonStructural,
        onAction: @escaping () -> Void
    ) {
        self.init(
            title: title,
            systemImage: systemImage,
            isEnabled: isEnabled,
            state: state,
            role: role,
            classification: classification,
            action: onAction
        )
    }
}

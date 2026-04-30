import AppKit
import Foundation

enum SidebarInputRecoveryReason: String, CaseIterable, CustomStringConvertible {
    case menuEnded = "menu-ended"
    case popoverDismissed = "popover-dismissed"
    case structuralMenuAction = "structural-menu-action"
    case ownerUnresolvedAfterSoftRecovery = "owner-unresolved-after-soft-recovery"
    case dragSessionRecovery = "drag-session-recovery"
    case explicitFallback = "explicit-fallback"
    case unknownFallback = "unknown-fallback"

    var description: String { rawValue }
}

enum SidebarRecoveryTier: Int, Comparable, CustomStringConvertible {
    case soft = 0
    case hardRehydrate = 1

    static func < (lhs: SidebarRecoveryTier, rhs: SidebarRecoveryTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var requiresSidebarInputRehydrate: Bool {
        self == .hardRehydrate
    }

    var description: String {
        switch self {
        case .soft:
            return "soft"
        case .hardRehydrate:
            return "hardRehydrate"
        }
    }
}

@MainActor
final class SidebarDeferredStateMutation<Value> {
    private var pendingValue: Value?
    private var isScheduled = false

    func schedule(
        _ value: Value,
        apply: @escaping @MainActor (Value) -> Void
    ) {
        pendingValue = value
        guard !isScheduled else { return }

        isScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isScheduled = false
            guard let pendingValue = self.pendingValue else { return }
            self.pendingValue = nil
            apply(pendingValue)
        }
    }
}

struct SidebarInteractiveOwnerRecoveryMetadata: Hashable, CustomStringConvertible {
    let ownerObjectID: ObjectIdentifier
    let ownerTypeName: String
    let dragItemID: UUID?
    let dragSourceZone: DropZoneID?

    var description: String {
        if let dragItemID, let dragSourceZone {
            return "\(ownerTypeName){id=\(ownerObjectID),dragItem=\(dragItemID.uuidString),source=\(sidebarDropZoneDebugDescription(dragSourceZone))}"
        }
        return "\(ownerTypeName){id=\(ownerObjectID)}"
    }
}

struct SidebarInteractiveOwnerRecoveryResult: Equatable {
    let recoveredOwnerCount: Int
    let sourceOwnerResolved: Bool
    let resolvedOwnerDescription: String?
    let resolutionReason: String?

    static let none = SidebarInteractiveOwnerRecoveryResult(
        recoveredOwnerCount: 0,
        sourceOwnerResolved: false,
        resolvedOwnerDescription: nil,
        resolutionReason: nil
    )
}

func sidebarDropZoneDebugDescription(_ dropZoneID: DropZoneID) -> String {
    switch dropZoneID {
    case .essentials:
        return "essentials"
    case .spacePinned(let id):
        return "spacePinned(\(id.uuidString))"
    case .spaceRegular(let id):
        return "spaceRegular(\(id.uuidString))"
    case .folder(let id):
        return "folder(\(id.uuidString))"
    }
}

@MainActor
enum SidebarTransientUIKind: String, CaseIterable {
    case contextMenu
    case dialog
    case themePicker
    case emojiPopover
    case sharingPicker
    case downloadsPopover
    case drag

    var blocksSidebarDragSources: Bool {
        switch self {
        case .contextMenu, .dialog, .themePicker, .emojiPopover, .sharingPicker, .downloadsPopover:
            return true
        case .drag:
            return false
        }
    }

    var pinsCollapsedSidebar: Bool {
        switch self {
        case .contextMenu, .dialog, .themePicker, .emojiPopover, .sharingPicker, .downloadsPopover, .drag:
            return true
        }
    }
}

@MainActor
struct SidebarTransientSessionToken: Hashable {
    let id: UUID
    let kind: SidebarTransientUIKind

    init(id: UUID = UUID(), kind: SidebarTransientUIKind) {
        self.id = id
        self.kind = kind
    }
}

@MainActor
final class SidebarTransientPresentationSource {
    let windowID: UUID
    let wasKeyWindow: Bool
    weak var window: NSWindow?
    weak var originOwnerView: NSView?
    weak var previousFirstResponder: NSResponder?
    weak var coordinator: SidebarTransientSessionCoordinator?
    var interactiveOwnerRecoveryMetadata: SidebarInteractiveOwnerRecoveryMetadata?

    init(
        windowID: UUID,
        window: NSWindow?,
        originOwnerView: NSView?,
        previousFirstResponder: NSResponder?,
        wasKeyWindow: Bool,
        coordinator: SidebarTransientSessionCoordinator?,
        interactiveOwnerRecoveryMetadata: SidebarInteractiveOwnerRecoveryMetadata? = nil
    ) {
        self.windowID = windowID
        self.window = window
        self.originOwnerView = originOwnerView
        self.previousFirstResponder = previousFirstResponder
        self.wasKeyWindow = wasKeyWindow
        self.coordinator = coordinator
        self.interactiveOwnerRecoveryMetadata = interactiveOwnerRecoveryMetadata
    }

    convenience init(
        windowID: UUID,
        window: NSWindow?,
        originOwnerView: NSView?,
        coordinator: SidebarTransientSessionCoordinator?
    ) {
        let resolvedWindow = window ?? originOwnerView?.window
        self.init(
            windowID: windowID,
            window: resolvedWindow,
            originOwnerView: originOwnerView,
            previousFirstResponder: resolvedWindow?.firstResponder,
            wasKeyWindow: resolvedWindow?.isKeyWindow == true,
            coordinator: coordinator,
            interactiveOwnerRecoveryMetadata: Self.recoveryMetadata(from: originOwnerView)
        )
    }

    func refresh(window: NSWindow?, originOwnerView: NSView?) {
        if let window {
            self.window = window
        }
        if let originOwnerView {
            self.originOwnerView = originOwnerView
            interactiveOwnerRecoveryMetadata = Self.recoveryMetadata(from: originOwnerView)
        }
    }

    private static func recoveryMetadata(from view: NSView?) -> SidebarInteractiveOwnerRecoveryMetadata? {
        (view as? SidebarInteractiveItemView)?.recoveryMetadata
    }
}

@MainActor
final class SidebarTransientSessionCoordinator {
    private struct PendingRecovery {
        var source: SidebarTransientPresentationSource
        var reasons: [String]
        var tier: SidebarRecoveryTier
        var hardRehydrateReason: SidebarInputRecoveryReason?
    }

    private struct SessionRecord {
        let token: SidebarTransientSessionToken
        let source: SidebarTransientPresentationSource
        let path: String
        var handles: [SidebarTransientInteractionHandle]
    }

    let windowID: UUID
    let interactionState: SidebarInteractionState
    var sidebarRecoveryCoordinator: SidebarHostRecoveryHandling = SidebarHostRecoveryCoordinator.shared
    var scheduleSidebarInputRehydrate: ((SidebarInputRecoveryReason) -> Void)?
    var recoverSidebarInteractiveOwners: ((NSWindow?, SidebarTransientPresentationSource) -> SidebarInteractiveOwnerRecoveryResult)?

    private var sessions: [UUID: SessionRecord] = [:]
    private var sessionOrder: [UUID] = []
    private var pendingPresentationSource: SidebarTransientPresentationSource?
    private var pendingCleanupScheduled = false
    private var pendingMenuActionCount = 0
    private var pendingMenuActionRecoveryTier: SidebarRecoveryTier = .soft
    private var pendingFinalRecoveryScheduled = false
    private var pendingRecoveriesByWindowID: [UUID: PendingRecovery] = [:]

    init(
        windowID: UUID,
        interactionState: SidebarInteractionState
    ) {
        self.windowID = windowID
        self.interactionState = interactionState
    }

    var currentPresentationWindowID: UUID? {
        if let mostRecent = activePinnedSessionRecords.last?.source.windowID {
            return mostRecent
        }
        return pendingPresentationSource?.windowID
    }

    func hasPinnedTransientUI(for windowID: UUID) -> Bool {
        if pendingPresentationSource?.windowID == windowID {
            return true
        }

        return activePinnedSessionRecords.contains { $0.source.windowID == windowID }
    }

    func prepareMenuPresentationSource(ownerView: NSView?) {
        pendingPresentationSource = capturePresentationSource(ownerView: ownerView)
        pendingCleanupScheduled = false
        pendingMenuActionRecoveryTier = .soft
        RuntimeDiagnostics.emit {
            "🧭 Sidebar transient source prepared window=\(windowID.uuidString) owner=\(ownerDebugDescription(from: pendingPresentationSource?.originOwnerView, metadata: pendingPresentationSource?.interactiveOwnerRecoveryMetadata))"
        }
    }

    func preparedPresentationSource(
        window: NSWindow?,
        ownerView: NSView? = nil
    ) -> SidebarTransientPresentationSource {
        if let pendingPresentationSource {
            pendingPresentationSource.refresh(
                window: window ?? pendingPresentationSource.window,
                originOwnerView: ownerView ?? pendingPresentationSource.originOwnerView
            )
            return pendingPresentationSource
        }

        return capturePresentationSource(
            window: window,
            ownerView: ownerView
        )
    }

    func consumePresentationSource(
        window: NSWindow?,
        ownerView: NSView? = nil,
        preferPending: Bool = true
    ) -> SidebarTransientPresentationSource {
        if preferPending,
           let pendingPresentationSource
        {
            pendingPresentationSource.refresh(
                window: window ?? pendingPresentationSource.window,
                originOwnerView: ownerView ?? pendingPresentationSource.originOwnerView
            )
            self.pendingPresentationSource = nil
            pendingCleanupScheduled = false
            return pendingPresentationSource
        }

        return capturePresentationSource(
            window: window,
            ownerView: ownerView
        )
    }

    func beginSession(
        kind: SidebarTransientUIKind,
        source: SidebarTransientPresentationSource,
        path: String,
        handles: [SidebarTransientInteractionHandle] = [],
        preservePendingSource: Bool = false
    ) -> SidebarTransientSessionToken {
        let token = SidebarTransientSessionToken(kind: kind)
        register(
            token: token,
            source: source,
            path: path,
            handles: handles,
            preservePendingSource: preservePendingSource
        )
        return token
    }

    func updateHandles(
        _ handles: [SidebarTransientInteractionHandle],
        for token: SidebarTransientSessionToken?
    ) {
        guard let token,
              var record = sessions[token.id]
        else { return }
        record.handles = handles
        sessions[token.id] = record
    }

    func endSession(_ token: SidebarTransientSessionToken?) {
        endSession(token, reason: "endSession")
    }

    func finishSession(
        _ token: SidebarTransientSessionToken?,
        reason: String,
        teardown: (() -> Void)? = nil
    ) {
        teardown?()
        endSession(token, reason: reason)
    }

    func beginMenuActionDispatch(
        path: String,
        classification: SidebarContextMenuActionClassification
    ) {
        pendingMenuActionCount += 1
        pendingCleanupScheduled = false
        pendingMenuActionRecoveryTier = max(
            pendingMenuActionRecoveryTier,
            classification.recoveryTier
        )
        RuntimeDiagnostics.emit {
            "🧭 Sidebar transient menu action begin window=\(windowID.uuidString) path=\(path) classification=\(classification.rawValue) pending=\(pendingMenuActionCount) tier=\(pendingMenuActionRecoveryTier)"
        }
    }

    func finishMenuActionDispatch(
        path: String,
        classification: SidebarContextMenuActionClassification
    ) {
        guard pendingMenuActionCount > 0 else { return }

        // Give menu actions one extra main-loop turn to open their next transient surface
        // or enqueue model mutations before final sidebar input recovery runs.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingMenuActionCount = max(0, self.pendingMenuActionCount - 1)
            self.pendingMenuActionRecoveryTier = max(
                self.pendingMenuActionRecoveryTier,
                classification.recoveryTier
            )
            RuntimeDiagnostics.emit {
                "🧭 Sidebar transient menu action drained window=\(self.windowID.uuidString) path=\(path) classification=\(classification.rawValue) pending=\(self.pendingMenuActionCount) tier=\(self.pendingMenuActionRecoveryTier)"
            }
            self.scheduleFinalRecoveryIfPossible(reason: "menu-action-drain:\(path)")
            if self.pendingMenuActionCount == 0 {
                self.pendingMenuActionRecoveryTier = .soft
            }
            self.schedulePendingPresentationSourceCleanup()
        }
    }

    private func endSession(_ token: SidebarTransientSessionToken?, reason: String) {
        guard let token else { return }
        guard let record = sessions.removeValue(forKey: token.id) else { return }

        sessionOrder.removeAll { $0 == token.id }
        interactionState.endSession(kind: token.kind, tokenID: token.id)

        RuntimeDiagnostics.emit {
            "🧭 Sidebar transient end [\(token.kind.rawValue)] window=\(record.source.windowID.uuidString) path=\(record.path)"
        }

        record.handles.forEach { $0.disarm() }
        reconcileInteractionState(reason: "end:\(reason):\(token.kind.rawValue)")
        queueFinalRecovery(
            for: record.source,
            reason: "\(reason):\(token.kind.rawValue)",
            tier: recoveryTierForSessionEnd(kind: token.kind)
        )
        schedulePendingPresentationSourceCleanup()
    }

    private var activePinnedSessionRecords: [SessionRecord] {
        sessionOrder.compactMap { sessions[$0] }.filter { $0.token.kind.pinsCollapsedSidebar }
    }

    private func register(
        token: SidebarTransientSessionToken,
        source: SidebarTransientPresentationSource,
        path: String,
        handles: [SidebarTransientInteractionHandle],
        preservePendingSource: Bool
    ) {
        source.coordinator = self
        source.refresh(window: source.window, originOwnerView: source.originOwnerView)
        sessions[token.id] = SessionRecord(
            token: token,
            source: source,
            path: path,
            handles: handles
        )
        sessionOrder.removeAll { $0 == token.id }
        sessionOrder.append(token.id)
        interactionState.beginSession(kind: token.kind, tokenID: token.id)
        if !preservePendingSource {
            pendingPresentationSource = nil
        }
        pendingCleanupScheduled = false
        reconcileInteractionState(reason: "begin:\(path):\(token.kind.rawValue)")

        RuntimeDiagnostics.emit {
            "🧭 Sidebar transient begin [\(token.kind.rawValue)] window=\(source.windowID.uuidString) path=\(path) owner=\(ownerDebugDescription(from: source.originOwnerView, metadata: source.interactiveOwnerRecoveryMetadata))"
        }
    }

    private func reconcileInteractionState(reason: String) {
        var activeTokenIDsByKind: [SidebarTransientUIKind: Set<UUID>] = [:]
        for record in sessions.values {
            activeTokenIDsByKind[record.token.kind, default: []].insert(record.token.id)
        }

        let before = interactionState.activeKindsDescription
        interactionState.reconcileSessions(activeTokenIDsByKind)
        let after = interactionState.activeKindsDescription
        if before != after {
            RuntimeDiagnostics.emit {
                "🧭 Sidebar transient interaction reconciled window=\(windowID.uuidString) reason=\(reason) before=\(before) after=\(after)"
            }
        }
    }

    private func capturePresentationSource(
        window: NSWindow? = nil,
        ownerView: NSView?
    ) -> SidebarTransientPresentationSource {
        SidebarTransientPresentationSource(
            windowID: windowID,
            window: window ?? ownerView?.window,
            originOwnerView: ownerView,
            coordinator: self
        )
    }

    private func schedulePendingPresentationSourceCleanup() {
        guard !pendingCleanupScheduled else { return }
        pendingCleanupScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingCleanupScheduled = false
            if self.activePinnedSessionRecords.isEmpty,
               self.pendingMenuActionCount == 0,
               self.pendingRecoveriesByWindowID.isEmpty
            {
                self.pendingPresentationSource = nil
            }
        }
    }

    private func queueFinalRecovery(
        for source: SidebarTransientPresentationSource,
        reason: String,
        tier: SidebarRecoveryTier
    ) {
        if var pendingRecovery = pendingRecoveriesByWindowID[source.windowID] {
            pendingRecovery.source.refresh(
                window: source.window ?? pendingRecovery.source.window,
                originOwnerView: source.originOwnerView ?? pendingRecovery.source.originOwnerView
            )
            pendingRecovery.reasons.append(reason)
            pendingRecovery.tier = max(pendingRecovery.tier, tier)
            pendingRecovery.hardRehydrateReason = pendingRecovery.hardRehydrateReason
                ?? hardRehydrateReason(for: tier)
            pendingRecoveriesByWindowID[source.windowID] = pendingRecovery
        } else {
            pendingRecoveriesByWindowID[source.windowID] = PendingRecovery(
                source: source,
                reasons: [reason],
                tier: tier,
                hardRehydrateReason: hardRehydrateReason(for: tier)
            )
        }

        RuntimeDiagnostics.emit {
            "🧭 Sidebar transient queued recovery window=\(source.windowID.uuidString) tier=\(tier) reason=\(reason)"
        }
        scheduleFinalRecoveryIfPossible(reason: reason)
    }

    private func scheduleFinalRecoveryIfPossible(reason: String) {
        guard !pendingFinalRecoveryScheduled else { return }
        pendingFinalRecoveryScheduled = true

        // Two ticks are intentional: tick 1 lets NSMenu/NSPopover/AppKit finish teardown;
        // tick 2 lets menu/dialog actions that enqueue model mutations run before rehydration.
        DispatchQueue.main.async { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pendingFinalRecoveryScheduled = false

                guard self.canRunFinalRecovery else {
                    RuntimeDiagnostics.emit {
                        "🧭 Sidebar transient final recovery blocked window=\(self.windowID.uuidString) reason=\(reason) activePinned=\(self.activePinnedSessionRecords.count) pendingActions=\(self.pendingMenuActionCount)"
                    }
                    return
                }

                let recoveries = Array(self.pendingRecoveriesByWindowID.values)
                self.pendingRecoveriesByWindowID.removeAll()

                guard recoveries.isEmpty == false else {
                    self.schedulePendingPresentationSourceCleanup()
                    return
                }

                for recovery in recoveries {
                    self.performFinalRecovery(recovery)
                }

                self.schedulePendingPresentationSourceCleanup()
            }
        }
    }

    private var canRunFinalRecovery: Bool {
        activePinnedSessionRecords.isEmpty && pendingMenuActionCount == 0
    }

    private func performFinalRecovery(_ recovery: PendingRecovery) {
        let source = recovery.source
        let reason = recovery.reasons.joined(separator: ",")
        reconcileInteractionState(reason: "final-recovery:\(reason)")
        if !interactionState.allowsSidebarDragSourceHitTesting {
            RuntimeDiagnostics.emit {
                "⚠️ Sidebar transient final recovery blocked drag-source hit-testing window=\(source.windowID.uuidString) activeKinds=\(interactionState.activeKindsDescription) reason=\(reason)"
            }
        }

        let window = source.window
        sidebarRecoveryCoordinator.recover(in: window)
        sidebarRecoveryCoordinator.recover(anchor: source.originOwnerView)
        var effectiveTier = recovery.tier
        var hardRehydrateReason = recovery.hardRehydrateReason
        let recoveryResult = recoverSidebarInteractiveOwners?(window, source) ?? .none
        if effectiveTier == .soft,
           source.interactiveOwnerRecoveryMetadata != nil,
           recoverSidebarInteractiveOwners != nil,
           !recoveryResult.sourceOwnerResolved
        {
            effectiveTier = .hardRehydrate
            hardRehydrateReason = .ownerUnresolvedAfterSoftRecovery
            RuntimeDiagnostics.emit {
                "⚠️ Sidebar transient soft recovery escalated to hard window=\(source.windowID.uuidString) reason=\(reason) source=\(source.interactiveOwnerRecoveryMetadata?.description ?? "none") resolved=\(recoveryResult.resolvedOwnerDescription ?? "nil") recoveredCount=\(recoveryResult.recoveredOwnerCount)"
            }
        }

        RuntimeDiagnostics.emit {
            "🧭 Sidebar transient final recovery window=\(source.windowID.uuidString) tier=\(effectiveTier) reason=\(reason) source=\(source.interactiveOwnerRecoveryMetadata?.description ?? "none") sourceResolved=\(recoveryResult.sourceOwnerResolved) recoveredCount=\(recoveryResult.recoveredOwnerCount) resolvedOwner=\(recoveryResult.resolvedOwnerDescription ?? "nil") resolution=\(recoveryResult.resolutionReason ?? "none")"
        }

        if effectiveTier.requiresSidebarInputRehydrate {
            scheduleSidebarInputRehydrate?(hardRehydrateReason ?? .unknownFallback)
        }

        guard let window else { return }

        DispatchQueue.main.async { [weak self, weak window, source] in
            guard let self, let window else { return }

            self.sidebarRecoveryCoordinator.recover(in: window)
            self.sidebarRecoveryCoordinator.recover(anchor: source.originOwnerView)
            _ = self.recoverSidebarInteractiveOwners?(window, source)
            self.restoreResponder(for: source, in: window)
        }
    }

    private func recoveryTierForSessionEnd(kind: SidebarTransientUIKind) -> SidebarRecoveryTier {
        switch kind {
        case .contextMenu:
            return pendingMenuActionRecoveryTier
        case .dialog, .themePicker, .emojiPopover, .sharingPicker, .downloadsPopover, .drag:
            return .soft
        }
    }

    private func hardRehydrateReason(for tier: SidebarRecoveryTier) -> SidebarInputRecoveryReason? {
        guard tier.requiresSidebarInputRehydrate else { return nil }
        return .explicitFallback
    }

    private func restoreResponder(
        for source: SidebarTransientPresentationSource,
        in window: NSWindow
    ) {
        guard NSApp.isActive else { return }

        if source.wasKeyWindow {
            window.makeKeyAndOrderFront(nil)
        }

        if let previousFirstResponder = validPreviousFirstResponder(source.previousFirstResponder, in: window),
           window.makeFirstResponder(previousFirstResponder)
        {
            RuntimeDiagnostics.emit {
                "🧭 Sidebar transient responder restored window=\(source.windowID.uuidString) responder=\(String(describing: type(of: previousFirstResponder)))"
            }
            return
        }

        _ = window.makeFirstResponder(nil)
        RuntimeDiagnostics.emit {
            "🧭 Sidebar transient responder reset window=\(source.windowID.uuidString)"
        }
    }

    private func validPreviousFirstResponder(
        _ responder: NSResponder?,
        in window: NSWindow
    ) -> NSResponder? {
        guard let responder else { return nil }

        if let view = responder as? NSView {
            guard view.window === window else { return nil }
        }

        return responder
    }

    private func ownerDebugDescription(
        from view: NSView?,
        metadata: SidebarInteractiveOwnerRecoveryMetadata? = nil
    ) -> String {
        if let metadata {
            return metadata.description
        }
        guard let view else { return "nil" }
        return String(describing: type(of: view))
    }
}

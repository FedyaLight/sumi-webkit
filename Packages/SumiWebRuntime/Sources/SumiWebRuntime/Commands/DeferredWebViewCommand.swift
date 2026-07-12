//
//  DeferredWebViewCommand.swift
//  Sumi
//
//  Value types for WebView commands that must wait behind compositor protection.
//

import Foundation

public enum DeferredWebViewCommandKey: Hashable {
    case removeWebViewFromContainers(ObjectIdentifier)
    case removeTrackedWebView(ObjectIdentifier, UUID, UUID)
    case closeWebViewFromWebKit(ObjectIdentifier)
    case cleanupWindow(UUID)
    case cleanupAllWebViews
    case rebuildLiveWebViews(UUID)
    case assignProfile(UUID)
    case assignSpaceProfile(UUID)
    /// One semantic main-frame slot per tracked WebView. Loads and reloads
    /// intentionally share this key so an older protected operation cannot
    /// execute after a newer semantic revision has won.
    case trackedMainFrameNavigation(ObjectIdentifier)
    case evictHiddenWebViews(UUID)
    case cleanupTabWebView(ObjectIdentifier)
    case performFallbackWebViewCleanup(ObjectIdentifier)
}

/// Describes how a deferred rebuild must recreate its WebViews. Keeping this
/// intent in the command prevents a protected extension-page navigation from
/// later being replayed with a normal-tab configuration.
public enum DeferredWebViewRebuildConfiguration: Equatable {
    case normal
    case currentExtensionPage
}

public enum DeferredWebViewRebuildKind: Equatable {
    /// User or policy navigation with an explicit semantic destination. This
    /// intent must never be overwritten by opportunistic maintenance work.
    case semanticNavigation
    /// Recreates the current surface without changing its semantic destination.
    case maintenance
}

public struct DeferredWebViewRebuildIntent: Equatable {
    public let revision: UInt64
    public let targetURL: URL
    public let configuration: DeferredWebViewRebuildConfiguration
    public let kind: DeferredWebViewRebuildKind

    public init(
        revision: UInt64,
        targetURL: URL,
        configuration: DeferredWebViewRebuildConfiguration,
        kind: DeferredWebViewRebuildKind
    ) {
        self.revision = revision
        self.targetURL = targetURL
        self.configuration = configuration
        self.kind = kind
    }
}

/// Immutable desired-profile transaction carried across compositor protection.
/// `desiredProfileID` is the value that will become observable on the Tab;
/// `resolvedProfileID` identifies the concrete profile used to provision every
/// replacement when the desired value intentionally inherits from a space.
public struct DeferredWebViewProfileAssignmentIntent: Equatable {
    public let revision: UInt64
    public let expectedProfileID: UUID?
    public let desiredProfileID: UUID?
    public let resolvedProfileID: UUID
    public let targetURL: URL
    public let requiresStructuralPersistence: Bool

    public init(
        revision: UInt64,
        expectedProfileID: UUID?,
        desiredProfileID: UUID?,
        resolvedProfileID: UUID,
        targetURL: URL,
        requiresStructuralPersistence: Bool = false
    ) {
        self.revision = revision
        self.expectedProfileID = expectedProfileID
        self.desiredProfileID = desiredProfileID
        self.resolvedProfileID = resolvedProfileID
        self.targetURL = targetURL
        self.requiresStructuralPersistence = requiresStructuralPersistence
    }
}

/// Immutable multi-tab transaction for changing the profile inherited from a
/// space. The space remains on `expectedProfileID` until every affected live
/// WebView has a target-profile replacement ready for one batch CAS.
public struct DeferredWebViewSpaceProfileTabIntent: Equatable {
    public let tabID: UUID
    public let intent: DeferredWebViewProfileAssignmentIntent

    public init(tabID: UUID, intent: DeferredWebViewProfileAssignmentIntent) {
        self.tabID = tabID
        self.intent = intent
    }
}

public struct DeferredWebViewSpaceProfileAssignmentIntent: Equatable {
    public let revision: UInt64
    public let spaceID: UUID
    public let expectedProfileID: UUID?
    public let desiredProfileID: UUID
    public let tabIntents: [DeferredWebViewSpaceProfileTabIntent]

    public init(
        revision: UInt64,
        spaceID: UUID,
        expectedProfileID: UUID?,
        desiredProfileID: UUID,
        tabIntents: [DeferredWebViewSpaceProfileTabIntent]
    ) {
        self.revision = revision
        self.spaceID = spaceID
        self.expectedProfileID = expectedProfileID
        self.desiredProfileID = desiredProfileID
        self.tabIntents = tabIntents
    }
}

/// Immutable identity for a cross-window navigation replay. The revision ties
/// the deferred load to the semantic navigation that produced it, so a stale
/// protected clone cannot navigate after a newer user action has won.
public struct DeferredWebViewNavigationIntent: Equatable {
    public let revision: UInt64
    public let targetURL: URL

    public init(revision: UInt64, targetURL: URL) {
        self.revision = revision
        self.targetURL = targetURL
    }
}

public enum WebRuntimeMainFrameReloadPolicy: Equatable {
    case standard
    case fromOrigin
}

/// Immutable identity for a reload that must survive compositor protection.
/// URL equality is deliberately insufficient: reloading an already matching
/// document is the effect, so validity is tied to the exact semantic revision.
public struct DeferredWebViewReloadIntent: Equatable {
    public let revision: UInt64
    public let targetURL: URL
    public let policy: WebRuntimeMainFrameReloadPolicy

    public init(
        revision: UInt64,
        targetURL: URL,
        policy: WebRuntimeMainFrameReloadPolicy
    ) {
        self.revision = revision
        self.targetURL = targetURL
        self.policy = policy
    }
}

public enum DeferredWebViewCommand {
    case removeWebViewFromContainers(webViewID: ObjectIdentifier)
    case removeTrackedWebView(webViewID: ObjectIdentifier, tabID: UUID, windowID: UUID)
    case closeWebViewFromWebKit(webViewID: ObjectIdentifier)
    case cleanupWindow(windowID: UUID)
    case cleanupAllWebViews
    case rebuildLiveWebViews(
        tabID: UUID,
        preferredPrimaryWindowID: UUID?,
        intent: DeferredWebViewRebuildIntent
    )
    case assignProfile(
        tabID: UUID,
        preferredPrimaryWindowID: UUID?,
        intent: DeferredWebViewProfileAssignmentIntent
    )
    case assignSpaceProfile(intent: DeferredWebViewSpaceProfileAssignmentIntent)
    case synchronizeTrackedNavigation(
        webViewID: ObjectIdentifier,
        tabID: UUID,
        windowID: UUID,
        intent: DeferredWebViewNavigationIntent
    )
    case reloadTrackedNavigation(
        webViewID: ObjectIdentifier,
        tabID: UUID,
        windowID: UUID,
        intent: DeferredWebViewReloadIntent
    )
    case evictHiddenWebViews(windowID: UUID)
    case cleanupTabWebView(webViewID: ObjectIdentifier, tabID: UUID)
    case performFallbackWebViewCleanup(
        webViewID: ObjectIdentifier,
        lease: WebViewPendingCleanupLease
    )

    public var key: DeferredWebViewCommandKey {
        switch self {
        case .removeWebViewFromContainers(let webViewID):
            return .removeWebViewFromContainers(webViewID)
        case .removeTrackedWebView(let webViewID, let tabID, let windowID):
            return .removeTrackedWebView(webViewID, tabID, windowID)
        case .closeWebViewFromWebKit(let webViewID):
            return .closeWebViewFromWebKit(webViewID)
        case .cleanupWindow(let windowID):
            return .cleanupWindow(windowID)
        case .cleanupAllWebViews:
            return .cleanupAllWebViews
        case .rebuildLiveWebViews(let tabID, _, _):
            return .rebuildLiveWebViews(tabID)
        case .assignProfile(let tabID, _, _):
            return .assignProfile(tabID)
        case .assignSpaceProfile(let intent):
            return .assignSpaceProfile(intent.spaceID)
        case .synchronizeTrackedNavigation(let webViewID, _, _, _):
            return .trackedMainFrameNavigation(webViewID)
        case .reloadTrackedNavigation(let webViewID, _, _, _):
            return .trackedMainFrameNavigation(webViewID)
        case .evictHiddenWebViews(let windowID):
            return .evictHiddenWebViews(windowID)
        case .cleanupTabWebView(let webViewID, _):
            return .cleanupTabWebView(webViewID)
        case .performFallbackWebViewCleanup(let webViewID, _):
            return .performFallbackWebViewCleanup(webViewID)
        }
    }

    public var debugSummary: String {
        switch self {
        case .removeWebViewFromContainers(let webViewID):
            return "removeWebViewFromContainers webView=\(webViewID)"
        case .removeTrackedWebView(let webViewID, let tabID, let windowID):
            return "removeTrackedWebView tab=\(tabID.uuidString.prefix(8)) window=\(windowID.uuidString.prefix(8)) webView=\(webViewID)"
        case .closeWebViewFromWebKit(let webViewID):
            return "closeWebViewFromWebKit webView=\(webViewID)"
        case .cleanupWindow(let windowID):
            return "cleanupWindow window=\(windowID.uuidString.prefix(8))"
        case .cleanupAllWebViews:
            return "cleanupAllWebViews"
        case .rebuildLiveWebViews(
            let tabID,
            let preferredPrimaryWindowID,
            let intent
        ):
            return "rebuildLiveWebViews tab=\(tabID.uuidString.prefix(8)) revision=\(intent.revision) kind=\(intent.kind) preferredWindow=\(preferredPrimaryWindowID?.uuidString.prefix(8) ?? "nil") target=\(intent.targetURL.absoluteString) configuration=\(intent.configuration)"
        case .assignProfile(
            let tabID,
            let preferredPrimaryWindowID,
            let intent
        ):
            return "assignProfile tab=\(tabID.uuidString.prefix(8)) revision=\(intent.revision) expected=\(intent.expectedProfileID?.uuidString.prefix(8) ?? "nil") desired=\(intent.desiredProfileID?.uuidString.prefix(8) ?? "nil") resolved=\(intent.resolvedProfileID.uuidString.prefix(8)) preferredWindow=\(preferredPrimaryWindowID?.uuidString.prefix(8) ?? "nil") target=\(intent.targetURL.absoluteString)"
        case .assignSpaceProfile(let intent):
            return "assignSpaceProfile space=\(intent.spaceID.uuidString.prefix(8)) revision=\(intent.revision) expected=\(intent.expectedProfileID?.uuidString.prefix(8) ?? "nil") desired=\(intent.desiredProfileID.uuidString.prefix(8)) tabs=\(intent.tabIntents.count)"
        case .synchronizeTrackedNavigation(
            let webViewID,
            let tabID,
            let windowID,
            let intent
        ):
            return "synchronizeTrackedNavigation tab=\(tabID.uuidString.prefix(8)) window=\(windowID.uuidString.prefix(8)) webView=\(webViewID) revision=\(intent.revision) target=\(intent.targetURL.absoluteString)"
        case .reloadTrackedNavigation(
            let webViewID,
            let tabID,
            let windowID,
            let intent
        ):
            return "reloadTrackedNavigation tab=\(tabID.uuidString.prefix(8)) window=\(windowID.uuidString.prefix(8)) webView=\(webViewID) revision=\(intent.revision) policy=\(intent.policy) target=\(intent.targetURL.absoluteString)"
        case .evictHiddenWebViews(let windowID):
            return "evictHiddenWebViews window=\(windowID.uuidString.prefix(8))"
        case .cleanupTabWebView(let webViewID, let tabID):
            return "cleanupTabWebView tab=\(tabID.uuidString.prefix(8)) webView=\(webViewID)"
        case .performFallbackWebViewCleanup(let webViewID, let lease):
            return "performFallbackWebViewCleanup tab=\(lease.tabID.uuidString.prefix(8)) lease=\(lease.id.uuidString.prefix(8)) webView=\(webViewID)"
        }
    }

    var requiresGuaranteedDelivery: Bool {
        switch self {
        case .rebuildLiveWebViews(_, _, let intent):
            return intent.kind == .semanticNavigation
        case .synchronizeTrackedNavigation,
             .reloadTrackedNavigation,
             .assignProfile,
             .assignSpaceProfile:
            return true
        case .evictHiddenWebViews:
            return false
        case .removeWebViewFromContainers,
             .removeTrackedWebView,
             .closeWebViewFromWebKit,
             .cleanupWindow,
             .cleanupAllWebViews,
             .cleanupTabWebView,
             .performFallbackWebViewCleanup:
            return true
        }
    }
}

public enum DeferredProtectedCommandEnqueueOutcome: Equatable {
    case enqueued
    case collapsed
    case droppedAtCapacity
}

public struct DeferredProtectedCommandEnqueueResult {
    public let outcome: DeferredProtectedCommandEnqueueOutcome
    public let queuedCommandCount: Int
    /// Commands whose effect is now represented by another queued command.
    /// This includes the incoming command when an existing broader command
    /// already covers it, allowing the owner to finish drop diagnostics.
    public let supersededCommands: [DeferredWebViewCommand]
    /// Replaceable maintenance work displaced solely to honor the soft
    /// capacity. Its effect is intentionally abandoned, not subsumed.
    public let capacityDisplacedCommands: [DeferredWebViewCommand]

    init(
        outcome: DeferredProtectedCommandEnqueueOutcome,
        queuedCommandCount: Int,
        supersededCommands: [DeferredWebViewCommand] = [],
        capacityDisplacedCommands: [DeferredWebViewCommand] = []
    ) {
        self.outcome = outcome
        self.queuedCommandCount = queuedCommandCount
        self.supersededCommands = supersededCommands
        self.capacityDisplacedCommands = capacityDisplacedCommands
    }
}

public enum DeferredProtectedCommandSchedulingOutcome: Equatable {
    case scheduled
    case notProtected
    case invalidTarget
    case droppedAtCapacity

    public var wasScheduled: Bool {
        self == .scheduled
    }
}

/// The executor's final disposition for a command already removed from its
/// protected-source queue.
public enum DeferredProtectedCommandExecutionOutcome: Equatable {
    /// The command's effect completed and the command is consumed.
    case executed
    /// The target became invalid after queue validation; the command is
    /// consumed and reported through the command dropper.
    case invalidTarget
    /// Execution could not complete for a transient reason. Guaranteed work
    /// is restored through the queue's normal dominance rules.
    case retry
}

public struct DeferredProtectedCommandBuffer {
    /// Memory-shedding threshold for replaceable maintenance work, not a hard
    /// correctness bound. Commands with guaranteed delivery may temporarily
    /// exceed it; repeated semantic keys still coalesce in place.
    public static let softCapacity = 8

    public private(set) var commands: [DeferredWebViewCommand] = []

    public init() {}

    public var count: Int { commands.count }
    public var isEmpty: Bool { commands.isEmpty }

    public mutating func enqueue(_ command: DeferredWebViewCommand) -> DeferredProtectedCommandEnqueueOutcome {
        enqueueReportingSupersededCommands(command).outcome
    }

    public mutating func enqueueReportingSupersededCommands(
        _ command: DeferredWebViewCommand
    ) -> DeferredProtectedCommandEnqueueResult {
        let matchingKeyIndex = commands.firstIndex { $0.key == command.key }
        if let matchingKeyIndex,
           command.semanticPriority(comparedTo: commands[matchingKeyIndex]) == .orderedAscending {
            return DeferredProtectedCommandEnqueueResult(
                outcome: .collapsed,
                queuedCommandCount: commands.count,
                supersededCommands: [command]
            )
        }

        if matchingKeyIndex == nil,
           commands.contains(where: { $0.dominates(command) }) {
            return DeferredProtectedCommandEnqueueResult(
                outcome: .collapsed,
                queuedCommandCount: commands.count,
                supersededCommands: [command]
            )
        }

        let supersededIndices = commands.indices.filter { index in
            index == matchingKeyIndex || command.dominates(commands[index])
        }
        let insertionIndex = supersededIndices.first ?? commands.endIndex
        let supersededCommands = supersededIndices.map { commands[$0] }
        for index in supersededIndices.reversed() {
            commands.remove(at: index)
        }

        if matchingKeyIndex != nil {
            commands.insert(command, at: min(insertionIndex, commands.endIndex))
            return DeferredProtectedCommandEnqueueResult(
                outcome: .collapsed,
                queuedCommandCount: commands.count,
                supersededCommands: supersededCommands
            )
        }

        guard commands.count < Self.softCapacity else {
            if command.requiresGuaranteedDelivery {
                var capacityDisplacedCommands: [DeferredWebViewCommand] = []
                var capacityInsertionIndex = insertionIndex
                if let replaceableIndex = commands.lastIndex(where: {
                    $0.requiresGuaranteedDelivery == false
                }) {
                    capacityDisplacedCommands.append(commands.remove(at: replaceableIndex))
                    if replaceableIndex < capacityInsertionIndex {
                        capacityInsertionIndex -= 1
                    }
                }
                if supersededIndices.isEmpty {
                    commands.append(command)
                } else {
                    commands.insert(
                        command,
                        at: min(capacityInsertionIndex, commands.endIndex)
                    )
                }
                return DeferredProtectedCommandEnqueueResult(
                    outcome: .enqueued,
                    queuedCommandCount: commands.count,
                    supersededCommands: supersededCommands,
                    capacityDisplacedCommands: capacityDisplacedCommands
                )
            }
            return DeferredProtectedCommandEnqueueResult(
                outcome: .droppedAtCapacity,
                queuedCommandCount: commands.count
            )
        }
        commands.insert(command, at: min(insertionIndex, commands.endIndex))
        return DeferredProtectedCommandEnqueueResult(
            outcome: .enqueued,
            queuedCommandCount: commands.count,
            supersededCommands: supersededCommands
        )
    }

    public mutating func prune(
        where shouldDrop: (DeferredWebViewCommand) -> Bool
    ) -> [DeferredWebViewCommand] {
        var dropped: [DeferredWebViewCommand] = []
        commands.removeAll { command in
            guard shouldDrop(command) else { return false }
            dropped.append(command)
            return true
        }
        return dropped
    }

    public mutating func drain() -> [DeferredWebViewCommand] {
        let drained = commands
        commands.removeAll(keepingCapacity: true)
        return drained
    }

    mutating func popFirst() -> DeferredWebViewCommand? {
        guard commands.isEmpty == false else { return nil }
        return commands.removeFirst()
    }

    @discardableResult
    mutating func restoreFirstIfNoNewerCommandExists(
        _ command: DeferredWebViewCommand
    ) -> [DeferredWebViewCommand] {
        let matchingKeyIndex = commands.firstIndex(where: {
            $0.key == command.key
        })
        if let matchingKeyIndex {
            guard command.semanticPriority(
                comparedTo: commands[matchingKeyIndex]
            ) == .orderedDescending else {
                return [command]
            }
        }

        guard commands.indices.contains(where: { index in
            index != matchingKeyIndex && commands[index].dominates(command)
        }) == false else {
            return [command]
        }

        var supersededCommands: [DeferredWebViewCommand] = []
        if let matchingKeyIndex {
            supersededCommands.append(commands.remove(at: matchingKeyIndex))
        }
        supersededCommands.append(contentsOf: commands.filter {
            command.dominates($0)
        })
        commands.removeAll { command.dominates($0) }
        commands.insert(command, at: 0)
        return supersededCommands
    }
}

private extension DeferredWebViewCommand {
    /// Whether this command makes `candidate` redundant in the same protected
    /// source-WebView queue. Scope IDs must prove containment; the source queue
    /// alone is not used to infer a window or tab owner.
    func dominates(_ candidate: DeferredWebViewCommand) -> Bool {
        switch self {
        case .cleanupAllWebViews:
            switch candidate {
            case .removeTrackedWebView,
                 .synchronizeTrackedNavigation,
                 .reloadTrackedNavigation,
                 .evictHiddenWebViews:
                return true
            case .removeWebViewFromContainers,
                 .closeWebViewFromWebKit,
                 .cleanupWindow,
                 .cleanupAllWebViews,
                 .assignProfile,
                 .assignSpaceProfile,
                 .rebuildLiveWebViews,
                 .cleanupTabWebView,
                 .performFallbackWebViewCleanup:
                return false
            }

        case .cleanupWindow(let windowID):
            switch candidate {
            case .cleanupWindow(let candidateWindowID),
                 .evictHiddenWebViews(let candidateWindowID):
                return candidateWindowID == windowID
            case .removeTrackedWebView(_, _, let candidateWindowID),
                 .synchronizeTrackedNavigation(_, _, let candidateWindowID, _),
                 .reloadTrackedNavigation(_, _, let candidateWindowID, _):
                return candidateWindowID == windowID
            default:
                return false
            }

        case .closeWebViewFromWebKit(let webViewID):
            switch candidate {
            case .removeWebViewFromContainers(let candidateWebViewID),
                 .removeTrackedWebView(let candidateWebViewID, _, _),
                 .synchronizeTrackedNavigation(let candidateWebViewID, _, _, _),
                 .reloadTrackedNavigation(let candidateWebViewID, _, _, _):
                return candidateWebViewID == webViewID
            default:
                return false
            }

        case .removeTrackedWebView(let webViewID, _, _),
             .cleanupTabWebView(let webViewID, _),
             .performFallbackWebViewCleanup(let webViewID, _):
            switch candidate {
            case .removeWebViewFromContainers(let candidateWebViewID),
                 .synchronizeTrackedNavigation(let candidateWebViewID, _, _, _),
                 .reloadTrackedNavigation(let candidateWebViewID, _, _, _):
                return candidateWebViewID == webViewID
            default:
                return false
            }

        case .assignProfile(let tabID, _, _):
            if case .rebuildLiveWebViews(
                let candidateTabID,
                _,
                let candidateIntent
            ) = candidate {
                return candidateTabID == tabID
                    && candidateIntent.kind == .maintenance
            }
            return false

        case .assignSpaceProfile(let intent):
            if case .rebuildLiveWebViews(
                let candidateTabID,
                _,
                let candidateIntent
            ) = candidate {
                return candidateIntent.kind == .maintenance
                    && intent.tabIntents.contains { $0.tabID == candidateTabID }
            }
            return false

        case .removeWebViewFromContainers,
             .rebuildLiveWebViews,
             .synchronizeTrackedNavigation,
             .reloadTrackedNavigation,
             .evictHiddenWebViews:
            return false
        }
    }

    func semanticPriority(
        comparedTo other: DeferredWebViewCommand
    ) -> ComparisonResult? {
        if case .rebuildLiveWebViews(_, _, let intent) = self,
           case .rebuildLiveWebViews(_, _, let otherIntent) = other {
            if intent.kind != otherIntent.kind {
                return intent.kind == .semanticNavigation
                    ? .orderedDescending
                    : .orderedAscending
            }
            if intent.revision != otherIntent.revision {
                return intent.revision > otherIntent.revision
                    ? .orderedDescending
                    : .orderedAscending
            }
            return .orderedSame
        }

        if case .assignProfile(_, _, let intent) = self,
           case .assignProfile(_, _, let otherIntent) = other {
            if intent.revision != otherIntent.revision {
                return intent.revision > otherIntent.revision
                    ? .orderedDescending
                    : .orderedAscending
            }
            return .orderedSame
        }

        if case .assignSpaceProfile(let intent) = self,
           case .assignSpaceProfile(let otherIntent) = other {
            if intent.revision != otherIntent.revision {
                return intent.revision > otherIntent.revision
                    ? .orderedDescending
                    : .orderedAscending
            }
            return .orderedSame
        }

        guard let navigationPriority,
              let otherNavigationPriority = other.navigationPriority else {
            return nil
        }
        if navigationPriority.revision != otherNavigationPriority.revision {
            return navigationPriority.revision > otherNavigationPriority.revision
                ? .orderedDescending
                : .orderedAscending
        }
        if navigationPriority.operationRank != otherNavigationPriority.operationRank {
            return navigationPriority.operationRank > otherNavigationPriority.operationRank
                ? .orderedDescending
                : .orderedAscending
        }
        return .orderedSame
    }

    var navigationPriority: (revision: UInt64, operationRank: Int)? {
        switch self {
        case .synchronizeTrackedNavigation(_, _, _, let intent):
            return (intent.revision, 0)
        case .reloadTrackedNavigation(_, _, _, let intent):
            return (intent.revision, intent.policy == .fromOrigin ? 2 : 1)
        default:
            return nil
        }
    }
}

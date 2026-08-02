import Foundation
import WebKit

/// Exact ownership token for one visual-handoff protection claim.
/// Multiple compositor generations may temporarily protect the same WebView;
/// releasing an older claim must not remove a newer controller's protection.
public struct WebViewVisualHandoffProtectionLease: Hashable {
    public let webViewID: ObjectIdentifier
    fileprivate let id: UUID

    fileprivate init(webViewID: ObjectIdentifier) {
        self.webViewID = webViewID
        self.id = UUID()
    }
}

private struct HistorySwipeProtectionContext {
    let windowID: UUID?
    let originURL: URL?
    let originHistoryItem: WKBackForwardListItem?
    let originHistoryURL: URL?
}

private struct WeakWebViewRegistry {
    private var webViewsByIdentifier: [ObjectIdentifier: WebViewIdentityWitness] = [:]

    mutating func note(_ webView: WKWebView) {
        let witness = WebViewIdentityWitness(webView)
        webViewsByIdentifier[witness.identifier] = witness
    }

    mutating func resolve(with identifier: ObjectIdentifier) -> WKWebView? {
        if let webView = webViewsByIdentifier[identifier]?.resolve() {
            return webView
        }
        webViewsByIdentifier.removeValue(forKey: identifier)
        return nil
    }

    mutating func pruneStaleIdentifiers() -> [ObjectIdentifier] {
        let staleIDs = webViewsByIdentifier.compactMap { key, entry -> ObjectIdentifier? in
            entry.resolve() == nil ? key : nil
        }
        for id in staleIDs {
            webViewsByIdentifier.removeValue(forKey: id)
        }
        return staleIDs
    }

    mutating func removeAll() {
        webViewsByIdentifier.removeAll()
    }
}

private struct DeferredProtectedWebViewCommandStore {
    private var buffersBySourceWebViewID: [ObjectIdentifier: DeferredProtectedCommandBuffer] = [:]

    var sourceWebViewIDs: [ObjectIdentifier] {
        Array(buffersBySourceWebViewID.keys)
    }

    var isEmpty: Bool {
        buffersBySourceWebViewID.isEmpty
    }

    func hasCommands(for sourceWebViewID: ObjectIdentifier) -> Bool {
        buffersBySourceWebViewID[sourceWebViewID]?.isEmpty == false
    }

    mutating func enqueue(
        _ command: DeferredWebViewCommand,
        sourceWebViewID: ObjectIdentifier
    ) -> DeferredProtectedCommandEnqueueResult {
        var buffer = buffersBySourceWebViewID[sourceWebViewID]
            ?? DeferredProtectedCommandBuffer()
        let result = buffer.enqueueReportingSupersededCommands(command)
        buffersBySourceWebViewID[sourceWebViewID] = buffer
        return result
    }

    mutating func drainCommands(for sourceWebViewID: ObjectIdentifier) -> [DeferredWebViewCommand] {
        var buffer = buffersBySourceWebViewID.removeValue(forKey: sourceWebViewID)
        return buffer?.drain() ?? []
    }

    func firstCommand(for sourceWebViewID: ObjectIdentifier) -> DeferredWebViewCommand? {
        buffersBySourceWebViewID[sourceWebViewID]?.commands.first
    }

    mutating func popFirstCommand(
        for sourceWebViewID: ObjectIdentifier
    ) -> DeferredWebViewCommand? {
        guard var buffer = buffersBySourceWebViewID[sourceWebViewID] else {
            return nil
        }
        let command = buffer.popFirst()
        if buffer.isEmpty {
            buffersBySourceWebViewID.removeValue(forKey: sourceWebViewID)
        } else {
            buffersBySourceWebViewID[sourceWebViewID] = buffer
        }
        return command
    }

    @discardableResult
    mutating func restoreFirstCommandIfNoNewerCommandExists(
        _ command: DeferredWebViewCommand,
        for sourceWebViewID: ObjectIdentifier
    ) -> [DeferredWebViewCommand] {
        var buffer = buffersBySourceWebViewID[sourceWebViewID]
            ?? DeferredProtectedCommandBuffer()
        let supersededCommands = buffer.restoreFirstIfNoNewerCommandExists(command)
        buffersBySourceWebViewID[sourceWebViewID] = buffer
        return supersededCommands
    }

    mutating func removeAllCommands(for sourceWebViewID: ObjectIdentifier) {
        buffersBySourceWebViewID.removeValue(forKey: sourceWebViewID)
    }

    mutating func removeAllCommands() {
        buffersBySourceWebViewID.removeAll()
    }

    mutating func pruneCommands(
        for sourceWebViewID: ObjectIdentifier,
        where shouldDrop: (DeferredWebViewCommand) -> Bool
    ) -> [DeferredWebViewCommand] {
        guard var buffer = buffersBySourceWebViewID[sourceWebViewID] else {
            return []
        }

        let droppedCommands = buffer.prune(where: shouldDrop)
        if buffer.isEmpty {
            buffersBySourceWebViewID.removeValue(forKey: sourceWebViewID)
        } else {
            buffersBySourceWebViewID[sourceWebViewID] = buffer
        }
        return droppedCommands
    }
}

@MainActor
public final class WebViewProtectedCommandOwner {
    public init() {}

    public typealias CommandValidator = (DeferredWebViewCommand) -> Bool
    public typealias CommandDropper = (DeferredWebViewCommand, ObjectIdentifier, String) -> Void
    public typealias CommandExecutor = (
        DeferredWebViewCommand
    ) -> DeferredProtectedCommandExecutionOutcome
    public typealias WebViewResolver = (ObjectIdentifier) -> WKWebView?

    private var activeHistorySwipeProtections: [ObjectIdentifier: HistorySwipeProtectionContext] = [:]
    private var visualHandoffProtectionLeasesByWebViewID: [
        ObjectIdentifier: Set<WebViewVisualHandoffProtectionLease>
    ] = [:]
    private var deferredProtectedWebViewCommands = DeferredProtectedWebViewCommandStore()
    private var weakWebViewRegistry = WeakWebViewRegistry()

    public func note(_ webView: WKWebView) {
        weakWebViewRegistry.note(webView)
    }

    public func resolveWeakWebView(with identifier: ObjectIdentifier) -> WKWebView? {
        weakWebViewRegistry.resolve(with: identifier)
    }

    public var hasDeferredCommands: Bool {
        deferredProtectedWebViewCommands.isEmpty == false
    }

    public func hasDeferredCommands(for sourceWebViewID: ObjectIdentifier) -> Bool {
        deferredProtectedWebViewCommands.hasCommands(for: sourceWebViewID)
    }

    public func beginHistorySwipeProtection(
        on webView: WKWebView,
        windowID: UUID?,
        originURL: URL?,
        originHistoryItem: WKBackForwardListItem?
    ) -> ObjectIdentifier {
        let webViewID = ObjectIdentifier(webView)
        note(webView)
        activeHistorySwipeProtections[webViewID] = HistorySwipeProtectionContext(
            windowID: windowID,
            originURL: originURL,
            originHistoryItem: originHistoryItem,
            originHistoryURL: originHistoryItem?.url
        )
        return webViewID
    }

    @discardableResult
    public func finishHistorySwipeProtection(
        on webView: WKWebView?,
        currentURL: URL?,
        currentHistoryItem: WKBackForwardListItem?
    ) -> (webViewID: ObjectIdentifier, wasCancelled: Bool)? {
        guard let webView else { return nil }
        let webViewID = ObjectIdentifier(webView)
        guard let context = activeHistorySwipeProtections.removeValue(
            forKey: webViewID
        ) else { return nil }
        let wasCancelled = isCancelledHistorySwipe(
            context: context,
            currentURL: currentURL,
            currentHistoryItem: currentHistoryItem
        )
        return (webViewID, wasCancelled)
    }

    public func hasActiveHistorySwipe(in windowID: UUID) -> Bool {
        activeHistorySwipeProtections.values.contains { $0.windowID == windowID }
    }

    public func isProtected(_ webView: WKWebView) -> Bool {
        isProtected(ObjectIdentifier(webView))
    }

    public func isProtected(_ webViewID: ObjectIdentifier) -> Bool {
        activeHistorySwipeProtections[webViewID] != nil
            || visualHandoffProtectionLeasesByWebViewID[webViewID]?.isEmpty == false
    }

    public func beginVisualHandoffProtection(
        for webView: WKWebView
    ) -> WebViewVisualHandoffProtectionLease {
        let webViewID = ObjectIdentifier(webView)
        note(webView)
        let lease = WebViewVisualHandoffProtectionLease(webViewID: webViewID)
        visualHandoffProtectionLeasesByWebViewID[webViewID, default: []].insert(lease)
        return lease
    }

    public func finishVisualHandoffProtection(
        _ lease: WebViewVisualHandoffProtectionLease
    ) -> ObjectIdentifier? {
        guard var leases = visualHandoffProtectionLeasesByWebViewID[lease.webViewID],
              leases.remove(lease) != nil else {
            return nil
        }
        if leases.isEmpty {
            visualHandoffProtectionLeasesByWebViewID.removeValue(forKey: lease.webViewID)
        } else {
            visualHandoffProtectionLeasesByWebViewID[lease.webViewID] = leases
        }
        return lease.webViewID
    }

    /// Removes protection owned by window/compositor runtime teardown and
    /// returns deferred-command sources that became executable as a result.
    /// History-swipe protection is intentionally preserved and those sources
    /// remain queued until the swipe ends.
    public func removeVisualHandoffProtections() -> [ObjectIdentifier] {
        let deferredSourceIDs = deferredProtectedWebViewCommands.sourceWebViewIDs
        visualHandoffProtectionLeasesByWebViewID.removeAll()
        return deferredSourceIDs
            .filter { isProtected($0) == false }
            .sorted {
                UInt(bitPattern: $0) < UInt(bitPattern: $1)
            }
    }

    /// Drops every protection claim and deferred command when the owning
    /// browser runtime has ended. Unlike window cleanup, terminal shutdown
    /// cannot wait for a history gesture or execute model-dependent commands.
    public func resetForTerminalShutdown() {
        activeHistorySwipeProtections.removeAll()
        visualHandoffProtectionLeasesByWebViewID.removeAll()
        deferredProtectedWebViewCommands.removeAllCommands()
        weakWebViewRegistry.removeAll()
    }

    @discardableResult
    public func enqueueDeferredCommandIfNeeded(
        _ command: DeferredWebViewCommand,
        for webView: WKWebView,
        reason: String,
        resolveWebView: WebViewResolver,
        isCommandValid: CommandValidator,
        dropCommand: CommandDropper,
        didPruneStaleWebViewIDs: ([ObjectIdentifier]) -> Void
    ) -> DeferredProtectedCommandSchedulingOutcome {
        let sourceWebViewID = ObjectIdentifier(webView)
        note(webView)
        guard isProtected(sourceWebViewID) else {
            return .notProtected
        }

        didPruneStaleWebViewIDs(
            pruneInvalidDeferredCommands(
                reason: "enqueue.preflight",
                resolveWebView: resolveWebView,
                isCommandValid: isCommandValid,
                dropCommand: dropCommand
            )
        )
        guard isCommandValid(command) else {
            dropCommand(
                command,
                sourceWebViewID,
                "\(reason).invalidTarget"
            )
            return .invalidTarget
        }

        let enqueueResult = deferredProtectedWebViewCommands.enqueue(
            command,
            sourceWebViewID: sourceWebViewID
        )
        for supersededCommand in enqueueResult.supersededCommands {
            dropCommand(
                supersededCommand,
                sourceWebViewID,
                "\(reason).superseded"
            )
        }
        for displacedCommand in enqueueResult.capacityDisplacedCommands {
            dropCommand(
                displacedCommand,
                sourceWebViewID,
                "\(reason).capacityReplacement"
            )
        }

        switch enqueueResult.outcome {
        case .enqueued:
            SumiWebRuntimeDiagnostics.emitPerformanceEvent(
                "WebViewProtectedCommandOwner.enqueueDeferredProtectedCommand"
            )
            SumiWebRuntimeDiagnostics.protectedWebViewTrace(
                "enqueueDeferredCommand reason=\(reason) sourceWebView=\(sourceWebViewID) command={\(command.debugSummary)} count=\(enqueueResult.queuedCommandCount)"
            )
        case .collapsed:
            SumiWebRuntimeDiagnostics.emitPerformanceEvent(
                "WebViewProtectedCommandOwner.collapseDeferredProtectedCommand"
            )
            SumiWebRuntimeDiagnostics.protectedWebViewTrace(
                "collapseDeferredCommand reason=\(reason) sourceWebView=\(sourceWebViewID) command={\(command.debugSummary)} count=\(enqueueResult.queuedCommandCount)"
            )
        case .droppedAtCapacity:
            dropCommand(
                command,
                sourceWebViewID,
                "\(reason).capacity"
            )
        }
        switch enqueueResult.outcome {
        case .enqueued, .collapsed:
            return .scheduled
        case .droppedAtCapacity:
            return .droppedAtCapacity
        }
    }

    /// Executes valid deferred commands while their source remains unprotected.
    /// Each final protection check, queue removal, and callback are contiguous
    /// on the main actor so callers cannot create a check/execute gap by taking
    /// ownership of a command first.
    @discardableResult
    public func executeDeferredCommandsIfUnprotected(
        for webViewID: ObjectIdentifier,
        resolveWebView: WebViewResolver,
        isCommandValid: CommandValidator,
        dropCommand: CommandDropper,
        didPruneStaleWebViewIDs: ([ObjectIdentifier]) -> Void,
        executeCommand: CommandExecutor
    ) -> Int {
        guard isProtected(webViewID) == false else { return 0 }
        didPruneStaleWebViewIDs(
            pruneInvalidDeferredCommands(
                reason: "flush.preflight",
                resolveWebView: resolveWebView,
                isCommandValid: isCommandValid,
                dropCommand: dropCommand
            )
        )
        guard isProtected(webViewID) == false else { return 0 }

        var executedCommandCount = 0
        while isProtected(webViewID) == false,
              let command = deferredProtectedWebViewCommands.firstCommand(for: webViewID) {
            let isValid = isCommandValid(command)
            guard isProtected(webViewID) == false else {
                return executedCommandCount
            }

            guard isValid else {
                _ = deferredProtectedWebViewCommands.popFirstCommand(for: webViewID)
                dropCommand(command, webViewID, "flush.invalidTarget")
                continue
            }
            guard let command = deferredProtectedWebViewCommands.popFirstCommand(
                for: webViewID
            ) else { continue }

            switch executeCommand(command) {
            case .executed:
                executedCommandCount += 1

            case .invalidTarget:
                dropCommand(command, webViewID, "flush.execution.invalidTarget")

            case .retry:
                guard command.requiresGuaranteedDelivery else {
                    dropCommand(command, webViewID, "flush.retry.replaceable")
                    continue
                }
                let supersededCommands = deferredProtectedWebViewCommands
                    .restoreFirstCommandIfNoNewerCommandExists(
                    command,
                    for: webViewID
                )
                for supersededCommand in supersededCommands {
                    dropCommand(
                        supersededCommand,
                        webViewID,
                        "flush.restore.superseded"
                    )
                }
                return executedCommandCount
            }
        }
        return executedCommandCount
    }

    @discardableResult
    public func pruneInvalidDeferredCommands(
        reason: String,
        resolveWebView: WebViewResolver,
        isCommandValid: CommandValidator,
        dropCommand: CommandDropper
    ) -> [ObjectIdentifier] {
        let staleIDs = pruneStaleBookkeeping(reason: "\(reason).staleBookkeeping")

        for sourceWebViewID in deferredProtectedWebViewCommands.sourceWebViewIDs {
            guard resolveWebView(sourceWebViewID) != nil else {
                activeHistorySwipeProtections.removeValue(forKey: sourceWebViewID)
                for command in deferredProtectedWebViewCommands.drainCommands(for: sourceWebViewID) {
                    dropCommand(
                        command,
                        sourceWebViewID,
                        "\(reason).deadSource"
                    )
                }
                continue
            }

            let droppedCommands = deferredProtectedWebViewCommands.pruneCommands(for: sourceWebViewID) { command in
                isCommandValid(command) == false
            }

            for command in droppedCommands {
                dropCommand(
                    command,
                    sourceWebViewID,
                    "\(reason).invalidTarget"
                )
            }
        }

        return staleIDs
    }

    @discardableResult
    public func pruneStaleBookkeeping(reason: String) -> [ObjectIdentifier] {
        let staleIDs = weakWebViewRegistry.pruneStaleIdentifiers()
        guard staleIDs.isEmpty == false else { return [] }
        for id in staleIDs {
            activeHistorySwipeProtections.removeValue(forKey: id)
            visualHandoffProtectionLeasesByWebViewID.removeValue(forKey: id)
            deferredProtectedWebViewCommands.removeAllCommands(for: id)
        }
        SumiWebRuntimeDiagnostics.protectedWebViewTrace(
            "pruneStaleWebViewBookkeeping reason=\(reason) count=\(staleIDs.count)"
        )
        return staleIDs
    }

    private func isCancelledHistorySwipe(
        context: HistorySwipeProtectionContext?,
        currentURL: URL?,
        currentHistoryItem: WKBackForwardListItem?
    ) -> Bool {
        guard let context else { return false }
        if let originHistoryItem = context.originHistoryItem,
           let currentHistoryItem,
           originHistoryItem === currentHistoryItem {
            return true
        }
        let originURL = context.originHistoryURL ?? context.originURL
        let currentURL = currentHistoryItem?.url ?? currentURL
        return originURL != nil && originURL == currentURL
    }
}

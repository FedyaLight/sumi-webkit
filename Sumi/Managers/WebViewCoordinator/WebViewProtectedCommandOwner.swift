import Combine
import Foundation
import WebKit

private struct HistorySwipeProtectionContext {
    let windowID: UUID?
    let originURL: URL?
    let originHistoryItem: WKBackForwardListItem?
    let originHistoryURL: URL?
}

private struct FullscreenProtectionContext {
    let windowID: UUID?
}

@MainActor
private final class FullscreenWebViewProtection {
    private var activeContexts: [ObjectIdentifier: FullscreenProtectionContext] = [:]
    private var stateCancellablesByWebViewID: [ObjectIdentifier: AnyCancellable] = [:]

    func hasActive(in windowID: UUID) -> Bool {
        activeContexts.values.contains { $0.windowID == windowID }
    }

    func activeWebViewIDs(in windowID: UUID) -> [ObjectIdentifier] {
        activeContexts.compactMap { webViewID, context in
            context.windowID == windowID ? webViewID : nil
        }
    }

    func isProtected(_ webViewID: ObjectIdentifier) -> Bool {
        activeContexts[webViewID] != nil
    }

    func begin(webViewID: ObjectIdentifier, windowID: UUID?) {
        activeContexts[webViewID] = FullscreenProtectionContext(windowID: windowID)
    }

    func finish(webViewID: ObjectIdentifier) -> FullscreenProtectionContext? {
        activeContexts.removeValue(forKey: webViewID)
    }

    func remove(_ webViewID: ObjectIdentifier) {
        activeContexts.removeValue(forKey: webViewID)
        stateCancellablesByWebViewID.removeValue(forKey: webViewID)?.cancel()
    }

    func removeAll() {
        activeContexts.removeAll()
        stateCancellablesByWebViewID.values.forEach { $0.cancel() }
        stateCancellablesByWebViewID.removeAll()
    }

    func installObservationIfNeeded(
        on webView: WKWebView,
        stateDidChange: @escaping @MainActor (WKWebView) -> Void
    ) {
        let webViewID = ObjectIdentifier(webView)
        guard stateCancellablesByWebViewID[webViewID] == nil else {
            if webView.sumiIsInFullscreenElementPresentation {
                stateDidChange(webView)
            }
            return
        }

        stateCancellablesByWebViewID[webViewID] = webView
            .publisher(for: \.fullscreenState, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak webView] _ in
                guard let webView else { return }
                stateDidChange(webView)
            }
    }

    func uninstallObservationIfUntracked(_ webView: WKWebView, isTracked: Bool) {
        guard !isTracked else { return }
        remove(ObjectIdentifier(webView))
    }
}

private struct WeakWKWebView {
    weak var value: WKWebView?
}

private struct WeakWebViewRegistry {
    private var webViewsByIdentifier: [ObjectIdentifier: WeakWKWebView] = [:]

    mutating func note(_ webView: WKWebView) {
        webViewsByIdentifier[ObjectIdentifier(webView)] = WeakWKWebView(value: webView)
    }

    mutating func resolve(with identifier: ObjectIdentifier) -> WKWebView? {
        if let webView = webViewsByIdentifier[identifier]?.value {
            return webView
        }
        webViewsByIdentifier.removeValue(forKey: identifier)
        return nil
    }

    mutating func pruneStaleIdentifiers() -> [ObjectIdentifier] {
        let staleIDs = webViewsByIdentifier.compactMap { key, entry -> ObjectIdentifier? in
            entry.value == nil ? key : nil
        }
        for id in staleIDs {
            webViewsByIdentifier.removeValue(forKey: id)
        }
        return staleIDs
    }
}

private struct DeferredProtectedWebViewCommandStore {
    private var buffersBySourceWebViewID: [ObjectIdentifier: DeferredProtectedCommandBuffer] = [:]

    var sourceWebViewIDs: [ObjectIdentifier] {
        Array(buffersBySourceWebViewID.keys)
    }

    mutating func enqueue(
        _ command: DeferredWebViewCommand,
        sourceWebViewID: ObjectIdentifier
    ) -> (outcome: DeferredProtectedCommandEnqueueOutcome, count: Int) {
        var buffer = buffersBySourceWebViewID[sourceWebViewID]
            ?? DeferredProtectedCommandBuffer()
        let outcome = buffer.enqueue(command)
        buffersBySourceWebViewID[sourceWebViewID] = buffer
        return (outcome, buffer.count)
    }

    mutating func drainCommands(for sourceWebViewID: ObjectIdentifier) -> [DeferredWebViewCommand] {
        var buffer = buffersBySourceWebViewID.removeValue(forKey: sourceWebViewID)
        return buffer?.drain() ?? []
    }

    mutating func removeAllCommands(for sourceWebViewID: ObjectIdentifier) {
        buffersBySourceWebViewID.removeValue(forKey: sourceWebViewID)
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
final class WebViewProtectedCommandOwner {
    typealias CommandValidator = (DeferredWebViewCommand) -> Bool
    typealias CommandDropper = (DeferredWebViewCommand, ObjectIdentifier, String) -> Void
    typealias WebViewResolver = (ObjectIdentifier) -> WKWebView?

    private var activeHistorySwipeProtections: [ObjectIdentifier: HistorySwipeProtectionContext] = [:]
    private var visualHandoffProtectedWebViewIDs: Set<ObjectIdentifier> = []
    private let fullscreenProtection = FullscreenWebViewProtection()
    private var deferredProtectedWebViewCommands = DeferredProtectedWebViewCommandStore()
    private var weakWebViewRegistry = WeakWebViewRegistry()

    func note(_ webView: WKWebView) {
        weakWebViewRegistry.note(webView)
    }

    func resolveWeakWebView(with identifier: ObjectIdentifier) -> WKWebView? {
        weakWebViewRegistry.resolve(with: identifier)
    }

    func beginHistorySwipeProtection(
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
    func finishHistorySwipeProtection(
        on webView: WKWebView?,
        currentURL: URL?,
        currentHistoryItem: WKBackForwardListItem?
    ) -> (webViewID: ObjectIdentifier, wasCancelled: Bool)? {
        guard let webView else { return nil }
        let webViewID = ObjectIdentifier(webView)
        let context = activeHistorySwipeProtections.removeValue(forKey: webViewID)
        let wasCancelled = isCancelledHistorySwipe(
            context: context,
            currentURL: currentURL,
            currentHistoryItem: currentHistoryItem
        )
        return (webViewID, wasCancelled)
    }

    func hasActiveHistorySwipe(in windowID: UUID) -> Bool {
        activeHistorySwipeProtections.values.contains { $0.windowID == windowID }
    }

    func hasActiveFullscreen(in windowID: UUID) -> Bool {
        fullscreenProtection.hasActive(in: windowID)
    }

    func activeFullscreenWebViewIDs(in windowID: UUID) -> [ObjectIdentifier] {
        fullscreenProtection.activeWebViewIDs(in: windowID)
    }

    func isFullscreenProtected(_ webViewID: ObjectIdentifier) -> Bool {
        fullscreenProtection.isProtected(webViewID)
    }

    func isProtected(_ webView: WKWebView) -> Bool {
        isProtected(ObjectIdentifier(webView))
    }

    func isProtected(_ webViewID: ObjectIdentifier) -> Bool {
        activeHistorySwipeProtections[webViewID] != nil
            || visualHandoffProtectedWebViewIDs.contains(webViewID)
            || fullscreenProtection.isProtected(webViewID)
    }

    func beginVisualHandoffProtection(for webView: WKWebView) {
        let webViewID = ObjectIdentifier(webView)
        note(webView)
        visualHandoffProtectedWebViewIDs.insert(webViewID)
    }

    func finishVisualHandoffProtection(for webView: WKWebView) -> ObjectIdentifier? {
        let webViewID = ObjectIdentifier(webView)
        guard visualHandoffProtectedWebViewIDs.remove(webViewID) != nil else { return nil }
        return webViewID
    }

    func beginFullscreenProtection(on webView: WKWebView, windowID: UUID?) -> ObjectIdentifier {
        let webViewID = ObjectIdentifier(webView)
        note(webView)
        fullscreenProtection.begin(webViewID: webViewID, windowID: windowID)
        return webViewID
    }

    func finishFullscreenProtection(on webView: WKWebView) -> (
        webViewID: ObjectIdentifier,
        windowID: UUID?
    )? {
        let webViewID = ObjectIdentifier(webView)
        guard let context = fullscreenProtection.finish(webViewID: webViewID) else {
            return nil
        }
        return (webViewID, context.windowID)
    }

    func removeVisualHandoffAndFullscreenProtections() {
        visualHandoffProtectedWebViewIDs.removeAll()
        fullscreenProtection.removeAll()
    }

    func installFullscreenStateObservationIfNeeded(
        on webView: WKWebView,
        stateDidChange: @escaping @MainActor (WKWebView) -> Void
    ) {
        note(webView)
        fullscreenProtection.installObservationIfNeeded(
            on: webView,
            stateDidChange: stateDidChange
        )
    }

    func uninstallFullscreenStateObservationIfUntracked(_ webView: WKWebView, isTracked: Bool) {
        fullscreenProtection.uninstallObservationIfUntracked(
            webView,
            isTracked: isTracked
        )
    }

    @discardableResult
    func enqueueDeferredCommandIfNeeded(
        _ command: DeferredWebViewCommand,
        for webView: WKWebView,
        reason: String,
        resolveWebView: WebViewResolver,
        isCommandValid: CommandValidator,
        dropCommand: CommandDropper,
        didPruneStaleWebViewIDs: ([ObjectIdentifier]) -> Void
    ) -> Bool {
        let sourceWebViewID = ObjectIdentifier(webView)
        note(webView)
        guard isProtected(sourceWebViewID) else {
            return false
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
            return true
        }

        let enqueueResult = deferredProtectedWebViewCommands.enqueue(
            command,
            sourceWebViewID: sourceWebViewID
        )

        switch enqueueResult.outcome {
        case .enqueued:
            PerformanceTrace.emitEvent("WebViewCoordinator.enqueueDeferredProtectedCommand")
            RuntimeDiagnostics.protectedWebViewTrace(
                "enqueueDeferredCommand reason=\(reason) sourceWebView=\(sourceWebViewID) command={\(command.debugSummary)} count=\(enqueueResult.count)"
            )
        case .collapsed:
            PerformanceTrace.emitEvent("WebViewCoordinator.collapseDeferredProtectedCommand")
            RuntimeDiagnostics.protectedWebViewTrace(
                "collapseDeferredCommand reason=\(reason) sourceWebView=\(sourceWebViewID) command={\(command.debugSummary)} count=\(enqueueResult.count)"
            )
        case .droppedAtCapacity:
            dropCommand(
                command,
                sourceWebViewID,
                "\(reason).capacity"
            )
        }

        return true
    }

    func commandsToFlushIfUnprotected(
        for webViewID: ObjectIdentifier,
        resolveWebView: WebViewResolver,
        isCommandValid: CommandValidator,
        dropCommand: CommandDropper,
        didPruneStaleWebViewIDs: ([ObjectIdentifier]) -> Void
    ) -> [DeferredWebViewCommand] {
        guard isProtected(webViewID) == false else { return [] }
        didPruneStaleWebViewIDs(
            pruneInvalidDeferredCommands(
                reason: "flush.preflight",
                resolveWebView: resolveWebView,
                isCommandValid: isCommandValid,
                dropCommand: dropCommand
            )
        )
        return deferredProtectedWebViewCommands.drainCommands(for: webViewID)
    }

    @discardableResult
    func pruneInvalidDeferredCommands(
        reason: String,
        resolveWebView: WebViewResolver,
        isCommandValid: CommandValidator,
        dropCommand: CommandDropper
    ) -> [ObjectIdentifier] {
        let staleIDs = pruneStaleBookkeeping(reason: "\(reason).staleBookkeeping")

        for sourceWebViewID in deferredProtectedWebViewCommands.sourceWebViewIDs {
            guard resolveWebView(sourceWebViewID) != nil else {
                activeHistorySwipeProtections.removeValue(forKey: sourceWebViewID)
                fullscreenProtection.remove(sourceWebViewID)
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
    func pruneStaleBookkeeping(reason: String) -> [ObjectIdentifier] {
        let staleIDs = weakWebViewRegistry.pruneStaleIdentifiers()
        guard staleIDs.isEmpty == false else { return [] }
        for id in staleIDs {
            activeHistorySwipeProtections.removeValue(forKey: id)
            visualHandoffProtectedWebViewIDs.remove(id)
            fullscreenProtection.remove(id)
            deferredProtectedWebViewCommands.removeAllCommands(for: id)
        }
        RuntimeDiagnostics.protectedWebViewTrace(
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
           originHistoryItem === currentHistoryItem
        {
            return true
        }
        let originURL = context.originHistoryURL ?? context.originURL
        let currentURL = currentHistoryItem?.url ?? currentURL
        return originURL != nil && originURL == currentURL
    }
}

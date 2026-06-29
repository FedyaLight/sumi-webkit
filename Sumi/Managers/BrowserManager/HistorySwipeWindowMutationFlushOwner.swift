import Foundation

enum HistorySwipeDeferredWindowMutationKind: Hashable {
    case refreshCompositor
    case prepareVisibleWebViews
}

@MainActor
struct HistorySwipeWindowMutationQueue {
    private var recordsByWindowId: [UUID: DeferredHistorySwipeWindowMutations] = [:]

    mutating func enqueue(
        _ kind: HistorySwipeDeferredWindowMutationKind,
        for windowState: BrowserWindowState
    ) {
        var record = recordsByWindowId[windowState.id]
            ?? DeferredHistorySwipeWindowMutations(windowState: WeakBrowserWindowState(windowState))
        record.windowState = WeakBrowserWindowState(windowState)
        record.pendingKinds.insert(kind)
        recordsByWindowId[windowState.id] = record
    }

    mutating func takePendingMutations(for windowId: UUID) -> PendingMutations? {
        guard let record = recordsByWindowId.removeValue(forKey: windowId),
              let windowState = record.windowState.value
        else {
            return nil
        }

        return PendingMutations(
            windowState: windowState,
            pendingKinds: record.pendingKinds
        )
    }

    mutating func cancel(in windowId: UUID) {
        recordsByWindowId.removeValue(forKey: windowId)
    }

    struct PendingMutations {
        let windowState: BrowserWindowState
        let pendingKinds: Set<HistorySwipeDeferredWindowMutationKind>

        var needsVisibleWebViewPreparation: Bool {
            pendingKinds.contains(.prepareVisibleWebViews)
        }

        var needsCompositorRefresh: Bool {
            pendingKinds.contains(.prepareVisibleWebViews)
                || pendingKinds.contains(.refreshCompositor)
        }
    }
}

@MainActor
final class HistorySwipeWindowMutationFlushOwner {
    private var queue = HistorySwipeWindowMutationQueue()

    func enqueue(
        _ kind: HistorySwipeDeferredWindowMutationKind,
        for windowState: BrowserWindowState
    ) {
        queue.enqueue(kind, for: windowState)
    }

    func flushPendingMutations(
        in windowId: UUID,
        prepareVisibleWebViews: @MainActor (BrowserWindowState) -> Bool,
        refreshCompositor: @MainActor (BrowserWindowState) -> Void
    ) {
        guard let pendingMutations = queue.takePendingMutations(for: windowId) else {
            return
        }

        if pendingMutations.needsVisibleWebViewPreparation {
            _ = prepareVisibleWebViews(pendingMutations.windowState)
        }
        if pendingMutations.needsCompositorRefresh {
            refreshCompositor(pendingMutations.windowState)
        }
    }

    func cancelPendingMutations(in windowId: UUID) {
        queue.cancel(in: windowId)
    }
}

private final class WeakBrowserWindowState {
    weak var value: BrowserWindowState?

    init(_ value: BrowserWindowState) {
        self.value = value
    }
}

private struct DeferredHistorySwipeWindowMutations {
    var windowState: WeakBrowserWindowState
    var pendingKinds: Set<HistorySwipeDeferredWindowMutationKind> = []
}

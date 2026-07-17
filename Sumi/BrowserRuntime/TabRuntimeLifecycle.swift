import Foundation

/// Owns the browser session's executable runtime and mutable tab state lifetime.
@MainActor
final class TabRuntimeLifecycle {
    private enum Phase {
        case idle
        case running
        case shutDown
    }

    private let runtimePorts: TabRuntimePortsAttachmentOwner
    private let faviconRefresh: TabFaviconPresentationRefreshOwner
    private let stateStore: TabStateStore
    private var phase = Phase.idle

    var canStart: Bool {
        guard case .idle = phase else { return false }
        return runtimePorts.canAttach
    }

    init(
        runtimePorts: TabRuntimePortsAttachmentOwner,
        faviconRefresh: TabFaviconPresentationRefreshOwner,
        stateStore: TabStateStore
    ) {
        self.runtimePorts = runtimePorts
        self.faviconRefresh = faviconRefresh
        self.stateStore = stateStore
    }

    @discardableResult
    func start(with ports: RuntimePortRegistry) -> TabRuntimePortsAttachmentOwner.Outcome {
        guard canStart else { return .busy }
        faviconRefresh.startObserving()
        let outcome = runtimePorts.attach(ports)
        guard outcome == .attached else {
            faviconRefresh.stop()
            return outcome
        }
        phase = .running
        return .attached
    }

    func startPersistedStateRestoreIfNeeded() {
        guard phase == .running else { return }
        runtimePorts.startPersistedStateRestoreIfNeeded()
    }

    func shutdown() {
        if case .shutDown = phase { return }
        precondition(
            runtimePorts.detach(),
            "Tab runtime ports must detach before their browser runtime deallocates"
        )
        faviconRefresh.stop()
        stateStore.removeAll()
        phase = .shutDown
    }
}

import Foundation

@MainActor
final class TabRuntimePortsAttachmentOwner {
    enum Outcome: Equatable {
        case attached
        case busy
        case superseded
    }

    private enum State {
        case detached
        case attaching
        case bootstrapping(TabRuntimePortLease)
        case attached(TabRuntimePortLease)
        case detaching(TabRuntimePortLease)
    }

    private let connection: TabRuntimePortConnection
    private let bootstrap: TabRuntimeAttachmentBootstrap
    private let settlement: TabRuntimeAttachmentSettlement
    private var state = State.detached

    var canAttach: Bool {
        if case .detached = state { return true }
        return false
    }

    init(
        connection: TabRuntimePortConnection,
        bootstrap: TabRuntimeAttachmentBootstrap,
        settlement: TabRuntimeAttachmentSettlement
    ) {
        self.connection = connection
        self.bootstrap = bootstrap
        self.settlement = settlement
    }

    @discardableResult
    func attach(_ ports: RuntimePortRegistry) -> Outcome {
        guard canAttach else { return .busy }
        state = .attaching
        connection.attach(ports)
        let lease = connection.captureLease()
        guard case .attaching = state, connection.accepts(lease) else {
            state = .detached
            return .superseded
        }
        state = .bootstrapping(lease)

        guard case .completed = bootstrap.run(using: lease), owns(lease) else {
            detachIfCurrent(lease)
            return .superseded
        }

        state = .attached(lease)
        switch settlement.finish(using: lease) {
        case .completed:
            return owns(lease) ? .attached : .superseded
        case .superseded:
            return .superseded
        }
    }

    @discardableResult
    func detach() -> Bool {
        switch state {
        case .detached:
            return true
        case .attaching, .detaching:
            return false
        case .bootstrapping, .attached:
            return detachCurrentIfPossible()
        }
    }

    func startPersistedStateRestoreIfNeeded() {
        guard let lease = currentLease, owns(lease) else { return }
        settlement.startPersistedStateRestoreIfNeeded(using: lease)
    }

#if DEBUG
    /// Lets tests invalidate captured leases without leaving lifecycle teardown
    /// owning a superseded attachment.
    func replaceForTests(_ ports: RuntimePortRegistry) {
        connection.attach(ports)
        state = .attached(connection.captureLease())
    }
#endif

    private var currentLease: TabRuntimePortLease? {
        switch state {
        case .detached, .attaching:
            return nil
        case .bootstrapping(let lease), .attached(let lease),
             .detaching(let lease):
            return lease
        }
    }

    private func owns(_ lease: TabRuntimePortLease) -> Bool {
        guard let currentLease else { return false }
        return connection.sameAttachment(currentLease, lease)
            && connection.accepts(lease)
    }

    @discardableResult
    private func detachCurrentIfPossible() -> Bool {
        guard let lease = currentLease, owns(lease) else { return false }
        let previousState = state
        state = .detaching(lease)
        guard settlement.prepareForDetach() else {
            if ownsDetachingClaim(lease), connection.accepts(lease) {
                state = previousState
            } else {
                state = .detached
            }
            return false
        }
        guard ownsDetachingClaim(lease), connection.accepts(lease) else {
            state = .detached
            return false
        }
        connection.detach()
        state = .detached
        return true
    }

    private func ownsDetachingClaim(_ lease: TabRuntimePortLease) -> Bool {
        guard case .detaching(let claimedLease) = state else { return false }
        return connection.sameAttachment(claimedLease, lease)
    }

    private func detachIfCurrent(_ lease: TabRuntimePortLease) {
        guard owns(lease) else { return }
        _ = detachCurrentIfPossible()
    }
}

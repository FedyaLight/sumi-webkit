import Foundation

/// Prevents ordinary browser events from publishing into WebKit while a
/// generation replacement or terminal retirement is crossing synchronous
/// extension callbacks.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimePublicationGate {
    enum ExactTabCloseDisposition: Equatable {
        case perform
        case deferUntilReloadHandoff
        case reject
    }

    struct ReloadClaim: Equatable {
        fileprivate let gateIdentity: ObjectIdentifier
        fileprivate let epoch: UInt64
    }

    private struct ReloadState: Equatable {
        let claim: ReloadClaim
        var acceptsBrowserEvents: Bool
        var deferredStructuralEvent: Bool
    }

    private enum Phase: Equatable {
        case active
        case reloading(ReloadState)
        case retiring(UInt64)
        case inactive
    }

    private var phase = Phase.active
    private var epoch: UInt64 = 0

    var acceptsBrowserEvents: Bool {
        switch phase {
        case .active:
            true
        case .reloading(let state):
            state.acceptsBrowserEvents
        case .retiring, .inactive:
            false
        }
    }

    var canCoalesceReloadRequest: Bool {
        guard case .reloading = phase else { return false }
        return true
    }

    func beginReload() -> ReloadClaim? {
        switch phase {
        case .active, .inactive:
            epoch &+= 1
            let claim = ReloadClaim(
                gateIdentity: ObjectIdentifier(self),
                epoch: epoch
            )
            phase = .reloading(
                ReloadState(
                    claim: claim,
                    acceptsBrowserEvents: false,
                    deferredStructuralEvent: false
                )
            )
            return claim
        case .reloading, .retiring:
            return nil
        }
    }

    func reloadIsCurrent(_ claim: ReloadClaim) -> Bool {
        guard claim.gateIdentity == ObjectIdentifier(self),
              case .reloading(let state) = phase
        else {
            return false
        }
        return state.claim == claim
    }

    /// Normal-window reconciliation has installed the new generation before
    /// it crosses didOpen callbacks. Ordinary events may now join that exact
    /// generation, while a nested generation reload remains exclusive.
    func beginBrowserEventHandoff(_ claim: ReloadClaim) -> Bool {
        guard reloadIsCurrent(claim),
              case .reloading(var state) = phase
        else {
            return false
        }
        state.acceptsBrowserEvents = true
        phase = .reloading(state)
        return true
    }

    /// Structural opens attempted from didOpenWindow callbacks cannot join the
    /// batch until every captured window is visible. Record one follow-up
    /// reconciliation instead of dropping the event or breaking window-first
    /// ordering.
    func admitStructuralBrowserEvent() -> Bool {
        switch phase {
        case .active:
            return true
        case .reloading(var state):
            guard state.acceptsBrowserEvents == false else { return true }
            state.deferredStructuralEvent = true
            phase = .reloading(state)
            return false
        case .retiring, .inactive:
            return false
        }
    }

    /// A physical Tab may already be absent from the next runtime snapshot.
    /// Unlike window reconciliation, its close cannot be represented by a
    /// boolean follow-up and must retain the exact Tab until the handoff.
    func exactTabCloseDisposition() -> ExactTabCloseDisposition {
        switch phase {
        case .active:
            .perform
        case .reloading(let state):
            state.acceptsBrowserEvents
                ? .perform
                : .deferUntilReloadHandoff
        case .retiring, .inactive:
            .reject
        }
    }

    /// Auxiliary publications remain synchronous for WebKit, but opening one
    /// during a reload requests a final generation pass so it is rebound with
    /// every other live session.
    func admitAuxiliaryBrowserEvent() -> Bool {
        switch phase {
        case .active:
            return true
        case .reloading(var state):
            state.deferredStructuralEvent = true
            phase = .reloading(state)
            return true
        case .retiring, .inactive:
            return false
        }
    }

    func takeDeferredStructuralEvent(
        for claim: ReloadClaim
    ) -> Bool? {
        guard reloadIsCurrent(claim),
              case .reloading(var state) = phase
        else {
            return nil
        }
        let wasDeferred = state.deferredStructuralEvent
        state.deferredStructuralEvent = false
        phase = .reloading(state)
        return wasDeferred
    }

    func finishReload(
        _ claim: ReloadClaim,
        publicationIsAvailable: Bool
    ) -> Bool {
        guard reloadIsCurrent(claim) else { return false }
        phase = publicationIsAvailable ? .active : .inactive
        return true
    }

    /// Claims the whole publication graph before either auxiliary or normal
    /// close callbacks run. A nested reload then fails before it can reopen a
    /// partially retired generation.
    func beginTerminalRetirement() -> Bool {
        switch phase {
        case .retiring, .inactive:
            return false
        case .active, .reloading:
            epoch &+= 1
            phase = .retiring(epoch)
            return true
        }
    }

    func finishTerminalRetirement() {
        guard case .retiring = phase else { return }
        phase = .inactive
    }
}

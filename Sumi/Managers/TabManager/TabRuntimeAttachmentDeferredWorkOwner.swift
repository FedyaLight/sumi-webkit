import Foundation

@MainActor
final class TabRuntimeAttachmentDeferredWorkOwner {
    private let connection: TabRuntimePortConnection
    private let spaceProfiles: SpaceProfileReconciliationService
    private let spaceAvailability: SpaceProfileTransitionAvailability
    private let pendingPins: PendingShortcutPinAdopter

    private var lease: TabRuntimePortLease?
    private var transition: SpaceProfileReconciliationService.DeferredTransition?
    private var availabilityObservation: SpaceProfileTransitionAvailability.Observation?
    private var revision: UInt64 = 0
    private var isStopping = false

    init(
        connection: TabRuntimePortConnection,
        spaceProfiles: SpaceProfileReconciliationService,
        spaceAvailability: SpaceProfileTransitionAvailability,
        pendingPins: PendingShortcutPinAdopter
    ) {
        self.connection = connection
        self.spaceProfiles = spaceProfiles
        self.spaceAvailability = spaceAvailability
        self.pendingPins = pendingPins
    }

    func start(using lease: TabRuntimePortLease) {
        guard connection.accepts(lease) else { return }
        stopObservation()
        self.lease = lease
        transition = nil
        isStopping = false
        revision &+= 1

        if let profileID = lease.currentProfileID {
            _ = pendingPins.adoptPendingPins(into: profileID)
        }
        advance(using: lease)
    }

    @discardableResult
    func prepareForDetach() -> Bool {
        guard let expectedLease = lease else {
            pendingPins.cancelDeferredAdoption()
            return true
        }
        isStopping = true
        revision &+= 1
        stopObservation()
        if let transition {
            switch spaceProfiles.drainForRuntimeDetach(transition) {
            case .drained, .noLongerOwned:
                break
            case .unavailable:
                isStopping = false
                armAvailability(
                    using: expectedLease,
                    after: spaceAvailability.revision
                )
                return false
            }
        }
        pendingPins.cancelDeferredAdoption()
        transition = nil
        lease = nil
        isStopping = false
        return true
    }

    private func advance(using expectedLease: TabRuntimePortLease) {
        guard owns(expectedLease), isStopping == false else { return }
        stopObservation()
        if let transition {
            if spaceProfiles.ownsLifecycle(of: transition) {
                armAvailability(
                    using: expectedLease,
                    after: spaceAvailability.revision
                )
                return
            }
            self.transition = nil
        }

        while owns(expectedLease), isStopping == false {
            revision &+= 1
            let attemptRevision = revision
            let start = spaceProfiles.startNext(
                using: expectedLease,
                capturingTransition: { [weak self] transition in
                    guard let self,
                          self.owns(expectedLease),
                          self.isStopping == false else { return }
                    self.transition = transition
                },
                completion: { [weak self] result in
                    self?.transitionCompleted(
                        result,
                        revision: attemptRevision,
                        using: expectedLease
                    )
                }
            )
            guard owns(expectedLease), isStopping == false else {
                if case .deferred(let stale) = start {
                    _ = spaceProfiles.drainForRuntimeDetach(stale)
                }
                return
            }
            switch start {
            case .completed(.committed):
                transition = nil
                continue
            case .completed(.noRemainingWork):
                transition = nil
                return
            case .completed(.unavailable):
                armAvailability(
                    using: expectedLease,
                    after: spaceAvailability.revision
                )
                return
            case .completed(.superseded):
                clear()
                return
            case .deferred(let transition):
                if self.transition == nil {
                    self.transition = transition
                }
                return
            }
        }
    }

    private func transitionCompleted(
        _ result: SpaceProfileReconciliationService.Result,
        revision expectedRevision: UInt64,
        using expectedLease: TabRuntimePortLease
    ) {
        guard expectedRevision == revision,
              owns(expectedLease),
              isStopping == false else { return }
        switch result {
        case .committed:
            transition = nil
            advance(using: expectedLease)
        case .unavailable:
            if let transition,
               spaceProfiles.ownsLifecycle(of: transition) == false {
                self.transition = nil
            }
            armAvailability(
                using: expectedLease,
                after: spaceAvailability.revision
            )
        case .noRemainingWork:
            transition = nil
        case .superseded:
            clear()
        }
    }

    private func armAvailability(
        using expectedLease: TabRuntimePortLease,
        after availabilityRevision: UInt64
    ) {
        guard owns(expectedLease), isStopping == false else { return }
        stopObservation()
        guard let observation = spaceAvailability.observeNext(
            after: availabilityRevision,
            { [weak self] in
            guard let self else { return }
            self.availabilityObservation = nil
            self.advance(using: expectedLease)
            }
        ) else {
            advance(using: expectedLease)
            return
        }
        availabilityObservation = observation
    }

    private func owns(_ expectedLease: TabRuntimePortLease) -> Bool {
        guard let lease else { return false }
        return connection.sameAttachment(lease, expectedLease)
            && connection.accepts(expectedLease)
    }

    private func stopObservation() {
        availabilityObservation?.cancel()
        availabilityObservation = nil
    }

    private func clear() {
        stopObservation()
        pendingPins.cancelDeferredAdoption()
        transition = nil
        lease = nil
    }
}

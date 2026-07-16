import Foundation
import SumiWebRuntime

enum RuntimeDetachDrainResult {
    case drained
    case unavailable
    case noLongerOwned
}

@MainActor
final class SpaceProfileTransitionRepository {
    @MainActor private final class Entry {
        let intent: DeferredWebViewSpaceProfileAssignmentIntent
        var transaction: SpaceProfileTransaction?
        var observer: ProfileTransitionService.Settlement?

        init(
            transaction: SpaceProfileTransaction,
            observer: ProfileTransitionService.Settlement?
        ) {
            intent = transaction.intent
            self.transaction = transaction
            self.observer = observer
        }

        func takeObserver() -> ProfileTransitionService.Settlement? {
            defer { observer = nil }
            return observer
        }
    }

    private let spaces: TabSpaceCollectionStateOwner
    private let pendingInheritance: PendingTabProfileInheritance
    private let publication: SpaceProfileTransitionPublication
    private var revisionBySpaceID: [UUID: UInt64] = [:]
    private var entriesBySpaceID: [UUID: Entry] = [:]

    init(
        spaces: TabSpaceCollectionStateOwner,
        pendingInheritance: PendingTabProfileInheritance,
        publication: SpaceProfileTransitionPublication
    ) {
        self.spaces = spaces
        self.pendingInheritance = pendingInheritance
        self.publication = publication
    }

    func space(with id: UUID) -> Space? {
        spaces.space(with: id)
    }

    func nextRevision(for spaceID: UUID) -> UInt64 {
        let revision = (revisionBySpaceID[spaceID] ?? 0) &+ 1
        revisionBySpaceID[spaceID] = revision
        return revision
    }

    func install(
        _ transaction: SpaceProfileTransaction,
        observer: ProfileTransitionService.Settlement?
    ) -> Bool {
        let intent = transaction.intent
        guard entriesBySpaceID[intent.spaceID] == nil,
              revisionBySpaceID[intent.spaceID] == intent.revision else {
            return false
        }
        entriesBySpaceID[intent.spaceID] = Entry(
            transaction: transaction,
            observer: observer
        )
        return true
    }

    func hasTransaction(for spaceID: UUID) -> Bool {
        entriesBySpaceID[spaceID] != nil
    }

    func ownsLifecycle(
        for intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) -> Bool {
        entry(for: intent) != nil
    }

    func transaction(
        for intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) -> SpaceProfileTransaction? {
        guard let transaction = entry(for: intent)?.transaction,
              transaction.intent == intent else { return nil }
        return transaction
    }

    func isCurrent(
        _ intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) -> Bool {
        transaction(for: intent)?.isCurrentPending(
            revision: intent.revision
        ) == true
    }

    func inFlightProfileID(for spaceID: UUID) -> UUID? {
        guard let transaction = entriesBySpaceID[spaceID]?.transaction,
              transaction.state != .terminal else { return nil }
        return transaction.desiredProfileID
    }

    @discardableResult
    func registerCreationFollower(
        _ tab: Tab,
        in spaceID: UUID,
        profileID: UUID
    ) -> Bool {
        guard let transaction = entriesBySpaceID[spaceID]?.transaction,
              transaction.state != .terminal,
              transaction.desiredProfileID == profileID,
              tab.profileId == profileID,
              publication.contains(tab, in: spaceID) else { return false }
        pendingInheritance.record(
            tab: tab,
            spaceID: spaceID,
            spaceRevision: transaction.intent.revision,
            inheritedProfileID: profileID
        )
        return true
    }

    func cancelPending(
        _ intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) {
        guard let entry = entry(for: intent),
              let transaction = entry.transaction,
              transaction.state == .pending else { return }
        transaction.abortPending()
        release(entry, notifying: .rejected(.failed))
    }

    @discardableResult
    func drainForRuntimeDetach(
        _ intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) -> RuntimeDetachDrainResult {
        guard let entry = entry(for: intent) else { return .noLongerOwned }
        guard let transaction = entry.transaction else {
            release(entry, notifying: .terminalShutdown)
            return .drained
        }
        guard transaction.canSettleTerminalDrain(),
              transaction.settleTerminalDrain() else { return .unavailable }
        release(entry)
        return .drained
    }

    func receive(
        _ settlement: ProfileTransitionSettlement,
        intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) {
        guard let entry = entry(for: intent) else { return }
        if case .conflicted = settlement {
            entry.observer?(settlement)
            return
        }
        let observer = entry.takeObserver()
        if entry.transaction == nil {
            remove(entry)
        }

        switch settlement {
        case .committed:
            pendingInheritance.spaceTransitionCommitted(
                intent: intent,
                canonicalProfileID: spaces.profileId(for: intent.spaceID),
                isTabStillInSpace: { [weak publication] tab, spaceID in
                    publication?.contains(tab, in: spaceID) == true
                }
            )
            publication.publishStructuralMutation(spaceID: intent.spaceID)
        case .rejected:
            abortPending(intent)
            pendingInheritance.discard(spaceIntent: intent)
        case .rolledBack:
            pendingInheritance.discard(spaceIntent: intent)
        case .leaseLost, .terminalShutdown:
            if let transaction = entry.transaction,
               transaction.settleTerminalDrain() {
                remove(entry)
            }
            pendingInheritance.discard(spaceIntent: intent)
        case .conflicted:
            preconditionFailure("Conflicted settlements remain nonterminal")
        }

        publication.publish()
        observer?(settlement)
    }

    func replacementModelDidPublish(
        _ candidate: SpaceProfileTransaction,
        structuralMutation: Bool
    ) {
        guard let entry = activeEntry(candidate) else { return }
        entry.transaction = nil
        if structuralMutation {
            publication.publishStructuralMutation(
                spaceID: candidate.intent.spaceID
            )
        }
    }

    func replacementModelDidSettleTerminalDrain(
        _ candidate: SpaceProfileTransaction
    ) {
        guard let entry = activeEntry(candidate) else { return }
        release(entry, notifying: .terminalShutdown)
    }

    private func abortPending(
        _ intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) {
        guard let entry = entry(for: intent),
              let transaction = entry.transaction else { return }
        switch transaction.state {
        case .pending:
            transaction.abortPending()
        case .terminal:
            break
        case .staged, .retainedCleanupConflict:
            return
        }
        remove(entry)
    }

    private func activeEntry(
        _ transaction: SpaceProfileTransaction
    ) -> Entry? {
        guard let entry = entry(for: transaction.intent),
              entry.transaction === transaction else { return nil }
        return entry
    }

    private func entry(
        for intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) -> Entry? {
        guard let entry = entriesBySpaceID[intent.spaceID],
              entry.intent == intent else { return nil }
        return entry
    }

    private func remove(_ entry: Entry) {
        guard entriesBySpaceID[entry.intent.spaceID] === entry else { return }
        entriesBySpaceID.removeValue(forKey: entry.intent.spaceID)
    }

    private func release(
        _ entry: Entry,
        notifying settlement: ProfileTransitionSettlement? = nil
    ) {
        guard entriesBySpaceID[entry.intent.spaceID] === entry else { return }
        remove(entry)
        pendingInheritance.discard(spaceIntent: entry.intent)
        let observer = entry.takeObserver()
        publication.publish()
        if let settlement { observer?(settlement) }
    }
}

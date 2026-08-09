import Foundation
import SumiWebRuntime

/// Process-wide admission barrier for destructive mutation of WebKit website
/// data stores. The owner acquires one exclusive lease before discovering live
/// WebViews; creation and ordinary main-frame submission paths consult the same
/// gate so the discovered set can reach a stable fixed point.
@MainActor
final class WebsiteDataMutationGate {
    typealias Lease = WebsiteDataMutationLeaseLedger.Lease
    typealias OrdinaryAdmissionDeferral = @MainActor (
        UUID,
        DeferredAdmissionKey,
        @escaping @MainActor () -> Void
    ) -> Bool

    enum OrdinaryRuntimeAdmissionOutcome: Equatable {
        case admitted
        case deferred
        case rejectedAfterTerminalShutdown

        var preventsImmediateMutation: Bool {
            self != .admitted
        }
    }

    enum DeferredAdmissionKey: Hashable, Sendable {
        case webViewRebuild(tabID: UUID)
        case webViewMaterialization(tabID: UUID)
        case profileAssignment(tabID: UUID)
        case spaceProfileAssignment(spaceID: UUID)
        case mainFrameSubmission(tabID: UUID, webViewID: ObjectIdentifier)
        case trackedRegistration(tabID: UUID, windowID: UUID)
        case trackedReplacement(tabID: UUID, windowID: UUID)
        case untrackedReplacement(tabID: UUID)
    }

    private struct DeferredAdmission {
        let profileID: UUID
        let replay: @MainActor () -> Void
    }

    private struct ScheduledAdmission {
        let key: DeferredAdmissionKey
        let admission: DeferredAdmission
    }

    private let leaseLedger = WebsiteDataMutationLeaseLedger()
    private var deferredAdmissions: [DeferredAdmissionKey: DeferredAdmission] = [:]
    private var scheduledAdmissions: [UUID: ScheduledAdmission] = [:]
    private var restoreRevisionByTabID: [UUID: UInt64] = [:]
    private var internalSubmissionDepth = 0
    private var isTerminallyShutDown = false

    func acquire(profileIDs: Set<UUID>) async -> Lease? {
        await leaseLedger.acquire(scopeIDs: profileIDs)
    }

    func release(_ lease: Lease) {
        guard leaseLedger.release(lease) else { return }
        restoreRevisionByTabID.removeAll()
        replayNewlyAdmittedWork()
    }

    func blocksOrdinaryRuntimeAdmission(for profileID: UUID?) -> Bool {
        leaseLedger.blocksAdmission(for: profileID)
    }

    /// Suspends asynchronous profile-scoped work instead of converting a
    /// temporary website-data transaction into a user-visible failure.
    func waitForOrdinaryRuntimeAdmission(for profileID: UUID) async -> Bool {
        await leaseLedger.waitForAdmission(for: profileID)
    }

    func owns(_ lease: Lease) -> Bool {
        leaseLedger.owns(lease)
    }

    var generation: UInt64 { leaseLedger.generation }

    func withInternalSubmission<Result>(_ operation: () -> Result) -> Result {
        internalSubmissionDepth += 1
        defer { internalSubmissionDepth -= 1 }
        return operation()
    }

    func authorizeRestoreSubmission(tabID: UUID, semanticRevision: UInt64) {
        guard leaseLedger.hasActiveLease else { return }
        restoreRevisionByTabID[tabID] = semanticRevision
    }

    func permitsInternalSubmission(
        tabID: UUID,
        semanticRevision: UInt64
    ) -> Bool {
        internalSubmissionDepth > 0
            || restoreRevisionByTabID[tabID] == semanticRevision
    }

    /// Retains only the newest semantic operation for an exact runtime slot,
    /// or rejects it once the runtime has entered terminal shutdown.
    func ordinaryRuntimeAdmission(
        for profileID: UUID?,
        key: DeferredAdmissionKey,
        replay: @escaping @MainActor () -> Void
    ) -> OrdinaryRuntimeAdmissionOutcome {
        guard isTerminallyShutDown == false else {
            return .rejectedAfterTerminalShutdown
        }
        guard let profileID,
              blocksOrdinaryRuntimeAdmission(for: profileID) else {
            revokeDeferredAdmission(for: key)
            return .admitted
        }
        deferredAdmissions[key] = DeferredAdmission(
            profileID: profileID,
            replay: replay
        )
        return .deferred
    }

    /// Compatibility for callers whose result surface only distinguishes
    /// immediate execution from "must not execute now". Terminal rejection is
    /// deliberately fail-closed and never schedules the replay.
    @discardableResult
    func deferOrdinaryRuntimeAdmission(
        for profileID: UUID?,
        key: DeferredAdmissionKey,
        replay: @escaping @MainActor () -> Void
    ) -> Bool {
        ordinaryRuntimeAdmission(
            for: profileID,
            key: key,
            replay: replay
        ).preventsImmediateMutation
    }

    private func revokeDeferredAdmission(for key: DeferredAdmissionKey) {
        deferredAdmissions.removeValue(forKey: key)
        scheduledAdmissions = scheduledAdmissions.filter { _, scheduled in
            scheduled.key != key
        }
    }

    func cancelDeferredAdmissions(forTabID tabID: UUID) {
        restoreRevisionByTabID.removeValue(forKey: tabID)
        deferredAdmissions = deferredAdmissions.filter { key, _ in
            deferredTabID(for: key) != tabID
        }
        scheduledAdmissions = scheduledAdmissions.filter { _, scheduled in
            deferredTabID(for: scheduled.key) != tabID
        }
    }

    func cancelDeferredAdmissions(forProfileID profileID: UUID) {
        deferredAdmissions = deferredAdmissions.filter { _, admission in
            admission.profileID != profileID
        }
        scheduledAdmissions = scheduledAdmissions.filter { _, scheduled in
            scheduled.admission.profileID != profileID
        }
    }

    func resetForTerminalShutdown() {
        isTerminallyShutDown = true
        leaseLedger.resetForTerminalShutdown()
        restoreRevisionByTabID.removeAll()
        internalSubmissionDepth = 0
        deferredAdmissions.removeAll()
        scheduledAdmissions.removeAll()
    }

    private func replayNewlyAdmittedWork() {
        let readyKeys = deferredAdmissions.compactMap { key, admission in
            blocksOrdinaryRuntimeAdmission(for: admission.profileID) ? nil : key
        }.sorted(by: deferredAdmissionPrecedes)
        let scheduledIDs = readyKeys.compactMap { key -> UUID? in
            guard let admission = deferredAdmissions.removeValue(forKey: key) else {
                return nil
            }
            let scheduledID = UUID()
            scheduledAdmissions[scheduledID] = ScheduledAdmission(
                key: key,
                admission: admission
            )
            return scheduledID
        }
        guard scheduledIDs.isEmpty == false else { return }
        Task { @MainActor [weak self] in
            scheduledIDs.forEach { self?.replayScheduledAdmission($0) }
        }
    }

    private func replayScheduledAdmission(_ scheduledID: UUID) {
        guard let scheduled = scheduledAdmissions.removeValue(
            forKey: scheduledID
        ) else {
            return
        }
        // Moving an admission to the scheduled queue releases its key. A
        // newer semantic operation can therefore occupy that key before this
        // task runs; the newer operation must win even when it targets a
        // different profile.
        guard deferredAdmissions[scheduled.key] == nil else { return }
        if blocksOrdinaryRuntimeAdmission(
            for: scheduled.admission.profileID
        ) {
            if deferredAdmissions[scheduled.key] == nil {
                deferredAdmissions[scheduled.key] = scheduled.admission
            }
            return
        }
        scheduled.admission.replay()
    }

    private func deferredTabID(for key: DeferredAdmissionKey) -> UUID? {
        switch key {
        case .webViewRebuild(let tabID),
             .webViewMaterialization(let tabID),
             .profileAssignment(let tabID),
             .mainFrameSubmission(let tabID, _),
             .trackedRegistration(let tabID, _),
             .trackedReplacement(let tabID, _),
             .untrackedReplacement(let tabID):
            return tabID
        case .spaceProfileAssignment:
            return nil
        }
    }

    private func deferredAdmissionPrecedes(
        _ lhs: DeferredAdmissionKey,
        _ rhs: DeferredAdmissionKey
    ) -> Bool {
        let lhsOrder = deferredAdmissionOrder(lhs)
        let rhsOrder = deferredAdmissionOrder(rhs)
        if lhsOrder.priority != rhsOrder.priority {
            return lhsOrder.priority < rhsOrder.priority
        }
        return lhsOrder.stableIdentity < rhsOrder.stableIdentity
    }

    private func deferredAdmissionOrder(
        _ key: DeferredAdmissionKey
    ) -> (priority: Int, stableIdentity: String) {
        switch key {
        case .spaceProfileAssignment(let spaceID):
            return (0, "\(spaceID.uuidString).space-profile")
        case .profileAssignment(let tabID):
            return (0, "\(tabID.uuidString).profile")
        case .webViewRebuild(let tabID):
            return (1, "\(tabID.uuidString).rebuild")
        case .webViewMaterialization(let tabID):
            return (2, tabID.uuidString)
        case .trackedRegistration(let tabID, let windowID):
            return (3, "\(tabID.uuidString).\(windowID.uuidString)")
        case .trackedReplacement(let tabID, let windowID):
            return (3, "\(tabID.uuidString).\(windowID.uuidString).replacement")
        case .untrackedReplacement(let tabID):
            return (3, "\(tabID.uuidString).untracked-replacement")
        case .mainFrameSubmission(let tabID, let webViewID):
            return (
                4,
                "\(tabID.uuidString).\(UInt(bitPattern: webViewID))"
            )
        }
    }
}

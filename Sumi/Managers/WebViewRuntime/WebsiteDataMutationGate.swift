import Foundation

/// Process-wide admission barrier for destructive mutation of WebKit website
/// data stores. The owner acquires one exclusive lease before discovering live
/// WebViews; creation and ordinary main-frame submission paths consult the same
/// gate so the discovered set can reach a stable fixed point.
@MainActor
final class WebsiteDataMutationGate {
    enum OrdinaryRuntimeAdmissionOutcome: Equatable {
        case admitted
        case deferred
        case rejectedAfterTerminalShutdown

        var preventsImmediateMutation: Bool {
            self != .admitted
        }
    }

    struct Lease: Equatable, Sendable {
        let id: UUID
        let profileIDs: Set<UUID>
        let admissionGeneration: UInt64
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

    private struct Waiter {
        let id: UUID
        let profileIDs: Set<UUID>
        let continuation: CheckedContinuation<Lease?, Never>
    }

    private struct AdmissionWaiter {
        let id: UUID
        let profileID: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private struct DeferredAdmission {
        let profileID: UUID
        let replay: @MainActor () -> Void
    }

    private struct ScheduledAdmission {
        let key: DeferredAdmissionKey
        let admission: DeferredAdmission
    }

    private var activeLease: Lease?
    private var waiters: [Waiter] = []
    private var admissionWaiters: [AdmissionWaiter] = []
    private var deferredAdmissions: [DeferredAdmissionKey: DeferredAdmission] = [:]
    private var scheduledAdmissions: [UUID: ScheduledAdmission] = [:]
    private var restoreRevisionByTabID: [UUID: UInt64] = [:]
    private var internalSubmissionDepth = 0
    private var admissionGeneration: UInt64 = 0
    private var isTerminallyShutDown = false

    func acquire(profileIDs: Set<UUID>) async -> Lease? {
        guard profileIDs.isEmpty == false,
              isTerminallyShutDown == false,
              Task.isCancelled == false else {
            return nil
        }
        if activeLease == nil {
            return installLease(profileIDs: profileIDs)
        }

        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled || isTerminallyShutDown {
                    continuation.resume(returning: nil)
                } else if activeLease == nil {
                    continuation.resume(returning: installLease(profileIDs: profileIDs))
                } else {
                    waiters.append(
                        Waiter(
                            id: waiterID,
                            profileIDs: profileIDs,
                            continuation: continuation
                        )
                    )
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancelWaiter(waiterID)
            }
        }
    }

    func release(_ lease: Lease) {
        guard activeLease == lease else { return }
        activeLease = nil
        restoreRevisionByTabID.removeAll()
        admissionGeneration &+= 1
        installNextLeaseIfPossible()
        resumeNewlyAdmittedWaiters()
        replayNewlyAdmittedWork()
    }

    func blocksOrdinaryRuntimeAdmission(for profileID: UUID?) -> Bool {
        guard let profileID, let activeLease else { return false }
        return activeLease.profileIDs.contains(profileID)
    }

    /// Suspends asynchronous profile-scoped work instead of converting a
    /// temporary website-data transaction into a user-visible failure.
    func waitForOrdinaryRuntimeAdmission(for profileID: UUID) async -> Bool {
        guard isTerminallyShutDown == false,
              Task.isCancelled == false else {
            return false
        }
        guard blocksOrdinaryRuntimeAdmission(for: profileID) else {
            return true
        }

        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled || isTerminallyShutDown {
                    continuation.resume(returning: false)
                } else if blocksOrdinaryRuntimeAdmission(for: profileID) == false {
                    continuation.resume(returning: true)
                } else {
                    admissionWaiters.append(
                        AdmissionWaiter(
                            id: waiterID,
                            profileID: profileID,
                            continuation: continuation
                        )
                    )
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancelAdmissionWaiter(waiterID)
            }
        }
    }

    func owns(_ lease: Lease) -> Bool {
        activeLease == lease && isTerminallyShutDown == false
    }

    var generation: UInt64 { admissionGeneration }

    func withInternalSubmission<Result>(_ operation: () -> Result) -> Result {
        internalSubmissionDepth += 1
        defer { internalSubmissionDepth -= 1 }
        return operation()
    }

    func authorizeRestoreSubmission(tabID: UUID, semanticRevision: UInt64) {
        guard activeLease != nil else { return }
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

    func resetForTerminalShutdown() {
        isTerminallyShutDown = true
        activeLease = nil
        restoreRevisionByTabID.removeAll()
        internalSubmissionDepth = 0
        admissionGeneration &+= 1
        let pending = waiters
        let pendingAdmissions = admissionWaiters
        waiters.removeAll()
        admissionWaiters.removeAll()
        deferredAdmissions.removeAll()
        scheduledAdmissions.removeAll()
        pending.forEach { $0.continuation.resume(returning: nil) }
        pendingAdmissions.forEach { $0.continuation.resume(returning: false) }
    }

    private func installLease(profileIDs: Set<UUID>) -> Lease {
        admissionGeneration &+= 1
        let lease = Lease(
            id: UUID(),
            profileIDs: profileIDs,
            admissionGeneration: admissionGeneration
        )
        activeLease = lease
        return lease
    }

    private func installNextLeaseIfPossible() {
        guard activeLease == nil,
              isTerminallyShutDown == false,
              waiters.isEmpty == false else {
            return
        }
        let waiter = waiters.removeFirst()
        waiter.continuation.resume(
            returning: installLease(profileIDs: waiter.profileIDs)
        )
    }

    private func cancelWaiter(_ waiterID: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == waiterID }) else {
            return
        }
        waiters.remove(at: index).continuation.resume(returning: nil)
    }

    private func cancelAdmissionWaiter(_ waiterID: UUID) {
        guard let index = admissionWaiters.firstIndex(where: { $0.id == waiterID }) else {
            return
        }
        admissionWaiters.remove(at: index).continuation.resume(returning: false)
    }

    private func resumeNewlyAdmittedWaiters() {
        var stillBlocked: [AdmissionWaiter] = []
        var ready: [AdmissionWaiter] = []
        for waiter in admissionWaiters {
            if blocksOrdinaryRuntimeAdmission(for: waiter.profileID) {
                stillBlocked.append(waiter)
            } else {
                ready.append(waiter)
            }
        }
        admissionWaiters = stillBlocked
        ready.forEach { $0.continuation.resume(returning: true) }
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

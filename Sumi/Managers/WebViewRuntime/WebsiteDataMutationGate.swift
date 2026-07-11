import Foundation

/// Process-wide admission barrier for destructive mutation of WebKit website
/// data stores. The owner acquires one exclusive lease before discovering live
/// WebViews; creation and ordinary main-frame submission paths consult the same
/// gate so the discovered set can reach a stable fixed point.
@MainActor
final class WebsiteDataMutationGate {
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

    private var activeLease: Lease?
    private var waiters: [Waiter] = []
    private var admissionWaiters: [AdmissionWaiter] = []
    private var deferredAdmissions: [DeferredAdmissionKey: DeferredAdmission] = [:]
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

    /// Retains only the newest semantic operation for an exact runtime slot.
    /// Returning `true` means the caller must not perform the physical WebKit
    /// mutation now; the supplied replay is scheduled once that profile leaves
    /// the protected website-data transaction.
    @discardableResult
    func deferOrdinaryRuntimeAdmission(
        for profileID: UUID?,
        key: DeferredAdmissionKey,
        replay: @escaping @MainActor () -> Void
    ) -> Bool {
        guard let profileID,
              blocksOrdinaryRuntimeAdmission(for: profileID) else {
            return false
        }
        deferredAdmissions[key] = DeferredAdmission(
            profileID: profileID,
            replay: replay
        )
        return true
    }

    func cancelDeferredAdmissions(forTabID tabID: UUID) {
        deferredAdmissions = deferredAdmissions.filter { key, _ in
            switch key {
            case .webViewRebuild(let candidateTabID),
                 .webViewMaterialization(let candidateTabID),
                 .profileAssignment(let candidateTabID),
                 .mainFrameSubmission(let candidateTabID, _),
                 .trackedRegistration(let candidateTabID, _):
                return candidateTabID != tabID
            case .spaceProfileAssignment:
                return true
            }
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
        let ready = readyKeys.compactMap { deferredAdmissions.removeValue(forKey: $0) }
        guard ready.isEmpty == false else { return }
        Task { @MainActor in
            ready.forEach { $0.replay() }
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
        case .mainFrameSubmission(let tabID, let webViewID):
            return (
                4,
                "\(tabID.uuidString).\(UInt(bitPattern: webViewID))"
            )
        }
    }
}

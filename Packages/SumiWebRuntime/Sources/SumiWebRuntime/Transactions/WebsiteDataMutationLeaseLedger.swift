import Foundation

/// Profile-agnostic exclusivity kernel for destructive website-data work.
/// The app maps its profile identifiers into opaque scope IDs and retains all
/// product-specific replay ordering and WebKit submission policy.
@MainActor
public final class WebsiteDataMutationLeaseLedger {
    public struct Lease: Equatable, Sendable {
        fileprivate let id: UUID
        fileprivate let scopeIDs: Set<UUID>
        fileprivate let admissionGeneration: UInt64

        fileprivate init(
            id: UUID,
            scopeIDs: Set<UUID>,
            admissionGeneration: UInt64
        ) {
            self.id = id
            self.scopeIDs = scopeIDs
            self.admissionGeneration = admissionGeneration
        }
    }

    private struct LeaseWaiter {
        let id: UUID
        let scopeIDs: Set<UUID>
        let continuation: CheckedContinuation<Lease?, Never>
    }

    private struct AdmissionWaiter {
        let id: UUID
        let scopeID: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var activeLease: Lease?
    private var leaseWaiters: [LeaseWaiter] = []
    private var admissionWaiters: [AdmissionWaiter] = []
    private var admissionGeneration: UInt64 = 0
    private var isTerminallyShutDown = false

    public init() {}

    public func acquire(scopeIDs: Set<UUID>) async -> Lease? {
        guard scopeIDs.isEmpty == false,
              isTerminallyShutDown == false,
              Task.isCancelled == false else {
            return nil
        }
        if activeLease == nil {
            return installLease(scopeIDs: scopeIDs)
        }

        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled || isTerminallyShutDown {
                    continuation.resume(returning: nil)
                } else if activeLease == nil {
                    continuation.resume(
                        returning: installLease(scopeIDs: scopeIDs)
                    )
                } else {
                    leaseWaiters.append(
                        LeaseWaiter(
                            id: waiterID,
                            scopeIDs: scopeIDs,
                            continuation: continuation
                        )
                    )
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancelLeaseWaiter(waiterID)
            }
        }
    }

    @discardableResult
    public func release(_ lease: Lease) -> Bool {
        guard activeLease == lease else { return false }
        activeLease = nil
        admissionGeneration &+= 1
        installNextLeaseIfPossible()
        resumeNewlyAdmittedWaiters()
        return true
    }

    public func blocksAdmission(for scopeID: UUID?) -> Bool {
        guard let scopeID, let activeLease else { return false }
        return activeLease.scopeIDs.contains(scopeID)
    }

    public func waitForAdmission(for scopeID: UUID) async -> Bool {
        guard isTerminallyShutDown == false,
              Task.isCancelled == false else {
            return false
        }
        guard blocksAdmission(for: scopeID) else { return true }

        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled || isTerminallyShutDown {
                    continuation.resume(returning: false)
                } else if blocksAdmission(for: scopeID) == false {
                    continuation.resume(returning: true)
                } else {
                    admissionWaiters.append(
                        AdmissionWaiter(
                            id: waiterID,
                            scopeID: scopeID,
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

    public func owns(_ lease: Lease) -> Bool {
        activeLease == lease && isTerminallyShutDown == false
    }

    public var hasActiveLease: Bool { activeLease != nil }

    public var generation: UInt64 { admissionGeneration }

    public func resetForTerminalShutdown() {
        isTerminallyShutDown = true
        activeLease = nil
        admissionGeneration &+= 1
        let pendingLeases = leaseWaiters
        let pendingAdmissions = admissionWaiters
        leaseWaiters.removeAll()
        admissionWaiters.removeAll()
        pendingLeases.forEach { $0.continuation.resume(returning: nil) }
        pendingAdmissions.forEach { $0.continuation.resume(returning: false) }
    }

    private func installLease(scopeIDs: Set<UUID>) -> Lease {
        admissionGeneration &+= 1
        let lease = Lease(
            id: UUID(),
            scopeIDs: scopeIDs,
            admissionGeneration: admissionGeneration
        )
        activeLease = lease
        return lease
    }

    private func installNextLeaseIfPossible() {
        guard activeLease == nil,
              isTerminallyShutDown == false,
              leaseWaiters.isEmpty == false else {
            return
        }
        let waiter = leaseWaiters.removeFirst()
        waiter.continuation.resume(
            returning: installLease(scopeIDs: waiter.scopeIDs)
        )
    }

    private func cancelLeaseWaiter(_ waiterID: UUID) {
        guard let index = leaseWaiters.firstIndex(where: { $0.id == waiterID }) else {
            return
        }
        leaseWaiters.remove(at: index).continuation.resume(returning: nil)
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
            if blocksAdmission(for: waiter.scopeID) {
                stillBlocked.append(waiter)
            } else {
                ready.append(waiter)
            }
        }
        admissionWaiters = stillBlocked
        ready.forEach { $0.continuation.resume(returning: true) }
    }
}

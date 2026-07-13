import Foundation

struct ExtensionRuntimeMutationLease: Hashable {
    enum Operation: String {
        case install
        case enable
        case disable
        case uninstall
    }

    let extensionID: String
    let operation: Operation
    fileprivate let token: UInt64
}

struct ExtensionRuntimeTerminalLease: Hashable {
    fileprivate let token: UInt64
}

/// Fail-busy admission for extension lifecycle mutations. A scoped lease seals
/// one extension against lazy loads and competing install/enable/disable work;
/// a terminal lease seals the entire runtime during shutdown.
@MainActor
final class ExtensionRuntimeMutationRegistry {
    private var leasesByExtensionID:
        [String: ExtensionRuntimeMutationLease] = [:]
    private var terminalLease: ExtensionRuntimeTerminalLease?
    private var irreversibleLeases = Set<ExtensionRuntimeMutationLease>()
    private var terminalAdmissionWaiters: [@MainActor () -> Void] = []
    private var nextToken: UInt64 = 0

    func begin(
        extensionID: String,
        operation: ExtensionRuntimeMutationLease.Operation
    ) -> ExtensionRuntimeMutationLease? {
        guard terminalLease == nil,
              leasesByExtensionID[extensionID] == nil
        else {
            return nil
        }
        nextToken &+= 1
        let lease = ExtensionRuntimeMutationLease(
            extensionID: extensionID,
            operation: operation,
            token: nextToken
        )
        leasesByExtensionID[extensionID] = lease
        return lease
    }

    func isCurrent(_ lease: ExtensionRuntimeMutationLease) -> Bool {
        terminalLease == nil
            && leasesByExtensionID[lease.extensionID] == lease
    }

    @discardableResult
    func finish(_ lease: ExtensionRuntimeMutationLease) -> Bool {
        guard isCurrent(lease) else { return false }
        let wasIrreversible = irreversibleLeases.contains(lease)
        irreversibleLeases.remove(lease)
        leasesByExtensionID.removeValue(forKey: lease.extensionID)
        if wasIrreversible, irreversibleLeases.isEmpty {
            let waiters = terminalAdmissionWaiters
            terminalAdmissionWaiters.removeAll()
            waiters.forEach { $0() }
        }
        return true
    }

    func enterIrreversiblePhase(
        _ lease: ExtensionRuntimeMutationLease
    ) -> Bool {
        guard isCurrent(lease) else { return false }
        irreversibleLeases.insert(lease)
        return true
    }

    /// Registers zero-cost, one-shot work for a terminal transition blocked
    /// by irreversible mutations. No observer or timer remains after the last
    /// irreversible lease finishes.
    func runWhenTerminalAdmissionAvailable(
        _ action: @escaping @MainActor () -> Void
    ) {
        guard irreversibleLeases.isEmpty == false else {
            action()
            return
        }
        terminalAdmissionWaiters.append(action)
    }

    func admitsLoad(
        extensionID: String,
        lease: ExtensionRuntimeMutationLease?
    ) -> Bool {
        guard terminalLease == nil else { return false }
        guard let current = leasesByExtensionID[extensionID] else {
            return lease == nil
        }
        return current == lease
    }

    func hasCompetingScopedMutation(
        extensionID: String,
        excluding lease: ExtensionRuntimeMutationLease?
    ) -> Bool {
        guard let current = leasesByExtensionID[extensionID] else {
            return false
        }
        return current != lease
    }

    func beginTerminal() -> ExtensionRuntimeTerminalLease? {
        guard irreversibleLeases.isEmpty else { return nil }
        return issueTerminalLease()
    }

    func beginTerminalIfNoScopedMutations()
        -> ExtensionRuntimeTerminalLease? {
        guard leasesByExtensionID.isEmpty else { return nil }
        return beginTerminal()
    }

    private func issueTerminalLease() -> ExtensionRuntimeTerminalLease {
        nextToken &+= 1
        let lease = ExtensionRuntimeTerminalLease(token: nextToken)
        terminalLease = lease
        leasesByExtensionID.removeAll()
        return lease
    }

    func isCurrent(_ lease: ExtensionRuntimeTerminalLease) -> Bool {
        terminalLease == lease
    }

    @discardableResult
    func finish(_ lease: ExtensionRuntimeTerminalLease) -> Bool {
        guard isCurrent(lease) else { return false }
        terminalLease = nil
        return true
    }
}

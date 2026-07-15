@MainActor
struct TabRuntimeAttachmentWitness {
    let connection: TabRuntimePortConnection
    let lease: TabRuntimePortLease

    func isCurrent() -> Bool {
        connection.acceptsExactAttachment(lease)
    }

    func currentRegistry() -> RuntimePortRegistry? {
        guard isCurrent() else { return nil }
        return lease.registry
    }

    func matches(_ other: TabRuntimeAttachmentWitness) -> Bool {
        connection === other.connection
            && connection.sameAttachment(lease, other.lease)
    }
}

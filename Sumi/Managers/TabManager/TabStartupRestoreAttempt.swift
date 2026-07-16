@MainActor
struct TabStartupRestorePolicy {
    let isEnabled: Bool
    let automaticallyStarts: Bool
    let requestedStructuralRevision: UInt64
}

@MainActor
struct TabStartupRestoreAttempt {
    let generation: UInt64
    let expectedStructuralRevision: UInt64
    let runtimeAttachment: TabRuntimeAttachmentWitness

    func matches(_ other: Self) -> Bool {
        generation == other.generation && runtimeAttachment.matches(
            other.runtimeAttachment
        )
    }

    func isRuntimeCurrent() -> Bool { runtimeAttachment.isCurrent() }
}

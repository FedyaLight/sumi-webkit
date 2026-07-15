@MainActor
final class ShortcutLiveRetirementBatchResidencePublication {
    private let registry: LiveShortcutTabRegistry
    private let changes: [LiveShortcutResidenceMutationStaging.Change]
    private var isPublished = false

    init(
        registry: LiveShortcutTabRegistry,
        changes: [LiveShortcutResidenceMutationStaging.Change]
    ) {
        self.registry = registry
        self.changes = changes
    }

    func publish() {
        guard isPublished == false else { return }
        isPublished = true
        if changes.isEmpty == false { registry.staging.publish(changes) }
    }
}

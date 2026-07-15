@MainActor
final class PreparedShortcutLiveResidencePublication {
    private let registry: LiveShortcutTabRegistry
    private let change: LiveShortcutResidenceMutationStaging.Change?
    private var isPublished = false

    init(
        registry: LiveShortcutTabRegistry,
        change: LiveShortcutResidenceMutationStaging.Change?
    ) {
        self.registry = registry
        self.change = change
    }

    func publish() {
        guard isPublished == false else { return }
        isPublished = true
        if let change { registry.staging.publish([change]) }
    }
}

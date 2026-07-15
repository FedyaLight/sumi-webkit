@MainActor
final class DetachedTabRuntimeRetirementPhysicalEffect {
    private enum Completion {
        case normal
        case aggregateDrain
    }

    private let publication: PreparedScopedTabRuntimePublication?
    private let committed: CommittedTabRuntimeRetirementCleanupOwnership?
    private let retirement: TabRuntimeRetirementService
    private let attachment: TabRuntimeAttachmentWitness
    private let completion: Completion
    private var isPublished = false

    static func normal(
        effect: DetachedTabRuntimeRetirementEffect,
        exposure: DetachedTabRuntimeExposureWitness,
        teardown: TabRuntimeTeardownService
    ) -> DetachedTabRuntimeRetirementPhysicalEffect? {
        guard case .cleanupOnly = effect else {
            return Self(
                effect: effect,
                exposure: exposure,
                teardown: teardown,
                completion: .normal
            )
        }
        return nil
    }

    static func aggregateDrain(
        effect: DetachedTabRuntimeRetirementEffect,
        exposure: DetachedTabRuntimeExposureWitness,
        teardown: TabRuntimeTeardownService
    ) -> DetachedTabRuntimeRetirementPhysicalEffect? {
        Self(
            effect: effect,
            exposure: exposure,
            teardown: teardown,
            completion: .aggregateDrain
        )
    }

    private init?(
        effect: DetachedTabRuntimeRetirementEffect,
        exposure: DetachedTabRuntimeExposureWitness,
        teardown: TabRuntimeTeardownService,
        completion: Completion
    ) {
        guard effect.isExact(
            exposure: exposure,
            retirement: teardown.retirement
        ) else { return nil }
        retirement = teardown.retirement
        attachment = exposure.runtimeAttachment
        self.completion = completion
        switch effect {
        case .none, .terminallyDrained:
            publication = nil
            committed = nil
        case .empty(let runtime):
            committed = nil
            switch completion {
            case .normal:
                publication = teardown.terminalRetirement
                    .prepareScopedRuntimePublication(
                        [exposure.tab], runtime: runtime
                    )
                if publication == nil { return nil }
            case .aggregateDrain:
                publication = nil
            }
        case .committed(let value), .cleanupOnly(let value):
            committed = value
            switch completion {
            case .normal:
                publication = teardown.terminalRetirement
                    .prepareScopedRuntimePublication(
                        [exposure.tab], runtime: value.runtime
                    )
                if publication == nil { return nil }
            case .aggregateDrain:
                publication = nil
            }
        }
    }

    func publish() {
        guard isPublished == false else { return }
        isPublished = true
        switch completion {
        case .normal:
            if attachment.isCurrent() { publication?.publish() }
            if let committed {
                retirement.destroyCommittedRuntime(committed)
            }
        case .aggregateDrain:
            if let committed {
                retirement.destroyAfterTerminalDrain(committed)
            }
        }
    }
}

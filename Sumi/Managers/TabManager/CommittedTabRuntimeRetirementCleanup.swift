import Foundation

@MainActor
final class CommittedTabRuntimeRetirementCleanupOwnership {
    enum CompletionPolicy { case normalOrDrain, drainOnly }
    private enum State { case owned, transferred }

    let tabs: [Tab]
    let runtime: RuntimePortRegistry
    let generations: [RetiredTabWebViewGeneration]
    private let completionPolicy: CompletionPolicy
    private var state = State.owned

    init(
        tabs: [Tab],
        runtime: RuntimePortRegistry,
        generations: [RetiredTabWebViewGeneration],
        completionPolicy: CompletionPolicy
    ) {
        self.tabs = tabs
        self.runtime = runtime
        self.generations = generations
        self.completionPolicy = completionPolicy
    }

    var isOwned: Bool {
        if case .owned = state { return true }
        return false
    }

    func claimNormalCompletion()
        -> ClaimedCommittedTabRuntimeRetirementCleanup? {
        guard case .owned = state,
              case .normalOrDrain = completionPolicy else { return nil }
        state = .transferred
        return ClaimedCommittedTabRuntimeRetirementCleanup(
            tabs: tabs,
            runtime: runtime,
            generations: generations,
            publicationCapability: .normalOrDrain
        )
    }

    func claimAggregateDrainCompletion()
        -> ClaimedCommittedTabRuntimeRetirementCleanup? {
        guard case .owned = state else { return nil }
        state = .transferred
        return ClaimedCommittedTabRuntimeRetirementCleanup(
            tabs: tabs,
            runtime: runtime,
            generations: generations,
            publicationCapability: .drainOnly
        )
    }
}

@MainActor
final class ClaimedCommittedTabRuntimeRetirementCleanup {
    fileprivate enum PublicationCapability { case normalOrDrain, drainOnly }
    struct Effect {
        let tabs: [Tab]
        let runtime: RuntimePortRegistry
        let generations: [RetiredTabWebViewGeneration]
    }

    private enum State { case claimed, terminal }

    private let effect: Effect
    private let publicationCapability: PublicationCapability
    private var state = State.claimed

    fileprivate init(
        tabs: [Tab],
        runtime: RuntimePortRegistry,
        generations: [RetiredTabWebViewGeneration],
        publicationCapability: PublicationCapability
    ) {
        effect = Effect(tabs: tabs, runtime: runtime, generations: generations)
        self.publicationCapability = publicationCapability
    }

    func takeNormalEffect() -> Effect? {
        guard case .claimed = state,
              case .normalOrDrain = publicationCapability else { return nil }
        state = .terminal
        return effect
    }

    func takeTerminalDrainEffect() -> Effect? {
        guard case .claimed = state else { return nil }
        state = .terminal
        return effect
    }
}

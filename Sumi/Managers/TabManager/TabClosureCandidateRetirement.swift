import Foundation

/// Outcome of retiring a mixed close-candidate batch before durable regular
/// collection mutation. Only `regularCandidates` may proceed to structural
/// removal; other categories are handled exclusively by their lifecycle owners.
struct TabClosureCandidateRetirementResult: Equatable {
    let regularCandidates: Set<UUID>
}

/// Retires shortcut, transient-extension, and auxiliary-window candidates, and
/// classifies the remainder as durable regular-tab candidates.
@MainActor
final class TabClosureCandidateRetirement {
    private let shortcutRetirement: ShortcutLiveTabRetirementService
    private let persistence: any TabClosurePersistence
    private let transientTabs: TabTransientWebKitTabLifecycleOwner

    init(
        shortcutRetirement: ShortcutLiveTabRetirementService,
        persistence: any TabClosurePersistence,
        transientTabs: TabTransientWebKitTabLifecycleOwner
    ) {
        self.shortcutRetirement = shortcutRetirement
        self.persistence = persistence
        self.transientTabs = transientTabs
    }

    func retire(_ ids: [UUID]) -> TabClosureCandidateRetirementResult {
        var seen = Set<UUID>()
        var regularCandidates = Set<UUID>()

        for id in ids where seen.insert(id).inserted {
            if shortcutRetirement.retire(tabId: id) != nil {
                continue
            }
            persistence.cancelRuntimeStatePersistence(for: id)
            if transientTabs.removeTransientExtensionTab(id: id) {
                continue
            }
            if transientTabs.closeAuxiliaryMiniWindowTabIfPresent(id: id) {
                continue
            }
            regularCandidates.insert(id)
        }

        return TabClosureCandidateRetirementResult(
            regularCandidates: regularCandidates
        )
    }
}

import Foundation
import SumiDomain

/// Topology-free divider-weight channel. It updates one exact group in place,
/// marks only split persistence dirty and deliberately emits no global tab
/// structure event or window-session write.
@MainActor
final class SplitLayoutWeightMutationService {
    private let splitGroups: SplitGroupStore
    private let persistence: TabStructuralPersistenceService

    init(
        splitGroups: SplitGroupStore,
        persistence: TabStructuralPersistenceService
    ) {
        self.splitGroups = splitGroups
        self.persistence = persistence
    }

    @discardableResult
    func update(
        expectedGroup: SumiDomain.SplitGroup,
        path: [Int],
        weights: [Double]
    ) -> Bool {
        let tree = SplitLayoutSizing.updatingChildWeights(
            in: expectedGroup.layoutTree,
            at: path,
            weights: weights
        )
        guard tree != expectedGroup.layoutTree,
              let replacement = expectedGroup.replacingLayoutTree(with: tree),
              splitGroups.replaceLayout(
                expectedGroup,
                with: replacement
              ) else {
            return false
        }
        persistence.markSplitGroupsStructurallyDirty()
        persistence.scheduleStructuralPersistence()
        return true
    }
}

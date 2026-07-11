import Foundation
import SumiDomain

/// Topology-free divider-weight channel. It updates one exact group in place,
/// marks only split persistence dirty and deliberately emits no global tab
/// structure event or window-session write.
@MainActor
final class SplitLayoutWeightMutationService {
    private let tabManager: @MainActor () -> TabManager?

    init(tabManager: @escaping @MainActor () -> TabManager?) {
        self.tabManager = tabManager
    }

    @discardableResult
    func update(
        expectedGroup: SumiDomain.SplitGroup,
        path: [Int],
        weights: [Double]
    ) -> Bool {
        guard let tabManager = tabManager() else { return false }
        let tree = SplitLayoutSizing.updatingChildWeights(
            in: expectedGroup.layoutTree,
            at: path,
            weights: weights
        )
        guard tree != expectedGroup.layoutTree,
              let replacement = expectedGroup.replacingLayoutTree(with: tree),
              tabManager.splitGroupStore.replaceLayout(
                expectedGroup,
                with: replacement
              ) else {
            return false
        }
        tabManager.structuralPersistence.markSplitGroupsStructurallyDirty()
        tabManager.structuralPersistence.scheduleStructuralPersistenceFromMain()
        return true
    }
}

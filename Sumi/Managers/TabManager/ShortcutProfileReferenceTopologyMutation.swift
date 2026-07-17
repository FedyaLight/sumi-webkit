import Foundation
import SumiDomain

@MainActor
final class ShortcutProfileReferenceTopologyMutation {
    private let splitGroups: SplitGroupStore
    private let splitMutations: SplitGroupMutationService

    init(
        splitGroups: SplitGroupStore,
        splitMutations: SplitGroupMutationService
    ) {
        self.splitGroups = splitGroups
        self.splitMutations = splitMutations
    }

    func prepare(
        _ replacement: ShortcutProfileReferenceMutationPlan.SplitReplacement?
    ) -> SplitGroupReplacementReceipt? {
        guard let replacement else { return nil }
        return splitMutations.prepareReplaceAll(
            expected: replacement.expected,
            with: replacement.replacement,
            persist: false
        )
    }

    func publish(
        _ receipt: SplitGroupReplacementReceipt,
        expected replacement: [SplitGroup]
    ) -> Bool {
        guard receipt.committedModelIsExact() else {
            _ = receipt.forfeitToForeignMutation()
            return false
        }
        receipt.publish()
        return splitGroups.groups == replacement
    }
}

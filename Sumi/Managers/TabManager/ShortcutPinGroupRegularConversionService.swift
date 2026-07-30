import Foundation
import SumiDomain

/// Converts one canonical shortcut split group to regular-tab residence.
@MainActor
final class ShortcutPinGroupRegularConversionService {
    private let admission: ShortcutPinPromotionAdmission
    private let transaction: ShortcutPinRegularConversionTransaction

    init(
        admission: ShortcutPinPromotionAdmission,
        transaction: ShortcutPinRegularConversionTransaction
    ) {
        self.admission = admission
        self.transaction = transaction
    }

    func convert(
        _ group: SplitGroup,
        into targetSpaceID: UUID,
        at targetIndex: Int,
        preferredWindowID: UUID?
    ) -> Bool {
        guard let pins = admission.canonicalGroupPins(for: group) else {
            return false
        }
        return transaction.commitGroup(
            group,
            pins: pins,
            into: targetSpaceID,
            at: targetIndex,
            preferredWindowID: preferredWindowID
        )
    }
}

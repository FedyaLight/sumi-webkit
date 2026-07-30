import Foundation

/// Promotes one canonical shortcut pin through an admitted split transition.
@MainActor
final class ShortcutPinRegularPromotionService {
    private let promotion: ShortcutTabPromotionService
    private let admission: ShortcutPinPromotionAdmission
    private let transaction: ShortcutPinRegularConversionTransaction
    private let runtimeConnection: TabRuntimePortConnection

    init(
        promotion: ShortcutTabPromotionService,
        admission: ShortcutPinPromotionAdmission,
        transaction: ShortcutPinRegularConversionTransaction,
        runtimeConnection: TabRuntimePortConnection
    ) {
        self.promotion = promotion
        self.admission = admission
        self.transaction = transaction
        self.runtimeConnection = runtimeConnection
    }

    func promote(
        _ candidatePin: ShortcutPin,
        into targetSpaceID: UUID,
        at targetIndex: Int? = nil,
        preferredWindowId: UUID? = nil
    ) -> ShortcutTabPromotionResult? {
        guard let pin = admission.canonicalPin(for: candidatePin) else { return nil }
        let sourceLiveFolderID = pin.folderId.flatMap { folderID in
            runtimeConnection.current?.isLiveFolder(folderID) == true
                ? folderID
                : nil
        }
        guard let plan = promotion.preparePromotion(
                  pin,
                  into: targetSpaceID,
                  at: targetIndex,
                  preferredWindowId: preferredWindowId,
                  allowsGroupedPin: true
              ) else { return nil }

        guard case .admitted(let split) = admission.splitOutcome(
            pinID: pin.id,
            promotedTabID: plan.tab.id,
            targetSpaceID: targetSpaceID
        ) else {
            _ = plan.placement.cancel()
            return nil
        }
        guard let result = transaction.commit(
            pin: pin,
            plan: plan,
            split: split
        ) else { return nil }
        if let sourceLiveFolderID {
            runtimeConnection.current?.reconcileLiveFolderItemMove(
                shortcutPinID: pin.id,
                fromFolderID: sourceLiveFolderID,
                toFolderID: nil,
                targetIndex: nil
            )
        }
        return result
    }
}

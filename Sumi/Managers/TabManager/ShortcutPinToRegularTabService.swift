import Foundation
import SumiDomain

/// Adapts regular and split-drop callers to exact pin-promotion services.
@MainActor
final class ShortcutPinToRegularTabService {
    private let singlePin: ShortcutPinRegularPromotionService
    private let group: ShortcutPinGroupRegularConversionService

    init(
        singlePin: ShortcutPinRegularPromotionService,
        group: ShortcutPinGroupRegularConversionService
    ) {
        self.singlePin = singlePin
        self.group = group
    }

    @discardableResult
    func convert(
        _ candidatePin: ShortcutPin,
        into targetSpaceId: UUID,
        at targetIndex: Int? = nil,
        preferredWindowId: UUID? = nil
    ) -> Bool {
        singlePin.promote(
            candidatePin,
            into: targetSpaceId,
            at: targetIndex,
            preferredWindowId: preferredWindowId
        ) != nil
    }

    func promoteForSplitDrop(
        _ candidatePin: ShortcutPin,
        into targetSpaceID: UUID,
        preferredWindowID: UUID
    ) -> Tab? {
        singlePin.promote(
            candidatePin,
            into: targetSpaceID,
            preferredWindowId: preferredWindowID
        )?.tab
    }

    func convertGroup(
        _ group: SplitGroup,
        into targetSpaceID: UUID,
        at targetIndex: Int,
        preferredWindowID: UUID?
    ) -> Bool {
        self.group.convert(
            group,
            into: targetSpaceID,
            at: targetIndex,
            preferredWindowID: preferredWindowID
        )
    }
}

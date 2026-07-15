import Foundation
import SumiDomain

struct ShortcutBindingIdentity: Equatable {
    let pinId: UUID
    let role: ShortcutPinRole
    let spaceId: UUID?

    init(pinId: UUID, role: ShortcutPinRole, spaceId: UUID?) {
        self.pinId = pinId
        self.role = role
        self.spaceId = spaceId
    }

    @MainActor
    init?(tab: Tab) {
        guard let pinId = tab.shortcutPinId,
              let role = tab.shortcutPinRole else {
            return nil
        }
        self.pinId = pinId
        self.role = role
        self.spaceId = tab.spaceId
    }
}

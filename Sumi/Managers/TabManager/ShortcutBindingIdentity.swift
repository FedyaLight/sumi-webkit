import Foundation
import SumiDomain

struct ShortcutBindingIdentity: Equatable {
    let pinId: UUID
    let role: ShortcutPinRole
    let spaceId: UUID?

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

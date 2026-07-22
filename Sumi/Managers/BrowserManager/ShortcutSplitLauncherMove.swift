import Foundation
import SumiDomain

struct ShortcutSplitLauncherDestination {
    let role: ShortcutPinRole
    let profileId: UUID?
    let spaceId: UUID?
    let folderId: UUID?
    let index: Int
    let opensFolder: Bool

    init(
        role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        index: Int,
        opensFolder: Bool
    ) {
        self.role = role
        self.profileId = profileId
        self.spaceId = spaceId
        self.folderId = folderId
        self.index = index
        self.opensFolder = opensFolder
    }
}

@MainActor
struct PreparedShortcutSplitLauncherMove {
    let pin: ShortcutPin
    let pinReceipt: ShortcutSplitLauncherCatalogPinReceipt
    let destination: ShortcutSplitLauncherDestination

    init(
        pin: ShortcutPin,
        destination: ShortcutSplitLauncherDestination
    ) {
        self.pin = pin
        pinReceipt = ShortcutSplitLauncherCatalogPinReceipt(pin)
        self.destination = destination
    }
}

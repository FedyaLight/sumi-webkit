import Foundation
import SumiDomain

struct ShortcutSplitLauncherDestination {
    let role: ShortcutPinRole
    let profileId: UUID?
    let spaceId: UUID?
    let folderId: UUID?
    let index: Int
}

@MainActor
struct PreparedShortcutSplitLauncherRestoration {
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

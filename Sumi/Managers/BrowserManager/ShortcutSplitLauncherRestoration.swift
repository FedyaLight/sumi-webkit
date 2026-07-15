import Foundation
import SumiDomain

struct ShortcutSplitLauncherDestination {
    let role: ShortcutPinRole
    let profileId: UUID?
    let spaceId: UUID?
    let folderId: UUID?
    let index: Int
}

struct PreparedShortcutSplitLauncherRestoration {
    let pin: ShortcutPin
    let destination: ShortcutSplitLauncherDestination
}

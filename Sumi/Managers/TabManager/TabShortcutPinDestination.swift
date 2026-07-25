import Foundation
import SumiDomain

/// Where a regular tab lands when it is converted into a shortcut pin: the pin
/// role, the profile/space/folder that owns it, its index within that
/// container, and whether the destination folder opens on commit.
struct TabShortcutPinDestination {
    let role: ShortcutPinRole
    let profileId: UUID?
    let spaceId: UUID?
    let folderId: UUID?
    let index: Int
    let opensFolder: Bool
}

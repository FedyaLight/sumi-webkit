import Foundation
import SumiDomain

/// Immutable proof for one canonical launcher object and all move-relevant
/// fields, including the otherwise mutable title.
@MainActor
struct ShortcutSplitLauncherCatalogPinReceipt {
    let pin: ShortcutPin
    private let role: ShortcutPinRole
    private let profileID: UUID?
    private let executionProfileID: UUID?
    private let spaceID: UUID?
    private let folderID: UUID?
    private let index: Int
    private let launchURL: URL
    private let title: String
    private let iconAsset: String?

    init(_ pin: ShortcutPin) {
        self.pin = pin
        role = pin.role
        profileID = pin.profileId
        executionProfileID = pin.executionProfileId
        spaceID = pin.spaceId
        folderID = pin.folderId
        index = pin.index
        launchURL = pin.launchURL
        title = pin.title
        iconAsset = pin.iconAsset
    }

    func accepts(_ current: ShortcutPin) -> Bool {
        current === pin
            && current.role == role
            && current.profileId == profileID
            && current.executionProfileId == executionProfileID
            && current.spaceId == spaceID
            && current.folderId == folderID
            && current.index == index
            && current.launchURL == launchURL
            && current.title == title
            && current.iconAsset == iconAsset
    }
}

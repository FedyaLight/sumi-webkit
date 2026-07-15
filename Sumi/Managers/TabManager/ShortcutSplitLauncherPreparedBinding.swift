import Foundation
import SumiDomain

@MainActor
struct ShortcutSplitLauncherBindingPinTarget {
    let id: UUID
    let role: ShortcutPinRole
    let profileID: UUID?
    let executionProfileID: UUID?
    let spaceID: UUID?
    let folderID: UUID?
    let launchURL: URL
    let title: String
    let iconAsset: String?

    init(_ pin: ShortcutPin) {
        id = pin.id
        role = pin.role
        profileID = pin.profileId
        executionProfileID = pin.executionProfileId
        spaceID = pin.spaceId
        folderID = pin.folderId
        launchURL = pin.launchURL
        title = pin.title
        iconAsset = pin.iconAsset
    }

    func accepts(_ pin: ShortcutPin) -> Bool {
        pin.id == id
            && pin.role == role
            && pin.profileId == profileID
            && pin.executionProfileId == executionProfileID
            && pin.spaceId == spaceID
            && pin.folderId == folderID
            && pin.launchURL == launchURL
            && pin.title == title
            && pin.iconAsset == iconAsset
    }
}

@MainActor
struct ShortcutSplitLauncherPreparedBinding {
    let pinTarget: ShortcutSplitLauncherBindingPinTarget
    let admission: LiveShortcutPresentationRefreshAdmission
    let plans: [ShortcutSplitLauncherBindingPlan]
    let profileAdmissions: [ShortcutTabProfileAssignmentAdmission]
}

@MainActor
struct ShortcutSplitLauncherPreparedBindingModel {
    let pinTarget: ShortcutSplitLauncherBindingPinTarget
    let input: ShortcutTabBindingModelTransaction.Input
    let profileAdmissions: [ShortcutTabProfileAssignmentAdmission]
}

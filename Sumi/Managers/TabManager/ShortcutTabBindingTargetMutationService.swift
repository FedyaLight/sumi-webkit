import Foundation

/// Applies the model/profile half of a shortcut binding against one resolved
/// target. Residence and window publication remain transaction-owned.
@MainActor
final class ShortcutTabBindingTargetMutationService {
    private let resolution: ShortcutPinRuntimeResolutionOwner
    private let profiles: TabProfileTransitionService

    init(
        resolution: ShortcutPinRuntimeResolutionOwner,
        profiles: TabProfileTransitionService
    ) {
        self.resolution = resolution
        self.profiles = profiles
    }

    func presentationPage(
        for pin: ShortcutPin,
        windowID: UUID,
        spaceID: UUID?
    ) -> LiveShortcutPresentationPageReceipt? {
        resolution.presentationPageReceipt(
            for: pin,
            windowID: windowID,
            presentationSpaceID: spaceID
        )
    }

    func initializeFresh(
        _ tab: Tab,
        for pin: ShortcutPin,
        currentSpaceID: UUID?
    ) {
        tab.isPinned = false
        tab.isSpacePinned = false
        tab.bindToShortcutPin(pin)
        tab.spaceId = resolution.resolvedLiveSpaceId(
            for: pin,
            currentSpaceId: currentSpaceID
        )
        tab.profileId = resolution.resolvedExecutionProfileId(
            for: pin,
            currentSpaceId: currentSpaceID
        )
        tab.folderId = pin.role == .essential ? nil : pin.folderId
    }

    func applyExisting(
        _ pin: ShortcutPin,
        to tab: Tab,
        currentSpaceID: UUID?
    ) {
        prepareExisting(
            pin,
            to: tab,
            currentSpaceID: currentSpaceID
        ).execute()
    }

    func prepareExisting(
        _ pin: ShortcutPin,
        to tab: Tab,
        currentSpaceID: UUID?
    ) -> ShortcutTabBindingExecutionReceipt {
        let targetSpaceID = resolution.resolvedLiveSpaceId(
            for: pin,
            currentSpaceId: currentSpaceID
        )
        let targetProfileID = resolution.resolvedExecutionProfileId(
            for: pin,
            currentSpaceId: currentSpaceID
        )
        tab.isPinned = false
        tab.isSpacePinned = false
        tab.bindToShortcutPin(pin)
        _ = profiles.prepareForSpaceTransition(
            tab: tab,
            targetSpaceID: targetSpaceID,
            desiredProfileID: targetProfileID
        )
        tab.spaceId = targetSpaceID
        tab.folderId = pin.role == .essential ? nil : pin.folderId
        return ShortcutTabBindingExecutionReceipt(
            profiles: profiles,
            tab: tab,
            targetProfileID: targetProfileID
        )
    }
}

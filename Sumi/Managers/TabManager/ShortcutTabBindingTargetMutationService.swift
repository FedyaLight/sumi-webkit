import Foundation

/// Applies the model/profile half of a shortcut binding against one resolved
/// target. Residence and window publication remain transaction-owned.
@MainActor
final class ShortcutTabBindingTargetMutationService {
    private let resolution: ShortcutPinRuntimeResolutionOwner
    let profiles: TabProfileTransitionService

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
        tab.profileId = resolution.desiredLiveTabProfileId(for: pin)
        tab.folderId = pin.role == .favorite ? nil : pin.folderId
    }

    func prepareExisting(
        _ pin: ShortcutPin,
        to tab: Tab,
        currentSpaceID: UUID?,
        using lease: TabRuntimePortLease
    ) -> PreparedShortcutTabBinding? {
        let candidateProfileID = resolution.resolvedExecutionProfileId(
            for: pin,
            currentSpaceId: currentSpaceID
        )
        let runtimeFallback = candidateProfileID == nil
            ? lease.captureFallbackProfileWitness()
            : nil
        guard let resolvedProfileID = candidateProfileID
            ?? runtimeFallback?.profileID else { return nil }
        let target = ShortcutSplitLauncherBindingTarget(
            spaceID: resolution.resolvedLiveSpaceId(
                for: pin,
                currentSpaceId: currentSpaceID
            ),
            desiredProfileID: resolution.desiredLiveTabProfileId(for: pin),
            resolvedProfileID: resolvedProfileID,
            runtimeFallback: runtimeFallback,
            folderID: pin.role == .favorite ? nil : pin.folderId
        )
        guard let profile = profiles.prepareShortcutAssignment(
            tab: tab,
            desiredProfileID: target.desiredProfileID,
            resolvedProfileID: target.resolvedProfileID,
            runtimeFallback: target.runtimeFallback,
            using: lease
        ) else { return nil }
        return PreparedShortcutTabBinding(
            receipt: ShortcutSplitLauncherTabReceipt(tab),
            target: target,
            profile: profile
        )
    }

}

import Foundation

/// Performs the admitted and reversible portion of Glance adoption after the
/// caller has proved that the source object has no existing residence.
@MainActor
final class GlanceTabAdoptionCommitter {
    private let creationPlacement: TabCreationPlacementService
    private let profileAdmissions: ProfileReferenceAdmissionLedger
    private let regularTabs: RegularTabCollectionOwner
    private let runtimeConnection: TabRuntimePortConnection
    private let publication: RegularTabPublicationTransaction

    init(
        creationPlacement: TabCreationPlacementService,
        profileAdmissions: ProfileReferenceAdmissionLedger,
        regularTabs: RegularTabCollectionOwner,
        runtimeConnection: TabRuntimePortConnection,
        publication: RegularTabPublicationTransaction
    ) {
        self.creationPlacement = creationPlacement
        self.profileAdmissions = profileAdmissions
        self.regularTabs = regularTabs
        self.runtimeConnection = runtimeConnection
        self.publication = publication
    }

    func commit(
        _ tab: Tab,
        sourceTab: Tab?,
        in space: Space?
    ) -> Tab? {
        let sourceProfileID = tab.profileId
        let sourceURL = tab.url
        return creationPlacement.withAdmittedCreationPlacement(
            preferred: space,
            fallbackSpaceId: sourceTab?.spaceId,
            bootstrapProfileId: tab.profileId
                ?? runtimeConnection.current?.currentProfileId,
            inheritsSpaceProfile: tab.profileId == nil,
            admission: { [profileAdmissions] placement in
                let profileID = tab.profileId ?? placement.effectiveProfileId
                return profileID.map(profileAdmissions.isReferenceAllowed) == true
            }
        ) { [regularTabs, runtimeConnection, publication] placement in
            if tab.profileId == nil {
                tab.profileId = placement.temporaryProfileOverrideId
            }
            let insertionIndex = Self.adoptionInsertionIndex(
                sourceTab: sourceTab,
                targetSpaceID: placement.space.id,
                regularTabs: regularTabs
            )
            if let currentURL = runtimeConnection.current?.webViewLifecycle
                .anyLiveWebView(for: tab)?.url {
                tab.url = currentURL
            }
            guard publication.add(
                tab,
                regularInsertionIndex: insertionIndex,
                admissionProfileIDs: placement.admissionProfileIDs
            ) else {
                tab.profileId = sourceProfileID
                tab.url = sourceURL
                return nil
            }
            return tab
        }
    }

    private static func adoptionInsertionIndex(
        sourceTab: Tab?,
        targetSpaceID: UUID,
        regularTabs: RegularTabCollectionOwner
    ) -> Int? {
        if let sourceTab,
           sourceTab.spaceId == targetSpaceID,
           let sourceIndex = regularTabs.firstIndex(
               of: sourceTab,
               in: targetSpaceID
           ) {
            return sourceIndex + 1
        }
        if sourceTab?.isPinned == true
            || sourceTab?.shortcutPinRole == .essential {
            return 0
        }
        return nil
    }
}

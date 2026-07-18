import Foundation
import WebKit

/// Owns creation-placement admission and publishes exactly one constructed
/// candidate. It returns nil before any detached candidate escapes on failure.
@MainActor
final class RegularTabCreationTransaction {
    private let creationPlacement: TabCreationPlacementService
    private let profileAdmissions: ProfileReferenceAdmissionLedger
    private let candidates: RegularTabCreationCandidateFactory
    private let publication: RegularTabPublicationTransaction

    init(
        creationPlacement: TabCreationPlacementService,
        profileAdmissions: ProfileReferenceAdmissionLedger,
        candidates: RegularTabCreationCandidateFactory,
        publication: RegularTabPublicationTransaction
    ) {
        self.creationPlacement = creationPlacement
        self.profileAdmissions = profileAdmissions
        self.candidates = candidates
        self.publication = publication
    }

    func create(
        url: String,
        in space: Space?,
        webViewConfigurationOverride: WKWebViewConfiguration?,
        webExtensionContextOverride: WKWebExtensionContext?,
        executionProfileID: UUID?,
        regularInsertionIndex: Int?,
        prepareBeforePublication: @MainActor (Tab) -> Void
    ) -> Tab? {
        creationPlacement.withAdmittedCreationPlacement(
            preferred: space,
            bootstrapProfileId: executionProfileID,
            inheritsSpaceProfile: executionProfileID == nil,
            admission: { [profileAdmissions] placement in
                placement.admissionProfileIDs.isEmpty == false
                    && placement.admissionProfileIDs.allSatisfy(
                        profileAdmissions.isReferenceAllowed
                    )
            }
        ) { [candidates, publication] placement in
            let tab = candidates.makeTab(
                url: url,
                placement: placement,
                executionProfileID: executionProfileID,
                regularInsertionIndex: regularInsertionIndex,
                webViewConfigurationOverride: webViewConfigurationOverride,
                webExtensionContextOverride: webExtensionContextOverride
            )
            prepareBeforePublication(tab)
            return publication.add(
                tab,
                regularInsertionIndex: regularInsertionIndex,
                admissionProfileIDs: placement.admissionProfileIDs
            ) ? tab : nil
        }
    }

    func createPopup(
        in space: Space?,
        webViewConfigurationOverride: WKWebViewConfiguration?,
        executionProfileID: UUID?,
        regularInsertionIndex: Int?
    ) -> Tab? {
        creationPlacement.withAdmittedCreationPlacement(
            preferred: space,
            bootstrapProfileId: executionProfileID,
            inheritsSpaceProfile: executionProfileID == nil,
            admission: { [profileAdmissions] placement in
                placement.admissionProfileIDs.isEmpty == false
                    && placement.admissionProfileIDs.allSatisfy(
                        profileAdmissions.isReferenceAllowed
                    )
            }
        ) { [candidates, publication] placement in
            let tab = candidates.makePopup(
                placement: placement,
                executionProfileID: executionProfileID,
                regularInsertionIndex: regularInsertionIndex,
                webViewConfigurationOverride: webViewConfigurationOverride
            )
            return publication.add(
                tab,
                regularInsertionIndex: tab.index,
                admissionProfileIDs: placement.admissionProfileIDs
            ) ? tab : nil
        }
    }
}

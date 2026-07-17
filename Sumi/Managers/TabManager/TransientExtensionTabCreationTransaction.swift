import Foundation
import SumiDomain
import WebKit

@MainActor
final class TransientExtensionTabCreationTransaction {
    private let urlResolver: TransientExtensionTabURLResolver
    private let creationPlacement: TabCreationPlacementService
    private let profileAdmissions: ProfileReferenceAdmissionLedger
    private let installer: TransientExtensionTabInstaller

    init(
        urlResolver: TransientExtensionTabURLResolver,
        creationPlacement: TabCreationPlacementService,
        profileAdmissions: ProfileReferenceAdmissionLedger,
        installer: TransientExtensionTabInstaller
    ) {
        self.urlResolver = urlResolver
        self.creationPlacement = creationPlacement
        self.profileAdmissions = profileAdmissions
        self.installer = installer
    }

    func create(
        url input: String,
        in space: Space?,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Tab {
        let url = urlResolver.resolve(input)
        var admissionLease: ProfileReferenceMutationLease?
        defer {
            if let admissionLease {
                precondition(
                    profileAdmissions.endReferenceMutation(admissionLease),
                    "Transient extension creation lost its admission lease"
                )
            }
        }

        let installed = creationPlacement.withAdmittedCreationPlacement(
            preferred: space,
            admission: { [profileAdmissions] placement in
                guard let profileID = placement.effectiveProfileId else {
                    return true
                }
                do {
                    let lease = try profileAdmissions.beginReferenceMutation(
                        to: [profileID]
                    )
                    guard profileAdmissions.validate(
                        lease,
                        covers: [profileID]
                    ) else {
                        precondition(profileAdmissions.endReferenceMutation(lease))
                        return false
                    }
                    admissionLease = lease
                    return true
                } catch {
                    return false
                }
            }
        ) { [self] placement in
            if let admissionLease {
                guard profileAdmissions.validate(
                    admissionLease,
                    covers: placement.admissionProfileIDs
                ) else { return nil }
            }

            let tab = installer.install(
                url: url,
                placement: placement,
                webExtensionContextOverride: webExtensionContextOverride
            )
            if let admissionLease {
                precondition(
                    profileAdmissions.validate(
                        admissionLease,
                        covers: placement.admissionProfileIDs
                    ),
                    "Transient extension creation crossed a retired profile boundary"
                )
            }
            return tab
        }

        return installed ?? installer.makeDetachedFallback(url: url)
    }
}

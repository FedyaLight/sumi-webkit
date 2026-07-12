import Foundation
import WebKit

/// Authority captured synchronously at the user-click boundary, before
/// runtime resolution is allowed to suspend or materialize WebKit state.
@available(macOS 15.5, *)
@MainActor
struct ExtensionActionRequestEvidence {
    struct PageAuthority {
        let tab: Tab
        let profileID: UUID?
        let resolvedProfileID: UUID?
        let profileAssignmentRevision: UInt64
        let documentProof: TabCommittedDocumentAuthorityProof
        let pageURL: URL
    }

    let extensionID: String
    let installedRecordRevision: UInt64
    let resolvedProfileID: UUID?
    let page: PageAuthority?
    /// An existing binding is exact authority. Absence is not: runtime
    /// resolution is specifically allowed to lazily create the binding.
    let runtimeBindingAtClick: ExtensionControllerCallbackEvidence?
}

/// Captures and revalidates only the pre-resolution click authority. It does
/// not resolve a runtime or mutate browser state.
@available(macOS 15.5, *)
@MainActor
final class ExtensionActionRequestAdmission {
    private let runtimeBindingAdmission: ExtensionControllerCallbackAdmission
    private let profileRuntime: ExtensionProfileRuntime
    private let runtime: @MainActor () -> ExtensionManagerRuntime
    private let installedExtensions: InstalledExtensionCollection

    init(
        runtimeBindingAdmission: ExtensionControllerCallbackAdmission,
        profileRuntime: ExtensionProfileRuntime,
        runtime: @escaping @MainActor () -> ExtensionManagerRuntime,
        installedExtensions: InstalledExtensionCollection
    ) {
        self.runtimeBindingAdmission = runtimeBindingAdmission
        self.profileRuntime = profileRuntime
        self.runtime = runtime
        self.installedExtensions = installedExtensions
    }

    func capture(
        extensionID: String,
        currentTab: Tab?
    ) -> ExtensionActionRequestEvidence? {
        let browserRuntime = runtime()
        if let currentTab,
           browserRuntime.allTabs().contains(where: { $0 === currentTab }) == false {
            return nil
        }
        let page = currentTab.map {
            ExtensionActionRequestEvidence.PageAuthority(
                tab: $0,
                profileID: $0.profileId,
                resolvedProfileID: profileRuntime.resolvedProfileId(
                    for: $0,
                    runtime: browserRuntime
                ),
                profileAssignmentRevision: $0.profileAssignment.changeRevision,
                documentProof: $0.committedDocumentRuntime.authorityProof,
                pageURL: $0.url
            )
        }
        let resolvedProfileID = page?.resolvedProfileID
            ?? profileRuntime.resolvedProfileId(
                explicitProfileId: nil,
                runtime: browserRuntime
            )
        let runtimeBindingAtClick: ExtensionControllerCallbackEvidence? =
            resolvedProfileID.flatMap { profileID in
            guard let context = profileRuntime.contexts(for: profileID)[extensionID],
                  let controller = profileRuntime.controller(for: profileID)
            else {
                return nil
            }
            return runtimeBindingAdmission.capture(
                context: context,
                controller: controller
            )
        }
        return ExtensionActionRequestEvidence(
            extensionID: extensionID,
            installedRecordRevision: installedExtensions.recordRevision(for: extensionID),
            resolvedProfileID: resolvedProfileID,
            page: page,
            runtimeBindingAtClick: runtimeBindingAtClick
        )
    }

    func isCurrent(_ evidence: ExtensionActionRequestEvidence) -> Bool {
        guard installedExtensions.recordRevision(for: evidence.extensionID)
            == evidence.installedRecordRevision else {
            return false
        }
        if let runtimeBindingAtClick = evidence.runtimeBindingAtClick,
           runtimeBindingAdmission.isCurrent(runtimeBindingAtClick) == false {
            return false
        }
        let browserRuntime = runtime()
        guard let page = evidence.page else {
            return profileRuntime.resolvedProfileId(
                explicitProfileId: nil,
                runtime: browserRuntime
            ) == evidence.resolvedProfileID
        }
        return browserRuntime.allTabs().contains { $0 === page.tab }
            && page.tab.profileAssignment.changeRevision
                == page.profileAssignmentRevision
            && page.tab.profileId == page.profileID
            && profileRuntime.resolvedProfileId(
                for: page.tab,
                runtime: browserRuntime
            ) == page.resolvedProfileID
            && page.tab.committedDocumentRuntime.authorityProof
                == page.documentProof
    }
}

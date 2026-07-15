import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionContextPublicationLifetime {
    private let profileTransition: ExtensionProfileRuntimeTransition
    private let contextResidency: ExtensionContextResidencyOwner
    private let websiteDataQuiescence: ExtensionWebsiteDataRuntimeQuiescence
    private let contextPublications: ExtensionContextPublicationQuery
    private let profileRuntimeState: ExtensionProfileRuntimeStateOwner
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        profileTransition: ExtensionProfileRuntimeTransition,
        contextResidency: ExtensionContextResidencyOwner,
        websiteDataQuiescence: ExtensionWebsiteDataRuntimeQuiescence,
        contextPublications: ExtensionContextPublicationQuery,
        profileRuntimeState: ExtensionProfileRuntimeStateOwner,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.profileTransition = profileTransition
        self.contextResidency = contextResidency
        self.websiteDataQuiescence = websiteDataQuiescence
        self.contextPublications = contextPublications
        self.profileRuntimeState = profileRuntimeState
        self.diagnostics = diagnostics
    }
}

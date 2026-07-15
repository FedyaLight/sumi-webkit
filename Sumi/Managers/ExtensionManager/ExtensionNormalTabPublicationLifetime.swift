import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalTabPublicationLifetime {
    private let publicationEvidence: ExtensionRuntimePublicationEvidenceIssuer
    private let lifecycle: ExtensionBrowserAttachmentAuthority.NormalTabLifecycle
    private let requestedTabs: ExtensionBrowserAttachmentAuthority.RequestedTabs
    private let query: ExtensionBrowserAttachmentAuthority.NormalTabQuery

    init(
        publicationEvidence: ExtensionRuntimePublicationEvidenceIssuer,
        lifecycle: ExtensionBrowserAttachmentAuthority.NormalTabLifecycle,
        requestedTabs: ExtensionBrowserAttachmentAuthority.RequestedTabs,
        query: ExtensionBrowserAttachmentAuthority.NormalTabQuery
    ) {
        self.publicationEvidence = publicationEvidence
        self.lifecycle = lifecycle
        self.requestedTabs = requestedTabs
        self.query = query
    }
}

import Foundation

/// Exact read state for normal-window publications. Lifecycle commands
/// populate it only after WebKit accepts the matching projection.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalWindowPublicationLedger {
    struct Publication {
        let lifecycleEpoch: UInt64
        let projection: ExtensionNormalWindowProjection
    }

    private var publicationsByWindowID: [UUID: Publication] = [:]
    private(set) var acceptsPublishedReads = true
    private(set) var publicationStage = ExtensionRuntimePublicationStage
        .loadedRuntime

    func updateReadPolicy(
        acceptsPublishedReads: Bool,
        publicationStage: ExtensionRuntimePublicationStage
    ) {
        self.acceptsPublishedReads = acceptsPublishedReads
        self.publicationStage = publicationStage
    }

    func publication(for windowID: UUID) -> Publication? {
        publicationsByWindowID[windowID]
    }

    func set(_ publication: Publication, for windowID: UUID) {
        publicationsByWindowID[windowID] = publication
    }

    @discardableResult
    func remove(for windowID: UUID) -> Publication? {
        publicationsByWindowID.removeValue(forKey: windowID)
    }

    func takeAll() -> [(windowID: UUID, publication: Publication)] {
        let publications = publicationsByWindowID.map {
            (windowID: $0.key, publication: $0.value)
        }
        publicationsByWindowID.removeAll()
        return publications
    }
}

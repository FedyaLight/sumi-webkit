import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionNormalWindowProjection {
    let windowIdentity: ObjectIdentifier
    let selectedTabIdentity: ObjectIdentifier
    let selectedTabID: UUID
    let profileID: UUID
    let runtimePublication: ExtensionRuntimePublicationEvidence
    let controller: WKWebExtensionController
    let windowAdapter: ExtensionWindowAdapter
    let selectedTabAdapter: ExtensionTabAdapter

    func belongsToSameWindowPublication(
        as other: ExtensionNormalWindowProjection
    ) -> Bool {
        windowIdentity == other.windowIdentity
            && profileID == other.profileID
            && runtimePublication == other.runtimePublication
            && controller === other.controller
            && windowAdapter === other.windowAdapter
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalWindowProjectionResolver {
    private let selection: ExtensionNormalWindowSelectionResolver
    private let publication: ExtensionNormalWindowPublicationProjectionResolver
    private let profileSwitcher: ExtensionNormalWindowProfileSwitcher

    init(
        selection: ExtensionNormalWindowSelectionResolver,
        publication: ExtensionNormalWindowPublicationProjectionResolver,
        profileSwitcher: ExtensionNormalWindowProfileSwitcher
    ) {
        self.selection = selection
        self.publication = publication
        self.profileSwitcher = profileSwitcher
    }

    func resolve(
        _ window: BrowserWindowState,
        publicationStage: ExtensionRuntimePublicationStage = .loadedRuntime
    ) -> ExtensionNormalWindowProjection? {
        guard let selection = selection.resolve(window) else { return nil }
        return publication.resolve(
            selection,
            publicationStage: publicationStage
        )
    }

    func switchToWindowProfile(_ window: BrowserWindowState) {
        profileSwitcher.switchToWindowProfile(window)
    }
}

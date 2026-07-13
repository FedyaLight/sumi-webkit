import Foundation
import WebKit

/// One exact, single-use physical Tab closure captured before structural
/// teardown can replace its controller or adapter-store entry.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalTabCloseReceipt {
    struct Publication {
        let controller: WKWebExtensionController
        let adapter: ExtensionTabAdapter
    }

    let tab: Tab
    let generation: ExtensionTabPublicationRevision
    let storedAdapter: ExtensionTabAdapter?
    let published: Publication?
    let implicit: Publication?
    let openClaim: TabExtensionOpenPublicationClaim?
    private var isPending = true

    init(
        tab: Tab,
        generation: ExtensionTabPublicationRevision,
        storedAdapter: ExtensionTabAdapter?,
        published: Publication?,
        implicit: Publication?,
        openClaim: TabExtensionOpenPublicationClaim?
    ) {
        self.tab = tab
        self.generation = generation
        self.storedAdapter = storedAdapter
        self.published = published
        self.implicit = implicit
        self.openClaim = openClaim
    }

    func beginClose() -> Bool {
        guard isPending else { return false }
        isPending = false
        return true
    }
}

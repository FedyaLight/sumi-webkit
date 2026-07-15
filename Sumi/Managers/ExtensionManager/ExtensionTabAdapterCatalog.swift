import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionTabAdapterCatalog: ExtensionTabAdapterResolving {
    private let adapterStore: ExtensionBrowserAdapterStore
    private let evidence: ExtensionTabAdapterEvidenceFactory
    private let projection: ExtensionTabAdapterProjectionFactory
    private let commands: ExtensionTabAdapterCommandFactory

    init(
        adapterStore: ExtensionBrowserAdapterStore,
        evidence: ExtensionTabAdapterEvidenceFactory,
        projection: ExtensionTabAdapterProjectionFactory,
        commands: ExtensionTabAdapterCommandFactory
    ) {
        self.adapterStore = adapterStore
        self.evidence = evidence
        self.projection = projection
        self.commands = commands
    }

    func stableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
        adapterStore.tabAdapter(for: tab) { [evidence, projection, commands] in
            guard let evidence = evidence.make(for: tab) else { return nil }
            let projection = projection.make(evidence: evidence)
            return ExtensionTabAdapter(
                evidence: evidence,
                projection: projection,
                commands: commands.make(evidence: evidence, projection: projection)
            )
        }
    }
}

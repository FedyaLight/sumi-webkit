import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionContextTransactionResidenceOwner {
    private let loadRevisions: ExtensionLoadRevisionAuthority
    private let tabPublicationRevisions: ExtensionTabPublicationRevisionAuthority
    private let mutationRegistry: ExtensionRuntimeMutationRegistry
    private let contextLoadRegistry: ExtensionContextLoadRegistry
    private let backgroundRuntimeState: ExtensionBackgroundRuntimeStateOwner
    private let demandCoordinator: ExtensionRuntimeDemandCoordinator

    init(
        loadRevisions: ExtensionLoadRevisionAuthority,
        tabPublicationRevisions: ExtensionTabPublicationRevisionAuthority,
        mutationRegistry: ExtensionRuntimeMutationRegistry,
        contextLoadRegistry: ExtensionContextLoadRegistry,
        backgroundRuntimeState: ExtensionBackgroundRuntimeStateOwner,
        demandCoordinator: ExtensionRuntimeDemandCoordinator
    ) {
        self.loadRevisions = loadRevisions
        self.tabPublicationRevisions = tabPublicationRevisions
        self.mutationRegistry = mutationRegistry
        self.contextLoadRegistry = contextLoadRegistry
        self.backgroundRuntimeState = backgroundRuntimeState
        self.demandCoordinator = demandCoordinator
    }
}

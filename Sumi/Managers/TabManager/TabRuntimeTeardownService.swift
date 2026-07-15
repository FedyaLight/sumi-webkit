import Foundation
import SumiWebRuntime

/// Publishes terminal runtime teardown after structural owners commit.
@MainActor
final class TabRuntimeTeardownService {
    let preparation = TabRuntimeTeardownPreparationService()
    let retirement: TabRuntimeRetirementService
    let terminalRetirement: TabRuntimeTeardownPublisher

    init(
        persistence: TabStructuralPersistenceService,
        membership: TabCollectionMembershipOwner,
        webViewSessions: WebViewSessionRepository
    ) {
        let terminalModel = TabTerminalModelPublisher(
            persistence: persistence,
            membership: membership
        )
        let publisher = TabRuntimeTeardownPublisher(
            membership: membership,
            terminalModel: terminalModel
        )
        terminalRetirement = publisher
        retirement = TabRuntimeRetirementService(
            webViewSessions: webViewSessions,
            publisher: publisher
        )
    }

    @discardableResult
    func teardown(
        _ tabs: [Tab],
        using runtime: RuntimePortRegistry
    ) -> Set<UUID> {
        guard let prepared = preparation.prepare(tabs, using: runtime) else {
            return []
        }
        return finish(prepared)
    }

    @discardableResult
    func finish(_ prepared: PreparedTabRuntimeTeardown) -> Set<UUID> {
        terminalRetirement.publish(prepared.tabs, runtime: prepared.runtime)
    }

    @discardableResult
    func finishRuntime(_ prepared: PreparedTabRuntimeTeardown) -> Set<UUID> {
        terminalRetirement.publishRuntime(
            prepared.tabs, runtime: prepared.runtime
        )
    }

}

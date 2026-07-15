import Foundation
import SumiWebRuntime

/// Publishes terminal runtime teardown after structural owners commit.
@MainActor
final class TabRuntimeTeardownService {
    let preparation = TabRuntimeTeardownPreparationService()
    let retirement: TabRuntimeRetirementService
    private let publisher: TabRuntimeTeardownPublisher

    init(
        persistence: TabStructuralPersistenceService,
        membership: TabCollectionMembershipOwner,
        webViewSessions: WebViewSessionRepository
    ) {
        let publisher = TabRuntimeTeardownPublisher(
            persistence: persistence,
            membership: membership
        )
        self.publisher = publisher
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
        publisher.publish(prepared.tabs, runtime: prepared.runtime)
    }
}

import SwiftData
import XCTest

@testable import Sumi
import SumiDomain

@MainActor
final class BrowserManagerStartupPersistenceTests: XCTestCase {
    func testProductionCompositionKeepsOneStartupPersistenceIdentity() {
        XCTAssertIdentical(
            BrowserManagerStartupPersistence.production,
            SumiStartupPersistenceComposition.browserManagerStartupPersistence
        )
        XCTAssertIdentical(
            BrowserConfiguration.shared.autoplayPolicyStore,
            BrowserManagerStartupPersistence.production.autoplayPolicyStore
        )
    }

    func testInjectedStartupPersistenceSuppliesManagerContexts() throws {
        let container = try makeInMemoryStartupContainer()
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(container: container)
        )

        XCTAssertIdentical(browserManager.modelContext.container, container)
        XCTAssertIdentical(browserManager.profileManager.context.container, container)
        XCTAssertIdentical(browserManager.tabManager.context.container, container)
        XCTAssertNotNil(browserManager.currentProfile)
    }

    func testInjectedStartupPersistenceSuppliesDefaultPermissionStore() async throws {
        let container = try makeInMemoryStartupContainer()
        let startupPersistence = BrowserManagerStartupPersistence(container: container)
        let browserManager = BrowserManager(
            startupPersistence: startupPersistence
        )
        let key = permissionKey(profilePartitionId: browserManager.currentProfile!.id.uuidString)

        try await browserManager.permissionRuntime.permissionCoordinator.setSiteDecision(
            for: key,
            state: .deny,
            source: .user,
            reason: "startup-persistence-test"
        )

        let records = try await SwiftDataPermissionStore(container: container)
            .listDecisions(profilePartitionId: key.profilePartitionId)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.key, key)
        XCTAssertEqual(records.first?.decision.state, .deny)
        XCTAssertEqual(records.first?.decision.reason, "startup-persistence-test")
    }

    func testInjectedStartupPersistenceSharesOnePermissionStoreWithBrowserConfiguration() throws {
        let container = try makeInMemoryStartupContainer()
        let startupPersistence = BrowserManagerStartupPersistence(container: container)
        let browserManager = BrowserManager(startupPersistence: startupPersistence)

        XCTAssertIdentical(
            browserManager.browserConfiguration.autoplayPolicyStore,
            browserManager.permissionRuntime.autoplayStore
        )
        XCTAssertIdentical(
            startupPersistence.autoplayPolicyStore,
            browserManager.permissionRuntime.autoplayStore
        )
        XCTAssertTrue(
            (startupPersistence.permissionStore as AnyObject)
                === (browserManager.permissionRuntime.autoplayStore.permissionStore as AnyObject)
        )
    }

    func testInjectedStartupPersistenceSuppliesAutoplayConfigurationStore() async throws {
        let container = try makeInMemoryStartupContainer()
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(container: container)
        )
        let profile = try XCTUnwrap(browserManager.currentProfile)
        let url = try XCTUnwrap(URL(string: "https://video.example"))

        try await browserManager.browserConfiguration.autoplayPolicyStore.setPolicy(
            .blockAll,
            for: url,
            profile: profile
        )

        let records = try await SwiftDataPermissionStore(container: container)
            .listDecisions(profilePartitionId: profile.id.uuidString)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.key.permissionType, .autoplay)
        XCTAssertEqual(
            browserManager.browserConfiguration.resolvedAutoplayPolicy(
                for: url,
                profile: profile
            ),
            .blockAll
        )
        XCTAssertEqual(
            TabBrowserNavigationRuntimeFactory.navigationDelegateRuntime(
                for: browserManager
            ).autoplayPolicy(url, profile),
            .blockAll
        )
    }

    func testExplicitBrowserConfigurationRemainsTheCanonicalPermissionOverride() async throws {
        let startupContainer = try makeInMemoryStartupContainer()
        let overrideContainer = try makeInMemoryStartupContainer()
        let overrideStore = SwiftDataPermissionStore(container: overrideContainer)
        let overrideAutoplayStore = SumiAutoplayPolicyStoreAdapter(
            persistentStore: overrideStore
        )
        let browserConfiguration = BrowserConfiguration(
            autoplayPolicyStore: overrideAutoplayStore
        )
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: startupContainer
            ),
            browserConfiguration: browserConfiguration
        )
        let profile = try XCTUnwrap(browserManager.currentProfile)
        let url = try XCTUnwrap(URL(string: "https://override.example"))

        XCTAssertIdentical(browserManager.browserConfiguration, browserConfiguration)
        XCTAssertIdentical(browserManager.permissionRuntime.autoplayStore, overrideAutoplayStore)

        try await browserManager.permissionRuntime.autoplayStore.setPolicy(
            .blockAudible,
            for: url,
            profile: profile
        )

        let overrideRecords = try await overrideStore.listDecisions(
            profilePartitionId: profile.id.uuidString
        )
        let startupRecords = try await SwiftDataPermissionStore(container: startupContainer)
            .listDecisions(profilePartitionId: profile.id.uuidString)
        XCTAssertEqual(overrideRecords.count, 1)
        XCTAssertTrue(startupRecords.isEmpty)
    }

    private func makeInMemoryStartupContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func permissionKey(profilePartitionId: String) -> SumiPermissionKey {
        let origin = SumiPermissionOrigin(string: "https://example.com")
        return SumiPermissionKey(
            requestingOrigin: origin,
            topOrigin: origin,
            permissionType: .geolocation,
            profilePartitionId: profilePartitionId
        )
    }
}

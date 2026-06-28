import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class BrowserManagerStartupPersistenceTests: XCTestCase {
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
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(container: container)
        )
        let key = permissionKey(profilePartitionId: browserManager.currentProfile!.id.uuidString)

        try await browserManager.permissionCoordinator.setSiteDecision(
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

    func testBrowserManagerSourceDoesNotReachForStartupPersistenceSingleton() throws {
        let source = try source(named: "Sumi/Managers/BrowserManager/BrowserManager.swift")

        XCTAssertFalse(source.contains("SumiStartupPersistence.shared"))
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

    private func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}

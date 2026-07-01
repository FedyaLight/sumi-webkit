import XCTest

@testable import Sumi

private let permissionCleanupServiceFixedDate = Date(timeIntervalSince1970: 1_800_000_300)

@MainActor
final class SumiPermissionCleanupServiceTests: XCTestCase {
    func testStoreFailureReturnsFailedInsteadOfCompleted() async {
        let profile = Profile(
            id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee") ?? preconditionFailure("Invalid UUID literal"),
            name: "Profile",
            icon: "person"
        )
        let service = SumiPermissionCleanupService(
            store: FailingCleanupPermissionStore(),
            recentActivityStore: SumiPermissionRecentActivityStore(),
            userDefaults: UserDefaults(suiteName: "SumiPermissionCleanupServiceTests") ?? preconditionFailure("Unable to create test user defaults"),
            now: { permissionCleanupServiceFixedDate }
        )

        let result = await service.run(
            profile: SumiPermissionSettingsProfileContext(profile: profile),
            settings: SumiPermissionCleanupSettings(isAutomaticCleanupEnabled: true),
            force: true
        )

        guard case .failed(let errorDescription) = result else {
            return XCTFail("Expected cleanup failure, got \(result)")
        }
        XCTAssertTrue(errorDescription.contains("listFailed"))
    }
}

private enum FailingCleanupPermissionStoreError: Error {
    case listFailed
}

private actor FailingCleanupPermissionStore: SumiPermissionStore {
    func getDecision(for _: SumiPermissionKey) async -> SumiPermissionStoreRecord? {
        nil
    }

    func setDecision(for _: SumiPermissionKey, decision _: SumiPermissionDecision) async { /* No-op. */ }

    func resetDecision(for _: SumiPermissionKey) async { /* No-op. */ }

    func listDecisions(profilePartitionId _: String) async throws -> [SumiPermissionStoreRecord] {
        throw FailingCleanupPermissionStoreError.listFailed
    }

    func recordLastUsed(for _: SumiPermissionKey, at _: Date) async { /* No-op. */ }
}

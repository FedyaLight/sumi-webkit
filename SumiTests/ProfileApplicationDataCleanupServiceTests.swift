import XCTest

@testable import Sumi

@MainActor
final class ProfileApplicationDataCleanupServiceTests: XCTestCase {
    func testFailureRetriesEveryIdempotentDomainBeforeCheckpointCanAdvance() async throws {
        let recorder = ProfileApplicationCleanupRecorder()
        let service = ProfileApplicationDataCleanupService(
            operations: recorder.operations
        )
        let profileID = UUID()

        do {
            try await service.cleanup(profileID: profileID)
            XCTFail("Expected the injected failure")
        } catch ProfileApplicationCleanupTestError.injectedFailure {
        }
        XCTAssertEqual(
            recorder.calls,
            [.history, .basicAuth, .sitePolicies, .zoom, .boosts]
        )

        try await service.cleanup(profileID: profileID)
        XCTAssertEqual(
            recorder.calls,
            [
                .history, .basicAuth, .sitePolicies, .zoom, .boosts,
                .history, .basicAuth, .sitePolicies, .zoom, .boosts,
                .adblockZapper, .extensionPrivateData,
            ]
        )
    }

    func testExtensionCleanupRemovesOnlyTargetProfileDocuments() throws {
        let database = try SumiDatabase.inMemory()
        let target = UUID()
        let retained = UUID()
        let targetKey = target.uuidString.lowercased()
        let retainedKey = retained.uuidString.lowercased()
        let siteAccess: [String: [String: String]] = [
            "\(targetKey)|extension": ["value": "target"],
            "\(retainedKey)|extension": ["value": "retained"],
        ]
        let pins: [String: [String]] = [
            ExtensionToolbarPinningOwner.pinnedToolbarProfileKey(for: target): ["target"],
            ExtensionToolbarPinningOwner.pinnedToolbarProfileKey(for: retained): ["retained"],
            ExtensionToolbarPinningOwner.pinnedToolbarProfileKey(for: nil): ["global"],
        ]
        try database.transaction {
            try $0.documents.save(siteAccess, forKey: "extensions.site-access")
            try $0.documents.save(pins, forKey: "extensions.toolbar-pins")
        }
        let cleaner = ExtensionProfilePrivateDataCleaner(
            database: database,
            deleteControllerStorage: { _ in },
            deleteProtonPassState: { _ in }
        )

        try cleaner.deleteProfileData(profileID: target)

        let result = try database.read {
            (
                siteAccess: try $0.documents.value(
                    [String: [String: String]].self,
                    forKey: "extensions.site-access"
                ),
                pins: try $0.documents.value(
                    [String: [String]].self,
                    forKey: "extensions.toolbar-pins"
                )
            )
        }
        XCTAssertEqual(result.siteAccess?.keys.sorted(), ["\(retainedKey)|extension"])
        XCTAssertNil(
            result.pins?[
                ExtensionToolbarPinningOwner.pinnedToolbarProfileKey(for: target)
            ]
        )
        XCTAssertEqual(
            result.pins?[
                ExtensionToolbarPinningOwner.pinnedToolbarProfileKey(for: retained)
            ],
            ["retained"]
        )
        XCTAssertEqual(
            result.pins?[
                ExtensionToolbarPinningOwner.pinnedToolbarProfileKey(for: nil)
            ],
            ["global"]
        )
    }
}

private enum ProfileApplicationCleanupDomain: Equatable {
    case history
    case basicAuth
    case sitePolicies
    case zoom
    case boosts
    case adblockZapper
    case extensionPrivateData
}

private enum ProfileApplicationCleanupTestError: Error {
    case injectedFailure
}

@MainActor
private final class ProfileApplicationCleanupRecorder {
    private(set) var calls: [ProfileApplicationCleanupDomain] = []
    private var shouldFailBoosts = true

    var operations: ProfileApplicationDataCleanupService.Operations {
        .init(
            clearHistory: { [self] _ in calls.append(.history) },
            clearBasicAuthCredentials: { [self] _ in calls.append(.basicAuth) },
            clearSiteDataPolicies: { [self] _ in calls.append(.sitePolicies) },
            clearZoomPreferences: { [self] _ in calls.append(.zoom) },
            clearBoosts: { [self] _ in
                calls.append(.boosts)
                if shouldFailBoosts {
                    shouldFailBoosts = false
                    throw ProfileApplicationCleanupTestError.injectedFailure
                }
            },
            clearAdblockZapperRules: { [self] _ in
                calls.append(.adblockZapper)
            },
            clearExtensionPrivateData: { [self] _ in
                calls.append(.extensionPrivateData)
            }
        )
    }
}

import SwiftData
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
            XCTFail("Expected the injected Boost cleanup failure")
        } catch ProfileApplicationCleanupTestError.injectedFailure {
            // Expected.
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
        XCTAssertEqual(recorder.cleanedProfileIDs, Set([profileID]))
    }

    func testCleanupDeletesOnlyTargetProfileAcrossEveryApplicationDataStore() async throws {
        let targetProfileID = UUID()
        let retainedProfileID = UUID()
        let historyContainer = try ModelContainer(
            for: Schema([HistoryEntryEntity.self, HistoryVisitEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let historyStore = HistoryStore(container: historyContainer)
        try await historyStore.recordVisit(
            url: URL(string: "https://target.example")!,
            title: "Target",
            visitedAt: Date(),
            profileId: targetProfileID
        )
        try await historyStore.recordVisit(
            url: URL(string: "https://retained.example")!,
            title: "Retained",
            visitedAt: Date(),
            profileId: retainedProfileID
        )

        let credentialStore = BasicAuthCredentialStore(
            service: "com.sumi.profile-cleanup-tests.\(UUID().uuidString)"
        )
        let targetCredentialKey = try XCTUnwrap(
            makeCredentialKey(profileID: targetProfileID)
        )
        let retainedCredentialKey = try XCTUnwrap(
            makeCredentialKey(profileID: retainedProfileID)
        )
        XCTAssertTrue(
            credentialStore.saveCredential(
                .init(username: "target", password: "secret"),
                for: targetCredentialKey
            )
        )
        XCTAssertTrue(
            credentialStore.saveCredential(
                .init(username: "retained", password: "secret"),
                for: retainedCredentialKey
            )
        )
        defer {
            _ = credentialStore.deleteCredential(for: targetCredentialKey)
            _ = credentialStore.deleteCredential(for: retainedCredentialKey)
        }

        let defaultsSuite = "ProfileApplicationDataCleanupTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let policyStore = SumiSiteDataPolicyStore(userDefaults: defaults)
        policyStore.setBlockStorage(
            true,
            forHost: "target.example",
            profileId: targetProfileID
        )
        policyStore.setBlockStorage(
            true,
            forHost: "retained.example",
            profileId: retainedProfileID
        )
        let zoomManager = ZoomManager(userDefaults: defaults)
        zoomManager.saveZoomLevel(
            1.5,
            for: "target.example",
            profileId: targetProfileID
        )
        zoomManager.saveZoomLevel(
            1.25,
            for: "retained.example",
            profileId: retainedProfileID
        )

        let boostDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ProfileApplicationDataCleanupTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: boostDirectory) }
        let boostStore = SumiBoostStore(rootDirectory: boostDirectory)
        let targetBoostURL = URL(string: "https://target.example")!
        let retainedBoostURL = URL(string: "https://retained.example")!
        _ = try boostStore.createDraft(
            for: targetBoostURL,
            profileId: targetProfileID,
            isEphemeral: false
        )

        let zapperStore = SumiAdblockZapperStore(userDefaults: defaults)
        zapperStore.setRules(
            [".target-ad"],
            forHost: "target.example",
            profilePartitionId: targetProfileID.uuidString,
            isEphemeralProfile: false
        )
        zapperStore.setRules(
            [".retained-ad"],
            forHost: "retained.example",
            profilePartitionId: retainedProfileID.uuidString,
            isEphemeralProfile: false
        )
        let siteAccessKey =
            "\(SumiAppIdentity.bundleIdentifier).extensions.siteAccess.v1"
        let permissionDecisionKey =
            "\(SumiAppIdentity.bundleIdentifier).extensions.permissionDecisions.v1"
        defaults.set(
            try JSONSerialization.data(withJSONObject: [
                "\(targetProfileID.uuidString.lowercased())|target-extension": ["value": 1],
                "\(retainedProfileID.uuidString.lowercased())|retained-extension": ["value": 2],
            ]),
            forKey: siteAccessKey
        )
        defaults.set(
            try JSONSerialization.data(withJSONObject: [
                "target-decision": ["profileId": targetProfileID.uuidString.lowercased()],
                "retained-decision": ["profileId": retainedProfileID.uuidString.lowercased()],
            ]),
            forKey: permissionDecisionKey
        )
        let targetProfileKey = targetProfileID.uuidString.lowercased()
        let retainedProfileKey = retainedProfileID.uuidString.lowercased()
        defaults.set(
            try JSONEncoder().encode([
                targetProfileKey: ["target-extension"],
                retainedProfileKey: ["retained-extension"],
            ]),
            forKey: ExtensionToolbarPinningOwner
                .pinnedToolbarExtensionIDsStorageKey
        )
        defaults.set(
            try JSONEncoder().encode([
                targetProfileKey: ["target-extension"],
                retainedProfileKey: ["retained-extension"],
            ]),
            forKey: ExtensionHubOrderingOwner.unpinnedOrderStorageKey
        )
        _ = try boostStore.createDraft(
            for: retainedBoostURL,
            profileId: retainedProfileID,
            isEphemeral: false
        )

        let service = ProfileApplicationDataCleanupService(
            operations: .init(
                clearHistory: { profileID in
                    _ = try await historyStore.clearAllExplicit(
                        profileId: profileID
                    )
                },
                clearBasicAuthCredentials: { profileID in
                    guard credentialStore.deleteCredentials(
                        profilePartitionId: profileID,
                        isEphemeralProfile: false
                    ) else {
                        throw ProfileApplicationCleanupTestError
                            .credentialDeletionFailed
                    }
                },
                clearSiteDataPolicies: { profileID in
                    try policyStore.deletePolicies(profileId: profileID)
                },
                clearZoomPreferences: { profileID in
                    try zoomManager.deletePreferences(profileID: profileID)
                },
                clearBoosts: { profileID in
                    try boostStore.deleteProfileData(profileID: profileID)
                },
                clearAdblockZapperRules: { profileID in
                    try zapperStore.deleteProfileData(profileID: profileID)
                },
                clearExtensionPrivateData: { profileID in
                    try ExtensionProfilePrivateDataCleaner(
                        preferences: defaults,
                        deleteControllerStorage: { _ in },
                        deleteProtonPassState: { _ in }
                    ).deleteProfileData(profileID: profileID)
                }
            )
        )

        try await service.cleanup(profileID: targetProfileID)
        try await service.cleanup(profileID: targetProfileID)

        XCTAssertThrowsError(
            try boostStore.createDraft(
                for: targetBoostURL,
                profileId: targetProfileID,
                isEphemeral: false
            )
        ) { error in
            XCTAssertEqual(error as? SumiBoostStoreError, .profileRetired)
        }
        zapperStore.appendRule(
            ".late-target-ad",
            forHost: "target.example",
            profilePartitionId: targetProfileID.uuidString,
            isEphemeralProfile: false
        )

        let targetHasVisits = try await historyStore.hasVisits(
            profileId: targetProfileID
        )
        let retainedHasVisits = try await historyStore.hasVisits(
            profileId: retainedProfileID
        )
        XCTAssertFalse(targetHasVisits)
        XCTAssertTrue(retainedHasVisits)
        XCTAssertNil(credentialStore.credential(for: targetCredentialKey))
        XCTAssertEqual(
            credentialStore.credential(for: retainedCredentialKey)?.username,
            "retained"
        )
        XCTAssertTrue(policyStore.hostsWithPolicies(profileId: targetProfileID).isEmpty)
        XCTAssertEqual(
            policyStore.hostsWithPolicies(profileId: retainedProfileID),
            ["retained.example"]
        )
        XCTAssertEqual(
            zoomManager.getZoomLevel(
                for: "target.example",
                profileId: targetProfileID
            ),
            1.0
        )
        XCTAssertEqual(
            zoomManager.getZoomLevel(
                for: "retained.example",
                profileId: retainedProfileID
            ),
            1.25
        )
        XCTAssertTrue(
            boostStore.boosts(
                for: targetBoostURL,
                profileId: targetProfileID
            ).isEmpty
        )
        XCTAssertEqual(
            boostStore.boosts(
                for: retainedBoostURL,
                profileId: retainedProfileID
            ).count,
            1
        )
        XCTAssertEqual(
            zapperStore.state(
                forHost: "target.example",
                profilePartitionId: targetProfileID.uuidString,
                isEphemeralProfile: false
            ),
            .empty
        )
        XCTAssertEqual(
            zapperStore.state(
                forHost: "retained.example",
                profilePartitionId: retainedProfileID.uuidString,
                isEphemeralProfile: false
            ).rules,
            [".retained-ad"]
        )
        let retainedSiteAccess = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try XCTUnwrap(defaults.data(forKey: siteAccessKey))
            ) as? [String: Any]
        )
        XCTAssertEqual(
            Set(retainedSiteAccess.keys),
            ["\(retainedProfileID.uuidString.lowercased())|retained-extension"]
        )
        let retainedPermissionDecisions = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try XCTUnwrap(defaults.data(forKey: permissionDecisionKey))
            ) as? [String: Any]
        )
        XCTAssertEqual(Set(retainedPermissionDecisions.keys), ["retained-decision"])
        let retainedToolbarPins = try JSONDecoder().decode(
            [String: [String]].self,
            from: try XCTUnwrap(
                defaults.data(
                    forKey: ExtensionToolbarPinningOwner
                        .pinnedToolbarExtensionIDsStorageKey
                )
            )
        )
        XCTAssertEqual(retainedToolbarPins, [retainedProfileKey: ["retained-extension"]])
        let retainedHubOrder = try JSONDecoder().decode(
            [String: [String]].self,
            from: try XCTUnwrap(
                defaults.data(
                    forKey: ExtensionHubOrderingOwner.unpinnedOrderStorageKey
                )
            )
        )
        XCTAssertEqual(retainedHubOrder, [retainedProfileKey: ["retained-extension"]])
    }

    func testReconstructedBoostAndZapperStoresShareRetirementAdmission()
        throws {
        let container = try makeInMemoryStartupModelContainer()
        let target = Profile(name: "Target")
        let fallback = Profile(name: "Fallback")
        container.mainContext.insert(ProfileEntity(
            id: target.id,
            name: target.name,
            icon: target.icon,
            index: 0
        ))
        container.mainContext.insert(ProfileEntity(
            id: fallback.id,
            name: fallback.name,
            icon: fallback.icon,
            index: 1
        ))
        try container.mainContext.save()
        let admission = try ProfileReferenceAdmissionLedger(
            context: container.mainContext
        )

        let boostDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ReconstructedProfileStores-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: boostDirectory) }
        let defaultsSuite = "ReconstructedProfileStores-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let targetURL = URL(string: "https://target.example")!
        let retainedURL = URL(string: "https://retained.example")!
        let boostStore = SumiBoostStore(
            rootDirectory: boostDirectory,
            profileReferenceAdmission: admission
        )
        _ = try boostStore.createDraft(
            for: targetURL,
            profileId: target.id,
            isEphemeral: false
        )
        _ = try boostStore.createDraft(
            for: retainedURL,
            profileId: fallback.id,
            isEphemeral: false
        )
        let zapperStore = SumiAdblockZapperStore(
            userDefaults: defaults,
            profileReferenceAdmission: admission
        )
        zapperStore.setRules(
            [".target"],
            forHost: "target.example",
            profilePartitionId: target.id.uuidString,
            isEphemeralProfile: false
        )
        zapperStore.setRules(
            [".retained"],
            forHost: "retained.example",
            profilePartitionId: fallback.id.uuidString,
            isEphemeralProfile: false
        )

        _ = try admission.reserve(profile: target, fallbackID: fallback.id)
        try boostStore.deleteProfileData(profileID: target.id)
        try zapperStore.deleteProfileData(profileID: target.id)

        let reconstructedBoostStore = SumiBoostStore(
            rootDirectory: boostDirectory,
            profileReferenceAdmission: admission
        )
        XCTAssertThrowsError(
            try reconstructedBoostStore.createDraft(
                for: targetURL,
                profileId: target.id,
                isEphemeral: false
            )
        ) { error in
            XCTAssertEqual(error as? SumiBoostStoreError, .profileRetired)
        }
        XCTAssertEqual(
            reconstructedBoostStore.boosts(
                for: retainedURL,
                profileId: fallback.id
            ).count,
            1
        )

        let reconstructedZapperStore = SumiAdblockZapperStore(
            userDefaults: defaults,
            profileReferenceAdmission: admission
        )
        reconstructedZapperStore.appendRule(
            ".late-target",
            forHost: "target.example",
            profilePartitionId: target.id.uuidString,
            isEphemeralProfile: false
        )
        XCTAssertEqual(
            reconstructedZapperStore.state(
                forHost: "target.example",
                profilePartitionId: target.id.uuidString,
                isEphemeralProfile: false
            ),
            .empty
        )
        XCTAssertEqual(
            reconstructedZapperStore.state(
                forHost: "retained.example",
                profilePartitionId: fallback.id.uuidString,
                isEphemeralProfile: false
            ).rules,
            [".retained"]
        )
        withExtendedLifetime(container) {}
    }

    func testCorruptProfileStoresFailClosedWithoutOverwritingPayloads() throws {
        let profileID = UUID()
        let defaultsSuite = "ProfileApplicationDataCorruptionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let corruptData = Data("not-json".utf8)

        let zapperKey =
            "settings.adblock.zapper.statesByPersistentProfileAndHost.v1"
        defaults.set(corruptData, forKey: zapperKey)
        let zapperStore = SumiAdblockZapperStore(userDefaults: defaults)
        XCTAssertThrowsError(
            try zapperStore.deleteProfileData(profileID: profileID)
        ) { error in
            XCTAssertEqual(
                error as? SumiAdblockZapperStoreError,
                .unreadablePersistentState
            )
        }
        XCTAssertEqual(defaults.data(forKey: zapperKey), corruptData)

        let extensionKey =
            "\(SumiAppIdentity.bundleIdentifier).extensions.siteAccess.v1"
        defaults.set(corruptData, forKey: extensionKey)
        XCTAssertThrowsError(
            try ExtensionProfilePrivateDataCleaner(preferences: defaults)
                .deleteProfileData(profileID: profileID)
        )
        XCTAssertEqual(defaults.data(forKey: extensionKey), corruptData)

        let policyKey = "profile-cleanup-corrupt-policy"
        defaults.set(corruptData, forKey: policyKey)
        let policyStore = SumiSiteDataPolicyStore(
            userDefaults: defaults,
            storageKey: policyKey
        )
        XCTAssertThrowsError(try policyStore.deletePolicies(profileId: profileID)) {
            error in
            XCTAssertEqual(
                error as? SumiSiteDataPolicyStoreError,
                .unreadablePayload
            )
        }
        XCTAssertEqual(defaults.data(forKey: policyKey), corruptData)

        let boostDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ProfileApplicationDataCorruptionTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: boostDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: boostDirectory) }
        let boostURL = boostDirectory.appendingPathComponent("boosts.json")
        try corruptData.write(to: boostURL)
        let boostStore = SumiBoostStore(rootDirectory: boostDirectory)
        XCTAssertThrowsError(
            try boostStore.deleteProfileData(profileID: profileID)
        ) { error in
            XCTAssertEqual(
                error as? SumiBoostStoreError,
                .profileCleanupStoreUnreadable
            )
        }
        XCTAssertEqual(try Data(contentsOf: boostURL), corruptData)
    }

    func testExtensionProfileMapCleanupFailsClosedForCorruptPayloads() throws {
        let profileID = UUID()
        let suiteName = "ProfileApplicationDataExtensionMapCorruption-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let corruptData = Data("not-json".utf8)
        let storageKeys = [
            ExtensionToolbarPinningOwner.pinnedToolbarExtensionIDsStorageKey,
            ExtensionHubOrderingOwner.unpinnedOrderStorageKey,
        ]

        for storageKey in storageKeys {
            defaults.removeObject(
                forKey: ExtensionToolbarPinningOwner
                    .pinnedToolbarExtensionIDsStorageKey
            )
            defaults.removeObject(
                forKey: ExtensionHubOrderingOwner.unpinnedOrderStorageKey
            )
            defaults.set(corruptData, forKey: storageKey)

            XCTAssertThrowsError(
                try ExtensionProfilePrivateDataCleaner(
                    preferences: defaults,
                    deleteControllerStorage: { _ in
                        XCTFail("Storage cleanup must not run after corrupt preferences")
                    },
                    deleteProtonPassState: { _ in
                        XCTFail("Keychain cleanup must not run after corrupt preferences")
                    }
                ).deleteProfileData(profileID: profileID)
            ) { error in
                XCTAssertEqual(
                    error as? ExtensionProfilePrivateDataCleanupError,
                    .unreadablePayload(storageKey)
                )
            }
            XCTAssertEqual(defaults.data(forKey: storageKey), corruptData)
        }
    }

    func testExtensionControllerStorageCleanupDeletesOnlyDerivedProfileRoot() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ExtensionControllerStorageRetirement-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let targetProfileID = UUID()
        let retainedProfileID = UUID()
        let planner = WebExtensionStorageCleanupPlanner()
        let targetStore = WebExtensionStorageCleanupStore(
            controllerStorageId: ExtensionControllerProvisioningOwner
                .persistentControllerIdentifier(for: targetProfileID),
            libraryDirectoryProvider: { rootDirectory },
            planner: planner
        )
        let retainedStore = WebExtensionStorageCleanupStore(
            controllerStorageId: ExtensionControllerProvisioningOwner
                .persistentControllerIdentifier(for: retainedProfileID),
            libraryDirectoryProvider: { rootDirectory },
            planner: planner
        )
        let targetDirectory = try XCTUnwrap(
            targetStore.directory(for: "target-extension")
        )
        let retainedDirectory = try XCTUnwrap(
            retainedStore.directory(for: "retained-extension")
        )
        try FileManager.default.createDirectory(
            at: targetDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: retainedDirectory,
            withIntermediateDirectories: true
        )

        try targetStore.deleteControllerStorageDirectory()
        try targetStore.deleteControllerStorageDirectory()

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: targetDirectory.deletingLastPathComponent().path
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: retainedDirectory.path))
    }

    func testExtensionPrivateCleanerRoutesPhysicalStoresForExactProfile() throws {
        let suiteName = "ExtensionPrivatePhysicalCleanup-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profileID = UUID()
        var controllerStorageProfiles: [UUID] = []
        var protonPassProfiles: [UUID] = []
        let cleaner = ExtensionProfilePrivateDataCleaner(
            preferences: defaults,
            deleteControllerStorage: {
                controllerStorageProfiles.append($0)
            },
            deleteProtonPassState: {
                protonPassProfiles.append($0)
            }
        )

        try cleaner.deleteProfileData(profileID: profileID)

        XCTAssertEqual(controllerStorageProfiles, [profileID])
        XCTAssertEqual(protonPassProfiles, [profileID])
    }

    func testProtonPassRetirementDeletesEveryExactProfileAccountAndVerifies() throws {
        final class State {
            var accounts: Set<String>
            init(accounts: Set<String>) { self.accounts = accounts }
        }

        let profileID = UUID()
        let foreignProfileID = UUID()
        let prefix = "\(profileID.uuidString.lowercased()):"
        let state = State(accounts: [
            "\(prefix)extension-a",
            "\(prefix)extension-b",
            "\(foreignProfileID.uuidString.lowercased()):extension-a",
            "x\(prefix)lookalike",
        ])
        let store = KeychainProtonPassSafariCompanionStore(
            service: "test-service",
            profileRetirementOperations: .init(
                accountsForService: { service in
                    XCTAssertEqual(service, "test-service")
                    return state.accounts.sorted()
                },
                deleteAccount: { service, account in
                    XCTAssertEqual(service, "test-service")
                    state.accounts.remove(account)
                }
            )
        )

        try store.deleteProfileData(profileID: profileID)
        try store.deleteProfileData(profileID: profileID)

        XCTAssertEqual(state.accounts, [
            "\(foreignProfileID.uuidString.lowercased()):extension-a",
            "x\(prefix)lookalike",
        ])
    }

    func testProtonPassRetirementFailsWhenDeletionCannotBeVerified() throws {
        let profileID = UUID()
        let targetAccount = "\(profileID.uuidString.lowercased()):extension-a"
        let store = KeychainProtonPassSafariCompanionStore(
            service: "test-service",
            profileRetirementOperations: .init(
                accountsForService: { _ in [targetAccount] },
                deleteAccount: { _, _ in }
            )
        )

        XCTAssertThrowsError(
            try store.deleteProfileData(profileID: profileID)
        ) { error in
            XCTAssertEqual(
                error as? ProtonPassSafariProfileRetirementError,
                .deletionVerificationFailed
            )
        }
    }

    private func makeCredentialKey(profileID: UUID) -> BasicAuthCredentialKey? {
        BasicAuthCredentialKey(
            protectionSpace: URLProtectionSpace(
                host: "auth.example",
                port: 443,
                protocol: "https",
                realm: "profile-cleanup",
                authenticationMethod: NSURLAuthenticationMethodHTTPBasic
            ),
            profileId: profileID,
            isEphemeralProfile: false,
            websiteDataStoreIdentifier: UUID()
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
    case credentialDeletionFailed
}

@MainActor
private final class ProfileApplicationCleanupRecorder {
    private(set) var calls: [ProfileApplicationCleanupDomain] = []
    private(set) var cleanedProfileIDs: Set<UUID> = []
    private var shouldFailBoosts = true

    var operations: ProfileApplicationDataCleanupService.Operations {
        .init(
            clearHistory: { [self] profileID in
                calls.append(.history)
                cleanedProfileIDs.insert(profileID)
            },
            clearBasicAuthCredentials: { [self] profileID in
                calls.append(.basicAuth)
                cleanedProfileIDs.insert(profileID)
            },
            clearSiteDataPolicies: { [self] profileID in
                calls.append(.sitePolicies)
                cleanedProfileIDs.insert(profileID)
            },
            clearZoomPreferences: { [self] profileID in
                calls.append(.zoom)
                cleanedProfileIDs.insert(profileID)
            },
            clearBoosts: { [self] profileID in
                calls.append(.boosts)
                if shouldFailBoosts {
                    shouldFailBoosts = false
                    throw ProfileApplicationCleanupTestError.injectedFailure
                }
                cleanedProfileIDs.insert(profileID)
            },
            clearAdblockZapperRules: { [self] profileID in
                calls.append(.adblockZapper)
                cleanedProfileIDs.insert(profileID)
            },
            clearExtensionPrivateData: { [self] profileID in
                calls.append(.extensionPrivateData)
                cleanedProfileIDs.insert(profileID)
            }
        )
    }
}

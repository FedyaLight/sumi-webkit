import Foundation
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SumiProfileWebExtensionRuntimeTests: XCTestCase {
    func testZeroDemandCreatesNoProfileRuntimeControllerOrInternalOwner() {
        let profile = Profile(name: "Zero demand")
        var initialProfileRequests = 0
        let runtime = SumiProfileWebExtensionRuntime(
            browserConfiguration: BrowserConfiguration(),
            profileReferenceAdmission: .testingAllowingReferences(),
            initialProfileProvider: {
                initialProfileRequests += 1
                return profile
            }
        )
        let configuration = WKWebViewConfiguration()

        runtime.prepareNormalTabConfiguration(
            configuration,
            profileID: profile.id
        )

        XCTAssertFalse(runtime.hasResidence)
        XCTAssertNil(configuration.webExtensionController)
        XCTAssertEqual(initialProfileRequests, 0)
    }

    func testAdblockUsesControllerWithoutMaterializingExtensionManager() async throws {
        let database = try SumiDatabase.inMemory()
        let profile = Profile(name: "Adblock only")
        let browserConfiguration = BrowserConfiguration()
        var managerCreations = 0
        let module = SumiExtensionsModule(
            moduleRegistry: .unavailable(),
            database: database,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            profileReferenceAdmission: .testingAllowingReferences(),
            managerFactory: { context, initialProfile, configuration, registry in
                managerCreations += 1
                return ExtensionManager(
                    database: context,
                    initialProfile: initialProfile,
                    browserConfiguration: configuration,
                    moduleRegistry: registry
                )
            }
        )
        let fixture = try URLCleaningFixture()
        defer { fixture.remove() }
        module.reconcileInternalURLCleaning(
            SumiURLCleaningContribution(
                generationID: "generation",
                rulesURL: fixture.rulesURL,
                disabledDomains: []
            ),
            profileID: profile.id
        )
        XCTAssertFalse(module.profileWebExtensionRuntime.hasResidence)

        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://example.com")
        )
        module.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "test.adblock-only"
        )
        let readiness = await module.ensureInitialExtensionContextsIfNeeded(
            profileId: profile.id
        )

        XCTAssertEqual(readiness, .ready)
        XCTAssertNotNil(configuration.webExtensionController)
        XCTAssertTrue(module.profileWebExtensionRuntime.hasResidence)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertEqual(managerCreations, 0)

        module.reconcileInternalURLCleaning(nil, profileID: profile.id)
        XCTAssertFalse(module.profileWebExtensionRuntime.hasResidence)
        XCTAssertEqual(managerCreations, 0)
    }

    func testUserDemandReusesAdblockControllerIdentity() async throws {
        let profile = Profile(name: "Shared controller")
        let browserConfiguration = BrowserConfiguration()
        let runtime = SumiProfileWebExtensionRuntime(
            browserConfiguration: browserConfiguration,
            profileReferenceAdmission: .testingAllowingReferences(),
            initialProfileProvider: { profile }
        )
        let fixture = try URLCleaningFixture()
        defer { fixture.remove() }
        runtime.setInternalContribution(
            SumiURLCleaningContribution(
                generationID: "generation",
                rulesURL: fixture.rulesURL,
                disabledDomains: []
            ),
            profileID: profile.id
        )
        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: nil
        )
        runtime.prepareNormalTabConfiguration(
            configuration,
            profileID: profile.id
        )
        let readiness = await runtime.waitForInternalContribution(
            profileID: profile.id
        )
        XCTAssertEqual(readiness, .ready)
        let internalController = try XCTUnwrap(
            configuration.webExtensionController
        )

        let profileRuntime = runtime.profileRuntimeForUserDemand(
            initialProfile: profile
        )
        let userController = try XCTUnwrap(
            runtime.controllerIfAdmitted(
                for: profile.id,
                mutationLease: nil
            )
        )

        XCTAssertIdentical(userController, internalController)
        XCTAssertIdentical(
            profileRuntime.controller(for: profile.id),
            internalController
        )

        runtime.releaseUserRuntime()
        XCTAssertIdentical(
            runtime.profileRuntimeForTests?.controller(for: profile.id),
            internalController
        )

    }

    func testExtensionManagerAdapterUsesAndPreservesInternalController() async throws {
        let database = try SumiDatabase.inMemory()
        let profile = Profile(name: "Shared manager")
        let browserConfiguration = BrowserConfiguration()
        let runtime = SumiProfileWebExtensionRuntime(
            browserConfiguration: browserConfiguration,
            profileReferenceAdmission: .testingAllowingReferences(),
            initialProfileProvider: { profile }
        )
        let fixture = try URLCleaningFixture()
        defer { fixture.remove() }
        runtime.setInternalContribution(
            SumiURLCleaningContribution(
                generationID: "generation",
                rulesURL: fixture.rulesURL,
                disabledDomains: []
            ),
            profileID: profile.id
        )
        let internalConfiguration = browserConfiguration
            .normalTabWebViewConfiguration(for: profile, url: nil)
        runtime.prepareNormalTabConfiguration(
            internalConfiguration,
            profileID: profile.id
        )
        let readiness = await runtime.waitForInternalContribution(
            profileID: profile.id
        )
        XCTAssertEqual(readiness, .ready)
        let internalController = try XCTUnwrap(
            internalConfiguration.webExtensionController
        )

        let manager = ExtensionManager(
            database: database,
            initialProfile: profile,
            profileReferenceAdmission: .testingAllowingReferences(),
            browserConfiguration: browserConfiguration,
            profileWebExtensionRuntime: runtime
        )
        let userConfiguration = browserConfiguration
            .normalTabWebViewConfiguration(for: profile, url: nil)
        manager.moduleResidence.browserRuntime.preparation.prepareConfiguration(
            userConfiguration,
            profileID: profile.id,
            reason: "test.shared-controller"
        )

        XCTAssertIdentical(
            userConfiguration.webExtensionController,
            internalController
        )
        XCTAssertNotNil(internalController.delegate)

        let result = manager.moduleResidence.shutDown(
            reason: "test.shared-controller"
        )
        XCTAssertTrue(result.completed)
        XCTAssertNil(internalController.delegate)
        XCTAssertIdentical(
            runtime.profileRuntimeForTests?.controller(for: profile.id),
            internalController
        )

        let reboundConfiguration = browserConfiguration
            .normalTabWebViewConfiguration(for: profile, url: nil)
        manager.moduleResidence.browserRuntime.preparation.prepareConfiguration(
            reboundConfiguration,
            profileID: profile.id,
            reason: "test.shared-controller-rebind"
        )
        XCTAssertIdentical(
            reboundConfiguration.webExtensionController,
            internalController
        )
        XCTAssertNotNil(internalController.delegate)
    }

    func testPrivateProfileUsesItsExactNonPersistentDataStore() async throws {
        let profile = Profile.createEphemeral()
        let browserConfiguration = BrowserConfiguration()
        let runtime = SumiProfileWebExtensionRuntime(
            browserConfiguration: browserConfiguration,
            profileReferenceAdmission: .testingAllowingReferences(),
            initialProfileProvider: { profile }
        )
        let fixture = try URLCleaningFixture()
        defer { fixture.remove() }
        runtime.setInternalContribution(
            SumiURLCleaningContribution(
                generationID: "generation",
                rulesURL: fixture.rulesURL,
                disabledDomains: []
            ),
            profileID: profile.id
        )
        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: nil
        )

        runtime.prepareNormalTabConfiguration(
            configuration,
            profileID: profile.id
        )
        let readiness = await runtime.waitForInternalContribution(
            profileID: profile.id
        )

        XCTAssertEqual(readiness, .ready)
        let controller = try XCTUnwrap(configuration.webExtensionController)
        XCTAssertIdentical(
            controller.configuration.defaultWebsiteDataStore,
            profile.dataStore
        )
        XCTAssertFalse(
            controller.configuration.defaultWebsiteDataStore.isPersistent
        )
    }

    func testInternalOnlyProfileRetirementReleasesItsController() async throws {
        let database = try SumiDatabase.inMemory()
        let profile = Profile(name: "Retiring")
        let fallback = Profile(name: "Fallback")
        try database.transaction {
            try $0.profiles.save(
                ProfileRecord(id: profile.id, name: profile.name, index: 0)
            )
            try $0.profiles.save(
                ProfileRecord(id: fallback.id, name: fallback.name, index: 1)
            )
        }
        let admission = try ProfileReferenceAdmissionLedger(database: database)
        let browserConfiguration = BrowserConfiguration()
        let runtime = SumiProfileWebExtensionRuntime(
            browserConfiguration: browserConfiguration,
            profileReferenceAdmission: admission,
            initialProfileProvider: { profile }
        )
        let fixture = try URLCleaningFixture()
        defer { fixture.remove() }
        runtime.setInternalContribution(
            SumiURLCleaningContribution(
                generationID: "generation",
                rulesURL: fixture.rulesURL,
                disabledDomains: []
            ),
            profileID: profile.id
        )
        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: nil
        )
        runtime.prepareNormalTabConfiguration(
            configuration,
            profileID: profile.id
        )
        let readiness = await runtime.waitForInternalContribution(
            profileID: profile.id
        )
        XCTAssertEqual(readiness, .ready)
        XCTAssertTrue(runtime.containsProfileReference(to: profile.id))
        let token = try admission.reserve(
            profile: profile,
            fallbackID: fallback.id
        )
        XCTAssertTrue(try admission.beginReferenceMigration(token))

        let suspended = runtime.suspendInternalContribution(
            profileID: profile.id
        )
        let retired = runtime.finishProfileRetirement(
            profileID: profile.id,
            fallbackProfileID: fallback.id
        )

        XCTAssertNotNil(suspended)
        XCTAssertTrue(retired)
        XCTAssertFalse(runtime.containsProfileReference(to: profile.id))
        XCTAssertFalse(runtime.hasResidence)
        XCTAssertNil(browserConfiguration.webViewConfiguration.webExtensionController)
    }
}

private struct URLCleaningFixture {
    let root: URL
    let rulesURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SumiProfileWebExtensionRuntime-\(UUID().uuidString)",
            isDirectory: true
        )
        rulesURL = root.appendingPathComponent("rules.json")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let rules: [[String: Any]] = [[
            "id": 1_500_000,
            "priority": 1,
            "action": ["type": "block"],
            "condition": [
                "urlFilter": "||ads.example^",
                "resourceTypes": ["script"],
            ],
        ]]
        try JSONSerialization.data(
            withJSONObject: rules,
            options: [.sortedKeys]
        ).write(to: rulesURL, options: .atomic)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

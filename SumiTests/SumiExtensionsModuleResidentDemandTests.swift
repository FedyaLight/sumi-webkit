import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SumiExtensionsModuleResidentDemandTests: XCTestCase {
    func testResidentEnabledCatalogPreparesNormalTabWithoutColdStoreLookup()
        throws
    {
        let fixture = try makeFixture(hasEnabledExtension: true)
        defer {
            _ = fixture.manager.shutDownExtensionRuntime(reason: #function)
        }
        let configuration = WKWebViewConfiguration()

        fixture.module.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: fixture.profile.id,
            reason: #function
        )

        XCTAssertIdentical(
            configuration.webExtensionController,
            fixture.manager.ensureExtensionController(for: fixture.profile.id)
        )
    }

    func testResidentCatalogWithoutEnabledExtensionsStaysZeroCost() throws {
        let fixture = try makeFixture(hasEnabledExtension: false)
        let configuration = WKWebViewConfiguration()

        fixture.module.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: fixture.profile.id,
            reason: #function
        )

        XCTAssertIdentical(
            fixture.module.managerIfLoadedAndEnabled(),
            fixture.manager
        )
        XCTAssertNil(configuration.webExtensionController)
        XCTAssertNil(fixture.manager.extensionController)
    }

    func testResidentCatalogWithoutEnabledExtensionsSkipsNormalTabRegistration()
        throws
    {
        let fixture = try makeFixture(hasEnabledExtension: false)
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let generation = fixture.manager.runtimeSession
            .tabOpenNotificationGeneration

        fixture.module.registerTabWithExtensionRuntimeIfLoaded(
            tab,
            reason: #function
        )

        XCTAssertFalse(
            tab.extensionPageRuntimeOwner.isEligible(for: generation)
        )
        XCTAssertNil(fixture.manager.extensionController)
    }

    func testDisabledModuleRetriesShutdownAfterIrreversibleMutationFinishes()
        async throws {
        let fixture = try makeFixture(hasEnabledExtension: true)
        let uninstall = try XCTUnwrap(
            fixture.manager.runtimeMutationRegistry.begin(
                extensionID: "resident-enabled",
                operation: .uninstall
            )
        )
        XCTAssertTrue(
            fixture.manager.runtimeMutationRegistry.enterIrreversiblePhase(
                uninstall
            )
        )

        fixture.module.setEnabled(false)

        XCTAssertTrue(
            fixture.module.hasLoadedRuntime,
            "the transaction retains its runtime until irreversible work ends"
        )
        XCTAssertTrue(
            fixture.manager.runtimeMutationRegistry.finish(uninstall)
        )
        for _ in 0..<4 {
            await Task.yield()
        }

        XCTAssertFalse(fixture.module.hasLoadedRuntime)
    }

    private func makeFixture(hasEnabledExtension: Bool) throws -> (
        container: ModelContainer,
        module: SumiExtensionsModule,
        manager: ExtensionManager,
        profile: Profile
    ) {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: UUID().uuidString)
        )
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        registry.enable(.extensions)
        let profile = Profile(name: "Resident extension runtime")
        let configuration = BrowserConfiguration()
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: configuration,
            moduleRegistry: registry
        )
        manager.installedExtensionCollection.setAll(
            hasEnabledExtension
                ? [makeInstalledExtension(isEnabled: true)]
                : []
        )
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: configuration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        XCTAssertIdentical(module.managerIfEnabled(), manager)
        return (container, module, manager, profile)
    }

    private func makeInstalledExtension(isEnabled: Bool) -> InstalledExtension {
        InstalledExtension(
            id: "resident-enabled",
            name: "Resident enabled",
            version: "1.0",
            manifestVersion: 3,
            description: nil,
            isEnabled: isEnabled,
            installDate: Date(),
            lastUpdateDate: Date(),
            packagePath: "/tmp/resident-enabled",
            iconPath: nil,
            sourceKind: .directory,
            backgroundModel: .none,
            incognitoMode: .spanning,
            sourcePathFingerprint: "resident-enabled",
            manifestRootFingerprint: "resident-enabled",
            sourceBundlePath: "/tmp/resident-enabled",
            optionsPagePath: nil,
            defaultPopupPath: nil,
            hasBackground: false,
            hasAction: false,
            hasOptionsPage: false,
            hasContentScripts: false,
            hasExtensionPages: false,
            activationSummary: ExtensionActivationSummary(
                matchPatternStrings: [],
                broadScope: false,
                hasContentScripts: false,
                hasAction: false,
                hasOptionsPage: false,
                hasExtensionPages: false
            ),
            manifest: [
                "manifest_version": 3,
                "name": "Resident enabled",
                "version": "1.0",
            ]
        )
    }
}

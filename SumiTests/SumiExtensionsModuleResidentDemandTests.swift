import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SumiExtensionsModuleResidentDemandTests: XCTestCase {
    func testEnabledModuleStartsOneBrowserSessionAfterRuntimeAttaches()
        throws {
        let container = try SumiDatabase.inMemory()
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: UUID().uuidString)
        )
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        let profile = Profile(name: "Passive extension surface")
        let configuration = BrowserConfiguration()
        var scheduledUpdates: [@MainActor () -> Void] = []
        let surfaceStore = BrowserExtensionSurfaceStore(
            updateScheduler: { operation in
                scheduledUpdates.append(operation)
            }
        )
        var managerFactoryAdmissions = 0
        var browserAttachments: [ExtensionManagerBrowserAttachment] = []
        var createdManager: ExtensionManager?
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
            browserConfiguration: configuration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in
                managerFactoryAdmissions += 1
                let manager = self.makeSafariExtensionTestExtensionManager(
            database: container,
                    initialProfile: profile,
                    browserConfiguration: configuration,
                    moduleRegistry: registry
                )
                createdManager = manager
                return manager
            },
            surfaceStore: surfaceStore
        )
        defer { module.setEnabled(false) }

        XCTAssertFalse(module.isEnabled)
        XCTAssertNil(createdManager)
        XCTAssertEqual(managerFactoryAdmissions, 0)
        XCTAssertTrue(scheduledUpdates.isEmpty)

        module.bindRuntimeProvider { nil }
        module.setEnabled(true)
        module.pinToToolbar("missing-extension", profileId: profile.id)
        XCTAssertFalse(module.hasAttachedRuntime)
        XCTAssertNil(createdManager)
        XCTAssertEqual(managerFactoryAdmissions, 0)
        XCTAssertTrue(browserAttachments.isEmpty)
        XCTAssertTrue(scheduledUpdates.isEmpty)

        module.attach(
            runtime: SumiExtensionsModuleRuntime(
                currentProfile: { profile },
                attachBrowser: { browserAttachments.append($0) },
                liveTabs: { [] }
            )
        )
        XCTAssertTrue(module.hasAttachedRuntime)
        let manager = try XCTUnwrap(createdManager)
        XCTAssertIdentical(createdManager, manager)
        XCTAssertEqual(browserAttachments.count, 1)
        XCTAssertEqual(managerFactoryAdmissions, 1)
        XCTAssertEqual(scheduledUpdates.count, 3)
        XCTAssertNotNil(
            configuration.webViewConfiguration.webExtensionController
        )

        module.pinToToolbar("missing-extension", profileId: profile.id)

        XCTAssertEqual(browserAttachments.count, 1)
        XCTAssertEqual(managerFactoryAdmissions, 1)
        XCTAssertEqual(
            scheduledUpdates.count,
            3,
            "resident manager access must not churn observers or schedule updates"
        )
    }

    func testResidentEnabledCatalogPreparesNormalTabWithoutColdStoreLookup()
        throws {
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
            fixture.inspection.controller.provisioning
                .ensureExtensionController(for: fixture.profile.id)
        )
    }

    func testBrowserSessionWithoutEnabledExtensionsLoadsNoContexts() throws {
        let fixture = try makeFixture(hasEnabledExtension: false)
        let configuration = WKWebViewConfiguration()

        fixture.module.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: fixture.profile.id,
            reason: #function
        )

        XCTAssertNotNil(configuration.webExtensionController)
        XCTAssertNotNil(
            fixture.inspection.contextState.profiles.controller(
                for: fixture.profile.id
            )
        )
        XCTAssertEqual(
            fixture.inspection.contextState.profiles
                .countLoadedExtensionContexts(),
            0
        )
    }

    func testResidentCatalogWithoutEnabledExtensionsSkipsNormalTabRegistration()
        throws {
        let fixture = try makeFixture(hasEnabledExtension: false)
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let generation = fixture.inspection.runtimeAuthorities
            .tabPublicationRevisions.issue()

        fixture.module.registerTabWithExtensionRuntimeIfLoaded(
            tab,
            reason: #function
        )

        XCTAssertFalse(
            tab.extensionPageRuntimeOwner.isEligible(for: generation)
        )
        XCTAssertNotNil(
            fixture.inspection.contextState.profiles.controller(
                for: fixture.profile.id
            )
        )
        XCTAssertEqual(
            fixture.inspection.contextState.profiles
                .countLoadedExtensionContexts(),
            0
        )
    }

    func testAttachPreparesControllerBeforeFirstExtensionIsAdded() throws {
        let container = try SumiDatabase.inMemory()
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: UUID().uuidString)
        )
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        registry.enable(.extensions)
        let profile = Profile(name: "Empty Extension Browser Session")

        let browserConfiguration = BrowserConfiguration()
        let inspectionCapture = ExtensionManagerInspectionCapture()
        let residentManager = makeSafariExtensionTestExtensionManager(
            database: container,
            initialProfile: profile,
            browserConfiguration: browserConfiguration,
            moduleRegistry: registry,
            inspectionCapture: inspectionCapture
        )
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in residentManager }
        )
        defer { module.setEnabled(false) }
        let browserManager = makeSafariExtensionTestBrowserManager(
            moduleRegistry: registry,
            profile: profile,
            browserConfiguration: browserConfiguration
        )

        module.attach(
            runtime: BrowserExtensionsModuleRuntimeFactory.runtime(
                for: browserManager
            )
        )

        XCTAssertTrue(module.hasLoadedRuntime)
        XCTAssertNotNil(
            inspectionCapture.inspection.contextState.profiles.controller(
                for: profile.id
            )
        )
        XCTAssertEqual(
            inspectionCapture.inspection.contextState.profiles
                .countLoadedExtensionContexts(),
            0,
            "Preparing browser lifecycle must not load extension contexts"
        )
    }

    func testTerminalBrowserAttachmentRetirementReleasesWindowRegistry()
        throws {
        let fixture = try makeFixture(hasEnabledExtension: true)
        var browser: BrowserManager? = BrowserManager()
        var windows: WindowRegistry? = browser?.windowRegistry
        fixture.browserAttachment.attach(to: try XCTUnwrap(browser))
        weak var releasedWindows = windows

        fixture.module.retireBrowserAttachmentIfLoaded()
        browser = nil
        windows = nil

        XCTAssertNil(releasedWindows)
        XCTAssertFalse(fixture.module.hasAttachedRuntime)
    }

    func testDisabledModuleRetriesShutdownAfterIrreversibleMutationFinishes()
        async throws {
        let fixture = try makeFixture(hasEnabledExtension: true)
        let uninstall = try XCTUnwrap(
            fixture.inspection.contextCoordination.mutations.begin(
                extensionID: "resident-enabled",
                operation: .uninstall
            )
        )
        XCTAssertTrue(
            fixture.inspection.contextCoordination.mutations
                .enterIrreversiblePhase(
                uninstall
            )
        )

        fixture.module.setEnabled(false)

        XCTAssertTrue(
            fixture.module.hasLoadedRuntime,
            "the transaction retains its runtime until irreversible work ends"
        )
        XCTAssertTrue(
            fixture.inspection.contextCoordination.mutations.finish(uninstall)
        )
        for _ in 0..<4 {
            await Task.yield()
        }

        XCTAssertFalse(fixture.module.hasLoadedRuntime)
    }

    private func makeFixture(hasEnabledExtension: Bool) throws -> (
        container: SumiDatabase,
        module: SumiExtensionsModule,
        manager: ExtensionManager,
        inspection: ExtensionManagerTestInspection,
        profile: Profile,
        browserAttachment: ExtensionManagerBrowserAttachment
    ) {
        let container = try SumiDatabase.inMemory()
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: UUID().uuidString)
        )
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        registry.enable(.extensions)
        let profile = Profile(name: "Resident extension runtime")
        let configuration = BrowserConfiguration()
        let inspectionCapture = ExtensionManagerInspectionCapture()
        let manager = makeSafariExtensionTestExtensionManager(
            database: container,
            initialProfile: profile,
            browserConfiguration: configuration,
            moduleRegistry: registry,
            inspectionCapture: inspectionCapture
        )
        let inspection = inspectionCapture.inspection
        inspection.actionSurfaces.installedExtensions.setAll(
            hasEnabledExtension
                ? [makeInstalledExtension(isEnabled: true)]
                : []
        )
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
            browserConfiguration: configuration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        var browserAttachments: [ExtensionManagerBrowserAttachment] = []
        module.attach(
            runtime: SumiExtensionsModuleRuntime(
                currentProfile: { profile },
                attachBrowser: { browserAttachments.append($0) },
                liveTabs: { [] }
            )
        )
        module.pinToToolbar("missing-extension", profileId: profile.id)
        XCTAssertEqual(browserAttachments.count, 1)
        return (
            container,
            module,
            manager,
            inspection,
            profile,
            try XCTUnwrap(browserAttachments.first)
        )
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

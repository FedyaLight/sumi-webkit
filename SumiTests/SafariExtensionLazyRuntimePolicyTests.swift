import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionLazyRuntimePolicyTests: XCTestCase {
    func testLaunchStartsWithZeroExtensionContexts() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Lazy Launch")
        let fixture = makeSafariExtensionManagerTestFixture(
            context: container,
            initialProfile: profile
        )
        let inspection = fixture.inspection

        XCTAssertEqual(inspection.contextState.profiles.countLoadedExtensionContexts(), 0)
        XCTAssertTrue(inspection.contextState.profiles.contextsByProfile.isEmpty)
        XCTAssertNil(
            inspection.normalTabs.deferredRuntime
                .loadedInitialDocumentRuntimePreparationOwner
        )
        XCTAssertFalse(inspection.nativeMessaging.hasLoadedWakeOwner)
    }

    func testAuxiliaryIntegrationReceiptDoesNotRetainExtensionManager()
        async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Weak Auxiliary Events")
        let attachedRuntime = ExtensionAttachedRuntimeCapture()
        var manager: ExtensionManager? = ExtensionManager(
            database: container,
            initialProfile: profile,
            attachedRuntimeDidInstall: attachedRuntime.install
        )
        let browserManager = makeSafariExtensionTestBrowserManager(
            profile: profile
        )
        manager?.attach(browserManager: browserManager)
        weak var weakManager = manager
        let integration = attachedRuntime.runtime.requestedTabs
            .auxiliaryIntegration
        let receiptHeld = expectation(description: "integration held by task")
        var releaseTask: CheckedContinuation<Void, Never>?
        let callbackTask = Task { @MainActor in
            withExtendedLifetime(integration) {
                receiptHeld.fulfill()
            }
            await withCheckedContinuation { releaseTask = $0 }
            withExtendedLifetime(integration) {}
        }
        await fulfillment(of: [receiptHeld], timeout: 1.0)

        manager = nil

        XCTAssertNil(weakManager)
        releaseTask?.resume()
        await callbackTask.value
    }

    func testDetachedDelegateModuleStateUsesInjectedRegistry() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Scoped Delegate")
        let registry = makeScopedModuleRegistry()
        registry.enable(.extensions)

        let fixture = makeSafariExtensionManagerTestFixture(
            context: container,
            initialProfile: profile,
            moduleRegistry: registry
        )

        XCTAssertEqual(
            fixture.inspection.nativeMessaging.owners.relayOwner()
                .extensionsModuleEnabledForCallbacks,
            true
        )
    }

    func testExtensionsModuleScopedRegistryGatesResidentDefaultManager() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Scoped Module")
        let registry = makeScopedModuleRegistry()
        registry.enable(.extensions)
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
            initialProfileProvider: { profile }
        )
        let browserManager = BrowserManager()
        module.attach(
            runtime: BrowserExtensionsModuleRuntimeFactory.runtime(
                for: browserManager
            )
        )

        let manager = try XCTUnwrap(module.managerForTesting())
        registry.disable(.extensions)

        XCTAssertFalse(module.isEnabled)
        XCTAssertNil(module.managerForTesting())
        registry.enable(.extensions)
        XCTAssertIdentical(module.managerForTesting(), manager)
    }

    func testExtensionsModuleRuntimeSuppliesProfileAndAttachesManager() throws {
        let container = try makeTestContainer()
        let registry = makeScopedModuleRegistry()
        registry.enable(.extensions)
        let fallbackProfile = Profile(name: "Fallback Module Profile")
        let runtimeProfile = Profile(name: "Runtime Module Profile")
        let browserManager = BrowserManager()
        browserManager.profileManager.profiles = [runtimeProfile]
        browserManager.currentProfile = runtimeProfile

        var initialProfileUsedByFactory: Profile?
        var createdManager: ExtensionManager?
        let attachedRuntime = ExtensionAttachedRuntimeCapture()
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
            initialProfileProvider: { fallbackProfile },
            managerFactory: { context, initialProfile, browserConfiguration, moduleRegistry in
                initialProfileUsedByFactory = initialProfile
                let manager = ExtensionManager(
            database: context,
                    initialProfile: initialProfile,
                    browserConfiguration: browserConfiguration,
                    moduleRegistry: moduleRegistry,
                    attachedRuntimeDidInstall: attachedRuntime.install
                )
                createdManager = manager
                return manager
            }
        )

        module.attach(runtime: BrowserExtensionsModuleRuntimeFactory.runtime(for: browserManager))
        _ = try XCTUnwrap(module.managerForTesting())

        XCTAssertIdentical(initialProfileUsedByFactory, runtimeProfile)
        let attachedManager = try XCTUnwrap(createdManager)
        XCTAssertTrue(
            attachedRuntime.runtime.bridge.availability.isAvailable
        )
        XCTAssertIdentical(
            attachedRuntime.runtime.profileQuery.currentProfile(),
            runtimeProfile
        )
        withExtendedLifetime(attachedManager) {}
    }

    func testDisabledInstallDoesNotCreateRuntimeControllerOrContext() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Disabled Install")
        let fixture = makeSafariExtensionManagerTestFixture(
            context: container,
            initialProfile: profile
        )
        let manager = fixture.manager
        let inspection = fixture.inspection

        let scratchDirectory = try makeScratchDirectory()
        _ = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "DisabledInstallExtension"
        )

        XCTAssertEqual(inspection.contextState.profiles.countLoadedExtensionContexts(), 0)
        XCTAssertTrue(inspection.contextState.profiles.contextsByProfile.isEmpty)
        XCTAssertTrue(inspection.contextState.profiles.controllersByProfile.isEmpty)
        XCTAssertNil(
            inspection.normalTabs.deferredRuntime
                .loadedInitialDocumentRuntimePreparationOwner
        )
        XCTAssertFalse(inspection.nativeMessaging.hasLoadedWakeOwner)
    }

    func testEightProfilesWithOneExtensionCreatesAtMostOneContextUntilUsed() async throws {
        let container = try makeTestContainer()
        var profiles: [Profile] = []
        for index in 1...8 {
            profiles.append(Profile(name: "Profile \(index)"))
        }

        let fixture = makeSafariExtensionManagerTestFixture(
            context: container,
            initialProfile: profiles[0]
        )
        let manager = fixture.manager
        let inspection = fixture.inspection

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "LazyPolicyExtension"
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)

        XCTAssertEqual(
            inspection.contextState.profiles.countLoadedExtensionContexts(),
            1,
            "Enable should load only the active profile's context"
        )

        for profile in profiles.dropFirst() {
            inspection.contextCoordination.profileTransition
                .switchProfile(profileID: profile.id)
        }

        XCTAssertEqual(
            inspection.contextState.profiles.countLoadedExtensionContexts(),
            0,
            "Switching across inactive profiles should unload prior contexts"
        )

        let targetProfile = profiles[7]
        _ = try await inspection.contextCoordination.residency
            .ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: targetProfile.id
        )

        XCTAssertEqual(
            inspection.contextState.profiles.countLoadedExtensionContexts(),
            1,
            "Only the requested profile/extension pair should be live"
        )
        XCTAssertNotNil(
            inspection.contextState.profiles.contexts(
                for: targetProfile.id
            )[installed.id]
        )
    }

    func testCachedWebExtensionIsReusedAcrossProfiles() async throws {
        let container = try makeTestContainer()
        let profileA = Profile(name: "Cache A")
        let profileB = Profile(name: "Cache B")
        let fixture = makeSafariExtensionManagerTestFixture(
            context: container,
            initialProfile: profileA
        )
        let manager = fixture.manager
        let inspection = fixture.inspection

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "CacheReuseExtension"
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)

        let contextA = try XCTUnwrap(
            inspection.contextState.profiles.contexts(for: profileA.id)[installed.id]
        )
        inspection.contextCoordination.residency
            .unloadExtensionContextsForInactiveProfiles(
                keepingProfileId: profileB.id
            )

        _ = try await inspection.contextCoordination.residency
            .ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profileB.id
        )
        let contextB = try XCTUnwrap(
            inspection.contextState.profiles.contexts(for: profileB.id)[installed.id]
        )

        XCTAssertNotIdentical(contextA, contextB)
        XCTAssertIdentical(
            contextA.webExtension,
            contextB.webExtension,
            "WKWebExtension resources should be cached and reused per extension id"
        )
    }

    func testDisableUnloadsAllProfileContextsForExtension() async throws {
        let container = try makeTestContainer()
        let profileA = Profile(name: "Disable A")
        let profileB = Profile(name: "Disable B")
        let fixture = makeSafariExtensionManagerTestFixture(
            context: container,
            initialProfile: profileA
        )
        let manager = fixture.manager
        let inspection = fixture.inspection

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "DisableUnloadExtension"
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)
        _ = try await inspection.contextCoordination.residency
            .ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profileB.id
        )
        XCTAssertEqual(
            inspection.contextState.profiles.countLoadedExtensionContexts(),
            2
        )
        let preparedController = try XCTUnwrap(
            inspection.contextState.profiles.controller(for: profileA.id)
        )

        try await inspection.installation.lifecycle.disable(installed.id)

        XCTAssertEqual(
            inspection.contextState.profiles.countLoadedExtensionContexts(),
            0
        )
        XCTAssertNil(
            inspection.contextState.sourceCache.entry(for: installed.id)
        )
        XCTAssertIdentical(
            inspection.contextState.profiles.controller(for: profileA.id),
            preparedController,
            "Disable must keep browser-session identity while the extension remains installed"
        )
    }

    func testUninstallKeepsControllerAndRemovesSumiOwnedState()
        async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Uninstall Browser Session")
        let secondProfile = Profile(name: "Uninstall Secondary Profile")
        try container.transaction {
            try $0.profiles.save(
                ProfileRecord(id: profile.id, name: profile.name, index: 0)
            )
            try $0.profiles.save(
                ProfileRecord(
                    id: secondProfile.id,
                    name: secondProfile.name,
                    index: 1
                )
            )
        }
        let fixture = makeSafariExtensionManagerTestFixture(
            context: container,
            initialProfile: profile
        )
        let scratchDirectory = try makeScratchDirectory()
        let first = try await installUnpackedExtension(
            manager: fixture.manager,
            scratchDirectory: scratchDirectory,
            name: "FirstUninstallExtension"
        )
        _ = try await fixture.inspection.installation.lifecycle.enable(first.id)
        let controller = try XCTUnwrap(
            fixture.inspection.contextState.profiles.controller(for: profile.id)
        )
        fixture.inspection.actionPolicy.store.updatePolicy(
            extensionId: first.id,
            profileId: profile.id
        ) {
            $0.defaultAccess = .deny
            $0.defaultAccessConfiguredByUser = true
        }
        fixture.inspection.actionPolicy.store.updatePolicy(
            extensionId: first.id,
            profileId: secondProfile.id
        ) {
            $0.defaultAccess = .deny
            $0.defaultAccessConfiguredByUser = true
        }
        fixture.inspection.actionPolicy.permissionDecisions
            .persistExtensionPermissionDecision(
                extensionId: first.id,
                profileId: profile.id,
                targetKind: .permission,
                target: "tabs",
                state: .denied,
                expiresAt: nil
            )
        fixture.inspection.actionPolicy.permissionDecisions
            .persistExtensionPermissionDecision(
                extensionId: first.id,
                profileId: secondProfile.id,
                targetKind: .permission,
                target: "tabs",
                state: .denied,
                expiresAt: nil
            )
        fixture.inspection.actionSurfaces.toolbarPinning.pinToToolbar(
            first.id,
            profileId: profile.id
        )
        fixture.inspection.actionSurfaces.toolbarPinning.pinToToolbar(
            first.id,
            profileId: secondProfile.id
        )
        fixture.inspection.actionSurfaces.hubOrdering.moveUnpinnedExtension(
            id: first.id,
            to: 1,
            within: [first.id, "retained-extension"],
            profileId: profile.id
        )
        fixture.inspection.actionSurfaces.hubOrdering.moveUnpinnedExtension(
            id: first.id,
            to: 1,
            within: [first.id, "retained-extension"],
            profileId: secondProfile.id
        )
        let importStore = SafariExtensionImportStore(database: container)
        importStore.markImported(
            extensionBundleIdentifier: "test.\(first.id)",
            appexPath: first.sourceBundlePath,
            installedExtensionId: first.id
        )
        let runtimeIdentifier = SafariWebExtensionRuntimeIdentity
            .webKitStorageIdentifier(
                extensionId: first.id,
                sourceKind: first.sourceKind,
                sourceBundlePath: first.sourceBundlePath
            )
        let extensionStorageDirectories = try [profile.id, secondProfile.id]
            .map { profileID in
                let cleanupStore = WebExtensionStorageCleanupStore(
                    controllerStorageId: ExtensionControllerProvisioningOwner
                        .extensionControllerIdentifier(for: profileID),
                    planner: WebExtensionStorageCleanupPlanner(),
                    storageDirectoryNameResolver: { _ in runtimeIdentifier }
                )
                let directory = try XCTUnwrap(
                    cleanupStore.directory(for: first.id)
                )
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                try Data("extension state".utf8).write(
                    to: directory.appendingPathComponent("ExtensionState.bin")
                )
                return directory
            }
        let originalSourceURL = URL(
            fileURLWithPath: first.sourceBundlePath,
            isDirectory: true
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalSourceURL.path))

        try await fixture.inspection.installation.lifecycle.uninstall(first.id)

        XCTAssertTrue(
            fixture.inspection.actionSurfaces.installedExtensions.records.isEmpty
        )
        XCTAssertIdentical(
            fixture.inspection.contextState.profiles.controller(for: profile.id),
            controller,
            "Uninstall must not restart the browser session controller"
        )
        XCTAssertEqual(
            fixture.inspection.actionPolicy.store.policy(
                extensionId: first.id,
                profileId: profile.id
            ).policy.defaultAccess,
            .ask
        )
        XCTAssertEqual(
            fixture.inspection.actionPolicy.store.policy(
                extensionId: first.id,
                profileId: secondProfile.id
            ).policy.defaultAccess,
            .ask
        )
        XCTAssertNil(
            fixture.inspection.actionPolicy.permissionDecisions
                .storedExtensionPermissionDecision(
                    extensionId: first.id,
                    profileId: profile.id,
                    targetKind: .permission,
                    target: "tabs"
                )
        )
        XCTAssertNil(
            fixture.inspection.actionPolicy.permissionDecisions
                .storedExtensionPermissionDecision(
                    extensionId: first.id,
                    profileId: secondProfile.id,
                    targetKind: .permission,
                    target: "tabs"
                )
        )
        XCTAssertFalse(
            fixture.inspection.actionSurfaces.toolbarPinning
                .pinnedToolbarExtensionIDs(profileId: profile.id)
                .contains(first.id)
        )
        XCTAssertFalse(
            fixture.inspection.actionSurfaces.toolbarPinning
                .pinnedToolbarExtensionIDs(profileId: secondProfile.id)
                .contains(first.id)
        )
        let persistedHubOrder = try container.read {
            try $0.documents.value(
                [String: [String]].self,
                forKey: "extensions.hub-order"
            ) ?? [:]
        }
        XCTAssertFalse(
            persistedHubOrder.values.joined().contains(first.id)
        )
        XCTAssertTrue(importStore.importedRecords().isEmpty)
        for extensionStorageDirectory in extensionStorageDirectories {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: extensionStorageDirectory.path
                )
            )
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: originalSourceURL.path),
            "Uninstall must not touch the user-owned source extension"
        )
    }

    func testWebsiteDataMutationQuiescesTargetProfileAndReloadsOnlyOnDemand() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Mutation Quiesce")
        let fixture = makeSafariExtensionManagerTestFixture(
            context: container,
            initialProfile: profile
        )
        let manager = fixture.manager
        let inspection = fixture.inspection
        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "MutationQuiesceExtension"
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)
        XCTAssertNotNil(
            inspection.contextState.profiles.contexts(for: profile.id)[installed.id]
        )

        let generationBeforeQuiesce = inspection.runtimeAuthorities
            .loadRevisions.issue()
        XCTAssertTrue(
            manager.quiesceForWebsiteDataMutation(profileIDs: [profile.id])
        )
        XCTAssertFalse(
            inspection.runtimeAuthorities.loadRevisions
                .isCurrent(generationBeforeQuiesce)
        )
        XCTAssertNil(
            inspection.contextState.profiles.contexts(for: profile.id)[installed.id]
        )

        _ = try await inspection.contextCoordination.residency
            .ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        XCTAssertNotNil(
            inspection.contextState.profiles.contexts(for: profile.id)[installed.id]
        )
    }

    private func makeTestContainer() throws -> SumiDatabase {
        try SumiDatabase.inMemory()
    }

    private func makeScopedModuleRegistry() -> SumiModuleRegistry {
        let suiteName = UUID().uuidString
        let userDefaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        return SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: userDefaults)
        )
    }

    private func makeScratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func installUnpackedExtension(
        manager: ExtensionManager,
        scratchDirectory: URL,
        name: String,
        manifestVersion: Int = 3
    ) async throws -> InstalledExtension {
        let directoryURL = scratchDirectory.appendingPathComponent(name, isDirectory: true)
        try writeTestPackage(
            at: directoryURL,
            name: name,
            manifestVersion: manifestVersion
        )
        return try await manager.settingsCatalogBinding().install(
            from: directoryURL,
            enableOnInstall: false
        )
    }

    private func writeTestPackage(
        at directoryURL: URL,
        name: String,
        manifestVersion: Int
    ) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": manifestVersion,
            "name": name,
            "version": "1.0",
            "host_permissions": ["<all_urls>"],
            "action": ["default_popup": "popup.html"],
        ]
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        )
        try manifestData.write(to: manifestURL, options: [.atomic])
        try Data("<!doctype html><title>popup</title>".utf8)
            .write(to: directoryURL.appendingPathComponent("popup.html"), options: [.atomic])
    }
}

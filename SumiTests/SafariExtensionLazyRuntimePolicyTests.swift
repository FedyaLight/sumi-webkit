import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionLazyRuntimePolicyTests: XCTestCase {
    func testLaunchStartsWithZeroExtensionContexts() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Lazy Launch")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        XCTAssertEqual(manager.countLoadedExtensionContexts(), 0)
        XCTAssertTrue(manager.extensionContextsByProfile.isEmpty)
    }

    func testDetachedDelegateModuleStateUsesInjectedRegistry() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Scoped Delegate")
        let sharedEnabled = SumiModuleRegistry.shared.isEnabled(.extensions)
        let registry = makeScopedModuleRegistry()
        registry.setEnabled(!sharedEnabled, for: .extensions)

        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            moduleRegistry: registry
        )

        XCTAssertEqual(
            manager.extensionsModuleEnabledForDelegateCallbacks,
            !sharedEnabled
        )
    }

    func testExtensionsModuleDefaultFactoryPassesScopedRegistryToManager() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Scoped Module")
        let sharedEnabled = SumiModuleRegistry.shared.isEnabled(.extensions)
        let registry = makeScopedModuleRegistry()
        registry.enable(.extensions)
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            initialProfileProvider: { profile }
        )

        let manager = try XCTUnwrap(module.managerIfEnabled())
        registry.setEnabled(!sharedEnabled, for: .extensions)

        XCTAssertEqual(
            manager.extensionsModuleEnabledForDelegateCallbacks,
            !sharedEnabled
        )
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
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            initialProfileProvider: { fallbackProfile },
            managerFactory: { context, initialProfile, browserConfiguration, moduleRegistry in
                initialProfileUsedByFactory = initialProfile
                let manager = ExtensionManager(
                    context: context,
                    initialProfile: initialProfile,
                    browserConfiguration: browserConfiguration,
                    moduleRegistry: moduleRegistry
                )
                createdManager = manager
                return manager
            }
        )

        module.attach(runtime: .live(browserManager: browserManager))
        _ = try XCTUnwrap(module.managerIfEnabled())

        XCTAssertIdentical(initialProfileUsedByFactory, runtimeProfile)
        let attachedManager = try XCTUnwrap(createdManager)
        XCTAssertTrue(attachedManager.runtime.browserRuntimeAvailable())
        XCTAssertIdentical(attachedManager.runtime.currentProfile(), runtimeProfile)
    }

    func testDisabledInstallDoesNotCreateRuntimeControllerOrContext() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Disabled Install")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let scratchDirectory = try makeScratchDirectory()
        _ = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "DisabledInstallExtension"
        )

        XCTAssertEqual(manager.countLoadedExtensionContexts(), 0)
        XCTAssertTrue(manager.extensionContextsByProfile.isEmpty)
        XCTAssertTrue(manager.extensionControllersByProfile.isEmpty)
    }

    func testEightProfilesWithOneExtensionCreatesAtMostOneContextUntilUsed() async throws {
        let container = try makeTestContainer()
        var profiles: [Profile] = []
        for index in 1...8 {
            profiles.append(Profile(name: "Profile \(index)"))
        }

        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profiles[0]
        )

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "LazyPolicyExtension"
        )
        _ = try await manager.enableExtension(installed.id)

        XCTAssertEqual(
            manager.countLoadedExtensionContexts(),
            1,
            "Enable should load only the active profile's context"
        )

        for profile in profiles.dropFirst() {
            manager.switchProfile(profileId: profile.id)
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(
            manager.countLoadedExtensionContexts(),
            0,
            "Switching across inactive profiles should unload prior contexts"
        )

        let targetProfile = profiles[7]
        _ = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: targetProfile.id
        )

        XCTAssertEqual(
            manager.countLoadedExtensionContexts(),
            1,
            "Only the requested profile/extension pair should be live"
        )
        XCTAssertNotNil(
            manager.getExtensionContext(
                for: installed.id,
                profileId: targetProfile.id
            )
        )
    }

    func testCachedWebExtensionIsReusedAcrossProfiles() async throws {
        let container = try makeTestContainer()
        let profileA = Profile(name: "Cache A")
        let profileB = Profile(name: "Cache B")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profileA
        )

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "CacheReuseExtension"
        )
        _ = try await manager.enableExtension(installed.id)

        let contextA = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profileA.id)
        )
        manager.unloadExtensionContextsForInactiveProfiles(keepingProfileId: profileB.id)

        _ = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profileB.id
        )
        let contextB = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profileB.id)
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
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profileA
        )

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "DisableUnloadExtension"
        )
        _ = try await manager.enableExtension(installed.id)
        _ = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profileB.id
        )
        XCTAssertEqual(manager.countLoadedExtensionContexts(), 2)

        try await manager.disableExtension(installed.id)

        XCTAssertEqual(manager.countLoadedExtensionContexts(), 0)
        XCTAssertNil(manager.cachedWebExtensionsByID[installed.id])
    }

    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
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
        return try await manager.performInstallation(
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

import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionActionPopupRuntimeTests: XCTestCase {
    func testLazyRuntimeLoadDoesNotResetExistingProfileContextsOnSourceGuard() throws {
        let profilesSource = try String(
            contentsOf: projectURL("Sumi/Managers/ExtensionManager/ExtensionManager+Profiles.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            profilesSource.contains("if forceReload {"),
            "Lazy runtime reload must only reset loaded contexts when forceReload is true"
        )
        XCTAssertFalse(
            profilesSource.contains("extensionContextsByProfile.isEmpty == false"),
            "Lazy runtime must not reset merely because another profile already has contexts"
        )
    }

    func testActionPopupPathLoadsOnlySelectedExtension() throws {
        let uiSource = try String(
            contentsOf: projectURL("Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift"),
            encoding: .utf8
        )
        let profilesSource = try String(
            contentsOf: projectURL("Sumi/Managers/ExtensionManager/ExtensionManager+Profiles.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            uiSource.contains("ensureExtensionLoaded"),
            "Action popup must lazily load only the selected extension context"
        )
        XCTAssertFalse(
            uiSource.contains("await ensureEnabledExtensionsLoaded(for: tabProfileId)"),
            "Action popup must not eagerly load every enabled extension for the profile"
        )
        XCTAssertFalse(
            profilesSource.contains("await self.ensureEnabledExtensionsLoaded(for: profileId)"),
            "Profile switches must not eagerly load every enabled extension"
        )
        XCTAssertTrue(
            uiSource.contains("classifyActionPopupRuntimeFailure")
                && uiSource.contains("actionPopupRuntimeDiagnosticLines"),
            "Action popup runtime failures must record sanitized diagnostics"
        )
    }

    func testRequestExtensionRuntimeAndWaitHonorsProfileReadinessWithoutForceReload() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Popup Profile")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )

        manager.runtimeState = .idle
        manager.markExtensionRuntimeReadyIfProfileContextsLoaded(for: profile.id)

        let runtimeReady = await manager.requestExtensionRuntimeAndWait(
            reason: .extensionAction,
            profileId: profile.id
        )
        XCTAssertTrue(
            runtimeReady,
            "Profile-scoped readiness should satisfy the action-popup runtime gate without a destructive reload"
        )
        XCTAssertEqual(manager.runtimeState, .ready)
    }

    func testProfileExtensionRuntimeReadinessTracksMissingContextsPerProfile() async throws {
        let container = try makeTestContainer()
        let profileA = Profile(name: "Profile A")
        let profileB = Profile(name: "Profile B")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profileA
        )

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "ProfileIsolationExtension"
        )
        _ = try await manager.enableExtension(installed.id)

        XCTAssertTrue(
            manager.isProfileExtensionRuntimeReady(for: profileA.id),
            "Enabled extension should be ready in the profile where it was enabled"
        )
        XCTAssertFalse(
            manager.isProfileExtensionRuntimeReady(for: profileB.id),
            "A different profile must not inherit another profile's loaded context"
        )

        await manager.ensureEnabledExtensionsLoaded(for: profileB.id)
        XCTAssertTrue(
            manager.isProfileExtensionRuntimeReady(for: profileB.id),
            "Profile B should load its own isolated context on demand"
        )
        XCTAssertNotIdentical(
            manager.getExtensionContext(for: installed.id, profileId: profileA.id),
            manager.getExtensionContext(for: installed.id, profileId: profileB.id),
            "Profile A and Profile B must not share the same WKWebExtensionContext instance"
        )
    }

    func testImportedSafariAppexCanOpenActionPopupAfterEnable() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Raindrop Profile")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installSafariStyleCopiedPackage(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "Raindrop",
            manifestVersion: 3
        )
        _ = try await manager.enableExtension(installed.id)

        let tab = Tab(url: URL(string: "https://example.com/")!)
        tab.profileId = profile.id

        let result = await manager.openActionPopupFromURLHub(
            extensionId: installed.id,
            currentTab: tab
        )

        let blocker = result.blocker
        XCTAssertTrue(
            result.opened
                || blocker == BrowserExtensionActionPopupBlocker.actionDisabled
                || blocker == BrowserExtensionActionPopupBlocker.noActionPopup,
            "Unexpected popup blocker: \(blocker?.rawValue ?? "nil") message=\(result.message) diagnostics=\(result.diagnostics)"
        )
        XCTAssertNotEqual(blocker, BrowserExtensionActionPopupBlocker.runtimeUnavailable)
        XCTAssertNotEqual(blocker, BrowserExtensionActionPopupBlocker.runtimeLoadFailed)
    }

    func testReimportAfterDeleteCanReachPopupRuntimeGate() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Reimport Profile")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installSafariStyleCopiedPackage(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "Reimport Extension"
        )
        _ = try await manager.enableExtension(installed.id)
        try await manager.uninstallExtension(installed.id)

        let reinstalled = try await installSafariStyleCopiedPackage(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "Reimport Extension",
            extensionId: installed.id
        )
        _ = try await manager.enableExtension(reinstalled.id)

        _ = try await manager.ensureExtensionLoaded(
            extensionId: reinstalled.id,
            profileId: profile.id
        )
        XCTAssertNotNil(
            manager.getExtensionContext(for: reinstalled.id, profileId: profile.id)
        )
    }

    func testMV2SafariAppexStillLoadsThroughRuntimeGate() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "MV2 Profile")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installSafariStyleCopiedPackage(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "Bitwarden",
            manifestVersion: 2
        )
        _ = try await manager.enableExtension(installed.id)

        _ = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        XCTAssertTrue(
            manager.isExtensionRuntimeReady(
                extensionId: installed.id,
                profileId: profile.id
            )
        )
    }

    func testRaindropManualE2EPathRepresentedInAcceptanceMatrix() {
        let raindrop = SafariExtensionCompatibilityTargets.all.first {
            $0.key == "raindrop"
        }
        XCTAssertNotNil(raindrop)
        XCTAssertEqual(raindrop?.displayName, "Raindrop")
    }

    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
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

    private func installSafariStyleCopiedPackage(
        manager: ExtensionManager,
        scratchDirectory: URL,
        name: String,
        manifestVersion: Int = 3,
        extensionId: String? = nil
    ) async throws -> InstalledExtension {
        let packageRoot = scratchDirectory.appendingPathComponent(
            "\(name)-package",
            isDirectory: true
        )
        try writeTestPackage(
            at: packageRoot,
            name: name,
            manifestVersion: manifestVersion
        )

        let resolvedExtensionId = extensionId ?? UUID().uuidString
        let extensionsDirectory = ExtensionUtils.extensionsDirectory()
        let destinationDirectory = extensionsDirectory.appendingPathComponent(
            resolvedExtensionId,
            isDirectory: true
        )
        if FileManager.default.fileExists(atPath: destinationDirectory.path) {
            try FileManager.default.removeItem(at: destinationDirectory)
        }
        try FileManager.default.copyItem(at: packageRoot, to: destinationDirectory)

        let manifestURL = destinationDirectory.appendingPathComponent("manifest.json")
        let manifest = try ExtensionUtils.validateManifest(
            at: manifestURL,
            policy: .safariWebExtension
        )
        let record = try manager.makeInstalledRecord(
            extensionId: resolvedExtensionId,
            manifest: manifest,
            extensionRoot: destinationDirectory,
            isEnabled: false,
            sourceKind: .safariAppExtension,
            sourceBundlePath: "/tmp/missing-\(resolvedExtensionId).appex",
            sourceFingerprintURL: destinationDirectory,
            existingEntity: nil
        )
        try manager.persist(record: record)
        _ = manager.loadInstalledExtensionMetadata()
        return record
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
        var manifest: [String: Any] = [
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

    private func projectURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
    }
}

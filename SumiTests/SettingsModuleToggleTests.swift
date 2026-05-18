import XCTest

@testable import Sumi

final class SettingsModuleToggleTests: XCTestCase {
    func testDescriptorsStillCoverOptionalModules() {
        XCTAssertEqual(
            moduleToggleDescriptors.map(\.moduleID),
            [.adBlocking, .extensions, .userScripts]
        )
    }

    @MainActor
    func testToggleModelsPersistThroughModuleRegistryStore() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        for descriptor in moduleToggleDescriptors {
            let registry = SumiModuleRegistry(settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults))
            let model = SumiSettingsModuleToggleModel(descriptor: descriptor, registry: registry)
            model.setEnabled(true)
            XCTAssertTrue(registry.isEnabled(descriptor.moduleID))
            model.setEnabled(false)
            XCTAssertFalse(registry.isEnabled(descriptor.moduleID))
        }
    }

    func testPrivacySettingsExposeUnifiedProtectionOnly() throws {
        let source = try Self.source(named: "Sumi/Components/Settings/PrivacySettingsView.swift")

        XCTAssertTrue(source.contains("Adblock & Protection"))
        XCTAssertTrue(source.contains("Apply selected protection level"))
        XCTAssertTrue(source.contains("Restart Sumi to finish applying global protection changes."))
        XCTAssertTrue(source.contains("Off"))
        XCTAssertTrue(source.contains("Protection"))
        XCTAssertTrue(source.contains("Adblock"))
        XCTAssertFalse(source.contains("SumiSettingsModuleToggleGate(descriptor: .trackingProtection)"))
        XCTAssertFalse(source.contains("SumiSettingsModuleToggleGate(descriptor: .adBlocking)"))
        XCTAssertFalse(source.contains("NativeAdblockSettingsView"))
        XCTAssertFalse(source.contains("LegacyTrackingProtectionRuntimeSettingsView"))
    }

    func testLegacyGenerationControlsAreRemovedFromPrivacySettings() throws {
        let source = try Self.source(named: "Sumi/Components/Settings/PrivacySettingsView.swift")

        for removedCopy in [
            "runtime-generated dev profile",
            "Rebuild selected Adblock profile now",
            "Reset deprecated runtime-generated lists",
            "Automatic filter updates",
            "Cosmetic filtering",
            "Filter lists",
            "Native profile",
            "raw list",
        ] {
            XCTAssertFalse(source.localizedCaseInsensitiveContains(removedCopy), removedCopy)
        }
    }

    func testSettingsScreensStillGateExtensionsAndUserScripts() throws {
        let settingsSource = try Self.source(named: "Sumi/Components/Settings/SettingsView.swift")

        XCTAssertTrue(settingsSource.contains("SumiSettingsModuleToggleGate(descriptor: .extensions)"))
        XCTAssertTrue(settingsSource.contains("SumiSettingsModuleToggleGate(descriptor: .userScripts)"))
    }

    func testModuleToggleSourceDoesNotConstructOptionalRuntimeTypes() throws {
        let source = try Self.source(named: "Sumi/Components/Settings/SumiSettingsModuleToggles.swift")

        for forbiddenPattern in [
            "SumiTrackingProtection(",
            "SumiAdBlockingModule(",
            "SumiContentBlockingService(",
            "ExtensionManager(",
            "NativeMessagingHandler(",
            "SumiScriptsManager(",
        ] {
            XCTAssertFalse(source.contains(forbiddenPattern), forbiddenPattern)
        }
    }

    func testSettingsSourcesAvoidDisallowedModuleSurfaces() throws {
        let source = try Self.combinedSource(in: "Sumi/Components/Settings")
        for pattern in [
            "onboarding",
            "first-run",
            "first run",
            "module diagnostics",
            "unified site settings",
        ] {
            XCTAssertFalse(source.localizedCaseInsensitiveContains(pattern), pattern)
        }
    }

    private var moduleToggleDescriptors: [SumiSettingsModuleToggleDescriptor] {
        [.adBlocking, .extensions, .userScripts]
    }

    private static func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private static func combinedSource(in relativeDirectory: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directoryURL = repoRoot.appendingPathComponent(relativeDirectory)
        let fileURLs = (FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }
        return try fileURLs.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }
}

import XCTest

@testable import Sumi

final class SettingsModuleToggleTests: XCTestCase {
    func testDescriptorsStillCoverOptionalModules() {
        XCTAssertEqual(
            moduleToggleDescriptors.map(\.moduleID),
            [.extensions, .userScripts]
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

    func testPrivacySettingsExposeSiteSettingsAndAdBlockingProtection() throws {
        let source = try Self.source(named: "Sumi/Components/Settings/PrivacySettingsView.swift")

        XCTAssertTrue(source.contains("SumiSiteSettingsNavigationRow"))
        XCTAssertTrue(source.contains("AdblockProtectionSettingsView("))
        XCTAssertLessThan(
            try XCTUnwrap(source.range(of: "SumiSiteSettingsNavigationRow")?.lowerBound),
            try XCTUnwrap(source.range(of: "AdblockProtectionSettingsView(")?.lowerBound)
        )

        for removedCopy in [
            "levelOptionButton(for: level)",
            "Apply to use this level.",
            "Copy Protection Diagnostics",
            "LegacyTrackingProtectionRuntimeSettingsView",
            "runtime-generated dev profile",
            "Cosmetic filtering",
        ] {
            XCTAssertFalse(source.contains(removedCopy), removedCopy)
        }
    }

    func testSettingsScreensStillGateExtensionsAndUserScripts() throws {
        let extensionsSettingsSource = try Self.source(named: "Sumi/Components/Settings/SumiExtensionsSettingsPane.swift")

        XCTAssertTrue(extensionsSettingsSource.contains("SumiSettingsModuleToggleGate(descriptor: .extensions)"))
        XCTAssertTrue(extensionsSettingsSource.contains("SumiSettingsModuleToggleGate(descriptor: .userScripts)"))
        XCTAssertFalse(extensionsSettingsSource.contains("case .adBlocker"))
        XCTAssertFalse(extensionsSettingsSource.contains("SumiSettingsModuleToggleGate(descriptor: .adBlocker)"))
        XCTAssertFalse(extensionsSettingsSource.contains("Extensions, ad blocker, and userscripts"))
    }

    func testModuleToggleSourceDoesNotConstructOptionalRuntimeTypes() throws {
        let source = try Self.source(named: "Sumi/Components/Settings/SumiSettingsModuleToggles.swift")

        for forbiddenPattern in [
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
        [.extensions, .userScripts]
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

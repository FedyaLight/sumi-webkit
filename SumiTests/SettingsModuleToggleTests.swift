import XCTest

@testable import Sumi

final class SettingsModuleToggleTests: XCTestCase {
    func testDescriptorsExposeExactlyOptionalModules() {
        XCTAssertEqual(
            moduleToggleDescriptors.map(\.moduleID),
            [.trackingProtection, .adBlocking, .extensions, .userScripts]
        )

        XCTAssertEqual(
            Set(moduleToggleDescriptors.map(\.moduleID)),
            Set(SumiModuleID.allCases)
        )
    }

    func testDescriptorCopyMatchesPerformanceFirstModuleContract() throws {
        let descriptorsByModule = Dictionary(
            uniqueKeysWithValues: moduleToggleDescriptors.map {
                ($0.moduleID, $0)
            }
        )

        let trackingCopy = copy(for: try XCTUnwrap(descriptorsByModule[.trackingProtection]))
        XCTAssertTrue(trackingCopy.contains("does not load tracker data"))
        XCTAssertTrue(trackingCopy.contains("rule lists"))
        XCTAssertTrue(trackingCopy.contains("update jobs"))
        XCTAssertTrue(trackingCopy.contains("protection scripts"))
        XCTAssertTrue(trackingCopy.contains("manual only"))
        XCTAssertTrue(trackingCopy.contains("background"))

        let adBlockingCopy = copy(for: try XCTUnwrap(descriptorsByModule[.adBlocking]))
        XCTAssertTrue(adBlockingCopy.contains("separate from Tracking Protection"))
        XCTAssertTrue(adBlockingCopy.contains("WebKit rule lists"))
        XCTAssertTrue(adBlockingCopy.contains("schedule updates"))

        let extensionsCopy = copy(for: try XCTUnwrap(descriptorsByModule[.extensions]))
        XCTAssertTrue(extensionsCopy.contains("scan manifests"))
        XCTAssertTrue(extensionsCopy.contains("attach extension scripts"))
        XCTAssertTrue(extensionsCopy.contains("native messaging"))
        XCTAssertTrue(extensionsCopy.contains("extension message handlers"))

        let userScriptsCopy = copy(for: try XCTUnwrap(descriptorsByModule[.userScripts]))
        XCTAssertTrue(userScriptsCopy.contains("read the userscript store"))
        XCTAssertTrue(userScriptsCopy.contains("attach WKUserScript"))
    }

    @MainActor
    func testToggleModelsReflectDisabledDefaults() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )

        for descriptor in moduleToggleDescriptors {
            let model = SumiSettingsModuleToggleModel(
                descriptor: descriptor,
                registry: registry
            )
            let isEnabled = model.isEnabled
            XCTAssertFalse(isEnabled, "\(descriptor.title) should default to disabled")
        }
    }

    @MainActor
    func testToggleModelsPersistThroughModuleRegistryStore() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        for descriptor in moduleToggleDescriptors {
            let firstRegistry = SumiModuleRegistry(
                settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
            )
            let firstModel = SumiSettingsModuleToggleModel(
                descriptor: descriptor,
                registry: firstRegistry
            )

            firstModel.setEnabled(true)

            let enabledRegistry = SumiModuleRegistry(
                settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
            )
            let enabledValue = enabledRegistry.isEnabled(descriptor.moduleID)
            XCTAssertTrue(enabledValue)

            let secondModel = SumiSettingsModuleToggleModel(
                descriptor: descriptor,
                registry: enabledRegistry
            )
            secondModel.setEnabled(false)

            let disabledRegistry = SumiModuleRegistry(
                settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
            )
            let disabledValue = disabledRegistry.isEnabled(descriptor.moduleID)
            XCTAssertFalse(disabledValue)
        }
    }

    func testSettingsScreensReferenceAllModuleToggleDescriptors() throws {
        let privacySource = try Self.source(named: "Sumi/Components/Settings/PrivacySettingsView.swift")
        let settingsSource = try Self.source(named: "Sumi/Components/Settings/SettingsView.swift")

        XCTAssertTrue(privacySource.contains("SumiSettingsModuleToggleGate(descriptor: .trackingProtection)"))
        XCTAssertTrue(privacySource.contains("SumiSettingsModuleToggleGate(descriptor: .adBlocking)"))
        XCTAssertTrue(settingsSource.contains("SumiSettingsModuleToggleGate(descriptor: .extensions)"))
        XCTAssertTrue(settingsSource.contains("SumiSettingsModuleToggleGate(descriptor: .userScripts)"))
    }

    func testModuleToggleSourceDoesNotConstructOptionalRuntimeTypes() throws {
        let source = try Self.source(named: "Sumi/Components/Settings/SumiSettingsModuleToggles.swift")

        for forbiddenPattern in [
            "Sumi" + "TrackingProtection(",
            "Sumi" + "AdBlockingModule(",
            "Sumi" + "ContentBlockingService(",
            "Extension" + "Manager(",
            "NativeMessaging" + "Handler(",
            "SumiScripts" + "Manager(",
        ] {
            XCTAssertFalse(source.contains(forbiddenPattern), "\(forbiddenPattern) is referenced by module toggles")
        }
    }

    func testAdBlockingSettingsExposeNativeSkeletonRuntimeUI() throws {
        let privacySource = try Self.source(named: "Sumi/Components/Settings/PrivacySettingsView.swift")
        let toggleSource = try Self.source(named: "Sumi/Components/Settings/SumiSettingsModuleToggles.swift")

        XCTAssertTrue(privacySource.contains("SumiSettingsModuleToggleGate(descriptor: .adBlocking)"))
        XCTAssertTrue(toggleSource.contains("moduleID: .adBlocking"))
        XCTAssertTrue(privacySource.contains("NativeAdblockSettingsView"))
        XCTAssertTrue(privacySource.contains("Automatic filter updates"))
        XCTAssertTrue(privacySource.contains("Cosmetic filtering"))
        XCTAssertTrue(privacySource.contains("Filter lists"))
        XCTAssertTrue(privacySource.contains("Base ads"))
        XCTAssertTrue(privacySource.contains("Regional ads"))
        XCTAssertTrue(privacySource.contains("Apply selected protection level"))
        XCTAssertTrue(privacySource.contains("Deprecated runtime-generated dev profile"))
        XCTAssertTrue(privacySource.contains("normal Off / Protection / Adblock / Extreme levels use prepared bundles only"))
        XCTAssertTrue(privacySource.contains("Embedded Adblock Bundle"))
        XCTAssertTrue(privacySource.contains("Bundle source"))
        XCTAssertTrue(privacySource.contains("Development Build"))
        XCTAssertTrue(privacySource.contains("futureRemoteBundle"))
        XCTAssertTrue(privacySource.contains("Install selected bundle"))
        XCTAssertTrue(privacySource.contains("DEBUG Adblock Diagnostics"))
        XCTAssertTrue(privacySource.contains("Deprecated runtime-generated rebuild"))
        XCTAssertTrue(privacySource.contains("Copy Adblock Diagnostics"))
        XCTAssertTrue(privacySource.contains("NSPasteboard.general"))

        for source in [privacySource, toggleSource] {
            XCTAssertFalse(source.contains("oraLikeNative"))
            XCTAssertFalse(source.contains("SafariConverterLib"))
            XCTAssertFalse(source.contains("AdGuard SafariConverterLib"))
            XCTAssertFalse(source.contains("assetsIfAvailable"))
            XCTAssertFalse(source.contains("normalTabDecision"))
            XCTAssertFalse(source.localizedCaseInsensitiveContains("onboarding"))
            XCTAssertFalse(source.localizedCaseInsensitiveContains("acceptable ads"))
        }
    }

    func testEmbeddedBundleSettingsControlsAreDebugOnly() throws {
        let source = try Self.source(named: "Sumi/Components/Settings/PrivacySettingsView.swift")
        let bundleSource = try Self.source(named: "Sumi/ContentBlocking/SumiAdblockNativeRuleBundle.swift")
        let debugStart = try XCTUnwrap(
            source.range(of: "#if DEBUG\n    @State private var rebuildStatus")
        )
        let debugEnd = try XCTUnwrap(
            source.range(of: "    #endif\n\n    private var filterListSelection")
        )
        let debugBlock = String(source[debugStart.lowerBound..<debugEnd.upperBound])
        var releaseSource = source
        releaseSource.removeSubrange(debugStart.lowerBound..<debugEnd.upperBound)

        XCTAssertTrue(debugBlock.contains("Embedded Adblock Bundle"))
        XCTAssertTrue(debugBlock.contains("No App Resource or Development Build Adblock bundles found"))
        XCTAssertTrue(debugBlock.contains("Expected app resource path"))
        XCTAssertTrue(debugBlock.contains("Expected development path"))
        XCTAssertTrue(debugBlock.contains("Generate command"))
        XCTAssertTrue(bundleSource.contains("scripts/build_sumi_adblock_bundle.sh --all-profiles --output .build/sumi-adblock-bundles"))
        XCTAssertTrue(debugBlock.contains("Generated outside app resources"))
        XCTAssertTrue(debugBlock.contains("installEmbeddedAdblockBundle("))
        XCTAssertTrue(debugBlock.contains("source: profile.source"))

        XCTAssertFalse(releaseSource.contains("Embedded Adblock Bundle"))
        XCTAssertFalse(releaseSource.contains("Install selected bundle"))
        XCTAssertFalse(releaseSource.contains("SumiEmbeddedAdblockBundleCatalog"))
    }

    func testNativeProfilePickerIsLabeledAsRuntimeGeneratedOnly() throws {
        let source = try Self.source(named: "Sumi/Components/Settings/PrivacySettingsView.swift")

        XCTAssertTrue(source.contains("Deprecated runtime-generated dev profile"))
        XCTAssertTrue(source.contains("DEBUG only. Disabled for the unified flow; normal Off / Protection / Adblock / Extreme levels use prepared bundles only."))
        XCTAssertTrue(source.contains("Reset deprecated runtime-generated lists"))
        XCTAssertTrue(source.contains("DEBUG only and deprecated. This does not affect the unified protection levels."))
        XCTAssertTrue(source.contains("Deprecated runtime-generated rebuild"))
        XCTAssertTrue(source.contains("DEBUG only and disabled for the unified flow. Browser runtime installs prepared bundles instead."))
        XCTAssertFalse(source.contains("title: \"Native profile\""))
    }

    func testTrackingProtectionSettingsRuntimeAccessStaysBehindModuleGate() throws {
        let source = try Self.source(named: "Sumi/Components/Settings/PrivacySettingsView.swift")

        XCTAssertTrue(source.contains("SumiSettingsModuleToggleGate(descriptor: .trackingProtection)"))
        XCTAssertTrue(source.contains("sumiTrackingProtectionModule"))
        XCTAssertTrue(source.contains("settingsIfEnabled()"))
        XCTAssertTrue(source.contains("dataStoreIfEnabled()"))
        XCTAssertTrue(source.contains("await trackingProtectionModule.updateTrackerDataManually()"))
        XCTAssertTrue(source.contains("await trackingProtectionModule.resetTrackerDataToBundledManually()"))

        for forbiddenPattern in [
            "SumiTrackingProtectionSettings.shared",
            "SumiTrackingProtectionDataStore.shared",
            "SumiContentBlockingService(",
            "SumiEmbeddedDDGTrackerDataRuleSource(",
            "SumiTrackerDataUpdater(",
            "trackingProtectionDataStore.updateTrackerData",
            "trackingProtectionDataStore.resetToBundled",
        ] {
            XCTAssertFalse(source.contains(forbiddenPattern), "\(forbiddenPattern) is referenced by Privacy settings")
        }
    }

    func testUserscriptsSettingsRuntimeAccessStaysBehindModuleGate() throws {
        let settingsSource = try Self.source(named: "Sumi/Components/Settings/SettingsView.swift")
        let toggleSource = try Self.source(named: "Sumi/Components/Settings/SumiSettingsModuleToggles.swift")

        XCTAssertTrue(settingsSource.contains("SumiSettingsModuleToggleGate(descriptor: .userScripts)"))
        XCTAssertTrue(settingsSource.contains("browserManager.userscriptsModule.managerIfEnabled()"))
        XCTAssertTrue(toggleSource.contains("userscriptsModule.setEnabled(isEnabled)"))

        for forbiddenPattern in [
            "browserManager.sumiScriptsManager",
            "SumiScriptsManager(",
            "UserScriptStore(",
            "UserScriptInjector(",
        ] {
            XCTAssertFalse(settingsSource.contains(forbiddenPattern), forbiddenPattern)
        }
    }

    func testExtensionsToggleForwardsThroughExtensionsModule() throws {
        let toggleSource = try Self.source(named: "Sumi/Components/Settings/SumiSettingsModuleToggles.swift")

        XCTAssertTrue(toggleSource.contains("sumiExtensionsModule"))
        XCTAssertTrue(toggleSource.contains("extensionsModule.setEnabled(isEnabled)"))
        XCTAssertFalse(toggleSource.contains("ExtensionManager("))
        XCTAssertFalse(toggleSource.contains("BrowserExtensionSurfaceStore("))
    }

    func testExtensionsSettingsRuntimeAccessStaysBehindModuleGate() throws {
        let settingsSource = try Self.source(named: "Sumi/Components/Settings/SettingsView.swift")

        XCTAssertTrue(settingsSource.contains("SumiSettingsModuleToggleGate(descriptor: .extensions)"))
        XCTAssertTrue(settingsSource.contains("browserManager.extensionsModule.managerIfEnabled()"))
        XCTAssertTrue(settingsSource.contains("browserManager.extensionsModule.discoverSafariExtensions()"))
        XCTAssertTrue(settingsSource.contains("browserManager.extensionsModule.installSafariExtension"))
        XCTAssertTrue(settingsSource.contains("browserManager.extensionsModule.enableExtension"))
        XCTAssertTrue(settingsSource.contains("browserManager.extensionsModule.disableExtension"))
        XCTAssertTrue(settingsSource.contains("browserManager.extensionsModule.uninstallExtension"))

        for forbiddenPattern in [
            "browserManager.extensionManager",
            "ExtensionManager(",
            "BrowserExtensionSurfaceStore(",
            "NativeMessagingHandler(",
        ] {
            XCTAssertFalse(settingsSource.contains(forbiddenPattern), forbiddenPattern)
        }
    }

    func testOpeningSettingsWhileDisabledDoesNotReferenceEnabledRuleListPipeline() throws {
        let source = try Self.source(named: "Sumi/Components/Settings/PrivacySettingsView.swift")

        XCTAssertTrue(source.contains("SumiSettingsModuleToggleGate(descriptor: .trackingProtection)"))
        XCTAssertFalse(source.contains("contentBlockingAssetsIfEnabled"))
        XCTAssertFalse(source.contains("contentBlockingServiceIfEnabled"))
        XCTAssertFalse(source.contains("SumiTrackingRuleListProvider"))
        XCTAssertFalse(source.contains("SumiTrackingContentBlockingAssets"))
    }

    func testTrackingProtectionSettingsAvoidAutomaticOrBrowserUpdateCopy() throws {
        let source = try Self.source(named: "Sumi/Components/Settings/PrivacySettingsView.swift")
        let trackingSection = try XCTUnwrap(
            source.range(of: "private struct LegacyTrackingProtectionRuntimeSettingsView")
                .flatMap { start in
                    source.range(of: "private var trackingDataControls", range: start.upperBound..<source.endIndex)
                        .map { controls in String(source[start.lowerBound..<controls.lowerBound]) }
                }
        )

        XCTAssertTrue(trackingSection.contains("Protection mode"))
        XCTAssertFalse(trackingSection.localizedCaseInsensitiveContains("stale"))
        XCTAssertFalse(trackingSection.localizedCaseInsensitiveContains("automatic update"))
        XCTAssertFalse(trackingSection.localizedCaseInsensitiveContains("browser update"))
        XCTAssertFalse(trackingSection.localizedCaseInsensitiveContains("app update"))
        XCTAssertFalse(trackingSection.localizedCaseInsensitiveContains("application update"))
    }

    func testSettingsSourcesAvoidDisallowedModuleSurfaces() throws {
        let source = try Self.combinedSource(in: "Sumi/Components/Settings")
        let targetWord = "tr" + "acker"
        let forbiddenPatterns = [
            "on" + "boarding",
            "first" + "-run",
            "first " + "run",
            "module " + "diag" + "nostics",
            "unified site " + "settings",
            "stale" + ".*" + targetWord,
            "auto" + "matic.*" + targetWord,
            "auto" + ".*" + targetWord,
        ]

        for pattern in forbiddenPatterns {
            XCTAssertNil(
                source.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
                "\(pattern) should not be present in Settings sources"
            )
        }
    }

    private func copy(for descriptor: SumiSettingsModuleToggleDescriptor) -> String {
        [
            descriptor.title,
            descriptor.toggleTitle,
            descriptor.detail,
        ].joined(separator: " ")
    }

    private var moduleToggleDescriptors: [SumiSettingsModuleToggleDescriptor] {
        [
            .trackingProtection,
            .adBlocking,
            .extensions,
            .userScripts,
        ]
    }

    private static func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func combinedSource(in relativeDirectory: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directoryURL = repoRoot.appendingPathComponent(relativeDirectory)
        let fileURLs = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )?.compactMap { $0 as? URL } ?? []

        return try fileURLs
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }
}

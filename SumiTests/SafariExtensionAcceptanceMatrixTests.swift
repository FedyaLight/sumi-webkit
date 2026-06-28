import XCTest

@testable import Sumi

@MainActor
final class SafariExtensionAcceptanceMatrixTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var importStore: SafariExtensionImportStore!

    override func setUp() {
        suiteName = "SafariExtensionAcceptanceMatrixTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        importStore = SafariExtensionImportStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        suiteName = nil
        defaults = nil
        importStore = nil
    }

    func testSDKProbeDocumentsWKWebExtensionDelegateMessaging() {
        XCTAssertTrue(SafariExtensionHostRelayAPIProbe.wkWebExtensionAppMessagingAvailable)
        XCTAssertTrue(SafariExtensionHostRelayAPIProbe.sdkProbeNote.contains("WKWebExtensionControllerDelegate.h"))
        XCTAssertTrue(SafariExtensionHostRelayAPIProbe.sdkProbeNote.contains("macOS 15.4+"))
        XCTAssertFalse(SafariExtensionHostRelayAPIProbe.sdkProbeNote.contains("hostRelayUnavailable"))
    }

    func testPasswordManagersClassifyCompanionProtocolUnknownRaindropDoesNot() {
        let bitwarden = SafariExtensionNativeMessagingClassificationCatalog
            .classifications(forTargetKey: "bitwarden")
        XCTAssertTrue(bitwarden.contains(.companionAppProtocolUnknown))
        XCTAssertTrue(bitwarden.contains(.noChromeStyleNativeHostRelay))
        XCTAssertFalse(bitwarden.contains(.platformBlocked))

        let raindrop = SafariExtensionNativeMessagingClassificationCatalog
            .classifications(forTargetKey: "raindrop")
        XCTAssertFalse(raindrop.contains(.companionAppProtocolUnknown))
    }

    func testSyntheticEnableActionSurfaceLogic() {
        XCTAssertTrue(
            SafariExtensionAcceptanceMatrixBuilder.isActionSurfaceReadyAfterSyntheticEnable(
                hasAction: false,
                isEnabled: true,
                isContextLoaded: true,
                isActionAvailable: false,
                hasSeededActionState: false
            )
        )
        XCTAssertTrue(
            SafariExtensionAcceptanceMatrixBuilder.isActionSurfaceReadyAfterSyntheticEnable(
                hasAction: true,
                isEnabled: true,
                isContextLoaded: true,
                isActionAvailable: true,
                hasSeededActionState: false
            )
        )
        XCTAssertFalse(
            SafariExtensionAcceptanceMatrixBuilder.isActionSurfaceReadyAfterSyntheticEnable(
                hasAction: true,
                isEnabled: true,
                isContextLoaded: false,
                isActionAvailable: false,
                hasSeededActionState: false
            )
        )
    }

    func testMatrixBuildsForUndiscoveredTarget() {
        let matrix = SafariExtensionAcceptanceMatrixBuilder.build(
            targets: [SafariExtensionCompatibilityTargets.all[0]],
            discovered: [],
            importStore: importStore
        )

        XCTAssertEqual(matrix.entries.count, 1)
        XCTAssertEqual(matrix.entries[0].targetKey, "bitwarden")
        XCTAssertEqual(matrix.entries[0].platformBlockers, [])
        XCTAssertTrue(
            matrix.entries[0].nativeMessagingClassifications.contains(.companionAppProtocolUnknown)
        )
        XCTAssertEqual(matrix.globalPlatformBlockers, [])
        XCTAssertTrue(
            matrix.globalNativeMessagingClassifications.contains(.wkWebExtensionAppMessagingAvailable)
        )

        let scannerResult = matrix.entries[0].results.first {
            $0.check == .scannerFindsInstalledTarget
        }
        XCTAssertNotNil(scannerResult)
    }

    func testCompatibilityReportUsesNativeMessagingClassifications() {
        let report = SafariExtensionCompatibilityReportBuilder.build(
            targets: [SafariExtensionCompatibilityTargets.all[3]],
            discovered: [],
            importStore: importStore
        )

        XCTAssertEqual(report.platformBlockers, [])
        XCTAssertFalse(report.sdkProbeNote.isEmpty)
        XCTAssertEqual(report.entries[0].platformBlockers, [])
        XCTAssertTrue(
            report.nativeMessagingClassifications.contains(.noChromeStyleNativeHostRelay)
        )
    }

    func testContentScriptTabReconcileProbeFindsWiring() {
        XCTAssertTrue(SafariExtensionContentScriptProbe.isTabReconcilePathWiredViaCompileTimePaths())
    }

    func testRaindropTabAdapterProbePasses() {
        let result = SafariExtensionRaindropTabAdapterProbe.evaluate()
        XCTAssertTrue(result.passed, result.detail)
    }

    func testMatrixSyntheticEnableSkippedWhenDisabled() throws {
        let candidate = try makeCandidate(
            bundleID: "com.bitwarden.desktop.safari",
            appexPath: "/tmp/bitwarden.appex"
        )
        importStore.markImported(
            extensionBundleIdentifier: candidate.extensionBundleIdentifier,
            appexPath: candidate.appexURL.path,
            installedExtensionId: "ext-bitwarden"
        )

        let installed = try makeInstalledExtension(
            id: "ext-bitwarden",
            isEnabled: false,
            sourceBundlePath: candidate.appexURL.path
        )

        let matrix = SafariExtensionAcceptanceMatrixBuilder.build(
            targets: [SafariExtensionCompatibilityTargets.all[0]],
            discovered: [candidate],
            importStore: importStore,
            installedExtensions: [installed]
        )

        let enableCheck = matrix.entries[0].results.first {
            $0.check == .syntheticEnableActionSurfaceReady
        }
        XCTAssertEqual(enableCheck?.passed, true)
        XCTAssertTrue(enableCheck?.detail.contains("Skipped") ?? false)
    }

    func testLiveAcceptanceMatrixAgainstInstalledTargets() {
        let roots = SafariExtensionScanner.defaultApplicationSearchRoots()
        let scanner = SafariExtensionScanner()
        var issues: [SafariExtensionScannerIssue] = []
        let discovered = scanner.scanInstalledExtensions(
            applicationSearchRoots: roots,
            issues: &issues
        )

        let matrix = SafariExtensionAcceptanceMatrixBuilder.build(
            discovered: discovered,
            importStore: importStore,
            applicationSearchRoots: roots
        )

        var installedTargetSummaries: [String] = []

        for target in SafariExtensionCompatibilityTargets.all {
            guard let entry = matrix.entries.first(where: { $0.targetKey == target.key }) else {
                XCTFail("Missing matrix entry for \(target.key)")
                continue
            }

            let appPath = roots
                .map { $0.appendingPathComponent("\(target.containingAppName).app") }
                .first { FileManager.default.fileExists(atPath: $0.path) }

            if appPath == nil {
                continue
            }

            let scannerCheck = entry.results.first {
                $0.check == .scannerFindsInstalledTarget
            }
            XCTAssertTrue(scannerCheck?.passed ?? false, scannerCheck?.detail ?? "missing check")

            let importCheck = entry.results.first {
                $0.check == .importSourceResolvable
            }
            XCTAssertTrue(importCheck?.passed ?? false, importCheck?.detail ?? "missing check")

            let reconcileCheck = entry.results.first {
                $0.check == .contentScriptTabReconcileWired
            }
            XCTAssertTrue(reconcileCheck?.passed ?? false, reconcileCheck?.detail ?? "missing check")

            installedTargetSummaries.append(
                "\(target.key): scanner=\(scannerCheck?.passed == true) import=\(importCheck?.passed == true) classifications=\(entry.nativeMessagingClassifications.map(\.rawValue).joined(separator: ","))"
            )
        }

        if installedTargetSummaries.isEmpty == false {
            print("Cycle8 live acceptance matrix: \(installedTargetSummaries.joined(separator: "; "))")
        }
    }

    private func makeInstalledExtension(
        id: String,
        isEnabled: Bool,
        sourceBundlePath: String
    ) -> InstalledExtension {
        let activationSummary = ExtensionActivationSummary(
            matchPatternStrings: ["<all_urls>"],
            broadScope: true,
            hasContentScripts: true,
            hasAction: true,
            hasOptionsPage: false,
            hasExtensionPages: true
        )
        return InstalledExtension(
            id: id,
            name: "Extension",
            version: "1.0",
            manifestVersion: 3,
            description: nil,
            isEnabled: isEnabled,
            installDate: Date(),
            lastUpdateDate: Date(),
            packagePath: "/tmp/sumi/\(UUID().uuidString)",
            iconPath: nil,
            sourceKind: .safariAppExtension,
            backgroundModel: .serviceWorker,
            incognitoMode: .spanning,
            sourcePathFingerprint: "src-fp",
            manifestRootFingerprint: "fp",
            sourceBundlePath: sourceBundlePath,
            optionsPagePath: nil,
            defaultPopupPath: "popup.html",
            hasBackground: true,
            hasAction: true,
            hasOptionsPage: false,
            hasContentScripts: true,
            hasExtensionPages: true,
            activationSummary: activationSummary,
            manifest: ["manifest_version": 3]
        )
    }

    private func makeCandidate(
        bundleID: String,
        appexPath: String
    ) -> DiscoveredSafariExtensionCandidate {
        let appexURL = URL(fileURLWithPath: appexPath)
        return DiscoveredSafariExtensionCandidate(
            extensionBundleIdentifier: bundleID,
            displayName: "Bitwarden",
            version: "1.0",
            extensionPointIdentifier: SafariExtensionScanner.safariWebExtensionPointIdentifier,
            containingAppName: "Bitwarden",
            containingAppBundleIdentifier: "com.bitwarden.desktop",
            containingAppURL: URL(fileURLWithPath: "/Applications/Bitwarden.app"),
            appexURL: appexURL,
            manifestURL: appexURL.appendingPathComponent("Contents/manifest.json"),
            isReadable: true
        )
    }
}

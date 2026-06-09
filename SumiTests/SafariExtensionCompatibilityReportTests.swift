import XCTest

@testable import Sumi

@MainActor
final class SafariExtensionCompatibilityReportTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var importStore: SafariExtensionImportStore!

    override func setUp() {
        suiteName = "SafariExtensionCompatibilityReportTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        importStore = SafariExtensionImportStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        suiteName = nil
        defaults = nil
        importStore = nil
    }

    func testReportMarksUndiscoveredTarget() {
        let report = SafariExtensionCompatibilityReportBuilder.build(
            targets: [SafariExtensionCompatibilityTargets.all[0]],
            discovered: [],
            importStore: importStore
        )

        XCTAssertEqual(report.entries.count, 1)
        XCTAssertEqual(report.entries[0].targetKey, "bitwarden")
        XCTAssertFalse(report.entries[0].isDiscovered)
        XCTAssertEqual(report.entries[0].lastErrorBucket, .notDiscovered)
    }

    func testReportMarksImportedDisabledExtension() throws {
        let candidate = try makeCandidate(
            bundleID: "com.bitwarden.desktop.safari",
            appexPath: "/tmp/bitwarden.appex"
        )
        importStore.markImported(
            extensionBundleIdentifier: candidate.extensionBundleIdentifier,
            appexPath: candidate.appexURL.path,
            installedExtensionId: "ext-bitwarden"
        )

        let activationSummary = ExtensionActivationSummary(
            matchPatternStrings: ["<all_urls>"],
            broadScope: true,
            hasContentScripts: true,
            hasAction: true,
            hasOptionsPage: false,
            hasExtensionPages: true
        )
        let installed = InstalledExtension(
            id: "ext-bitwarden",
            name: "Bitwarden",
            version: "1.0",
            manifestVersion: 3,
            description: nil,
            isEnabled: false,
            installDate: Date(),
            lastUpdateDate: Date(),
            packagePath: "/tmp/sumi/ext-bitwarden",
            iconPath: nil,
            sourceKind: .safariAppExtension,
            backgroundModel: .serviceWorker,
            incognitoMode: .spanning,
            sourcePathFingerprint: "src-fp",
            manifestRootFingerprint: "fp",
            sourceBundlePath: candidate.appexURL.path,
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

        let report = SafariExtensionCompatibilityReportBuilder.build(
            targets: [SafariExtensionCompatibilityTargets.all[0]],
            discovered: [candidate],
            importStore: importStore,
            installedExtensions: [installed]
        )

        XCTAssertTrue(report.entries[0].isDiscovered)
        XCTAssertTrue(report.entries[0].isImported)
        XCTAssertEqual(report.entries[0].installedExtensionId, "ext-bitwarden")
        XCTAssertFalse(report.entries[0].isEnabled)
        XCTAssertEqual(report.entries[0].lastErrorBucket, .disabled)
    }

    func testReportPopupLoadStatusNotApplicableWithoutPopup() throws {
        let candidate = try makeCandidate(
            bundleID: "io.raindrop.safari.extension",
            appexPath: "/tmp/raindrop.appex"
        )

        let report = SafariExtensionCompatibilityReportBuilder.build(
            targets: [SafariExtensionCompatibilityTargets.all[3]],
            discovered: [candidate],
            importStore: importStore
        )

        XCTAssertEqual(report.entries[0].popupLoadStatus, .notApplicable)
    }

    func testReportPopupLoadStatusUnavailableWhenDisabled() throws {
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

        let report = SafariExtensionCompatibilityReportBuilder.build(
            targets: [SafariExtensionCompatibilityTargets.all[0]],
            discovered: [candidate],
            importStore: importStore,
            installedExtensions: [installed]
        )

        XCTAssertEqual(report.entries[0].popupLoadStatus, .unavailable)
        XCTAssertEqual(report.entries[0].safariRuntimeLoadSource, .copiedPackage)
    }

    func testResolvePopupLoadStatusLoadedWhenActionPresentsPopup() throws {
        let installed = try makeInstalledExtension(
            id: "ext-1password",
            isEnabled: true,
            sourceBundlePath: "/tmp/1password.appex"
        )
        let actionState = BrowserExtensionActionSurfaceState(
            extensionID: installed.id,
            label: "1Password",
            badgeText: "",
            hasUnreadBadgeText: false,
            isEnabled: true,
            presentsPopup: true,
            icon: nil
        )

        let status = SafariExtensionCompatibilityReportBuilder.resolvePopupLoadStatus(
            installed: installed,
            isEnabled: true,
            isContextLoaded: true,
            isActionAvailable: true,
            actionState: actionState,
            extensionsModuleEnabled: true,
            lastErrorBucket: .none
        )

        XCTAssertEqual(status, .loaded)
    }

    func testResolvePopupLoadStatusEmptyWhenPopupResourceExistsButNotSurfaced() throws {
        let popupDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: popupDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: popupDirectory) }

        let popupFile = popupDirectory.appendingPathComponent("popup.html")
        try Data("popup".utf8).write(to: popupFile)

        let installed = try makeInstalledExtension(
            id: "ext-bitwarden",
            isEnabled: true,
            packagePath: popupDirectory.path,
            sourceBundlePath: "/tmp/bitwarden.appex"
        )

        let status = SafariExtensionCompatibilityReportBuilder.resolvePopupLoadStatus(
            installed: installed,
            isEnabled: true,
            isContextLoaded: true,
            isActionAvailable: true,
            actionState: nil,
            extensionsModuleEnabled: true,
            lastErrorBucket: .none
        )

        XCTAssertEqual(status, .empty)
    }

    func testEnablePathReconcilesOpenTabsForContentScripts() throws {
        let profilesSource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "Sumi/Managers/ExtensionManager/ExtensionManager+Profiles.swift"
                ),
            encoding: .utf8
        )
        let uiSource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift"
                ),
            encoding: .utf8
        )

        XCTAssertTrue(profilesSource.contains("reconcileOpenTabsAfterExtensionContextLoad"))
        XCTAssertTrue(uiSource.contains("reconcileOpenTabsAfterExtensionContextLoad"))
        XCTAssertTrue(uiSource.contains("finalizeEnabledExtensionRuntime"))
    }

    func testReportIncludesNativeMessagingClassificationsForPasswordManagers() throws {
        let report = SafariExtensionCompatibilityReportBuilder.build(
            discovered: [],
            importStore: importStore
        )

        XCTAssertEqual(report.platformBlockers, [])
        XCTAssertFalse(report.sdkProbeNote.isEmpty)
        XCTAssertTrue(
            report.nativeMessagingClassifications.contains(.wkWebExtensionAppMessagingAvailable)
        )

        let bitwarden = report.entries.first { $0.targetKey == "bitwarden" }
        let raindrop = report.entries.first { $0.targetKey == "raindrop" }
        XCTAssertTrue(
            bitwarden?.nativeMessagingClassifications.contains(.companionAppProtocolUnknown) ?? false
        )
        XCTAssertFalse(
            raindrop?.nativeMessagingClassifications.contains(.companionAppProtocolUnknown) ?? true
        )
        XCTAssertEqual(bitwarden?.platformBlockers, [])
        XCTAssertEqual(raindrop?.platformBlockers, [])
    }

    func testReportMarksModuleDisabled() throws {
        let candidate = try makeCandidate(
            bundleID: "com.bitwarden.desktop.safari",
            appexPath: "/tmp/bitwarden.appex"
        )

        let report = SafariExtensionCompatibilityReportBuilder.build(
            targets: [SafariExtensionCompatibilityTargets.all[0]],
            discovered: [candidate],
            importStore: importStore,
            extensionsModuleEnabled: false
        )

        XCTAssertEqual(report.entries[0].lastErrorBucket, .moduleDisabled)
    }

    func testRealBundleProbeRecordsExpectedIdentifiersWhenPresent() throws {
        let roots = SafariExtensionScanner.defaultApplicationSearchRoots()
        let scanner = SafariExtensionScanner()
        var issues: [SafariExtensionScannerIssue] = []
        let discovered = scanner.scanInstalledExtensions(
            applicationSearchRoots: roots,
            issues: &issues
        )

        for target in SafariExtensionCompatibilityTargets.all {
            let appPath = roots
                .map { $0.appendingPathComponent("\(target.containingAppName).app") }
                .first { FileManager.default.fileExists(atPath: $0.path) }

            if appPath == nil {
                continue
            }

            let match = discovered.first {
                $0.extensionBundleIdentifier == target.expectedAppexBundleIdentifier
            }
            XCTAssertNotNil(
                match,
                "Expected Safari Web Extension \(target.expectedAppexBundleIdentifier) in \(target.containingAppName)"
            )
            XCTAssertEqual(match?.extensionPointIdentifier, SafariExtensionScanner.safariWebExtensionPointIdentifier)
        }
    }

    private func makeInstalledExtension(
        id: String,
        isEnabled: Bool,
        packagePath: String = "/tmp/sumi/\(UUID().uuidString)",
        sourceBundlePath: String
    ) throws -> InstalledExtension {
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
            packagePath: packagePath,
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
    ) throws -> DiscoveredSafariExtensionCandidate {
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

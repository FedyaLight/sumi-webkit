import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionAutofillInfrastructureTests: XCTestCase {
    func testInfrastructureClassificationPassesWhenModuleEnabled() {
        let result = SafariExtensionAutofillInfrastructureClassifier.classifyInfrastructure(
            extensionsModuleEnabled: true
        )
        XCTAssertEqual(result.primaryBlocker, .none)
        XCTAssertTrue(result.isReady)
    }

    func testInfrastructureClassificationWhenModuleDisabled() {
        let result = SafariExtensionAutofillInfrastructureClassifier.classifyInfrastructure(
            extensionsModuleEnabled: false
        )
        XCTAssertEqual(result.primaryBlocker, .extensionsModuleDisabled)
    }

    func testFileURLClassifiedAsHostPermissionDeniedForAllURLs() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )
        let installed = try await installProbeExtension(manager: manager)
        _ = try await manager.enableExtension(installed.id)
        manager.setDefaultSiteAccess(
            .allow,
            extensionId: installed.id,
            profileId: profile.id
        )
        let loadedContext = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let context = try XCTUnwrap(loadedContext)

        let blocker = SafariExtensionAutofillInfrastructureClassifier.hostPermissionBlocker(
            for: URL(fileURLWithPath: "/tmp/login-form.html"),
            installedExtension: installed,
            extensionContext: context
        )
        XCTAssertEqual(blocker, .hostPermissionDenied)
    }

    func testHTTPSLocalhostPassesHostPermissionWithAllURLs() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )
        let installed = try await installProbeExtension(manager: manager)
        _ = try await manager.enableExtension(installed.id)
        manager.setDefaultSiteAccess(
            .allow,
            extensionId: installed.id,
            profileId: profile.id
        )
        let loadedContext = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let context = try XCTUnwrap(loadedContext)

        let blocker = SafariExtensionAutofillInfrastructureClassifier.hostPermissionBlocker(
            for: URL(string: "http://127.0.0.1:8765/login-form.html")!,
            installedExtension: installed,
            extensionContext: context
        )
        XCTAssertNil(blocker)
    }

    func testClassifySiteSpecificURLDoesNotPreemptivelyBlockProductionSites() {
        let blocker = SafariExtensionAutofillInfrastructureClassifier.classifySiteSpecificURL(
            URL(string: "https://example.com/login")!
        )
        XCTAssertNil(blocker)
    }

    func testClassifyTabReportsPrivateTabBlocked() async throws {
        let container = try makeTestContainer()
        let profile = Profile.createEphemeral()
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )
        let browserManager = makeSafariExtensionTestBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)
        manager.extensionsLoaded = true
        let installed = try await installProbeExtension(manager: manager)
        let tab = Tab(
            url: URL(string: "http://127.0.0.1/login-form.html")!,
            name: "Private"
        )
        tab.profileId = profile.id
        tab.attachBrowserRuntime(browserManager.makeTabBrowserRuntime())

        let result = SafariExtensionAutofillInfrastructureClassifier.classifyTab(
            tab: tab,
            installedExtension: installed,
            extensionContext: nil,
            extensionManager: manager,
            extensionsModuleEnabled: true
        )
        XCTAssertEqual(result.primaryBlocker, .privateTabBlocked)
    }

    func testClassifyTabReportsMissingControllerOnLoadedHTTPSPage() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let browserConfiguration = BrowserConfiguration()
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: browserConfiguration
        )
        let browserManager = makeSafariExtensionTestBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        _ = manager.ensureExtensionController(for: profile.id)
        manager.extensionsLoaded = true

        let installed = try await installProbeExtension(manager: manager)
        _ = try await manager.enableExtension(installed.id)
        manager.setDefaultSiteAccess(
            .allow,
            extensionId: installed.id,
            profileId: profile.id
        )
        let loadedExtensionContext = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(loadedExtensionContext)

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        let tab = Tab(
            url: URL(string: "http://127.0.0.1/login-form.html")!,
            name: "Loaded"
        )
        tab.profileId = profile.id
        tab.attachBrowserRuntime(browserManager.makeTabBrowserRuntime())
        tab.extensionPageRuntimeOwner.eligibleGeneration = manager.tabOpenNotificationGeneration
        _ = manager.stableAdapter(for: tab)

        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab._webView = webView
        webView.load(
            URLRequest(url: URL(string: "http://127.0.0.1/login-form.html")!)
        )

        let result = SafariExtensionAutofillInfrastructureClassifier.classifyTab(
            tab: tab,
            installedExtension: installed,
            extensionContext: extensionContext,
            extensionManager: manager,
            extensionsModuleEnabled: true
        )
        XCTAssertEqual(result.primaryBlocker, .targetWebViewMissingExtensionController)
    }

    func testClassifyTabReadyForWiredNormalTab() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let browserConfiguration = BrowserConfiguration()
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: browserConfiguration
        )
        let browserManager = makeSafariExtensionTestBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        let expectedController = manager.ensureExtensionController(for: profile.id)
        manager.extensionsLoaded = true

        let installed = try await installProbeExtension(manager: manager)
        _ = try await manager.enableExtension(installed.id)
        manager.setDefaultSiteAccess(
            .allow,
            extensionId: installed.id,
            profileId: profile.id
        )
        let loadedExtensionContext = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(loadedExtensionContext)

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionAutofillInfrastructureTests"
        )

        let tab = Tab(
            url: URL(string: "http://127.0.0.1/login-form.html")!,
            name: "Ready"
        )
        tab.profileId = profile.id
        tab.attachBrowserRuntime(browserManager.makeTabBrowserRuntime())
        tab.extensionPageRuntimeOwner.eligibleGeneration = manager.tabOpenNotificationGeneration

        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab._webView = webView
        _ = manager.stableAdapter(for: tab)

        let result = SafariExtensionAutofillInfrastructureClassifier.classifyTab(
            tab: tab,
            installedExtension: installed,
            extensionContext: extensionContext,
            extensionManager: manager,
            extensionsModuleEnabled: true
        )
        XCTAssertEqual(result.primaryBlocker, .none, result.detail)
        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            expectedController
        )
    }

    func testRuntimeDiagnosticReportIncludesAutofillInfrastructureBlocker() {
        let report = SafariExtensionRuntimeDiagnosticsBuilder.build(
            targets: [SafariExtensionCompatibilityTargets.all[0]],
            discovered: [],
            importStore: EmptySafariExtensionImportRecordProvider(),
            extensionsModuleEnabled: true
        )
        XCTAssertEqual(
            report.entries[0].runtimeStatus.autofillInfrastructureBlocker,
            .none
        )
    }

    private func installProbeExtension(
        manager: ExtensionManager
    ) async throws -> InstalledExtension {
        let scratchDirectory = try makeScratchDirectory()
        let directoryURL = scratchDirectory.appendingPathComponent(
            "AutofillInfrastructureProbe",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "AutofillInfrastructureProbe",
            "version": "1.0",
            "host_permissions": ["<all_urls>"],
            "content_scripts": [[
                "matches": ["<all_urls>"],
                "js": ["content.js"],
                "run_at": "document_idle",
            ]],
        ]
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: manifestURL, options: [.atomic])
        try Data("true;".utf8)
            .write(to: directoryURL.appendingPathComponent("content.js"), options: [.atomic])

        return try await manager.performInstallation(
            from: directoryURL,
            enableOnInstall: false
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

    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}

private final class EmptySafariExtensionImportRecordProvider: SafariExtensionImportRecordProviding {
    func importedRecords() -> [SafariExtensionImportedRecord] {
        []
    }
}

import XCTest

@testable import Sumi

@MainActor
final class SumiUpdaterServiceTests: XCTestCase {
    func testServiceMapsBackendStateWithoutNetwork() {
        let backend = FakeUpdaterBackend()
        backend.canCheckForUpdates = true
        backend.automaticallyChecksForUpdates = true
        backend.lastUpdateCheckDate = Date(timeIntervalSince1970: 1_700_000_000)
        backend.feedURL = URL(string: "https://example.com/appcast-alpha.xml")

        let service = makeService(backend: backend)
        service.start()

        XCTAssertEqual(backend.startCount, 1)
        XCTAssertTrue(service.state.canCheckForUpdates)
        XCTAssertTrue(service.state.automaticallyChecksForUpdates)
        XCTAssertEqual(service.state.lastCheckedAt, backend.lastUpdateCheckDate)
        XCTAssertEqual(service.state.feedURL, backend.feedURL)
        XCTAssertTrue(service.state.isSparkleAvailable)
        XCTAssertTrue(service.state.isConfigured)
    }

    func testUserCheckRoutesToBackend() {
        let backend = FakeUpdaterBackend()
        backend.canCheckForUpdates = true
        let service = makeService(backend: backend)

        service.checkForUpdatesFromUserAction()

        XCTAssertEqual(backend.startCount, 1)
        XCTAssertEqual(backend.informationCheckCount, 1)
    }

    func testBackgroundCheckDoesNotRunWhenAutomaticChecksAreDisabled() {
        let backend = FakeUpdaterBackend()
        backend.canCheckForUpdates = true
        backend.automaticallyChecksForUpdates = false
        let service = makeService(backend: backend)

        service.checkForUpdatesInBackgroundIfAllowed()

        XCTAssertEqual(backend.informationCheckCount, 0)

        service.setAutomaticallyChecksForUpdates(true)
        service.checkForUpdatesInBackgroundIfAllowed()

        XCTAssertEqual(backend.informationCheckCount, 1)
    }

    func testAboutViewStartsBackgroundCheckIndependentOfAutomaticChecks() {
        let backend = FakeUpdaterBackend()
        backend.canCheckForUpdates = true
        backend.automaticallyChecksForUpdates = false
        let service = makeService(backend: backend)

        service.checkForUpdatesFromAboutView()

        XCTAssertEqual(backend.startCount, 1)
        XCTAssertEqual(backend.informationCheckCount, 1)
        XCTAssertTrue(service.state.isCheckingForUpdates)
    }

    func testSidebarUpdateActionRoutesToBackendInstall() {
        let backend = FakeUpdaterBackend()
        backend.canCheckForUpdates = true
        let service = makeService(backend: backend)

        service.startUpdateFromSidebarNotice()

        XCTAssertEqual(backend.startCount, 1)
        XCTAssertEqual(backend.installCount, 1)
    }

    func testSidebarNoticeVisibilityAndPerVersionDismissalRules() {
        let store = FakeDismissalStore()
        let first = update(displayVersion: "1.0.0", buildVersion: "100")
        let second = update(displayVersion: "1.0.1", buildVersion: "101")

        XCTAssertNil(
            SumiUpdateNoticeVisibilityResolver.sidebarNotice(
                availability: .none,
                operationNotice: nil,
                installedUpdate: nil,
                dismissalStore: store
            )
        )

        let firstNotice = SumiUpdateNoticeVisibilityResolver.sidebarNotice(
            availability: .available(first),
            operationNotice: nil,
            installedUpdate: nil,
            dismissalStore: store
        )
        XCTAssertEqual(firstNotice, .available(first))

        let operation = SumiUpdateOperationNotice(
            stage: .downloading,
            title: "Updating Sumi",
            detail: "Downloading Sumi 1.0.0...",
            progress: nil
        )
        XCTAssertEqual(
            SumiUpdateNoticeVisibilityResolver.sidebarNotice(
                availability: .available(first),
                operationNotice: operation,
                installedUpdate: nil,
                dismissalStore: store
            ),
            .operation(operation)
        )

        store.dismissNotice(identifier: first.noticeIdentifier)
        XCTAssertNil(
            SumiUpdateNoticeVisibilityResolver.sidebarNotice(
                availability: .available(first),
                operationNotice: nil,
                installedUpdate: nil,
                dismissalStore: store
            )
        )

        let secondNotice = SumiUpdateNoticeVisibilityResolver.sidebarNotice(
            availability: .available(second),
            operationNotice: nil,
            installedUpdate: nil,
            dismissalStore: store
        )
        XCTAssertEqual(secondNotice, .available(second))
    }

    func testInstalledVersionChangeShowsSuccessSidebarNoticeOnce() {
        let store = FakeInstalledUpdateStore(
            notice: SumiInstalledUpdate(displayVersion: "2.0.0", buildVersion: "200")
        )
        let service = makeService(installedUpdateStore: store)

        XCTAssertEqual(
            service.sidebarNotice,
            .installed(SumiInstalledUpdate(displayVersion: "2.0.0", buildVersion: "200"))
        )

        service.dismissSidebarNotice(
            .installed(SumiInstalledUpdate(displayVersion: "2.0.0", buildVersion: "200"))
        )

        XCTAssertNil(service.sidebarNotice)
    }

    func testInstalledUpdateStoreShowsSuccessOnlyForNewerVersionOrBuild() throws {
        let suiteName = "SumiUpdaterServiceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SumiInstalledUpdateNoticeStore(userDefaults: defaults, key: "lastSeen")

        XCTAssertNil(
            store.consumeInstalledUpdateNotice(
                current: SumiAppVersionMetadata(displayName: "Sumi", shortVersion: "1.0.0", buildNumber: "100")
            )
        )
        XCTAssertEqual(defaults.string(forKey: "lastSeen"), "1.0.0|100")

        XCTAssertEqual(
            store.consumeInstalledUpdateNotice(
                current: SumiAppVersionMetadata(displayName: "Sumi", shortVersion: "1.0.1", buildNumber: "101")
            ),
            SumiInstalledUpdate(displayVersion: "1.0.1", buildVersion: "101")
        )

        XCTAssertNil(
            store.consumeInstalledUpdateNotice(
                current: SumiAppVersionMetadata(displayName: "Sumi", shortVersion: "1.0.0", buildNumber: "100")
            )
        )

        XCTAssertEqual(
            store.consumeInstalledUpdateNotice(
                current: SumiAppVersionMetadata(displayName: "Sumi", shortVersion: "1.0.0", buildNumber: "101")
            ),
            SumiInstalledUpdate(displayVersion: "1.0.0", buildVersion: "101")
        )
    }

    func testServiceDismissesOnlyCurrentAvailableVersionOrBuild() {
        let store = FakeDismissalStore()
        let service = makeService(dismissalStore: store)
        let available = update(displayVersion: "1.2.0", buildVersion: "120")

        service.recordAvailableUpdate(available)
        XCTAssertNotNil(service.sidebarNotice)

        service.dismissUpdateNotice(forVersion: "older")
        XCTAssertNotNil(service.sidebarNotice)

        service.dismissUpdateNotice(forVersion: "120")
        XCTAssertNil(service.sidebarNotice)
        XCTAssertEqual(store.dismissedNoticeIdentifier(), available.noticeIdentifier)
    }

    func testDismissalStorePersistsPerVersionBuildIdentifier() throws {
        let suiteName = "SumiUpdaterServiceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SumiUpdateNoticeDismissalStore(userDefaults: defaults, key: "dismissed")
        let identifier = SumiUpdateNoticeIdentifier(displayVersion: "2.0.0", buildVersion: "200")

        XCTAssertNil(store.dismissedNoticeIdentifier())
        store.dismissNotice(identifier: identifier)

        XCTAssertEqual(store.dismissedNoticeIdentifier(), identifier)
        XCTAssertNotEqual(
            store.dismissedNoticeIdentifier(),
            SumiUpdateNoticeIdentifier(displayVersion: "2.0.1", buildVersion: "201")
        )
    }

    func testAboutViewModelFormatsVersionBuildAndRoutesCheckAction() {
        let metadata = SumiAppVersionMetadata.resolve(
            infoDictionary: [
                "CFBundleDisplayName": "Sumi",
                "CFBundleShortVersionString": "3.4.5",
                "CFBundleVersion": "345",
            ]
        )
        var state = SumiUpdateState.initial(channel: .alpha)
        state.canCheckForUpdates = true
        state.isSparkleAvailable = true
        state.isConfigured = true
        var didCheck = false

        let viewModel = SumiAboutUpdateViewModel(
            metadata: metadata,
            state: state,
            checkForUpdates: { didCheck = true }
        )

        XCTAssertEqual(viewModel.metadata.summaryLine, "Version 3.4.5 / Build 345")
        XCTAssertEqual(viewModel.channelDisplayName, "Alpha")
        XCTAssertTrue(viewModel.checkButtonIsEnabled)
        XCTAssertEqual(viewModel.panelState, .ready)

        viewModel.checkForUpdates()

        XCTAssertTrue(didCheck)
    }

    func testAboutViewModelMapsSinglePanelStates() {
        let metadata = SumiAppVersionMetadata.resolve(
            infoDictionary: [
                "CFBundleDisplayName": "Sumi",
                "CFBundleShortVersionString": "3.4.5",
                "CFBundleVersion": "345",
            ]
        )
        let update = update(displayVersion: "3.5.0", buildVersion: "350")

        var state = SumiUpdateState.initial(channel: .alpha)
        state.isSparkleAvailable = true
        state.isConfigured = true

        state.isCheckingForUpdates = true
        XCTAssertEqual(
            SumiAboutUpdateViewModel(metadata: metadata, state: state, checkForUpdates: { /* no-op */ }).panelState,
            .checking
        )

        state.isCheckingForUpdates = false
        state.availability = .available(update)
        XCTAssertEqual(
            SumiAboutUpdateViewModel(metadata: metadata, state: state, checkForUpdates: { /* no-op */ }).panelState,
            .updateAvailable(update)
        )

        state.availability = .none
        state.lastCheckedAt = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            SumiAboutUpdateViewModel(metadata: metadata, state: state, checkForUpdates: { /* no-op */ }).panelState,
            .upToDate
        )

        state.lastCheckedAt = nil
        state.diagnosticMessage = "Network unavailable"
        XCTAssertEqual(
            SumiAboutUpdateViewModel(metadata: metadata, state: state, checkForUpdates: { /* no-op */ }).panelState,
            .checkFailed("Network unavailable")
        )
    }

    func testInfoPlistUsesAlphaAppcastAndPublicEdDSAKey() throws {
        let plist = try infoPlist()
        XCTAssertEqual(
            plist["SUFeedURL"] as? String,
            "https://fedyalight.github.io/sumi-webkit/appcast-alpha.xml"
        )
        let publicKey = try XCTUnwrap(plist["SUPublicEDKey"] as? String)
        XCTAssertFalse(publicKey.isEmpty)
        XCTAssertNotEqual(publicKey, "REPLACE_ME")
        XCTAssertEqual(plist["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        XCTAssertEqual(plist["SUEnableSystemProfiling"] as? Bool, false)
    }

    func testSettingsAboutAndAppMenuRouteManualChecksThroughUpdaterService() throws {
        let aboutSource = try combinedSource(relativePaths: ["Sumi/Components/Settings/Tabs/About.swift"])
        XCTAssertTrue(
            aboutSource.contains("updaterService.checkForUpdatesFromAboutView()"),
            "Settings > About must start a background update check through SumiUpdaterService."
        )
        XCTAssertTrue(
            aboutSource.contains("checkForUpdates: { updaterService.startUpdateFromSidebarNotice() }"),
            "Settings > About update action must route through SumiUpdaterService."
        )

        let commandSource = try combinedSource(relativePaths: ["App/SumiCommands.swift"])
        XCTAssertTrue(
            commandSource.contains("SumiCheckForUpdatesCommand(updaterService: SumiUpdaterService.shared)"),
            "App menu must use the shared updater service command view."
        )
        XCTAssertTrue(
            commandSource.contains("updaterService.checkForUpdatesFromUserAction()"),
            "App menu check command must route through SumiUpdaterService."
        )

        let updateSource = try combinedSource(relativePaths: ["Sumi/Updates/SumiUpdaterService.swift"])
        XCTAssertTrue(
            updateSource.contains("updater.checkForUpdateInformation()"),
            "Manual discovery should use Sparkle probing checks so update availability is shown in the sidebar."
        )
        XCTAssertFalse(
            updateSource.contains("SPUStandardUpdaterController"),
            "Update availability must not be routed through Sparkle's standard alert UI."
        )
    }

    func testSourceGuardsPreventCustomUpdaterAndSecurityBypassCode() throws {
        let updateSource = try combinedSource(relativePaths: ["Sumi/Updates"])
        assertExcludes(
            updateSource,
            [
                "URLSession",
                "Process(",
                "FileManager.default.moveItem",
                "FileManager.default.replaceItem",
                "NSWorkspace.shared.launchApplication",
            ],
            context: "updater layer"
        )

        let appSource = try combinedSource(relativePaths: ["App", "Sumi", "Settings", "Navigation", "UI", "FloatingBar"])
        assertExcludes(
            appSource,
            ["x" + "attr"],
            context: "app executable source"
        )
    }

    func testSourceGuardsPreventUserLocalAbsolutePaths() throws {
        let source = try combinedSource(
            relativePaths: [
                ".github",
                "App",
                "Sumi",
                "SumiTests",
                "Settings",
                "Navigation",
                "UI",
                "FloatingBar",
                "docs/UPDATES.md",
                "docs/RELEASES.md",
                "docs/appcast-alpha.xml",
                "docs/appcast.xml",
                "docs/roadmap.md",
                "docs/demo-script.md",
                "docs/architecture.md",
                "scripts",
                "Sumi.xcodeproj/project.pbxproj",
                "Sumi.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
                "README.md",
                "SECURITY.md",
                ".gitignore",
            ]
        )

        assertExcludes(
            source,
            [
                "/" + "Users/",
                "file:///" + "Users/",
            ],
            context: "committable source and release files"
        )
    }

    func testRuntimeDoesNotContainLocalFeedOverride() throws {
        let runtimeSurface = try combinedSource(
            relativePaths: [
                "Sumi/Updates",
                "Sumi/Info.plist",
                "App/SumiCommands.swift",
                "Sumi/Components/Settings/Tabs/About.swift",
                "Sumi/Components/Sidebar/SumiUpdateSidebarNoticeView.swift",
                "Navigation/Sidebar/SpacesSideBarView.swift",
            ]
        )

        assertExcludes(
            runtimeSurface,
            [
                "SUMI_DEV_SPARKLE_FEED_URL",
                "--sumi-dev-sparkle-feed",
                "dev.sumi.updates.localFeedURL",
                "SumiDeveloperUpdateFeedOverride",
                "appcast-preview.xml",
                "http://localhost",
                "http://127.0.0.1",
                "feedURLString(for updater:",
            ],
            context: "runtime updater surface"
        )
    }

    func testSourceGuardsPreventCommittedSecretsAndCredentialAssumptions() throws {
        let releaseSurface = try combinedSource(
            relativePaths: [
                ".github/workflows",
                "scripts/release",
                "docs",
                "Sumi/Info.plist",
                "README.md",
            ]
        )

        assertExcludes(
            releaseSurface,
            [
                "gh" + "p_",
                "gh" + "s_",
                "github" + "_pat_",
                "BEGIN " + "PRIVATE KEY",
                "BEGIN " + "OPENSSH PRIVATE KEY",
            ],
            context: "release infrastructure"
        )

        let workflows = try combinedSource(relativePaths: [".github/workflows"])
        assertExcludes(
            workflows,
            [
                "APPLE_ID",
                "ASC_KEY",
                "APP_STORE_CONNECT",
                "notarytool",
                "NOTARIZATION",
            ],
            context: "alpha GitHub Actions"
        )
    }

    func testReleaseSurfaceUsesAlphaNamingAndNoLocalUpdateWorkflow() throws {
        let releaseSurface = try combinedSource(
            relativePaths: [
                ".github/workflows",
                "scripts/release",
                "docs/UPDATES.md",
                "docs/RELEASES.md",
                "README.md",
                "Sumi/Info.plist",
            ]
        )

        XCTAssertTrue(releaseSurface.contains("appcast-alpha.xml"))
        XCTAssertTrue(releaseSurface.contains("package_alpha_release.sh"))
        XCTAssertTrue(releaseSurface.contains("generate_alpha_appcast.sh"))
        assertExcludes(
            releaseSurface,
            [
                "package_preview_release.sh",
                "generate_preview_appcast.sh",
                "preview-release.yml",
                "preview-macos.zip",
                "scripts/local-update-test",
                "LOCAL_UPDATE_TESTING.md",
                "Local Sparkle Update Testing",
                "SUMI_DEV_SPARKLE_FEED_URL",
                "--sumi-dev-sparkle-feed",
                "dev.sumi.updates.localFeedURL",
            ],
            context: "current release surface"
        )
    }

    private func makeService(
        dismissalStore: SumiUpdateNoticeDismissalPersisting = FakeDismissalStore(),
        installedUpdateStore: SumiInstalledUpdateNoticePersisting = FakeInstalledUpdateStore(),
        backend: FakeUpdaterBackend = FakeUpdaterBackend()
    ) -> SumiUpdaterService {
        SumiUpdaterService(
            channel: .alpha,
            dismissalStore: dismissalStore,
            installedUpdateStore: installedUpdateStore,
            currentVersion: SumiAppVersionMetadata(displayName: "Sumi", shortVersion: "1.0.0", buildNumber: "100"),
            backend: backend,
            backendFactory: { _ in backend }
        )
    }

    private func update(displayVersion: String, buildVersion: String) -> SumiAvailableUpdate {
        SumiAvailableUpdate(
            displayVersion: displayVersion,
            buildVersion: buildVersion,
            title: nil,
            subtitle: "Improvements and fixes",
            releaseNotesURL: URL(string: "https://example.com/releases/\(displayVersion)"),
            isInformationOnly: false
        )
    }

    private func assertExcludes(
        _ source: String,
        _ forbiddenStrings: [String],
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for forbiddenString in forbiddenStrings {
            XCTAssertFalse(
                source.contains(forbiddenString),
                "\(context) must not contain \(forbiddenString)",
                file: file,
                line: line
            )
        }
    }

    private func combinedSource(relativePaths: [String]) throws -> String {
        let root = repositoryRoot()
        var chunks: [String] = []

        for relativePath in relativePaths {
            let url = root.appendingPathComponent(relativePath)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }

            if isDirectory.boolValue {
                for fileURL in try sourceFiles(under: url) {
                    chunks.append(try String(contentsOf: fileURL, encoding: .utf8))
                }
            } else {
                chunks.append(try String(contentsOf: url, encoding: .utf8))
            }
        }

        return chunks.joined(separator: "\n")
    }

    private func sourceFiles(under directory: URL) throws -> [URL] {
        let allowedExtensions: Set<String> = ["swift", "sh", "yml", "yaml", "md", "xml", "plist", "pbxproj", "resolved"]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item in
            guard let fileURL = item as? URL else { return nil }
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { return nil }
            guard allowedExtensions.contains(fileURL.pathExtension) else { return nil }
            return fileURL
        }
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func infoPlist() throws -> [String: Any] {
        let url = repositoryRoot().appendingPathComponent("Sumi/Info.plist")
        let data = try Data(contentsOf: url)
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(object as? [String: Any])
    }
}

@MainActor
private final class FakeUpdaterBackend: SumiUpdaterBackend {
    var canCheckForUpdates = false
    var automaticallyChecksForUpdates = false
    var lastUpdateCheckDate: Date?
    var feedURL: URL?
    var isSparkleAvailable = true
    var isConfigured = true

    private(set) var startCount = 0
    private(set) var informationCheckCount = 0
    private(set) var installCount = 0

    func start() {
        startCount += 1
    }

    func checkForUpdateInformation() {
        informationCheckCount += 1
    }

    func installAvailableUpdate() {
        installCount += 1
    }
}

private final class FakeDismissalStore: SumiUpdateNoticeDismissalPersisting {
    private var identifier: SumiUpdateNoticeIdentifier?
    private var installedIdentifier: SumiUpdateNoticeIdentifier?

    func dismissedNoticeIdentifier() -> SumiUpdateNoticeIdentifier? {
        identifier
    }

    func dismissNotice(identifier: SumiUpdateNoticeIdentifier) {
        self.identifier = identifier
    }

    func dismissedInstalledNoticeIdentifier() -> SumiUpdateNoticeIdentifier? {
        installedIdentifier
    }

    func dismissInstalledNotice(identifier: SumiUpdateNoticeIdentifier) {
        installedIdentifier = identifier
    }
}

private struct FakeInstalledUpdateStore: SumiInstalledUpdateNoticePersisting {
    var notice: SumiInstalledUpdate?

    func consumeInstalledUpdateNotice(current _: SumiAppVersionMetadata) -> SumiInstalledUpdate? {
        notice
    }
}

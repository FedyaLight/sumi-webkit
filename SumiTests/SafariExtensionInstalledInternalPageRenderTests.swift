import AppKit
import SwiftData
import WebKit
import XCTest

@testable import Sumi

private actor InstalledExtensionRenderTestLock {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withLock(
        _ operation: @MainActor () async throws -> Void
    ) async rethrows {
        await acquire()
        defer { release() }
        try await operation()
    }

    private func acquire() async {
        if isLocked == false {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard waiters.isEmpty == false else {
            isLocked = false
            return
        }
        waiters.removeFirst().resume()
    }
}

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionInstalledInternalPageRenderTests: XCTestCase {
    private static let onePasswordRenderLock = InstalledExtensionRenderTestLock()

    func testInstalled1PasswordInternalPagesResolveThroughWebKitContext() async throws {
        try await Self.onePasswordRenderLock.withLock {
            let candidate = try installedCandidate(
                extensionBundleIdentifier: "com.1password.safari.extension",
                targetName: "1Password"
            )

            guard let bundle = Bundle(url: candidate.appexURL) else {
                XCTFail("Unable to open installed appex bundle for \(candidate.extensionBundleIdentifier)")
                return
            }

            let webExtension = try await WKWebExtension(appExtensionBundle: bundle)
            let extensionContext = WKWebExtensionContext(for: webExtension)
            let controllerConfiguration = WKWebExtensionController.Configuration.nonPersistent()
            let controller = WKWebExtensionController(configuration: controllerConfiguration)
            try controller.load(extensionContext)
            defer {
                try? controller.unload(extensionContext)
            }

            let welcomeURL = try resolvedInstalledExtensionPageURL(
                candidate: candidate,
                extensionContext: extensionContext,
                pagePath: "app/app.html#/page/welcome?language=ru"
            )
            let migrationURL = try resolvedInstalledExtensionPageURL(
                candidate: candidate,
                extensionContext: extensionContext,
                pagePath: "app/app.html#/page/migration"
            )

            XCTAssertIdentical(controller.extensionContext(for: welcomeURL), extensionContext)
            XCTAssertIdentical(controller.extensionContext(for: migrationURL), extensionContext)
            let configuration = try XCTUnwrap(
                extensionContext.webViewConfiguration,
                "Expected WebKit to provide an extension-page WKWebViewConfiguration"
            )
            XCTAssertIdentical(configuration.webExtensionController, controller)
        }
    }

    func testInstalled1PasswordInternalPagesRenderThroughSumiTabLifecycle() async throws {
        try await Self.onePasswordRenderLock.withLock {
        let candidate = try installedCandidate(
            extensionBundleIdentifier: "com.1password.safari.extension",
            targetName: "1Password"
        )

        let container = try makeTestContainer()
        let profile = Profile(name: "Installed 1Password Profile")
        let browserConfiguration = BrowserConfiguration()
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: browserConfiguration
        )
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule
        )
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.webViewCoordinator = WebViewCoordinator()
        browserManager.tabManager = TabManager(
            browserManager: browserManager,
            context: container.mainContext,
            loadPersistedState: false
        )
        let space = browserManager.tabManager.createSpace(
            name: "Installed 1Password",
            profileId: profile.id
        )
        let windowState = BrowserWindowState()
        windowState.currentProfileId = profile.id
        windowState.currentSpaceId = space.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        manager.attach(browserManager: browserManager)
        _ = manager.requestExtensionRuntime(
            reason: ExtensionManager.ExtensionRuntimeRequestReason.attach,
            allowWithoutEnabledExtensions: true,
            profileId: profile.id
        )

        guard let bundle = Bundle(url: candidate.appexURL) else {
            XCTFail("Unable to open installed appex bundle for \(candidate.extensionBundleIdentifier)")
            return
        }
        let webExtension = try await WKWebExtension(appExtensionBundle: bundle)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        let controller = manager.ensureExtensionController(for: profile.id)
        let extensionId = candidate.extensionBundleIdentifier

        manager.prepareExtensionContextForRuntime(
            extensionContext,
            extensionId: extensionId,
            profileId: profile.id,
            manifest: webExtension.manifest
        )
        manager.setExtensionContext(
            extensionContext,
            extensionId: extensionId,
            profileId: profile.id
        )
        manager.loadedExtensionManifests[extensionId] = webExtension.manifest
        manager.extensionsLoaded = true

        try controller.load(extensionContext)
        defer {
            try? controller.unload(extensionContext)
        }

        let welcome = try await renderMetricsThroughSumiTab(
            manager: manager,
            controller: controller,
            extensionContext: extensionContext,
            pagePath: "app/app.html#/page/welcome?language=ru"
        )
        XCTAssertTrue(welcome.loadedFromExtensionScheme, welcome.debugSummary)
        XCTAssertEqual(welcome.readyState, "complete", welcome.debugSummary)
        XCTAssertGreaterThan(welcome.elementCount, 0, welcome.debugSummary)
        XCTAssertGreaterThan(welcome.scriptCount, 0, welcome.debugSummary)

        let migration = try await renderMetricsThroughSumiTab(
            manager: manager,
            controller: controller,
            extensionContext: extensionContext,
            pagePath: "app/app.html#/page/migration"
        )
        XCTAssertTrue(migration.loadedFromExtensionScheme, migration.debugSummary)
        XCTAssertEqual(migration.readyState, "complete", migration.debugSummary)
        XCTAssertGreaterThan(migration.elementCount, 0, migration.debugSummary)
        XCTAssertGreaterThan(migration.scriptCount, 0, migration.debugSummary)
        }
    }

    func testInstalledBitwardenAndRaindropPagesRenderThroughWebKitContext() async throws {
        let bitwarden = try installedCandidate(
            extensionBundleIdentifier: "com.bitwarden.desktop.safari",
            targetName: "Bitwarden"
        )
        let bitwardenPopup = try await renderMetrics(
            for: bitwarden,
            pagePath: "popup/index.html"
        )
        XCTAssertTrue(bitwardenPopup.loadedFromExtensionScheme, bitwardenPopup.debugSummary)
        XCTAssertEqual(bitwardenPopup.readyState, "complete", bitwardenPopup.debugSummary)
        XCTAssertGreaterThan(bitwardenPopup.visibleElementCount, 0, bitwardenPopup.debugSummary)

        let raindrop = try installedCandidate(
            extensionBundleIdentifier: "io.raindrop.safari.extension",
            targetName: "Raindrop"
        )
        let raindropAction = try await renderMetrics(
            for: raindrop,
            pagePath: "assets/action_in_iframe.html"
        )
        XCTAssertTrue(raindropAction.loadedFromExtensionScheme, raindropAction.debugSummary)
        XCTAssertEqual(raindropAction.readyState, "complete", raindropAction.debugSummary)
        XCTAssertGreaterThan(raindropAction.visibleElementCount, 0, raindropAction.debugSummary)
    }

    private func installedCandidate(
        extensionBundleIdentifier: String,
        targetName: String
    ) throws -> DiscoveredSafariExtensionCandidate {
        let scanner = SafariExtensionScanner()
        var issues: [SafariExtensionScannerIssue] = []
        let candidates = scanner.scanInstalledExtensions(issues: &issues)

        guard let candidate = candidates.first(where: {
            $0.extensionBundleIdentifier == extensionBundleIdentifier
        }) else {
            throw XCTSkip("\(targetName) Safari Web Extension is not installed")
        }

        return candidate
    }

    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func resolvedInstalledExtensionPageURL(
        candidate: DiscoveredSafariExtensionCandidate,
        extensionContext: WKWebExtensionContext,
        pagePath: String
    ) throws -> URL {
        let resourcePath = pagePath.split(separator: "#", maxSplits: 1).first
            .map(String.init) ?? pagePath
        let resourceURL = candidate.appexURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(resourcePath)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: resourceURL.path),
            "Expected installed extension resource \(resourcePath) for \(candidate.extensionBundleIdentifier)"
        )

        return try XCTUnwrap(
            URL(string: pagePath, relativeTo: extensionContext.baseURL)?.absoluteURL
        )
    }

    private func renderMetrics(
        for candidate: DiscoveredSafariExtensionCandidate,
        pagePath: String
    ) async throws -> InstalledExtensionPageRenderMetrics {
        let resourcePath = pagePath.split(separator: "#", maxSplits: 1).first
            .map(String.init) ?? pagePath
        let resourceURL = candidate.appexURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(resourcePath)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: resourceURL.path),
            "Expected installed extension resource \(resourcePath) for \(candidate.extensionBundleIdentifier)"
        )

        guard let bundle = Bundle(url: candidate.appexURL) else {
            XCTFail("Unable to open installed appex bundle for \(candidate.extensionBundleIdentifier)")
            return .empty
        }

        let webExtension = try await WKWebExtension(appExtensionBundle: bundle)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        let controllerConfiguration = WKWebExtensionController.Configuration.nonPersistent()
        let pageConfiguration = WKWebViewConfiguration()
        pageConfiguration.websiteDataStore = .nonPersistent()
        pageConfiguration.defaultWebpagePreferences.allowsContentJavaScript = true
        controllerConfiguration.webViewConfiguration = pageConfiguration
        controllerConfiguration.defaultWebsiteDataStore = .nonPersistent()

        let controller = WKWebExtensionController(configuration: controllerConfiguration)
        try controller.load(extensionContext)
        defer {
            try? controller.unload(extensionContext)
        }

        let pageURL = try XCTUnwrap(
            URL(string: pagePath, relativeTo: extensionContext.baseURL)?.absoluteURL
        )
        XCTAssertIdentical(
            controller.extensionContext(for: pageURL),
            extensionContext,
            "Extension URL must resolve to the loaded WebKit context"
        )

        let configuration = try XCTUnwrap(
            extensionContext.webViewConfiguration,
            "Expected WebKit to provide an extension-page WKWebViewConfiguration"
        )
        XCTAssertIdentical(
            configuration.webExtensionController,
            controller,
            "Extension page web views must use the context's controller-bound configuration"
        )

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 700),
            configuration: configuration
        )
        webView.load(URLRequest(url: pageURL))

        return try await pollRenderMetrics(in: webView)
    }

    private func renderMetricsThroughSumiTab(
        manager: ExtensionManager,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext,
        pagePath: String
    ) async throws -> InstalledExtensionPageRenderMetrics {
        let pageURL = try XCTUnwrap(
            URL(string: pagePath, relativeTo: extensionContext.baseURL)?.absoluteURL
        )
        let tab = try manager.openExtensionRequestedTab(
            url: pageURL,
            shouldBeActive: true,
            shouldBePinned: false,
            requestedWindow: nil,
            controller: controller,
            reason: "SafariExtensionInstalledInternalPageRenderTests"
        )
        XCTAssertIdentical(tab.webExtensionContextOverride, extensionContext)
        defer {
            tab.performComprehensiveWebViewCleanup()
            manager.browserManager?.tabManager.removeTab(tab.id)
        }
        XCTAssertFalse(
            tab.isUnloaded,
            "Active extension-created internal tab must materialize through window selection"
        )
        let webView = try XCTUnwrap(tab.existingWebView)
        webView.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        XCTAssertIdentical(webView.configuration.webExtensionController, controller)
        XCTAssertIdentical(
            webView.configuration.websiteDataStore,
            controller.configuration.defaultWebsiteDataStore
        )
        return try await pollRenderMetrics(in: webView)
    }

    private func pollRenderMetrics(
        in webView: WKWebView
    ) async throws -> InstalledExtensionPageRenderMetrics {
        var lastMetrics = InstalledExtensionPageRenderMetrics.empty
        for _ in 0..<80 {
            try await Task.sleep(nanoseconds: 100_000_000)
            if let metrics = try? await pageRenderMetrics(in: webView) {
                lastMetrics = metrics
                if metrics.readyState == "complete",
                   metrics.loadedFromExtensionScheme,
                   metrics.elementCount > 0,
                   metrics.scriptCount > 0 {
                    return metrics
                }
            }
        }

        XCTFail("Timed out waiting for extension page resources; \(lastMetrics.debugSummary)")
        return lastMetrics
    }

    private func pageRenderMetrics(
        in webView: WKWebView
    ) async throws -> InstalledExtensionPageRenderMetrics {
        let script = """
            (() => {
              const body = document.body;
              const elementCount = document.querySelectorAll('body *').length;
              const scriptCount = document.scripts.length;
              const visibleCount = Array.from(document.querySelectorAll('body *')).filter((element) => {
                const style = getComputedStyle(element);
                const rect = element.getBoundingClientRect();
                return style.visibility !== 'hidden' && style.display !== 'none' && rect.width > 0 && rect.height > 0;
              }).length;
              return [
                document.readyState,
                body ? body.childElementCount : -1,
                elementCount,
                scriptCount,
                visibleCount,
                location.href.startsWith('webkit-extension://') || location.href.startsWith('safari-web-extension://')
              ].join('|');
            })();
            """
        let rawValue = try await webView.evaluateJavaScript(script) as? String
        return try InstalledExtensionPageRenderMetrics(rawValue: rawValue ?? "")
    }
}

private struct InstalledExtensionPageRenderMetrics: Equatable {
    var readyState: String
    var bodyChildElementCount: Int
    var elementCount: Int
    var scriptCount: Int
    var visibleElementCount: Int
    var loadedFromExtensionScheme: Bool

    static let empty = InstalledExtensionPageRenderMetrics(
        readyState: "",
        bodyChildElementCount: 0,
        elementCount: 0,
        scriptCount: 0,
        visibleElementCount: 0,
        loadedFromExtensionScheme: false
    )

    var debugSummary: String {
        [
            "ready=\(readyState)",
            "bodyChildren=\(bodyChildElementCount)",
            "elements=\(elementCount)",
            "scripts=\(scriptCount)",
            "visible=\(visibleElementCount)",
            "extensionScheme=\(loadedFromExtensionScheme)",
        ].joined(separator: " ")
    }

    init(
        readyState: String,
        bodyChildElementCount: Int,
        elementCount: Int,
        scriptCount: Int,
        visibleElementCount: Int,
        loadedFromExtensionScheme: Bool
    ) {
        self.readyState = readyState
        self.bodyChildElementCount = bodyChildElementCount
        self.elementCount = elementCount
        self.scriptCount = scriptCount
        self.visibleElementCount = visibleElementCount
        self.loadedFromExtensionScheme = loadedFromExtensionScheme
    }

    init(rawValue: String) throws {
        let parts = rawValue.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 6,
              let bodyChildren = Int(parts[1]),
              let elements = Int(parts[2]),
              let scripts = Int(parts[3]),
              let visible = Int(parts[4])
        else {
            throw NSError(
                domain: "SafariExtensionInstalledInternalPageRenderTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid render metrics"]
            )
        }

        readyState = String(parts[0])
        bodyChildElementCount = bodyChildren
        elementCount = elements
        scriptCount = scripts
        visibleElementCount = visible
        loadedFromExtensionScheme = parts[5] == "true"
    }
}

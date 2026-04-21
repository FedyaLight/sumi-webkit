import Foundation
import SwiftData
import WebKit
import XCTest
@testable import Sumi

@MainActor
private final class TestWebViewNavigationObserver: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func install(
        on webView: WKWebView,
        continuation: CheckedContinuation<Void, Error>
    ) {
        self.continuation = continuation
        webView.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume(returning: ())
        continuation = nil
        webView.navigationDelegate = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
        webView.navigationDelegate = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
        webView.navigationDelegate = nil
    }
}

@MainActor
final class TestExternallyConnectableNativeReplyHandler: NSObject, WKScriptMessageHandlerWithReply {
    typealias Responder = @MainActor ([String: Any]) -> (Any?, String?)

    let responder: Responder
    private(set) var receivedPayloads: [[String: Any]] = []

    init(responder: @escaping Responder) {
        self.responder = responder
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard let payload = message.body as? [String: Any] else {
            replyHandler(nil, "Invalid payload")
            return
        }

        receivedPayloads.append(payload)
        var merged = payload
        if let params = payload["params"] as? [String: Any] {
            for (key, value) in params {
                merged[key] = value
            }
        }
        let (reply, errorMessage) = responder(merged)
        replyHandler(reply, errorMessage)
    }
}

@MainActor
final class TestExternallyConnectableNativePortHandler: NSObject, WKScriptMessageHandlerWithReply {
    weak var webView: WKWebView?

    private(set) var openPayloads: [[String: Any]] = []
    private(set) var postPayloads: [[String: Any]] = []
    private(set) var disconnectPayloads: [[String: Any]] = []

    var openErrorMessage: String?
    var autoEchoPosts = true

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard let body = message.body as? [String: Any],
              let featureName = body["featureName"] as? String,
              featureName == "runtime",
              let method = body["method"] as? String
        else {
            replyHandler(nil, "Invalid payload")
            return
        }

        var payload = body
        if let params = body["params"] as? [String: Any] {
            for (key, value) in params {
                payload[key] = value
            }
        }

        switch method {
        case "runtime.connect.open":
            openPayloads.append(payload)
            let portId = payload["portId"] as? String ?? ""
            let portName = ((payload["connectInfo"] as? [String: Any])?["name"] as? String) ?? ""
            if let openErrorMessage {
                replyHandler(nil, openErrorMessage)
                Task { @MainActor [weak self] in
                    try? await self?.disconnectPort(portId: portId, errorMessage: openErrorMessage)
                }
                return
            }

            replyHandler(["accepted": true], nil)
            Task { @MainActor [weak self] in
                try? await self?.openPort(portId: portId, name: portName)
            }

        case "runtime.connect.postMessage":
            postPayloads.append(payload)
            replyHandler(["accepted": true], nil)
            guard autoEchoPosts, let portId = payload["portId"] as? String else { return }
            let messagePayload = payload["message"]
            Task { @MainActor [weak self] in
                try? await self?.sendPortMessage(
                    portId: portId,
                    message: [
                        "echo": messagePayload as Any,
                        "ok": true,
                        "type": "port-echo",
                    ]
                )
            }

        case "runtime.connect.disconnect":
            disconnectPayloads.append(payload)
            replyHandler(["accepted": true], nil)

        default:
            replyHandler(nil, "Unsupported externally_connectable connect method")
        }
    }

    func openPort(portId: String, name: String) async throws {
        guard let webView else { return }
        _ = try await webView.callAsyncJavaScript(
            """
            return !!window.__sumiEcNativePortOpened(portId, { name: portName, extensionId: 'debug.extension' });
            """,
            arguments: [
                "portId": portId,
                "portName": name,
            ],
            contentWorld: .page
        )
    }

    func sendPortMessage(portId: String, message: Any) async throws {
        guard let webView else { return }
        _ = try await webView.callAsyncJavaScript(
            """
            return !!window.__sumiEcNativePortMessage(portId, portMessage);
            """,
            arguments: [
                "portId": portId,
                "portMessage": message,
            ],
            contentWorld: .page
        )
    }

    func disconnectPort(portId: String, errorMessage: String?) async throws {
        guard let webView else { return }
        _ = try await webView.callAsyncJavaScript(
            """
            return !!window.__sumiEcNativePortDisconnected(portId, errorMessage);
            """,
            arguments: [
                "portId": portId,
                "errorMessage": errorMessage as Any,
            ],
            contentWorld: .page
        )
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionManagerTests: XCTestCase {
    struct ExtensionRuntimeHarness {
        let container: ModelContainer
        let browserConfiguration: BrowserConfiguration
    }

    private var testBrowserConfigurations: [BrowserConfiguration] = []
    private var testManagers: [ExtensionManager] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        testBrowserConfigurations = []
        testManagers = []
    }

    override func tearDownWithError() throws {
        let controllerIdentifiers = testManagers.map(\.controllerIdentifier)
        cleanupTestManagers()
        cleanupTestBrowserConfigurations()
        testManagers.removeAll()
        testBrowserConfigurations.removeAll()
        drainMainRunLoop()
        cleanupTestWebExtensionControllerStorage(
            controllerIdentifiers: controllerIdentifiers
        )
        try super.tearDownWithError()
    }

    func makeExtensionRuntimeHarness() throws -> ExtensionRuntimeHarness {
        let browserConfiguration = BrowserConfiguration.makeTestingInstance()
        testBrowserConfigurations.append(browserConfiguration)
        return ExtensionRuntimeHarness(
            container: try makeInMemoryContainer(),
            browserConfiguration: browserConfiguration
        )
    }

    func makeExtensionManager(
        in harness: ExtensionRuntimeHarness,
        initialProfile: Profile? = nil
    ) -> ExtensionManager {
        let resolvedInitialProfile = initialProfile ?? Profile(name: "Tests")
        let manager = ExtensionManager(
            context: harness.container.mainContext,
            initialProfile: resolvedInitialProfile,
            browserConfiguration: harness.browserConfiguration
        )
        testManagers.append(manager)
        return manager
    }

    private func cleanupTestManagers() {
        for manager in testManagers {
            manager.resetInjectedBrowserConfigurationRuntimeState()
        }
    }

    private func cleanupTestBrowserConfigurations() {
        for browserConfiguration in testBrowserConfigurations {
            let configuration = browserConfiguration.webViewConfiguration
            resetManagedBridgeScripts(in: browserConfiguration)
            if configuration.webExtensionController != nil {
                configuration.webExtensionController = nil
            }
        }
    }

    private func drainMainRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }

    private func cleanupTestWebExtensionControllerStorage(
        controllerIdentifiers: [UUID]
    ) {
        guard let libraryDirectory = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first else {
            return
        }

        let webExtensionsRoot = libraryDirectory
            .appendingPathComponent("WebKit", isDirectory: true)
            .appendingPathComponent(SumiAppIdentity.runtimeBundleIdentifier, isDirectory: true)
            .appendingPathComponent("WebExtensions", isDirectory: true)

        for controllerIdentifier in controllerIdentifiers {
            try? FileManager.default.removeItem(
                at: webExtensionsRoot.appendingPathComponent(
                    controllerIdentifier.uuidString.uppercased(),
                    isDirectory: true
                )
            )
        }
    }

    func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    func installExtension(
        _ manager: ExtensionManager,
        from sourceURL: URL
    ) async -> Result<InstalledExtension, ExtensionError> {
        await withCheckedContinuation { continuation in
            manager.installExtension(from: sourceURL) { result in
                continuation.resume(returning: result)
            }
        }
    }

    func sendNativeMessage(
        _ message: Any,
        with handler: NativeMessagingHandler
    ) async -> Result<Any?, Error> {
        await withCheckedContinuation { continuation in
            handler.sendMessage(message) { response, error in
                if let error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(response))
                }
            }
        }
    }

    func waitUntil(
        timeout: TimeInterval,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while condition() == false {
            if Date() >= deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func withTemporaryUserDefault<T>(
        key: String,
        value: Any?,
        perform: () async throws -> T
    ) async rethrows -> T {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: key)

        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }

        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        return try await perform()
    }

    func loadHTMLString(
        _ html: String,
        baseURL: URL,
        in webView: WKWebView
    ) async throws {
        let observer = TestWebViewNavigationObserver()
        try await withCheckedThrowingContinuation { continuation in
            observer.install(on: webView, continuation: continuation)
            _ = webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    func makeExternallyConnectableShimWebView(
        nativeResponder: @escaping TestExternallyConnectableNativeReplyHandler.Responder
    ) async throws -> (WKWebView, TestExternallyConnectableNativeReplyHandler) {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        let controller = WKUserContentController()
        let nativeHandler = TestExternallyConnectableNativeReplyHandler(
            responder: nativeResponder
        )
        controller.addScriptMessageHandler(
            nativeHandler,
            contentWorld: .page,
            name: ExtensionManager.externallyConnectableNativeBridgeHandlerName
        )
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        try await loadHTMLString(
            "<!doctype html><html><head></head><body>shim</body></html>",
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        return (webView, nativeHandler)
    }

    func makeExternallyConnectableNativeConnectShimWebView() async throws
        -> (WKWebView, TestExternallyConnectableNativePortHandler)
    {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        let controller = WKUserContentController()
        let nativeHandler = TestExternallyConnectableNativePortHandler()
        controller.addScriptMessageHandler(
            nativeHandler,
            contentWorld: .page,
            name: ExtensionManager.externallyConnectableNativeBridgeHandlerName
        )
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        nativeHandler.webView = webView
        try await loadHTMLString(
            "<!doctype html><html><head></head><body>native-connect-shim</body></html>",
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        return (webView, nativeHandler)
    }

    func makeExtensionContext(
        at extensionRoot: URL
    ) async throws -> WKWebExtensionContext {
        let webExtension = try await WKWebExtension(resourceBaseURL: extensionRoot)
        return WKWebExtensionContext(for: webExtension)
    }

    func makeInstalledExtensionRecord(
        id: String,
        packagePath: String,
        sourceBundlePath: String,
        manifest: [String: Any],
        isEnabled: Bool
    ) -> InstalledExtensionRecord {
        let extensionRoot = URL(fileURLWithPath: packagePath)
        let optionsPagePath = ExtensionUtils.storedOptionsPagePath(
            from: manifest,
            in: extensionRoot
        )
        let defaultPopupPath = ExtensionUtils.defaultPopupPath(from: manifest)
        let manifestActivationSummary = ExtensionUtils.activationSummary(from: manifest)
        let activationSummary = ExtensionActivationSummary(
            matchPatternStrings: manifestActivationSummary.matchPatternStrings,
            broadScope: manifestActivationSummary.broadScope,
            hasContentScripts: manifestActivationSummary.hasContentScripts,
            hasAction: manifestActivationSummary.hasAction,
            hasOptionsPage: optionsPagePath != nil,
            hasExtensionPages: optionsPagePath != nil || defaultPopupPath != nil
        )

        return InstalledExtensionRecord(
            id: id,
            name: manifest["name"] as? String ?? id,
            version: manifest["version"] as? String ?? "1.0",
            manifestVersion: manifest["manifest_version"] as? Int ?? 3,
            description: manifest["description"] as? String,
            isEnabled: isEnabled,
            installDate: Date(),
            lastUpdateDate: Date(),
            packagePath: packagePath,
            iconPath: nil,
            sourceKind: .directory,
            backgroundModel: ExtensionUtils.backgroundModel(from: manifest),
            incognitoMode: (try? IncognitoExtensionMode.fromManifest(manifest)) ?? .spanning,
            sourcePathFingerprint: ExtensionUtils.normalizePathFingerprint(
                URL(fileURLWithPath: sourceBundlePath)
            ),
            manifestRootFingerprint: ExtensionUtils.fingerprint(
                fileAt: URL(fileURLWithPath: packagePath).appendingPathComponent("manifest.json")
            ),
            sourceBundlePath: sourceBundlePath,
            teamID: nil,
            appBundleID: nil,
            appexBundleID: nil,
            optionsPagePath: optionsPagePath,
            defaultPopupPath: defaultPopupPath,
            hasBackground: ExtensionUtils.backgroundModel(from: manifest) != .none,
            hasAction: activationSummary.hasAction,
            hasOptionsPage: activationSummary.hasOptionsPage,
            hasContentScripts: activationSummary.hasContentScripts,
            hasExtensionPages: activationSummary.hasExtensionPages,
            trustSummary: SafariExtensionTrustSummary(
                state: .developmentDirectory,
                teamID: nil,
                appBundleID: nil,
                appexBundleID: nil,
                signingIdentifier: nil,
                sourcePath: sourceBundlePath,
                importedAt: Date()
            ),
            activationSummary: activationSummary,
            manifest: manifest
        )
    }

    func makeUnpackedExtensionDirectory(
        manifest: [String: Any]
    ) throws -> URL {
        let directoryURL = try temporaryDirectory()
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        )
        try manifestData.write(to: directoryURL.appendingPathComponent("manifest.json"))
        return directoryURL
    }

    func makeNativeHostScript(
        in rootURL: URL,
        name: String,
        body: String
    ) throws -> String {
        let scriptURL = rootURL.appendingPathComponent(name)
        let script = """
        #!/bin/zsh
        /usr/bin/python3 - <<'PY'
        \(body)
        PY
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )
        return scriptURL.path
    }

    func writeNativeMessagingManifest(
        in supportRoot: URL,
        applicationId: String,
        hostPath: String
    ) throws {
        let manifestDirectory = supportRoot.appendingPathComponent(
            "NativeMessagingHosts",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: manifestDirectory,
            withIntermediateDirectories: true
        )
        let manifestURL = manifestDirectory.appendingPathComponent("\(applicationId).json")
        try ExtensionUtils.writeJSONObject(
            ["path": hostPath],
            to: manifestURL
        )
    }

    private func resetManagedBridgeScripts(
        in browserConfiguration: BrowserConfiguration
    ) {
        let controller = browserConfiguration.webViewConfiguration.userContentController
        let preservedScripts = controller.userScripts.filter {
            ExtensionManager.isManagedExternallyConnectablePageBridgeScript($0) == false
        }
        controller.removeAllUserScripts()
        for script in preservedScripts {
            controller.addUserScript(script)
        }
    }

    func cleanupBrowserWindowTestRuntime(
        _ browserManager: BrowserManager,
        windowRegistry: WindowRegistry
    ) {
        for tab in browserManager.tabManager.allTabs() {
            browserManager.tabManager.removeTab(tab.id)
        }

        for windowID in Array(windowRegistry.windows.keys) {
            windowRegistry.unregister(windowID)
        }
    }

    func makeSafariExtensionFixture() throws -> (
        rootURL: URL,
        appURL: URL,
        appexURL: URL,
        resourcesURL: URL
    ) {
        let rootURL = try temporaryDirectory()

        let appURL = rootURL.appendingPathComponent("Fixture.app", isDirectory: true)
        let appexURL = appURL
            .appendingPathComponent("Contents/PlugIns", isDirectory: true)
            .appendingPathComponent("FixtureExtension.appex", isDirectory: true)
        let resourcesURL = appexURL.appendingPathComponent("Contents/Resources", isDirectory: true)

        try FileManager.default.createDirectory(
            at: resourcesURL,
            withIntermediateDirectories: true
        )

        let appInfoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.createDirectory(
            at: appInfoPlistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let appInfo: [String: Any] = [
            "CFBundleIdentifier": "com.sumi.fixture.app",
            "CFBundleName": "Fixture",
        ]
        let appexInfo: [String: Any] = [
            "CFBundleIdentifier": "com.sumi.fixture.extension",
            "CFBundleName": "Fixture Extension",
            "NSExtension": [
                "NSExtensionPointIdentifier": "com.apple.Safari.web-extension"
            ],
        ]

        let appInfoData = try PropertyListSerialization.data(
            fromPropertyList: appInfo,
            format: .xml,
            options: 0
        )
        try appInfoData.write(to: appInfoPlistURL)

        let appexInfoURL = appexURL.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.createDirectory(
            at: appexInfoURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let appexInfoData = try PropertyListSerialization.data(
            fromPropertyList: appexInfo,
            format: .xml,
            options: 0
        )
        try appexInfoData.write(to: appexInfoURL)

        let manifestData = Data(
            """
            {"manifest_version":3,"name":"Fixture","version":"1.0"}
            """.utf8
        )
        try manifestData.write(to: resourcesURL.appendingPathComponent("manifest.json"))

        return (rootURL, appURL, appexURL, resourcesURL)
    }

    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func makeWebExtensionStorageDirectory(
        for manager: ExtensionManager,
        extensionId: String
    ) throws -> URL {
        let storageDirectory = try XCTUnwrap(
            manager.webExtensionStorageDirectory(for: extensionId)
        )
        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(
                at: storageDirectory.deletingLastPathComponent()
            )
        }
        return storageDirectory
    }

    func testPrepareWebViewConfigurationForExtensionRuntimeAssignsControllerBeforeCreation() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let configuration = WKWebViewConfiguration()

        XCTAssertNil(configuration.webExtensionController)

        manager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            reason: #function
        )

        XCTAssertNotNil(configuration.webExtensionController)
        XCTAssertTrue(configuration.defaultWebpagePreferences.allowsContentJavaScript)
        XCTAssertTrue(configuration.webExtensionController === manager.nativeController)
    }

    func testPrepareWebViewForExtensionRuntimeDoesNotLateBindExistingWebView() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)

        XCTAssertNil(webView.configuration.webExtensionController)

        manager.prepareWebViewForExtensionRuntime(
            webView,
            currentURL: URL(string: "https://www.youtube.com/watch?v=test"),
            reason: #function
        )

        XCTAssertNil(webView.configuration.webExtensionController)
        XCTAssertTrue(webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
    }

    func testIsolatedWebViewConfigurationCopyCreatesFreshUserContentController() {
        let browserConfiguration = BrowserConfiguration.makeTestingInstance()
        let template = browserConfiguration.webViewConfiguration
        template.userContentController.addUserScript(
            WKUserScript(
                source: "window.__sumiTemplateScript = true;",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let isolated = browserConfiguration.isolatedWebViewConfigurationCopy(
            from: template,
            websiteDataStore: template.websiteDataStore
        )

        XCTAssertFalse(isolated.userContentController === template.userContentController)
        XCTAssertEqual(
            isolated.userContentController.userScripts.count,
            template.userContentController.userScripts.count
        )
    }
}

import AppKit
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariNativeMessagePayloadShapeContractTests: XCTestCase {
    func testApplicationIDPayloadShapeContract() async {
        do {
            let fixture = try makeResourceFixture()
            let webExtension: WKWebExtension
            do {
                webExtension = try await WKWebExtension(resourceBaseURL: fixture)
            } catch {
                XCTFail("WKWebExtension(resourceBaseURL:) failed: \(Self.errorSummary(error))")
                return
            }

            try await runApplicationIDPayloadShapeContract(
                webExtension: webExtension,
                pagePath: "contract.html",
                loadMode: .resourceBaseURL,
                payloads: NativeMessageShapeProbePayload.allCases
            )
        } catch {
            XCTFail("Native message payload shape contract probe threw: \(error)")
        }
    }

    func testSyntheticAppExtensionBundleApplicationIDPayloadShapeContract() async throws {
        let bundle = try makeAppExtensionBundleFixture()
        let webExtension: WKWebExtension
        do {
            webExtension = try await WKWebExtension(appExtensionBundle: bundle)
        } catch {
            throw XCTSkip(
                "Synthetic appExtensionBundle fixture did not load: \(Self.errorSummary(error))"
            )
        }

        try await runApplicationIDPayloadShapeContract(
            webExtension: webExtension,
            pagePath: "contract.html",
            loadMode: .appExtensionBundleFixture,
            payloads: [.jsonString]
        )
    }

    func testInstalledProtonAppExtensionBundleApplicationIDPayloadShapeContract() async throws {
        let appexURL = URL(
            fileURLWithPath:
                "/Applications/Proton Pass for Safari.app/Contents/PlugIns/Safari Extension.appex"
        )
        guard FileManager.default.fileExists(atPath: appexURL.path) else {
            throw XCTSkip("Proton Pass for Safari is not installed")
        }
        let bundle = try XCTUnwrap(Bundle(url: appexURL))
        let webExtension: WKWebExtension
        do {
            webExtension = try await WKWebExtension(appExtensionBundle: bundle)
        } catch {
            XCTFail("Installed Proton appExtensionBundle failed: \(Self.errorSummary(error))")
            return
        }

        try await runApplicationIDPayloadShapeContract(
            webExtension: webExtension,
            pagePath: "popup.html",
            loadMode: .installedProtonAppExtensionBundle,
            payloads: [.jsonString]
        )
    }

    private func runApplicationIDPayloadShapeContract(
        webExtension: WKWebExtension,
        pagePath: String,
        loadMode: NativeMessageShapeLoadMode,
        payloads: [NativeMessageShapeProbePayload]
    ) async throws {
        let extensionContext = WKWebExtensionContext(for: webExtension)
        extensionContext.setPermissionStatus(.grantedExplicitly, for: .nativeMessaging)

        let controllerConfiguration = WKWebExtensionController.Configuration.nonPersistent()
        let pageConfiguration = WKWebViewConfiguration()
        pageConfiguration.websiteDataStore = .nonPersistent()
        pageConfiguration.defaultWebpagePreferences.allowsContentJavaScript = true
        controllerConfiguration.webViewConfiguration = pageConfiguration
        controllerConfiguration.defaultWebsiteDataStore = .nonPersistent()

        let delegate = NativeMessageShapeSpyDelegate()
        let controller = WKWebExtensionController(configuration: controllerConfiguration)
        controller.delegate = delegate
        do {
            try controller.load(extensionContext)
        } catch {
            XCTFail("WKWebExtensionController.load failed: \(Self.errorSummary(error))")
            return
        }
        defer {
            try? controller.unload(extensionContext)
        }

        let configuration = try XCTUnwrap(extensionContext.webViewConfiguration)
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            configuration: configuration
        )
        let pageURL = try XCTUnwrap(
            URL(string: pagePath, relativeTo: extensionContext.baseURL)?
                .absoluteURL
        )
        do {
            try await load(pageURL, in: webView)
        } catch {
            XCTFail("Extension page load failed: \(Self.errorSummary(error))")
            return
        }

        var results: [NativeMessageShapeProbeResult] = []
        for payload in payloads {
            let before = delegate.records.count
            let scriptResult = try await runProbe(payload, in: webView, loadMode: loadMode)
            let reachedRecord = delegate.records.dropFirst(before).first
            results.append(
                NativeMessageShapeProbeResult(
                    payload: payload,
                    delegateRecord: reachedRecord,
                    scriptResult: scriptResult
                )
            )
        }

        let matrix = NativeMessageShapeProbeResult.matrixDescription(
            results,
            loadMode: loadMode
        )
        XCTAssertFalse(results.isEmpty, matrix)
        XCTAssertTrue(
            results.allSatisfy(\.delegateReached),
            matrix
        )
        for payload in payloads where payload != .nullValue {
            XCTAssertEqual(
                results.first(where: { $0.payload == payload })?
                    .delegateRecord?
                    .applicationIdentifier,
                "application.id",
                matrix
            )
        }
    }

    private func makeResourceFixture() throws -> URL {
        let resourcesURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: resourcesURL,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: resourcesURL)
        }

        try writeContractResources(to: resourcesURL)
        return resourcesURL
    }

    private func makeAppExtensionBundleFixture() throws -> Bundle {
        let bundleRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundleURL = bundleRoot.appendingPathComponent(
            "NativeMessagePayloadShapeContract.appex",
            isDirectory: true
        )
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let executableURL = contentsURL
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("NativeMessagePayloadShapeContract")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: resourcesURL,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundleRoot)
        }

        let plist: [String: Any] = [
            "CFBundleDisplayName": "Native Message Payload Shape Contract",
            "CFBundleExecutable": "NativeMessagePayloadShapeContract",
            "CFBundleIdentifier": "dev.sumi.tests.native-message-payload-shape",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "Native Message Payload Shape Contract",
            "CFBundlePackageType": "XPC!",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "NSExtension": [
                "NSExtensionPointIdentifier": SafariExtensionScanner
                    .safariWebExtensionPointIdentifier,
                "NSExtensionPrincipalClass":
                    "NativeMessagePayloadShapeContract.ExtensionHandler",
            ],
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(
            to: contentsURL.appendingPathComponent("Info.plist"),
            options: [.atomic]
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        try writeContractResources(to: resourcesURL)

        guard let bundle = Bundle(url: bundleURL) else {
            throw NativeMessageShapeFixtureError.bundleUnavailable(bundleURL.path)
        }
        return bundle
    }

    private func writeContractResources(to resourcesURL: URL) throws {
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Native Message Payload Shape Contract",
            "version": "1.0",
            "permissions": ["nativeMessaging"],
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: resourcesURL.appendingPathComponent("manifest.json"), options: [.atomic])
        try Data(
            """
            <!doctype html>
            <html>
            <body>
            <script src="contract.js"></script>
            </body>
            </html>
            """.utf8
        ).write(to: resourcesURL.appendingPathComponent("contract.html"), options: [.atomic])
        try Data(
            """
            globalThis.__sumiRunNativeMessagePayloadProbe = async (payloadName) => {
              const runtime = (globalThis.browser && globalThis.browser.runtime) ||
                (globalThis.chrome && globalThis.chrome.runtime);
              const payloads = {
                plainString: "plain string",
                jsonString: JSON.stringify({ environment: "proton.me" }),
                object: { environment: "proton.me" },
                array: ["environment", "proton.me"],
                nullValue: null
              };
              try {
                const value = await runtime.sendNativeMessage(
                  "application.id",
                  payloads[payloadName]
                );
                return JSON.stringify({
                  resolved: true,
                  valueType: typeof value
                });
              } catch (error) {
                return JSON.stringify({
                  resolved: false,
                  errorName: error && error.name ? String(error.name) : "",
                  errorMessage: error && error.message ? String(error.message) : String(error)
                });
              }
            };
            """.utf8
        ).write(to: resourcesURL.appendingPathComponent("contract.js"), options: [.atomic])
    }

    private func load(_ url: URL, in webView: WKWebView) async throws {
        let delegate = NavigationDelegateBox()
        webView.navigationDelegate = delegate
        try await delegate.waitForFinish {
            webView.load(URLRequest(url: url))
        }
        webView.navigationDelegate = nil
    }

    private func runProbe(
        _ payload: NativeMessageShapeProbePayload,
        in webView: WKWebView,
        loadMode: NativeMessageShapeLoadMode
    ) async throws -> NativeMessageShapeScriptResult {
        let script: String
        let arguments: [String: Any]
        switch loadMode {
        case .resourceBaseURL, .appExtensionBundleFixture:
            script = """
            return await globalThis.__sumiRunNativeMessagePayloadProbe(payloadName);
            """
            arguments = ["payloadName": payload.rawValue]
        case .installedProtonAppExtensionBundle:
            script = """
            const runtime = (globalThis.browser && globalThis.browser.runtime) ||
              (globalThis.chrome && globalThis.chrome.runtime);
            try {
              const value = await runtime.sendNativeMessage(
                "application.id",
                JSON.stringify({ environment: "proton.me" })
              );
              return JSON.stringify({
                resolved: true,
                valueType: typeof value
              });
            } catch (error) {
              return JSON.stringify({
                resolved: false,
                errorName: error && error.name ? String(error.name) : "",
                errorMessage: error && error.message ? String(error.message) : String(error)
              });
            }
            """
            arguments = [:]
        }

        let rawValue = try await webView.callAsyncJavaScript(
            script,
            arguments: arguments,
            in: nil,
            contentWorld: .page
        ) as? String
        let data = try XCTUnwrap(rawValue?.data(using: .utf8))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return NativeMessageShapeScriptResult(
            resolved: object["resolved"] as? Bool ?? false,
            errorName: object["errorName"] as? String ?? "",
            errorMessage: object["errorMessage"] as? String ?? ""
        )
    }

    private final class NativeMessageShapeSpyDelegate:
        NSObject,
        WKWebExtensionControllerDelegate
    {
        private(set) var records: [NativeMessageShapeDelegateRecord] = []

        func webExtensionController(
            _ controller: WKWebExtensionController,
            sendMessage message: Any,
            toApplicationWithIdentifier applicationIdentifier: String?,
            for extensionContext: WKWebExtensionContext,
            replyHandler: @escaping (Any?, (any Error)?) -> Void
        ) {
            _ = (controller, extensionContext)
            records.append(
                NativeMessageShapeDelegateRecord(
                    applicationIdentifier: applicationIdentifier,
                    nativeType: Self.nativeTypeDescription(for: message),
                    topLevelShape: Self.topLevelShape(for: message)
                )
            )
            replyHandler(["ok": true], nil)
        }

        private static func nativeTypeDescription(for message: Any) -> String {
            String(describing: type(of: message))
        }

        private static func topLevelShape(for message: Any) -> String {
            if let object = message as? [String: Any] {
                let keys = object.keys.sorted().joined(separator: ",")
                return "object{\(keys)}"
            }
            if message is [Any] {
                return "array"
            }
            if message is NSNull {
                return "null"
            }
            if message is String {
                return "string"
            }
            return "unsupported"
        }
    }

    private final class NavigationDelegateBox: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, any Error>?

        func waitForFinish(_ start: () -> Void) async throws {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                start()
            }
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            _ = (webView, navigation)
            continuation?.resume()
            continuation = nil
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: any Error
        ) {
            _ = (webView, navigation)
            continuation?.resume(throwing: error)
            continuation = nil
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            _ = (webView, navigation)
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    private static func errorSummary(_ error: any Error) -> String {
        let nsError = error as NSError
        return [
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "description=\(nsError.localizedDescription)",
            "reason=\(nsError.localizedFailureReason ?? "-")",
        ].joined(separator: " ")
    }
}

private enum NativeMessageShapeFixtureError: Error, CustomStringConvertible {
    case bundleUnavailable(String)

    var description: String {
        switch self {
        case .bundleUnavailable(let path):
            return "Bundle(url:) failed for \(path)"
        }
    }
}

private enum NativeMessageShapeLoadMode: String {
    case resourceBaseURL
    case appExtensionBundleFixture
    case installedProtonAppExtensionBundle
}

private enum NativeMessageShapeProbePayload: String, CaseIterable {
    case plainString
    case jsonString
    case object
    case array
    case nullValue

    var displayName: String {
        switch self {
        case .plainString:
            return #""plain string""#
        case .jsonString:
            return #"JSON.stringify({ environment: "proton.me" })"#
        case .object:
            return #"{ environment: "proton.me" }"#
        case .array:
            return #"["environment", "proton.me"]"#
        case .nullValue:
            return "null"
        }
    }
}

private struct NativeMessageShapeScriptResult {
    let resolved: Bool
    let errorName: String
    let errorMessage: String
}

private struct NativeMessageShapeDelegateRecord {
    let applicationIdentifier: String?
    let nativeType: String
    let topLevelShape: String
}

private struct NativeMessageShapeProbeResult {
    let payload: NativeMessageShapeProbePayload
    let delegateRecord: NativeMessageShapeDelegateRecord?
    let scriptResult: NativeMessageShapeScriptResult

    var delegateReached: Bool {
        delegateRecord != nil
    }

    static func matrixDescription(
        _ results: [Self],
        loadMode: NativeMessageShapeLoadMode
    ) -> String {
        (
            [
                "Load mode: \(loadMode.rawValue)",
                "Payload shape | Delegate reached? | Application id | Native type | Top-level shape | Error",
            ] + results.map { result in
                [
                    result.payload.displayName,
                    result.delegateReached ? "yes" : "no",
                    result.delegateRecord?.applicationIdentifier ?? "-",
                    result.delegateRecord?.nativeType ?? "-",
                    result.delegateRecord?.topLevelShape ?? "-",
                    result.delegateReached ? "-" : result.scriptResult.errorDescription,
                ].joined(separator: " | ")
            }
        ).joined(separator: "\n")
    }
}

private extension NativeMessageShapeScriptResult {
    var errorDescription: String {
        guard resolved == false else { return "-" }
        let name = errorName.isEmpty ? "Error" : errorName
        return "\(name): \(errorMessage)"
    }
}

import Foundation
import XCTest

#if canImport(WebKit)
import WebKit
#endif

@testable import Sumi

final class ChromeMV3ScriptingExecuteScriptFileResultTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

    @MainActor
    func testControlledFileExecuteScriptCallbackInvocationReturnsInjectionResults()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Named WKContentWorld execution requires macOS 15.5.")
        }

        let root = try makeTemporaryDirectory()
        let assets = root.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(
            at: assets,
            withIntermediateDirectories: true
        )
        try writeFixture(
            "({marker:9})",
            to: assets.appendingPathComponent("callback-result.js")
        )

        let handler = try await makeExecutingHandler(
            bundleRoot: root,
            html: "<!doctype html><title>fixture</title>"
        )
        let response = await handler.handleAsync(
            ChromeMV3RuntimeJSBridgeHostRequest(
                bridgeCallID: UUID().uuidString,
                namespace: "scripting",
                methodName: "executeScript",
                invocationMode: .callback,
                arguments: [
                    .object([
                        "target": .object(["tabId": .number(1)]),
                        "files": .array([.string("assets/callback-result.js")]),
                    ]),
                ],
                listenerID: nil,
                eventName: nil,
                portID: nil,
                diagnostics: []
            )
        )

        XCTAssertTrue(response.succeeded)
        guard case .array(let results) = response.resultPayload,
              case .object(let frame) = results[0],
              case .object(let value) = frame["result"]
        else {
            return XCTFail("Expected callback-mode executeScript InjectionResult payload.")
        }
        XCTAssertEqual(value["marker"], .number(9))
    }

    @MainActor
    func testControlledFileExecuteScriptCapturesPackagedParseJSIfAvailable()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Named WKContentWorld execution requires macOS 15.5.")
        }

        let packagedParse = URL(
            fileURLWithPath:
                "/Users/fedaefimov/Downloads/Aura/mv3-test-extensions/raindrop/assets/parse.js",
            isDirectory: false
        )
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: packagedParse.path),
            "Local packaged parse.js fixture is not available."
        )

        let root = try makeTemporaryDirectory()
        let assets = root.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(
            at: assets,
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: packagedParse,
            to: assets.appendingPathComponent("parse.js")
        )

        let handler = try await makeExecutingHandler(
            bundleRoot: root,
            html: """
            <!doctype html>
            <html>
              <head><title>Fixture article</title></head>
              <body><main><h1>Example article</h1><p>fixture</p></main></body>
            </html>
            """
        )
        let response = await executeFixture(
            handler: handler,
            relativePath: "assets/parse.js"
        )

        XCTAssertTrue(response.succeeded)
        guard case .array(let results) = response.resultPayload,
              case .object(let frame) = results[0]
        else {
            return XCTFail("Expected InjectionResult array payload for packaged parse.js.")
        }
        XCTAssertEqual(frame["frameId"], .number(0))
        XCTAssertEqual(frame["documentId"], .string("document-0"))
        guard case .object(let parsed) = frame["result"] else {
            return XCTFail(
                "Packaged parse.js should return an object-like InjectionResult.result, not null/undefined."
            )
        }
        XCTAssertFalse(parsed.isEmpty)
        XCTAssertNotNil(parsed["link"])
        XCTAssertNotNil(parsed["title"])
    }

    @MainActor
    func testControlledFileExecuteScriptCapturesPrimitiveObjectAndPromiseResults()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Named WKContentWorld execution requires macOS 15.5.")
        }

        let root = try makeTemporaryDirectory()
        let assets = root.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(
            at: assets,
            withIntermediateDirectories: true
        )

        try writeFixture(
            "function fixtureInner(){return {marker:1,nested:[{kind:\"item\"}]}} fixtureInner();",
            to: assets.appendingPathComponent("object-result.js")
        )
        try writeFixture(
            "Promise.resolve({marker:2})",
            to: assets.appendingPathComponent("promise-result.js")
        )
        try writeFixture(
            """
            function fixtureOuter(){
              function fixtureInner(){
                return {marker:3};
              }
              return fixtureInner();
            }
            fixtureOuter();
            """,
            to: assets.appendingPathComponent("nested-function-result.js")
        )
        try writeFixture(
            """
            function fixtureParseLike(){
              return {
                link: location.href,
                title: document.title,
                media: [{type: "image", link: location.href}]
              };
            }
            fixtureParseLike();
            """,
            to: assets.appendingPathComponent("parse-shaped-result.js")
        )

        let handler = try await makeExecutingHandler(
            bundleRoot: root,
            html: """
            <!doctype html>
            <html>
              <head><title>fixture</title></head>
              <body><main><h1>fixture</h1></main></body>
            </html>
            """
        )

        try writeFixture(
            "globalThis.__sumiFileResultFixture = 7; 7",
            to: assets.appendingPathComponent("primitive-result.js")
        )
        let primitive = await executeFixture(
            handler: handler,
            relativePath: "assets/primitive-result.js"
        )
        assertInjectionResultEnvelope(
            primitive,
            expectedResult: .number(7),
            label: "primitive"
        )

        let object = await executeFixture(
            handler: handler,
            relativePath: "assets/object-result.js"
        )
        assertInjectionResultEnvelope(
            object,
            expectedResult: .object([
                "marker": .number(1),
                "nested": .array([
                    .object(["kind": .string("item")]),
                ]),
            ]),
            label: "object"
        )

        let nestedFunction = await executeFixture(
            handler: handler,
            relativePath: "assets/nested-function-result.js"
        )
        assertInjectionResultEnvelope(
            nestedFunction,
            expectedResult: .object(["marker": .number(3)]),
            label: "nested-function"
        )

        let parseShaped = await executeFixture(
            handler: handler,
            relativePath: "assets/parse-shaped-result.js"
        )
        guard case .array(let parseResults) = parseShaped.resultPayload,
              case .object(let parseFrame) = parseResults[0],
              case .object(let parseValue) = parseFrame["result"]
        else {
            return XCTFail(
                "parse-shaped: expected object InjectionResult payload."
            )
        }
        XCTAssertTrue(parseShaped.succeeded)
        XCTAssertEqual(parseValue["title"], .string("fixture"))
        XCTAssertEqual(parseValue["link"], .string("https://example.com/"))
        XCTAssertEqual(
            parseValue["media"],
            .array([
                .object([
                    "type": .string("image"),
                    "link": .string("https://example.com/"),
                ]),
            ])
        )

        let promise = await executeFixture(
            handler: handler,
            relativePath: "assets/promise-result.js"
        )
        assertInjectionResultEnvelope(
            promise,
            expectedResult: .object(["marker": .number(2)]),
            label: "promise"
        )
    }

    @MainActor
    private func makeExecutingHandler(
        bundleRoot: URL,
        html: String
    ) async throws -> ChromeMV3PopupOptionsJSBridgeHandler {
        let extensionID = "scripting-file-result-extension"
        let profileID = "scripting-file-result-profile"
        let activeTabGrant = ChromeMV3ActiveTabGrant(
            extensionID: extensionID,
            profileID: profileID,
            tabID: 1,
            scope: .origin("https://example.com"),
            reason: .actionClick,
            userGestureModeled: true,
            createdSequence: 1,
            diagnostics: ["test activeTab grant"]
        )
        let configuration = ChromeMV3PopupOptionsJSBridgeConfiguration(
            extensionID: extensionID,
            profileID: profileID,
            surfaceID: "\(profileID):\(extensionID):actionPopup",
            surface: .actionPopup,
            extensionBaseURLString: "chrome-extension://\(extensionID)/",
            generatedBundleRootPath: bundleRoot.path,
            permissionStateRootPath: nil,
            storageLocalRootPath: nil,
            storageSyncRootPath: nil,
            moduleState: .enabled,
            bridgeAvailable: true,
            popupOptionsJSBridgeAvailableInDeveloperPreview: true,
            popupOptionsJSBridgeAvailableInPublicProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            contentScriptAttachmentAvailableInProduct: false,
            runtimeLoadable: false,
            runtimeManifest: nil,
            i18nCatalogSnapshot: nil,
            manifestPermissions: ["activeTab", "scripting"],
            manifestOptionalPermissions: [],
            manifestHostPermissions: [],
            manifestOptionalHostPermissions: [],
            activeTabGrants: [activeTabGrant],
            allowlist: .controlledActionPopupPolicy,
            diagnostics: []
        )

        let webViewConfiguration = WKWebViewConfiguration()
        webViewConfiguration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: webViewConfiguration)
        let navigationObserver =
            ChromeMV3ScriptingExecuteScriptFileResultNavigationObserver()
        webView.navigationDelegate = navigationObserver
        let navigation = webView.loadHTMLString(
            html,
            baseURL: URL(string: "https://example.com/")!
        )
        _ = try await navigationObserver.wait(navigation: navigation)

        let contentWorldName = "sumi.mv3.content.\(profileID).\(extensionID)"
        return ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration,
            scriptingExecuteScriptTargetProvider: { _, _, tabID, frameID in
                guard tabID == 1, frameID == 0 else { return nil }
                return ChromeMV3ScriptingExecuteScriptWebViewTarget(
                    webView: webView,
                    contentWorld: WKContentWorld.world(name: contentWorldName),
                    contentWorldName: contentWorldName,
                    frameID: 0,
                    localTabID: 1
                )
            }
        )
    }

    @MainActor
    private func executeFixture(
        handler: ChromeMV3PopupOptionsJSBridgeHandler,
        relativePath: String
    ) async -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        await handler.handleAsync(
            ChromeMV3RuntimeJSBridgeHostRequest(
                bridgeCallID: UUID().uuidString,
                namespace: "scripting",
                methodName: "executeScript",
                invocationMode: .promise,
                arguments: [
                    .object([
                        "target": .object(["tabId": .number(1)]),
                        "files": .array([.string(relativePath)]),
                        "injectImmediately": .bool(true),
                    ]),
                ],
                listenerID: nil,
                eventName: nil,
                portID: nil,
                diagnostics: []
            )
        )
    }

    private func assertInjectionResultEnvelope(
        _ response: ChromeMV3PopupOptionsJSBridgeHostResponse,
        expectedResult: ChromeMV3StorageValue,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            response.succeeded,
            "\(label) executeScript failed: \(response.lastErrorCode ?? "nil") \(response.diagnostics.joined(separator: " | "))",
            file: file,
            line: line
        )
        XCTAssertNil(response.lastErrorCode, file: file, line: line)
        guard case .array(let results) = response.resultPayload else {
            XCTFail("\(label): expected InjectionResult array payload.", file: file, line: line)
            return
        }
        XCTAssertEqual(results.count, 1, file: file, line: line)
        guard case .object(let first) = results[0] else {
            XCTFail("\(label): expected object InjectionResult.", file: file, line: line)
            return
        }
        XCTAssertEqual(first["frameId"], .number(0), file: file, line: line)
        XCTAssertEqual(
            first["documentId"],
            .string("document-0"),
            file: file,
            line: line
        )
        XCTAssertEqual(first["result"], expectedResult, file: file, line: line)
        XCTAssertTrue(
            response.diagnostics.contains("executionClassifier=filesExecuted"),
            file: file,
            line: line
        )
        XCTAssertTrue(
            response.diagnostics.contains {
                $0.contains("resultFrameCount=1")
                    || $0.contains("resultFrameCount=1.")
            },
            file: file,
            line: line
        )
    }

    private func writeFixture(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        return directory
    }
}

#if canImport(WebKit)
@MainActor
private final class ChromeMV3ScriptingExecuteScriptFileResultNavigationObserver:
    NSObject,
    WKNavigationDelegate
{
    private var continuation: CheckedContinuation<Void, Error>?

    func wait(navigation: WKNavigation?) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            if navigation == nil {
                continuation.resume()
                self.continuation = nil
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        continuation?.resume()
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
#endif

import WebKit
import XCTest
@testable import Sumi

@MainActor
final class UserScriptsRuntimeTests: XCTestCase {
    func testMetadataParserCapturesSourceAndAntifeatures() throws {
        let source = """
        // ==UserScript==
        // @name Src Test
        // @source https://github.com/example/repo
        // @antifeature tracking
        // @antifeature ads
        // ==/UserScript==
        void 0;
        """
        let metadata = try XCTUnwrap(UserScriptMetadataParser.parse(source))
        XCTAssertEqual(metadata.sourceURL, "https://github.com/example/repo")
        XCTAssertEqual(metadata.antifeatures, ["tracking", "ads"])
    }

    func testMetadataParserSupportsViolentmonkeyStyleKeysAndLocalization() throws {
        let source = """
        // ==UserScript==
        // @name Base Name
        // @name:fr Nom francais
        // @description Base description
        // @description:fr Description francaise
        // @namespace https://example.test/scripts
        // @version 1.2.3
        // @supportURL https://example.test/support
        // @run-at document-body
        // @inject-into content
        // @grant GM_xmlhttpRequest
        // @connect api.example.test
        // @unwrap
        // @top-level-await
        // ==/UserScript==
        console.log('ok');
        """

        let metadata = try XCTUnwrap(UserScriptMetadataParser.parse(source))
        XCTAssertEqual(metadata.name, "Base Name")
        XCTAssertEqual(metadata.localizedNames["fr"], "Nom francais")
        XCTAssertEqual(metadata.localizedDescriptions["fr"], "Description francaise")
        XCTAssertEqual(metadata.supportURL, "https://example.test/support")
        XCTAssertEqual(metadata.runAt, .documentBody)
        XCTAssertEqual(metadata.injectInto, .content)
        XCTAssertEqual(metadata.grants, ["GM_xmlhttpRequest"])
        XCTAssertEqual(metadata.connects, ["api.example.test"])
        XCTAssertTrue(metadata.unwrap)
        XCTAssertTrue(metadata.topLevelAwait)
    }

    func testMatchEngineHonorsMatchIncludeAndExcludeRules() throws {
        let metadata = try XCTUnwrap(UserScriptMetadataParser.parse("""
        // ==UserScript==
        // @name Match Test
        // @match https://*.example.test/*
        // @include https://fallback.test/path/*
        // @exclude-match https://private.example.test/*
        // @exclude https://fallback.test/path/blocked/*
        // ==/UserScript==
        console.log('ok');
        """))
        let script = SumiInstalledUserScript(filename: "match.user.js", metadata: metadata)

        XCTAssertTrue(UserScriptMatchEngine.shouldInject(script: script, into: try XCTUnwrap(URL(string: "https://www.example.test/page"))))
        XCTAssertFalse(UserScriptMatchEngine.shouldInject(script: script, into: try XCTUnwrap(URL(string: "https://private.example.test/page"))))
        XCTAssertTrue(UserScriptMatchEngine.shouldInject(script: script, into: try XCTUnwrap(URL(string: "https://fallback.test/path/ok"))))
        XCTAssertFalse(UserScriptMatchEngine.shouldInject(script: script, into: try XCTUnwrap(URL(string: "https://fallback.test/path/blocked/item"))))
    }

    func testGMShimExposesNativeRuntimeAliases() throws {
        let metadata = try XCTUnwrap(UserScriptMetadataParser.parse("""
        // ==UserScript==
        // @name GM Test
        // @grant GM_getValue
        // @grant GM_setValues
        // @grant GM_xmlhttpRequest
        // @grant GM_download
        // @grant GM_openInTab
        // ==/UserScript==
        console.log('ok');
        """))
        let script = SumiInstalledUserScript(filename: "gm.user.js", metadata: metadata)
        let bridge = UserScriptGMBridge(
            script: script,
            profileId: nil,
            contentWorld: .page,
            tabOpenHandler: nil,
            downloadManager: nil
        )

        let shim = bridge.generateJSShim()
        XCTAssertTrue(shim.contains("GM.setValues"))
        XCTAssertTrue(shim.contains("GM_getValues"))
        XCTAssertTrue(shim.contains("GM.deleteValues"))
        XCTAssertTrue(shim.contains("GM.download"))
        XCTAssertTrue(shim.contains("GM.openInTab"))
        XCTAssertTrue(shim.contains("xmlhttpRequest: function"))
        XCTAssertTrue(shim.contains("new Blob([buffer])"))
        XCTAssertTrue(shim.contains("finalUrl"))
        XCTAssertTrue(shim.contains("GM_addValueChangeListener"))
        XCTAssertTrue(shim.contains("unsafeWindow"))
        XCTAssertTrue(shim.contains("scriptMetaStr:"))
        XCTAssertTrue(shim.contains("uuid:"))
        XCTAssertTrue(shim.contains("antifeature:"))
        XCTAssertTrue(shim.contains("exclude:"))
    }

    func testGMShimRunsBeforeRequireDependencies() throws {
        let metadata = try XCTUnwrap(UserScriptMetadataParser.parse("""
        // ==UserScript==
        // @name Require Order Test
        // @grant GM_addStyle
        // @require https://example.test/require.js
        // ==/UserScript==
        console.log('user');
        """))
        let script = SumiInstalledUserScript(
            filename: "require-order.user.js",
            metadata: metadata,
            requiredCode: ["GM_addStyle('.from-require{}');"]
        )

        let assembled = script.assembledCode(gmShim: "window.GM_addStyle = function() {};")
        let shimRange = try XCTUnwrap(assembled.range(of: "window.GM_addStyle = function() {};"))
        let requireRange = try XCTUnwrap(assembled.range(of: "GM_addStyle('.from-require{}');"))
        XCTAssertLessThan(shimRange.lowerBound, requireRange.lowerBound)
    }

    func testMetadataParserCapturesSumiCompatLines() throws {
        let source = """
        // ==UserScript==
        // @name Compat Test
        // @sumi-compat webkit-media
        // @sumi-compat unknown-module
        // ==/UserScript==
        void 0;
        """
        let metadata = try XCTUnwrap(UserScriptMetadataParser.parse(source))
        XCTAssertEqual(metadata.sumiCompat, ["webkit-media", "unknown-module"])
    }

    func testBundledWebkitMediaCompatSourceLoads() {
        let src = UserScriptBundledCompatScript.source(moduleID: "webkit-media")
        XCTAssertNotNil(src)
        XCTAssertTrue(src?.contains("__sumiWebkitMediaCompatInstalled") == true)
    }

    func testInternalRequireURLResolvesWebkitMedia() {
        let url = "sumi-internal://userscript-compat/webkit-media.js"
        let content = UserScriptInternalRequireURL.content(from: url)
        XCTAssertNotNil(content)
        XCTAssertTrue(content?.contains("__sumiWebkitMediaCompatInstalled") == true)
    }

    func testCompatAssemblyDedupesModules() throws {
        let source = """
        // ==UserScript==
        // @name Dedup
        // @sumi-compat webkit-media
        // @sumi-compat webkit-media
        // ==/UserScript==
        void 0;
        """
        let metadata = try XCTUnwrap(UserScriptMetadataParser.parse(source))
        let fragments = UserScriptCompatAssembly.preludeFragments(for: metadata)
        XCTAssertEqual(fragments.count, 1)
    }

    func testAssembledCodeOrderShimCompatRequire() throws {
        let metadata = try XCTUnwrap(UserScriptMetadataParser.parse("""
        // ==UserScript==
        // @name Order
        // @grant GM_addStyle
        // @require https://example.test/require.js
        // @sumi-compat webkit-media
        // ==/UserScript==
        console.log('user');
        """))
        let compat = UserScriptCompatAssembly.preludeFragments(for: metadata)
        let script = SumiInstalledUserScript(
            filename: "order.user.js",
            metadata: metadata,
            compatPreludeFragments: compat,
            requiredCode: ["/* require */"]
        )
        let assembled = script.assembledCode(gmShim: "/* shim */")
        let shimRange = try XCTUnwrap(assembled.range(of: "/* shim */"))
        let compatRange = try XCTUnwrap(assembled.range(of: "__sumiWebkitMediaCompatInstalled"))
        let requireRange = try XCTUnwrap(assembled.range(of: "/* require */"))
        XCTAssertLessThan(shimRange.lowerBound, compatRange.lowerBound)
        XCTAssertLessThan(compatRange.lowerBound, requireRange.lowerBound)
    }

    func testRuntimeErrorLogSuppressesResizeObserverNoise() {
        XCTAssertFalse(
            UserScriptRuntimeErrorLogFilter.shouldRecord(
                message: "ResizeObserver loop completed with undelivered notifications."
            )
        )
        XCTAssertTrue(UserScriptRuntimeErrorLogFilter.shouldRecord(message: "ReferenceError: foo is not defined"))
    }

    func testTopLevelAwaitAssemblesAsyncWrapperUnlessUnwrapped() throws {
        let wrappedMetadata = try XCTUnwrap(UserScriptMetadataParser.parse("""
        // ==UserScript==
        // @name Await Test
        // @top-level-await
        // @grant none
        // ==/UserScript==
        await Promise.resolve();
        """))
        let wrapped = SumiInstalledUserScript(filename: "await.user.js", metadata: wrappedMetadata)
        XCTAssertTrue(wrapped.assembledCode(gmShim: "").contains("(async () => {"))

        let unwrappedMetadata = try XCTUnwrap(UserScriptMetadataParser.parse("""
        // ==UserScript==
        // @name Unwrap Test
        // @unwrap
        // @top-level-await
        // @grant none
        // ==/UserScript==
        await Promise.resolve();
        """))
        let unwrapped = SumiInstalledUserScript(filename: "unwrap.user.js", metadata: unwrappedMetadata)
        XCTAssertFalse(unwrapped.assembledCode(gmShim: "").contains("(async () => {"))
    }
}

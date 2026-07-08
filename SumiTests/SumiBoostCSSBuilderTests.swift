import JavaScriptCore
import XCTest

@testable import Sumi

final class SumiBoostCSSBuilderTests: XCTestCase {
    func testContentCSSIncludesZapsFontCaseAndCustomCSS() {
        var data = SumiBoostData.empty()
        data.zapSelectors = [".ad", "#promo"]
        data.fontFamily = "SF Pro"
        data.textCaseOverride = .uppercase
        data.customCSS = "main { max-width: 900px; }"

        let css = SumiBoostCSSBuilder.contentCSS(for: data)

        XCTAssertTrue(css.contains(".ad:not([zen-zap-unhide]) { display: none !important; }"))
        XCTAssertTrue(css.contains("#promo:not([zen-zap-unhide]) { display: none !important; }"))
        XCTAssertTrue(css.contains("font-family: 'SF Pro' !important;"))
        XCTAssertTrue(css.contains("text-transform: uppercase !important;"))
        XCTAssertTrue(css.contains("main { max-width: 900px; }"))
    }

    func testContentCSSIncludesBackgroundColorFromSecondaryDotWhenColorBoostEnabled() {
        var data = SumiBoostData.empty()
        data.enableColorBoost = true
        data.dotAngleDeg = 100
        data.secondaryDotAngleDegDelta = 80
        data.dotDistance = 0.75

        let css = SumiBoostCSSBuilder.contentCSS(for: data)

        XCTAssertTrue(css.contains("html, body"))
        XCTAssertTrue(css.contains("background-color: hsl(180.000deg, 75.000%, 20.000%) !important;"))

        data.enableColorBoost = false
        XCTAssertFalse(SumiBoostCSSBuilder.contentCSS(for: data).contains("background-color:"))
    }

    func testFilterCSSIsDeterministicForColorBoostAndSmartInvert() {
        var data = SumiBoostData.empty()
        data.enableColorBoost = true
        data.smartInvert = true
        data.dotAngleDeg = 405
        data.brightness = 0.5
        data.saturation = 0.5
        data.contrast = 0.75

        let css = SumiBoostCSSBuilder.filterCSS(for: data)

        // Color boost no longer applies a hue-rotate: a global hue-rotate would
        // also shift the picked background color and break the match between
        // the editor dots and the page. Only the smart-invert path keeps a
        // hue-rotate(180deg) to neutralize images.
        XCTAssertFalse(css.contains("hue-rotate(45.000deg)"))
        XCTAssertTrue(css.contains("brightness(1.000)"))
        XCTAssertTrue(css.contains("saturate(1.000)"))
        XCTAssertTrue(css.contains("contrast(1.250)"))
        XCTAssertTrue(css.contains("invert(1) hue-rotate(180deg)"))
        XCTAssertTrue(css.contains("img, video, canvas, picture, iframe"))
    }

    func testFilterCSSSupportsMonochromeSaturation() {
        var data = SumiBoostData.empty()
        data.enableColorBoost = true
        data.saturation = 0

        let css = SumiBoostCSSBuilder.filterCSS(for: data)

        XCTAssertTrue(css.contains("saturate(0.000)"))
    }

    func testInstallJavaScriptEscapesCSSPayloadThroughJSON() {
        let script = SumiBoostCSSBuilder.installJavaScript(
            boostId: "boost",
            contentCSS: "body::before { content: \"`$\"; }",
            filterCSS: ""
        )

        XCTAssertTrue(script.contains("const payload ="))
        XCTAssertTrue(script.contains(#""boostId":"boost""#))
        XCTAssertTrue(script.contains(#"body::before { content: \"`$\"; }"#))
    }

    // MARK: - Threat model: hostile Boost payloads must never break out of the
    // JSON-encoded JS string context (see the doc comment on
    // `SumiBoostCSSBuilder.installJavaScript`).

    /// Classic "JSON-into-JS" and string-breakout payloads. Each one is embedded as
    /// `contentCSS` (and separately as `filterCSS` and `boostId`) and the resulting
    /// script must (a) round-trip the payload byte-for-byte through the emitted JSON
    /// literal and (b) evaluate as syntactically valid JS that never executes
    /// attacker-controlled code.
    private static let hostilePayloads: [String] = [
        "\"</script><script>alert(1)</script>",
        "\\\\",
        "\\\"",
        "\u{2028}",
        "\u{2029}",
        "line1\u{2028}line2\u{2029}line3",
        "`${globalThis.pwned = true}`",
        "'; globalThis.pwned = true; '",
        "\"; globalThis.pwned = true; \"",
        "\n\r\t",
        "mix \\\" ' ` ${1+1} \u{2028} \u{2029} </script> end",
    ]

    func testHostilePayloadsRoundTripThroughEmittedJSONLiteral() throws {
        for payload in Self.hostilePayloads {
            let script = SumiBoostCSSBuilder.installJavaScript(
                boostId: payload,
                contentCSS: payload,
                filterCSS: payload
            )

            let decoded = try Self.decodedPayload(fromGeneratedScript: script, payload: payload)

            XCTAssertEqual(decoded.boostId, payload, "boostId mismatch for payload: \(payload.debugDescription)")
            XCTAssertEqual(decoded.contentCSS, payload, "contentCSS mismatch for payload: \(payload.debugDescription)")
            XCTAssertEqual(decoded.filterCSS, payload, "filterCSS mismatch for payload: \(payload.debugDescription)")
        }
    }

    /// Extracts the `const payload = {...};` object literal from the generated script
    /// and decodes it as JSON. Because the containment mechanism is "the payload is
    /// always valid JSON, and valid JSON is always safe JS source", successfully
    /// decoding it back to the exact original strings is itself evidence that no
    /// escaping was lost or corrupted while keeping the surrounding JS syntax intact.
    private static func decodedPayload(
        fromGeneratedScript script: String,
        payload: String
    ) throws -> (boostId: String, contentCSS: String, filterCSS: String) {
        // The JSON literal is emitted on a single physical line terminated by
        // ";\n": JSONEncoder escapes "\n" inside string values, and raw
        // U+2028/U+2029 (if any pass through unescaped) are not "\n", so they
        // cannot break this line-based extraction.
        guard let prefixRange = script.range(of: "const payload = "),
              let suffixRange = script.range(
                  of: ";\n",
                  range: prefixRange.upperBound..<script.endIndex
              )
        else {
            XCTFail("Could not locate payload literal boundaries in generated script")
            return ("", "", "")
        }
        let jsonSlice = script[prefixRange.upperBound..<suffixRange.lowerBound]
        let jsonData = Data(jsonSlice.utf8)
        let object = try JSONDecoder().decode([String: String].self, from: jsonData)
        return (object["boostId"] ?? "", object["contentCSS"] ?? "", object["filterCSS"] ?? "")
    }

    func testHostilePayloadsNeverExecuteAsCodeInPageContentWorld() throws {
        for payload in Self.hostilePayloads {
            try assertPayloadStaysInertWhenEvaluated(payload)
        }
    }

    /// Evaluates the real generated install script with JavaScriptCore against a
    /// minimal `document` stub, using a payload that also tries to smuggle a
    /// side-effecting statement (`globalThis.pwned = true`) via the hostile string.
    /// Passes only if: no syntax error, no thrown exception, `globalThis.pwned` is
    /// never set, and the captured `style.textContent` equals the raw payload exactly
    /// (i.e. it was treated purely as opaque string data, never re-parsed as code).
    private func assertPayloadStaysInertWhenEvaluated(_ payload: String) throws {
        let script = SumiBoostCSSBuilder.installJavaScript(
            boostId: "boost-id",
            contentCSS: payload,
            filterCSS: ""
        )

        let context = try XCTUnwrap(JSContext())
        var caughtException: String?
        context.exceptionHandler = { _, exception in
            caughtException = exception?.toString() ?? "unknown JS exception"
        }

        // Minimal DOM stub: a fake `document` sufficient for installJavaScript to run
        // without touching a real WebKit content world.
        context.evaluateScript(
            """
            var __styleTexts = [];
            var __attrs = {};
            function makeElement() {
                var el = { textContent: null, _attrs: {} };
                el.setAttribute = function(name, value) { el._attrs[name] = value; };
                return el;
            }
            var document = {
                head: { appendChild: function(el) { __styleTexts.push(el.textContent); } },
                documentElement: {
                    setAttribute: function(name, value) { __attrs[name] = value; },
                    removeAttribute: function(name) { delete __attrs[name]; }
                },
                body: null,
                createElement: function(tag) { return makeElement(); },
                querySelector: function(selector) { return null; }
            };
            """
        )
        XCTAssertNil(caughtException, "DOM stub setup threw: \(caughtException ?? "")")

        context.evaluateScript(script)

        if let caughtException {
            XCTFail(
                "Generated script threw evaluating hostile payload \(payload.debugDescription): \(caughtException)"
            )
            return
        }

        let pwned = context.evaluateScript("globalThis.pwned")
        XCTAssertTrue(
            pwned == nil || pwned!.isUndefined || pwned!.isNull,
            "Hostile payload \(payload.debugDescription) escaped its string context and executed code (globalThis.pwned was set)"
        )

        let styleTexts = context.evaluateScript("__styleTexts")
        let capturedText = styleTexts?.toArray()?.first as? String
        XCTAssertEqual(
            capturedText,
            payload,
            "Payload \(payload.debugDescription) was not preserved verbatim as inert style text"
        )
    }

    @MainActor
    func testBoostModuleContributesScriptOnlyForActiveMatchingHTTPHost() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.boosts)
        let store = SumiBoostStore(rootDirectory: temporaryDirectory())
        let module = SumiBoostsModule(
            moduleRegistry: registry,
            storeFactory: { store }
        )
        let profileId = UUID()
        let url = URL(string: "https://example.test/page")!
        let boost = try store.createDraft(for: url, profileId: profileId, isEphemeral: false)

        XCTAssertEqual(
            module.normalTabUserScripts(for: url, profileId: profileId, isEphemeral: false).count,
            1
        )
        XCTAssertTrue(
            module.normalTabUserScripts(
                for: URL(string: "https://sub.example.test/page")!,
                profileId: profileId,
                isEphemeral: false
            ).isEmpty
        )

        module.toggleActiveBoost(boost, isEphemeral: false)

        XCTAssertTrue(
            module.normalTabUserScripts(for: url, profileId: profileId, isEphemeral: false).isEmpty
        )
    }

    @MainActor
    func testManagedScriptProviderRevisionAdvancesOnlyWhenBoostScriptSetChanges() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.boosts)
        let store = SumiBoostStore(rootDirectory: temporaryDirectory())
        let module = SumiBoostsModule(
            moduleRegistry: registry,
            storeFactory: { store }
        )
        let profileId = UUID()
        let url = URL(string: "https://example.test/page")!
        _ = try store.createDraft(for: url, profileId: profileId, isEphemeral: false)
        let scripts = module.normalTabUserScripts(for: url, profileId: profileId, isEphemeral: false)
        let provider = SumiNormalTabUserScripts(managedUserScripts: scripts)

        XCTAssertFalse(provider.replaceManagedUserScriptsIfChanged(scripts))
        XCTAssertTrue(provider.replaceManagedUserScriptsIfChanged([]))
        XCTAssertEqual(provider.scriptsRevision, 1)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiBoostCSSBuilderTests-\(UUID().uuidString)", isDirectory: true)
    }
}

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

        XCTAssertTrue(css.contains("hue-rotate(45.000deg)"))
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

    @MainActor
    func testBoostModuleContributesScriptOnlyForActiveMatchingHTTPHost() throws {
        let store = SumiBoostStore(rootDirectory: temporaryDirectory())
        let module = SumiBoostsModule(store: store)
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
        let store = SumiBoostStore(rootDirectory: temporaryDirectory())
        let module = SumiBoostsModule(store: store)
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

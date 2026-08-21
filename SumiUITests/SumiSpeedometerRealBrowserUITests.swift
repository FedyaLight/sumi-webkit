import XCTest

/// Runs the real Speedometer 3.1 inside the actual Sumi application with the
/// user's real profile (installed extensions, active adblock generation) and
/// reports the score. Gated behind SUMI_RUN_REAL_SPEEDO=1 because a run takes
/// minutes.
final class SumiSpeedometerRealBrowserUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSpeedometer31InRealBrowser() throws {
        guard ProcessInfo.processInfo.environment["SUMI_RUN_REAL_SPEEDO"] == "1" else {
            throw XCTSkip("Set SUMI_RUN_REAL_SPEEDO=1 to run the real-browser benchmark")
        }

        let app = XCUIApplication()
        // No smoke flags, no container overrides: this must be the real
        // browser with the real profile state.
        app.launch()
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 20), "Browser window did not appear")

        openSpeedometer(in: app)

        let score = try waitForScore(in: app, timeout: 900)
        print("BENCH real-app speedo: \(score)")
        XCTAssertFalse(score.isEmpty, "No Speedometer score was detected")
    }

    /// Re-runs the benchmark in the already-running browser for repeat
    /// measurements without relaunch cost noise.
    func testSpeedometer31RepeatRun() throws {
        guard ProcessInfo.processInfo.environment["SUMI_RUN_REAL_SPEEDO_REPEAT"] == "1" else {
            throw XCTSkip("Set SUMI_RUN_REAL_SPEEDO_REPEAT=1 to re-run in the live browser")
        }
        let app = XCUIApplication(bundleIdentifier: "com.sumi.browser.testhost")
        app.activate()
        XCTAssertTrue(app.waitForExistence(timeout: 10), "Running browser was not found")
        _ = try waitForScore(in: app, timeout: 60)
        startBenchmark(in: app)
        let score = try waitForScore(in: app, timeout: 900)
        print("BENCH real-app speedo repeat: \(score)")
    }

    private func openSpeedometer(in app: XCUIApplication) {
        app.menuBars.menuBarItems["File"].click()
        app.menuItems["New Tab"].click()
        let input = app.textFields["command-palette-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "URL Hub did not appear")
        input.click()
        input.typeText("https://browserbench.org/Speedometer3.1/\n")
        let urlBar = app.staticTexts["sidebar-urlbar"]
        let loaded = NSPredicate(
            format: "value CONTAINS %@",
            "browserbench.org"
        )
        let exists = NSPredicate(format: "exists == true")
        let expectation = expectation(
            for: NSCompoundPredicate(andPredicateWithSubpredicates: [loaded, exists]),
            evaluatedWith: urlBar,
            handler: nil
        )
        wait(for: [expectation], timeout: 45)
    }

    @discardableResult
    private func startBenchmark(in app: XCUIApplication) -> Bool {
        let startButton = app.buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "Start", "Start tests")
        ).firstMatch
        if startButton.waitForExistence(timeout: 30), startButton.isHittable {
            startButton.click()
            return true
        }
        // Fallback: the primary button sits near the horizontal center,
        // slightly above the middle of the viewport.
        let window = app.windows.element(boundBy: 0)
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)).tap()
        return true
    }

    private func waitForScore(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) throws -> String {
        startBenchmark(in: app)
        let deadline = Date().addingTimeInterval(timeout)
        var lastCandidate = ""
        var stableSamples = 0
        while Date() < deadline {
            sleep(15)
            let numeric = NSPredicate(
                format: "label MATCHES %@",
                "^[0-9]{2}\\.[0-9]$"
            )
            let candidates = app.descendants(matching: .any)
                .matching(numeric).allElementsBoundByIndex
            let labels = candidates.compactMap { $0.label }
            if let candidate = labels.first(where: {
                let value = Double($0) ?? 0
                return (15...80).contains(value)
            }) {
                if candidate == lastCandidate {
                    stableSamples += 1
                } else {
                    stableSamples = 1
                    lastCandidate = candidate
                }
                if stableSamples >= 2 {
                    return candidate
                }
            } else {
                stableSamples = 0
            }
        }
        XCTFail("Speedometer did not produce a score within \(timeout)s")
        return ""
    }
}

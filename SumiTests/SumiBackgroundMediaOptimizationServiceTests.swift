import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BackgroundMediaOptimizationTests: XCTestCase {
    func testReconcileUsesInjectedRuntimeForHiddenSilentTabWithoutBrowserManager() {
        let harness = BackgroundMediaOptimizationHarness()
        let windowID = UUID()
        let tab = makeTab()
        let webView = harness.attach(tab, windowID: windowID)
        harness.visibleTabIDsByWindow = [windowID: []]

        harness.service.reconcileNow(reason: "visibility")

        XCTAssertEqual(harness.recorder.commands.count, 1)
        XCTAssertIdentical(harness.recorder.commands[0].webView, webView)
        XCTAssertEqual(harness.recorder.commands[0].mode, .hiddenPauseSilentVideo)
        XCTAssertEqual(harness.recorder.commands[0].graceMilliseconds, 10_000)
        XCTAssertEqual(harness.recorder.commands[0].reason, "visibility")
        XCTAssertTrue(
            harness.recorder.commands[0].source.contains("__sumiBackgroundVideoOptimizer")
        )
    }

    func testHiddenAudibleTabPreservesAudio() {
        let harness = BackgroundMediaOptimizationHarness()
        let windowID = UUID()
        let tab = makeTab()
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        harness.attach(tab, windowID: windowID)
        harness.visibleTabIDsByWindow = [windowID: []]

        harness.service.reconcileNow(reason: "audio")

        XCTAssertEqual(harness.recorder.commands.count, 1)
        XCTAssertEqual(harness.recorder.commands[0].mode, .hiddenPreserveAudio)
    }

    func testVisibleAndIneligibleHiddenTabsUseVisibleMode() {
        let harness = BackgroundMediaOptimizationHarness()
        let windowID = UUID()
        let visibleTab = makeTab()
        let ineligibleHiddenTab = makeTab(url: URL(fileURLWithPath: "/tmp/local-video.html"))
        harness.attach(visibleTab, windowID: windowID)
        harness.attach(ineligibleHiddenTab, windowID: windowID)
        harness.visibleTabIDsByWindow = [windowID: [visibleTab.id]]

        harness.service.reconcileNow(reason: "visibility")

        XCTAssertEqual(harness.recorder.commands.count, 2)
        XCTAssertEqual(harness.recorder.commands[0].mode, .visible)
        XCTAssertEqual(harness.recorder.commands[1].mode, .visible)
    }

    func testEnergySaverRuntimeUsesShortHiddenGraceInterval() {
        let harness = BackgroundMediaOptimizationHarness()
        let windowID = UUID()
        let tab = makeTab()
        harness.energySaverActive = true
        harness.attach(tab, windowID: windowID)
        harness.visibleTabIDsByWindow = [windowID: []]

        harness.service.reconcileNow(reason: "energy-saver")

        XCTAssertEqual(harness.recorder.commands.count, 1)
        XCTAssertEqual(harness.recorder.commands[0].graceMilliseconds, 2_000)
    }

    func testDuplicateCommandsAreSuppressedUntilNavigationFinishResetsCache() {
        let harness = BackgroundMediaOptimizationHarness()
        let windowID = UUID()
        let tab = makeTab()
        harness.attach(tab, windowID: windowID)
        harness.visibleTabIDsByWindow = [windowID: []]

        harness.service.reconcileNow(reason: "first")
        harness.service.reconcileNow(reason: "second")
        harness.service.reconcileNow(reason: "navigation-did-finish")

        XCTAssertEqual(harness.recorder.commands.count, 2)
        XCTAssertEqual(harness.recorder.commands[0].reason, "first")
        XCTAssertEqual(harness.recorder.commands[1].reason, "navigation-did-finish")
    }

    func testScheduleReconcileCoalescesPendingReasons() async {
        let harness = BackgroundMediaOptimizationHarness()
        let windowID = UUID()
        let tab = makeTab()
        harness.attach(tab, windowID: windowID)
        harness.visibleTabIDsByWindow = [windowID: []]
        let commandRecorded = expectation(description: "background media command recorded")
        harness.recorder.onRecord = {
            commandRecorded.fulfill()
        }

        harness.service.scheduleReconcile(reason: "visibility")
        harness.service.scheduleReconcile(reason: "audio")
        await fulfillment(of: [commandRecorded], timeout: 1)

        XCTAssertEqual(harness.recorder.commands.count, 1)
        XCTAssertEqual(harness.recorder.commands[0].reason, "visibility,audio")
    }

    func testMissingCoordinatorDoesNotReadBroadRuntimeSnapshots() {
        let service = SumiBackgroundMediaOptimizationService()
        var energySaverReadCount = 0
        var allKnownTabsReadCount = 0
        var visibleTabsReadCount = 0
        var commandCount = 0
        service.attach(
            runtime: SumiBackgroundMediaOptimizationRuntime(
                webViewCoordinator: { nil },
                energySaverActive: {
                    energySaverReadCount += 1
                    return false
                },
                allKnownTabs: {
                    allKnownTabsReadCount += 1
                    return []
                },
                visibleTabIDsByWindow: {
                    visibleTabsReadCount += 1
                    return [:]
                },
                executeJavaScriptCommand: { _, _, _ in
                    commandCount += 1
                }
            )
        )

        service.reconcileNow(reason: "no-coordinator")

        XCTAssertEqual(energySaverReadCount, 0)
        XCTAssertEqual(allKnownTabsReadCount, 0)
        XCTAssertEqual(visibleTabsReadCount, 0)
        XCTAssertEqual(commandCount, 0)
    }

    private func makeTab(url: URL = URL(string: "https://example.com/video")!) -> Tab {
        Tab(
            url: url,
            name: "Example",
            loadsCachedFaviconOnInit: false
        )
    }
}

@MainActor
private final class BackgroundMediaOptimizationHarness {
    let service = SumiBackgroundMediaOptimizationService()
    let coordinator = WebViewCoordinator()
    let recorder = MediaOptimizationCommandRecorder()
    var tabs: [Tab] = []
    var visibleTabIDsByWindow: [UUID: Set<UUID>] = [:]
    var energySaverActive = false

    init() {
        service.attach(runtime: makeRuntime())
    }

    @discardableResult
    func attach(
        _ tab: Tab,
        windowID: UUID,
        webView: WKWebView = WKWebView()
    ) -> WKWebView {
        tabs.append(tab)
        coordinator.setWebView(webView, for: tab.id, in: windowID)
        return webView
    }

    private func makeRuntime() -> SumiBackgroundMediaOptimizationRuntime {
        SumiBackgroundMediaOptimizationRuntime(
            webViewCoordinator: { [weak self] in
                self?.coordinator
            },
            energySaverActive: { [weak self] in
                self?.energySaverActive ?? false
            },
            allKnownTabs: { [weak self] in
                self?.tabs ?? []
            },
            visibleTabIDsByWindow: { [weak self] in
                self?.visibleTabIDsByWindow ?? [:]
            },
            executeJavaScriptCommand: { [weak self] webView, source, arguments in
                self?.recorder.record(webView: webView, source: source, arguments: arguments)
            }
        )
    }
}

@MainActor
private final class MediaOptimizationCommandRecorder {
    private(set) var commands: [RecordedMediaOptimizationCommand] = []
    var onRecord: (() -> Void)?

    func record(webView: WKWebView, source: String, arguments: [String: Any]) {
        commands.append(
            RecordedMediaOptimizationCommand(
                webView: webView,
                source: source,
                mode: (arguments["mode"] as? String)
                    .flatMap(SumiBackgroundMediaOptimizationMode.init(rawValue:)),
                graceMilliseconds: arguments["graceMs"] as? Int,
                reason: arguments["reason"] as? String
            )
        )
        onRecord?()
    }
}

private struct RecordedMediaOptimizationCommand {
    let webView: WKWebView
    let source: String
    let mode: SumiBackgroundMediaOptimizationMode?
    let graceMilliseconds: Int?
    let reason: String?
}

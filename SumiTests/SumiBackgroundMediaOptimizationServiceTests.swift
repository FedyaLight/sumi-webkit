import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BackgroundMediaOptimizationTests: XCTestCase {
    func testReconcileUsesInjectedRuntimeForHiddenSilentTabWithoutBrowserManager() {
        let harness = BackgroundMediaOptimizationHarness()
        let windowID = UUID()
        let tab = harness.makeTab()
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
        let tab = harness.makeTab()
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
        let visibleTab = harness.makeTab()
        let ineligibleHiddenTab = harness.makeTab(
            url: URL(fileURLWithPath: "/tmp/local-video.html")
        )
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
        let tab = harness.makeTab()
        harness.energySaverActive = true
        harness.attach(tab, windowID: windowID)
        harness.visibleTabIDsByWindow = [windowID: []]

        harness.service.reconcileNow(reason: "energy-saver")

        XCTAssertEqual(harness.recorder.commands.count, 1)
        XCTAssertEqual(harness.recorder.commands[0].graceMilliseconds, 2_000)
    }

    func testNavigationInvalidationReappliesOnlyTheNavigatedWebViewCommand() {
        let harness = BackgroundMediaOptimizationHarness()
        let windowID = UUID()
        let navigatedTab = harness.makeTab()
        let unaffectedTab = harness.makeTab()
        let navigatedWebView = harness.attach(navigatedTab, windowID: windowID)
        let unaffectedWebView = harness.attach(unaffectedTab, windowID: windowID)
        harness.visibleTabIDsByWindow = [windowID: []]

        harness.service.reconcileNow(reason: "first")
        harness.service.reconcileNow(reason: "second")
        harness.service.invalidateAppliedCommand(for: navigatedWebView)
        harness.service.reconcileNow(reason: "navigation-did-finish")

        XCTAssertEqual(harness.recorder.commands.count, 3)
        XCTAssertEqual(harness.recorder.commands[0].reason, "first")
        XCTAssertEqual(harness.recorder.commands[1].reason, "first")
        XCTAssertIdentical(harness.recorder.commands[2].webView, navigatedWebView)
        XCTAssertEqual(harness.recorder.commands[2].reason, "navigation-did-finish")
        XCTAssertEqual(
            harness.recorder.commands.filter { $0.webView === unaffectedWebView }.count,
            1
        )
    }

    func testScheduleReconcileCoalescesPendingReasons() async {
        let harness = BackgroundMediaOptimizationHarness()
        let windowID = UUID()
        let tab = harness.makeTab()
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

    func testInitAndDetachedCallsCreateNoResourcesOrDeferredWork() async {
        let notificationCenter = CountingNotificationCenter()
        let service = SumiBackgroundMediaOptimizationService(
            notificationCenter: notificationCenter
        )
        let probe = BackgroundMediaRuntimeProbe()

        XCTAssertEqual(notificationCenter.activeObserverCount, 0)
        service.scheduleReconcile(reason: "detached-schedule")
        service.invalidateAppliedCommand(for: probe.webView)
        notificationCenter.post(name: .sumiEnergySaverPolicyChanged, object: nil)

        service.attach(runtime: probe.makeRuntime())
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(notificationCenter.activeObserverCount, 1)
        XCTAssertEqual(probe.energySaverReadCount, 0)
        XCTAssertTrue(probe.commandReasons.isEmpty)

        service.detach()
        XCTAssertEqual(notificationCenter.activeObserverCount, 0)
    }

    func testReattachReplacesObserverAndRuntimeWithoutDuplication() async {
        let notificationCenter = CountingNotificationCenter()
        let service = SumiBackgroundMediaOptimizationService(
            notificationCenter: notificationCenter
        )
        let retiredProbe = BackgroundMediaRuntimeProbe()
        let replacementProbe = BackgroundMediaRuntimeProbe()
        let commandRecorded = expectation(description: "replacement runtime command")
        replacementProbe.onCommand = { commandRecorded.fulfill() }

        service.attach(runtime: retiredProbe.makeRuntime())
        service.attach(runtime: replacementProbe.makeRuntime())

        XCTAssertEqual(notificationCenter.registrationCount, 2)
        XCTAssertEqual(notificationCenter.removalCount, 1)
        XCTAssertEqual(notificationCenter.activeObserverCount, 1)

        notificationCenter.post(name: .sumiEnergySaverPolicyChanged, object: nil)
        await fulfillment(of: [commandRecorded], timeout: 1)

        XCTAssertEqual(retiredProbe.energySaverReadCount, 0)
        XCTAssertTrue(retiredProbe.commandReasons.isEmpty)
        XCTAssertEqual(replacementProbe.energySaverReadCount, 1)
        XCTAssertEqual(
            replacementProbe.commandReasons,
            ["energy-saver-policy-changed"]
        )
    }

    func testDetachCancelsQueuedReconcileAndDoesNotRunAgainstReplacementRuntime() async {
        let service = SumiBackgroundMediaOptimizationService(
            notificationCenter: CountingNotificationCenter()
        )
        let retiredProbe = BackgroundMediaRuntimeProbe()
        let replacementProbe = BackgroundMediaRuntimeProbe()

        service.attach(runtime: retiredProbe.makeRuntime())
        service.scheduleReconcile(reason: "retired-runtime")
        service.detach()
        service.attach(runtime: replacementProbe.makeRuntime())
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(retiredProbe.commandReasons.isEmpty)
        XCTAssertTrue(replacementProbe.commandReasons.isEmpty)

        let commandRecorded = expectation(description: "replacement reconcile")
        replacementProbe.onCommand = { commandRecorded.fulfill() }
        service.scheduleReconcile(reason: "replacement-runtime")
        await fulfillment(of: [commandRecorded], timeout: 1)

        XCTAssertEqual(retiredProbe.energySaverReadCount, 0)
        XCTAssertEqual(replacementProbe.energySaverReadCount, 1)
        XCTAssertEqual(replacementProbe.commandReasons, ["replacement-runtime"])
    }

    func testReattachRejectsNotificationQueuedByRetiredObserver() async {
        let notificationCenter = CountingNotificationCenter()
        let service = SumiBackgroundMediaOptimizationService(
            notificationCenter: notificationCenter
        )
        let retiredProbe = BackgroundMediaRuntimeProbe()
        let replacementProbe = BackgroundMediaRuntimeProbe()
        service.attach(runtime: retiredProbe.makeRuntime())

        notificationCenter.post(name: .sumiEnergySaverPolicyChanged, object: nil)
        service.detach()
        service.attach(runtime: replacementProbe.makeRuntime())
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(retiredProbe.energySaverReadCount, 0)
        XCTAssertEqual(replacementProbe.energySaverReadCount, 0)
        XCTAssertTrue(retiredProbe.commandReasons.isEmpty)
        XCTAssertTrue(replacementProbe.commandReasons.isEmpty)
    }

    func testDetachClearsCommandCacheBeforeReattach() {
        let service = SumiBackgroundMediaOptimizationService()
        let probe = BackgroundMediaRuntimeProbe()
        let runtime = probe.makeRuntime()

        service.attach(runtime: runtime)
        service.reconcileNow(reason: "first-attachment")
        service.detach()
        service.attach(runtime: runtime)
        service.reconcileNow(reason: "second-attachment")

        XCTAssertEqual(
            probe.commandReasons,
            ["first-attachment", "second-attachment"]
        )
    }

    func testDeinitRemovesObserverAndReleasesRuntime() {
        let notificationCenter = CountingNotificationCenter()
        var service: SumiBackgroundMediaOptimizationService? =
            SumiBackgroundMediaOptimizationService(
                notificationCenter: notificationCenter
            )
        var probe: BackgroundMediaRuntimeProbe? = BackgroundMediaRuntimeProbe()
        weak let releasedProbe = probe
        if let probe {
            service?.attach(runtime: probe.makeRuntime())
        }
        probe = nil

        XCTAssertEqual(notificationCenter.activeObserverCount, 1)
        XCTAssertNotNil(releasedProbe)

        service = nil

        XCTAssertEqual(notificationCenter.activeObserverCount, 0)
        XCTAssertNil(releasedProbe)
    }

    func testAttachedRuntimeWithEmptyCatalogDoesNotExecuteCommands() {
        let service = SumiBackgroundMediaOptimizationService()
        var energySaverReadCount = 0
        var allKnownTabsReadCount = 0
        var visibleTabsReadCount = 0
        var commandCount = 0
        service.attach(
            runtime: SumiBackgroundMediaOptimizationRuntime(
                liveWebViewEntries: { _ in [] },
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

        service.reconcileNow(reason: "empty-catalog")

        XCTAssertEqual(energySaverReadCount, 1)
        XCTAssertEqual(allKnownTabsReadCount, 1)
        XCTAssertEqual(visibleTabsReadCount, 1)
        XCTAssertEqual(commandCount, 0)
    }

}

private final class CountingNotificationCenter: NotificationCenter, @unchecked Sendable {
    private(set) var registrationCount = 0
    private(set) var removalCount = 0

    var activeObserverCount: Int {
        registrationCount - removalCount
    }

    override func addObserver(
        forName name: Notification.Name?,
        object observedObject: Any?,
        queue: OperationQueue?,
        using block: @Sendable @escaping (Notification) -> Void
    ) -> NSObjectProtocol {
        registrationCount += 1
        return super.addObserver(
            forName: name,
            object: observedObject,
            queue: queue,
            using: block
        )
    }

    override func removeObserver(_ observer: Any) {
        removalCount += 1
        super.removeObserver(observer)
    }
}

@MainActor
private final class BackgroundMediaRuntimeProbe {
    let webViewRuntime = makeTestWebViewRuntimeGraph()
    let windowID = UUID()
    lazy var tab = Tab(
        url: URL(string: "https://example.com/video")!,
        name: "Runtime Probe",
        webViewSessions: webViewRuntime.webViewSessions,
        loadsCachedFaviconOnInit: false
    )
    lazy var webView: FocusableWKWebView = {
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        return webView
    }()
    private(set) var energySaverReadCount = 0
    private(set) var commandReasons: [String] = []
    var onCommand: (() -> Void)?

    func makeRuntime() -> SumiBackgroundMediaOptimizationRuntime {
        SumiBackgroundMediaOptimizationRuntime(
            liveWebViewEntries: { [self] candidate in
                guard candidate.id == tab.id else { return [] }
                return [(windowID: Optional(windowID), webView: webView)]
            },
            energySaverActive: { [self] in
                energySaverReadCount += 1
                return false
            },
            allKnownTabs: { [self] in [tab] },
            visibleTabIDsByWindow: { [self] in [windowID: []] },
            executeJavaScriptCommand: { [self] _, _, arguments in
                commandReasons.append(arguments["reason"] as? String ?? "")
                onCommand?()
            }
        )
    }
}

@MainActor
private final class BackgroundMediaOptimizationHarness {
    let service = SumiBackgroundMediaOptimizationService()
    let webViewRuntime = makeTestWebViewRuntimeGraph()
    let recorder = MediaOptimizationCommandRecorder()
    var tabs: [Tab] = []
    var visibleTabIDsByWindow: [UUID: Set<UUID>] = [:]
    var energySaverActive = false

    init() {
        service.attach(runtime: makeRuntime())
    }

    func makeTab(
        url: URL = URL(string: "https://example.com/video")!
    ) -> Tab {
        Tab(
            url: url,
            name: "Example",
            webViewSessions: webViewRuntime.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
    }

    @discardableResult
    func attach(
        _ tab: Tab,
        windowID: UUID,
        webView: FocusableWKWebView = FocusableWKWebView()
    ) -> WKWebView {
        tabs.append(tab)
        webView.owningTab = tab
        webViewRuntime.trackedWebViewAdmission.registerAuxiliaryTrackedWebView(
            webView,
            for: tab,
            in: windowID
        )
        return webView
    }

    private func makeRuntime() -> SumiBackgroundMediaOptimizationRuntime {
        SumiBackgroundMediaOptimizationRuntime(
            liveWebViewEntries: { [weak self] tab in
                guard let self else { return [] }
                return webViewRuntime.ownershipQuery.windowIDs(for: tab.id)
                    .compactMap { windowID in
                        webViewRuntime.ownershipQuery.webView(
                            for: tab.id,
                            in: windowID
                        ).map { (windowID: Optional(windowID), webView: $0) }
                    }
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

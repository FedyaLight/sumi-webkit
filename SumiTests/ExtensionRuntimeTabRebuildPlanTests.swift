import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeTabRebuildPlanTests: XCTestCase {
    func testCaptureIsZeroCostWithoutLoadedUserRuntime() {
        let tab = makeCandidateTab()
        var liveWebViewQueries = 0
        let plan = ExtensionRuntimeTabRebuildPlan.capture(
            hasLoadedUserRuntime: false,
            controllers: [],
            tabs: [tab],
            liveWebViews: { _ in
                liveWebViewQueries += 1
                return []
            }
        )

        XCTAssertTrue(
            plan.execute(
                canonicalTabs: RuntimeTabRebuildQuery(canonical: tab),
                runtime: makeRuntime(
                    rebuilds: RuntimeTabRebuildRecorder(
                        outcome: .committed
                    )
                ),
                trace: { _, _ in
                    XCTFail("an empty plan must not emit trace events")
                }
            ).isEmpty
        )
        XCTAssertEqual(liveWebViewQueries, 0)
        assertRuntimeStatePreserved(on: tab)
    }

    func testExecutionRebuildsExactCanonicalTabOnlyOnce() {
        let tab = makeCandidateTab()
        let tabs = RuntimeTabRebuildQuery(canonical: tab)
        let rebuilds = RuntimeTabRebuildRecorder(outcome: .committed)
        var traces: [(Tab, ExtensionRuntimeTabRebuildPlan.Outcome)] = []
        let plan = makePlan(tabs: [tab, tab])

        let executions = plan.execute(
            canonicalTabs: tabs,
            runtime: makeRuntime(rebuilds: rebuilds),
            trace: { traces.append(($0, $1)) }
        )

        XCTAssertEqual(executions.count, 1)
        XCTAssertEqual(executions[0].tabID, tab.id)
        XCTAssertEqual(executions[0].tabIdentity, ObjectIdentifier(tab))
        XCTAssertEqual(executions[0].outcome, .committed)
        XCTAssertEqual(rebuilds.tabs.count, 1)
        XCTAssertIdentical(rebuilds.tabs[0], tab)
        XCTAssertEqual(traces.count, 1)
        XCTAssertIdentical(traces[0].0, tab)
        XCTAssertEqual(traces[0].1, .committed)
        assertRuntimeStateCleared(on: tab)
    }

    func testSameUUIDReplacementRejectsStaleCandidateWithoutClearingOrRebuild() {
        let candidate = makeCandidateTab()
        let replacement = Tab(
            id: candidate.id,
            url: URL(string: "https://replacement.example")!,
            name: "Replacement"
        )
        let tabs = RuntimeTabRebuildQuery(canonical: replacement)
        let rebuilds = RuntimeTabRebuildRecorder(outcome: .committed)
        var tracedTab: Tab?
        var tracedOutcome: ExtensionRuntimeTabRebuildPlan.Outcome?
        let plan = makePlan(tabs: [candidate])

        let executions = plan.execute(
            canonicalTabs: tabs,
            runtime: makeRuntime(rebuilds: rebuilds),
            trace: {
                tracedTab = $0
                tracedOutcome = $1
            }
        )

        XCTAssertEqual(
            executions,
            [
                .init(
                    tabID: candidate.id,
                    tabIdentity: ObjectIdentifier(candidate),
                    outcome: .staleTab
                ),
            ]
        )
        XCTAssertIdentical(tracedTab, candidate)
        XCTAssertEqual(tracedOutcome, .staleTab)
        XCTAssertTrue(rebuilds.tabs.isEmpty)
        assertRuntimeStatePreserved(on: candidate)
    }

    func testBrowserUnavailableDoesNotClearOrSubmitCanonicalCandidate() {
        let tab = makeCandidateTab()
        let tabs = RuntimeTabRebuildQuery(canonical: tab)
        let rebuilds = RuntimeTabRebuildRecorder(outcome: .committed)
        var tracedOutcome: ExtensionRuntimeTabRebuildPlan.Outcome?
        let plan = makePlan(tabs: [tab])

        let executions = plan.execute(
            canonicalTabs: tabs,
            runtime: makeRuntime(
                browserAvailable: false,
                rebuilds: rebuilds
            ),
            trace: { _, outcome in tracedOutcome = outcome }
        )

        XCTAssertEqual(executions.map(\.outcome), [.browserUnavailable])
        XCTAssertEqual(tracedOutcome, .browserUnavailable)
        XCTAssertTrue(rebuilds.tabs.isEmpty)
        assertRuntimeStatePreserved(on: tab)
    }

    func testMapsEveryTypedRebuildSubmissionOutcome() {
        let cases: [(
            submission: ExtensionTabWebViewRebuildSubmissionOutcome,
            expected: ExtensionRuntimeTabRebuildPlan.Outcome
        )] = [
            (.committed, .committed),
            (.deferred, .deferred),
            (.noLiveWindows, .noLiveWindows),
            (.failed, .failed),
        ]

        for testCase in cases {
            let tab = makeCandidateTab()
            let tabs = RuntimeTabRebuildQuery(canonical: tab)
            let rebuilds = RuntimeTabRebuildRecorder(
                outcome: testCase.submission
            )
            var tracedOutcome: ExtensionRuntimeTabRebuildPlan.Outcome?

            let executions = makePlan(tabs: [tab]).execute(
                canonicalTabs: tabs,
                runtime: makeRuntime(rebuilds: rebuilds),
                trace: { _, outcome in tracedOutcome = outcome }
            )

            XCTAssertEqual(
                executions.map(\.outcome),
                [testCase.expected],
                "submission: \(testCase.submission)"
            )
            XCTAssertEqual(
                tracedOutcome,
                testCase.expected,
                "submission: \(testCase.submission)"
            )
            XCTAssertEqual(rebuilds.tabs.count, 1)
            XCTAssertIdentical(rebuilds.tabs[0], tab)
            assertRuntimeStateCleared(on: tab)
        }
    }

    private func makeCandidateTab() -> Tab {
        let tab = Tab(
            id: UUID(),
            url: URL(string: "https://candidate.example")!,
            name: "Runtime rebuild candidate"
        )
        let configuration = WKWebViewConfiguration()
        configuration.webExtensionController = WKWebExtensionController(
            configuration: .init(identifier: UUID())
        )
        tab.webViewConfigurationOverride = configuration
        tab.extensionPageRuntimeOwner.documentSequence = 9
        tab.extensionPageRuntimeOwner.committedMainDocumentURL = tab.url
        tab.extensionPageRuntimeOwner.openNotifiedDocumentSequence = 9
        tab.extensionPageRuntimeOwner.markDidOpenTab(
            generation: ExtensionTabPublicationRevision(generation: 23)
        )
        return tab
    }

    private func makePlan(tabs: [Tab]) -> ExtensionRuntimeTabRebuildPlan {
        ExtensionRuntimeTabRebuildPlan.capture(
            hasLoadedUserRuntime: true,
            controllers: [],
            tabs: tabs,
            liveWebViews: { _ in [] }
        )
    }

    private func makeRuntime(
        browserAvailable: Bool = true,
        rebuilds: RuntimeTabRebuildRecorder
    ) -> ExtensionManagerRuntime {
        ExtensionManagerRuntime(
            currentProfile: { nil },
            profile: { _ in nil },
            ephemeralProfile: { _ in nil },
            windowState: { _ in nil },
            windowRegistrationReceipt: { _ in nil },
            registeredWindow: { _ in nil },
            activeWindowState: { nil },
            allTabs: { [] },
            allWindowStates: { [] },
            windowStateContainingTab: { _ in nil },
            windowOwnedWebView: { _, _ in nil },
            primaryTrackedWindowId: { _ in nil },
            untrackedOwnedWebView: { _ in nil },
            trackedWebViews: { _ in [] },
            rebuildLiveWebViews: { rebuilds.rebuild($0) },
            websiteDataMutationAdmissionIsBlocked: { _ in false },
            waitForWebsiteDataMutationAdmission: { _ in true },
            browserRuntimeAvailable: { browserAvailable },
            extensionsModuleEnabled: { .enabled(true) }
        )
    }

    private func assertRuntimeStatePreserved(
        on tab: Tab,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNotNil(
            tab.webViewConfigurationOverride,
            file: file,
            line: line
        )
        XCTAssertEqual(
            tab.extensionPageRuntimeOwner.documentBindingSnapshot()
                .documentSequence,
            9,
            file: file,
            line: line
        )
        XCTAssertEqual(
            tab.extensionPageRuntimeOwner.currentOpenNotificationGeneration(),
            ExtensionTabPublicationRevision(generation: 23),
            file: file,
            line: line
        )
    }

    private func assertRuntimeStateCleared(
        on tab: Tab,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNil(
            tab.webViewConfigurationOverride,
            file: file,
            line: line
        )
        XCTAssertNil(
            tab.webExtensionContextOverride,
            file: file,
            line: line
        )
        XCTAssertEqual(
            tab.extensionPageRuntimeOwner.documentBindingSnapshot()
                .documentSequence,
            0,
            file: file,
            line: line
        )
        XCTAssertNil(
            tab.extensionPageRuntimeOwner.currentOpenNotificationGeneration(),
            file: file,
            line: line
        )
    }
}

@available(macOS 15.5, *)
@MainActor
private final class RuntimeTabRebuildQuery: ExtensionTabQuery {
    var canonical: Tab?

    init(canonical: Tab?) {
        self.canonical = canonical
    }

    func extensionTab(for tabId: UUID) -> Tab? {
        canonical?.id == tabId ? canonical : nil
    }

    func isTransientExtensionTab(_: Tab) -> Bool { false }
    func isAuxiliaryMiniWindowTab(_: Tab) -> Bool { false }
    func isPinnedExtensionTab(_: Tab) -> Bool { false }
}

@available(macOS 15.5, *)
@MainActor
private final class RuntimeTabRebuildRecorder {
    let outcome: ExtensionTabWebViewRebuildSubmissionOutcome
    private(set) var tabs: [Tab] = []

    init(outcome: ExtensionTabWebViewRebuildSubmissionOutcome) {
        self.outcome = outcome
    }

    func rebuild(_ tab: Tab) -> ExtensionTabWebViewRebuildSubmissionOutcome {
        tabs.append(tab)
        return outcome
    }
}

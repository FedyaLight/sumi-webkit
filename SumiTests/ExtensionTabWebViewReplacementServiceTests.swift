import WebKit
import XCTest

@testable import Sumi

@MainActor
final class ExtensionTabWebViewReplacementServiceTests: XCTestCase {
    func testReentrantConfigurationReplacementInSameSlotSupersedesOuterRequest()
        throws {
        let fixture = makeFixture()
        let windowID = UUID()
        var innerOutcome: ExtensionTabWebViewReplacementOutcome?
        var preparedInner: WKWebView?
        var outerPreparationCount = 0

        let outerOutcome = fixture.service.replace(
            for: fixture.tab,
            in: windowID,
            reason: "test.outer",
            prepareCandidateConfiguration: { _, _ in
                innerOutcome = fixture.service.replace(
                    for: fixture.tab,
                    in: windowID,
                    reason: "test.inner",
                    prepareCommittedReplacement: { preparedInner = $0 },
                    validate: { _ in true }
                )
            },
            prepareCommittedReplacement: { _ in
                outerPreparationCount += 1
            },
            validate: { _ in true }
        )

        guard case .superseded = outerOutcome else {
            return XCTFail("Outer same-slot request must be superseded")
        }
        guard case .committed(let innerWebView)? = innerOutcome else {
            return XCTFail("Inner replacement must commit")
        }
        XCTAssertIdentical(preparedInner, innerWebView)
        XCTAssertIdentical(
            fixture.runtime.ownershipQuery.webView(
                for: fixture.tab.id,
                in: windowID
            ),
            innerWebView
        )
        XCTAssertEqual(outerPreparationCount, 0)
    }

    func testReentrantReplacementInDifferentWindowDoesNotSupersedeOuterRequest()
        throws {
        let fixture = makeFixture()
        let outerWindowID = UUID()
        let innerWindowID = UUID()
        var innerOutcome: ExtensionTabWebViewReplacementOutcome?

        let outerOutcome = fixture.service.replace(
            for: fixture.tab,
            in: outerWindowID,
            reason: "test.outer-window",
            prepareCandidateConfiguration: { _, _ in
                innerOutcome = fixture.service.replace(
                    for: fixture.tab,
                    in: innerWindowID,
                    reason: "test.inner-window",
                    validate: { _ in true }
                )
            },
            validate: { _ in true }
        )

        guard case .committed(let outerWebView) = outerOutcome,
              case .committed(let innerWebView)? = innerOutcome else {
            return XCTFail("Independent window slots must both commit")
        }
        XCTAssertIdentical(
            fixture.runtime.ownershipQuery.webView(
                for: fixture.tab.id,
                in: outerWindowID
            ),
            outerWebView
        )
        XCTAssertIdentical(
            fixture.runtime.ownershipQuery.webView(
                for: fixture.tab.id,
                in: innerWindowID
            ),
            innerWebView
        )
        XCTAssertFalse(outerWebView === innerWebView)
    }

    func testReentrantDetachedReplacementSupersedesOuterRequest() {
        let fixture = makeFixture()
        var innerOutcome: ExtensionTabWebViewReplacementOutcome?

        let outerOutcome = fixture.service.replace(
            for: fixture.tab,
            in: nil,
            reason: "test.outer-detached",
            prepareCandidateConfiguration: { _, _ in
                innerOutcome = fixture.service.replace(
                    for: fixture.tab,
                    in: nil,
                    reason: "test.inner-detached",
                    validate: { _ in true }
                )
            },
            validate: { _ in true }
        )

        guard case .superseded = outerOutcome,
              case .committed(let innerWebView)? = innerOutcome else {
            return XCTFail("Newest detached request must win")
        }
        XCTAssertIdentical(
            fixture.tab.webViewSession.untrackedWebView,
            innerWebView
        )
    }

    func testValidationRejectionCleansCandidateWithoutCanonicalResidence() {
        let fixture = makeFixture()
        let windowID = UUID()
        var rejectedCandidate: WKWebView?

        let outcome = fixture.service.replace(
            for: fixture.tab,
            in: windowID,
            reason: "test.validation-rejection",
            validate: { candidate in
                rejectedCandidate = candidate
                return false
            }
        )

        guard case .rejected(.validationFailed) = outcome else {
            return XCTFail("Validation failure must remain typed")
        }
        XCTAssertNil(
            fixture.runtime.ownershipQuery.webView(
                for: fixture.tab.id,
                in: windowID
            )
        )
        XCTAssertNil(
            rejectedCandidate?.sumiPreparedConfigurationPolicyChange
        )
        XCTAssertNil(
            rejectedCandidate.flatMap {
                fixture.runtime.webViewSessions.residence(of: $0)
            }
        )
    }

    func testReentrantCommittedPreparationSupersedesOuterResult() {
        let fixture = makeFixture()
        let windowID = UUID()
        var innerOutcome: ExtensionTabWebViewReplacementOutcome?
        var outerCommittedCandidate: WKWebView?

        let outerOutcome = fixture.service.replace(
            for: fixture.tab,
            in: windowID,
            reason: "test.outer-committed-callback",
            prepareCommittedReplacement: { candidate in
                outerCommittedCandidate = candidate
                innerOutcome = fixture.service.replace(
                    for: fixture.tab,
                    in: windowID,
                    reason: "test.inner-committed-callback"
                )
            }
        )

        guard case .superseded = outerOutcome,
              case .committed(let innerWebView)? = innerOutcome else {
            return XCTFail("Newer same-slot replacement must own the result")
        }
        XCTAssertFalse(outerCommittedCandidate === innerWebView)
        XCTAssertIdentical(
            fixture.runtime.ownershipQuery.webView(
                for: fixture.tab.id,
                in: windowID
            ),
            innerWebView
        )
    }

    func testWebsiteDataGateDefersBeforeCandidateCreationAndReplaysFreshCandidate()
        async throws {
        let fixture = makeFixture()
        let profileID = try XCTUnwrap(fixture.manager.currentProfile?.id)
        let windowID = UUID()
        var initialOutcome: ExtensionTabWebViewReplacementOutcome?
        var candidateConfigurationCount = 0
        var committedCandidate: WKWebView?

        let cleanupCompleted = await fixture.runtime.websiteDataCleanupService
            .performDestructiveDataCleanup(profileIDs: [profileID]) {
                initialOutcome = fixture.service.replace(
                    for: fixture.tab,
                    in: windowID,
                    reason: "test.website-data-deferral",
                    prepareCandidateConfiguration: { _, _ in
                        candidateConfigurationCount += 1
                    },
                    prepareCommittedReplacement: { committedCandidate = $0 }
                )
                guard case .deferred = initialOutcome else {
                    return XCTFail("Blocked replacement must defer")
                }
                XCTAssertEqual(candidateConfigurationCount, 0)
                XCTAssertNil(fixture.runtime.ownershipQuery.webView(
                    for: fixture.tab.id,
                    in: windowID
                ))
            }

        XCTAssertTrue(cleanupCompleted)
        for _ in 0..<10 {
            await Task.yield()
            if committedCandidate != nil { break }
        }
        let replayed = try XCTUnwrap(committedCandidate)
        XCTAssertEqual(candidateConfigurationCount, 1)
        XCTAssertIdentical(
            fixture.runtime.ownershipQuery.webView(
                for: fixture.tab.id,
                in: windowID
            ),
            replayed
        )
    }

    func testWebsiteDataGateDefersUntrackedReplacementBeforeCandidateCreation()
        async throws {
        let fixture = makeFixture()
        let profileID = try XCTUnwrap(fixture.manager.currentProfile?.id)
        var initialOutcome: ExtensionTabWebViewReplacementOutcome?
        var candidateConfigurationCount = 0
        var committedCandidate: WKWebView?

        let cleanupCompleted = await fixture.runtime.websiteDataCleanupService
            .performDestructiveDataCleanup(profileIDs: [profileID]) {
                initialOutcome = fixture.service.replace(
                    for: fixture.tab,
                    in: nil,
                    reason: "test.untracked-website-data-deferral",
                    prepareCandidateConfiguration: { _, _ in
                        candidateConfigurationCount += 1
                    },
                    prepareCommittedReplacement: { committedCandidate = $0 }
                )
                guard case .deferred = initialOutcome else {
                    return XCTFail("Blocked detached replacement must defer")
                }
                XCTAssertEqual(candidateConfigurationCount, 0)
                XCTAssertNil(fixture.tab.webViewSession.untrackedWebView)
            }

        XCTAssertTrue(cleanupCompleted)
        for _ in 0..<10 {
            await Task.yield()
            if committedCandidate != nil { break }
        }
        let replayed = try XCTUnwrap(committedCandidate)
        XCTAssertEqual(candidateConfigurationCount, 1)
        XCTAssertIdentical(
            fixture.tab.webViewSession.untrackedWebView,
            replayed
        )
        XCTAssertTrue(
            fixture.runtime.ownershipQuery.windowIDs(for: fixture.tab.id)
                .isEmpty
        )
    }

    private func makeFixture() -> (
        manager: BrowserManager,
        runtime: WebViewRuntimeGraph,
        tab: Tab,
        service: ExtensionTabWebViewReplacementService
    ) {
        let manager = BrowserManager()
        let runtime = manager.testWebViewRuntime()
        let tab = manager.tabManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/replacement")!,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = manager.currentProfile?.id
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: manager))
        return (manager, runtime, tab, runtime.extensionTabWebViewReplacement)
    }
}

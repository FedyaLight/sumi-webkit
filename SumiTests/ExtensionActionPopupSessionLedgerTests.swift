import AppKit
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupSessionLedgerTests: XCTestCase {
    private final class PopupUIDelegate: NSObject, WKUIDelegate {}

    func testPendingIdentityIsExclusiveUntilFailureSettlesOnce() async throws {
        let fixture = try await makeFixture()
        let lifecycle = makeLifecycle()
        let ledger = lifecycle.ledger
        let popover = NSPopover()
        let webView = WKWebView()
        var settlements = [Error?]()
        let completion = ExtensionActionPopupCompletion {
            settlements.append($0)
        }
        let claim = ledger.reserve(
            evidence: fixture.evidence,
            action: fixture.action,
            popover: popover,
            popupWebView: webView
        )

        XCTAssertNotNil(ledger.activate(
            claim,
            evidence: fixture.evidence,
            completion: completion
        ))
        XCTAssertFalse(ledger.admits(popover: popover, popupWebView: webView))

        lifecycle.retirement.failPending(claim, error: CancellationError())
        lifecycle.retirement.failPending(claim, error: CancellationError())
        lifecycle.retirement.popoverDidClose(
            claim: claim,
            popover: popover
        )

        XCTAssertTrue(ledger.admits(popover: popover, popupWebView: webView))
        XCTAssertEqual(settlements.count, 1)
        XCTAssertNotNil(settlements[0])
    }

    func testDistinctActivationSupersedesPendingWithoutStaleRetirement()
        async throws {
        let fixture = try await makeFixture()
        let lifecycle = makeLifecycle()
        let ledger = lifecycle.ledger
        let firstPopover = NSPopover()
        let firstWebView = WKWebView()
        var firstSettlements = 0
        let firstClaim = ledger.reserve(
            evidence: fixture.evidence,
            action: fixture.action,
            popover: firstPopover,
            popupWebView: firstWebView
        )
        XCTAssertNotNil(ledger.activate(
            firstClaim,
            evidence: fixture.evidence,
            completion: ExtensionActionPopupCompletion { _ in
                firstSettlements += 1
            }
        ))

        let secondPopover = NSPopover()
        let secondWebView = WKWebView()
        var secondSettlements = 0
        let secondClaim = ledger.reserve(
            evidence: fixture.evidence,
            action: fixture.action,
            popover: secondPopover,
            popupWebView: secondWebView
        )
        let activation = ledger.activate(
            secondClaim,
            evidence: fixture.evidence,
            completion: ExtensionActionPopupCompletion { _ in
                secondSettlements += 1
            }
        )
        XCTAssertNotNil(activation)
        lifecycle.retirement.execute(activation?.superseded)

        XCTAssertEqual(firstSettlements, 1)
        XCTAssertFalse(ledger.isPending(firstClaim))
        XCTAssertTrue(ledger.isPending(secondClaim))
        lifecycle.retirement.failPending(
            firstClaim,
            error: CancellationError()
        )
        XCTAssertTrue(ledger.isPending(secondClaim))
        XCTAssertEqual(secondSettlements, 0)

        lifecycle.retirement.failPending(
            secondClaim,
            error: CancellationError()
        )
        lifecycle.retirement.failPending(
            secondClaim,
            error: CancellationError()
        )
        XCTAssertEqual(secondSettlements, 1)
    }

    func testClosingIdentityRemainsExclusiveAndStaleClosePreservesReplacement()
        async throws {
        let fixture = try await makeFixture()
        let lifecycle = makeLifecycle()
        let ledger = lifecycle.ledger
        let firstPopover = NSPopover()
        let firstWebView = WKWebView()
        var firstSettlements = 0
        let firstCompletion = ExtensionActionPopupCompletion { _ in
            firstSettlements += 1
        }
        let firstClaim = ledger.reserve(
            evidence: fixture.evidence,
            action: fixture.action,
            popover: firstPopover,
            popupWebView: firstWebView
        )
        XCTAssertNotNil(ledger.activate(
            firstClaim,
            evidence: fixture.evidence,
            completion: firstCompletion
        ))
        let firstSession = makeSession(
            fixture: fixture,
            claim: firstClaim,
            popover: firstPopover,
            webView: firstWebView,
            completion: firstCompletion
        )
        XCTAssertTrue(ledger.stage(firstSession, for: firstClaim))
        XCTAssertNotNil(ledger.commit(firstSession))
        XCTAssertTrue(ledger.settleCommitted(firstSession))
        firstCompletion.settle(nil)

        lifecycle.retirement.popoverWillClose(
            claim: firstClaim,
            popover: firstPopover
        )
        XCTAssertFalse(ledger.admits(
            popover: firstPopover,
            popupWebView: firstWebView
        ))

        let replacementPopover = NSPopover()
        let replacementWebView = WKWebView()
        let replacementClaim = ledger.reserve(
            evidence: fixture.evidence,
            action: fixture.action,
            popover: replacementPopover,
            popupWebView: replacementWebView
        )
        XCTAssertNotNil(ledger.activate(
            replacementClaim,
            evidence: fixture.evidence,
            completion: ExtensionActionPopupCompletion { _ in }
        ))

        lifecycle.retirement.popoverDidClose(
            claim: firstClaim,
            popover: firstPopover
        )

        XCTAssertTrue(ledger.isPending(replacementClaim))
        XCTAssertTrue(ledger.admits(
            popover: firstPopover,
            popupWebView: firstWebView
        ))
        XCTAssertEqual(firstSettlements, 1)
    }

    func testCommittedSessionRetirementPreservesWebKitUIDelegate()
        async throws {
        let fixture = try await makeFixture()
        let lifecycle = makeLifecycle()
        let popover = NSPopover()
        let webView = WKWebView()
        let uiDelegate = PopupUIDelegate()
        webView.uiDelegate = uiDelegate
        let completion = ExtensionActionPopupCompletion { _ in }
        let claim = lifecycle.ledger.reserve(
            evidence: fixture.evidence,
            action: fixture.action,
            popover: popover,
            popupWebView: webView
        )
        XCTAssertNotNil(lifecycle.ledger.activate(
            claim,
            evidence: fixture.evidence,
            completion: completion
        ))
        let session = makeSession(
            fixture: fixture,
            claim: claim,
            popover: popover,
            webView: webView,
            completion: completion
        )
        XCTAssertTrue(lifecycle.ledger.stage(session, for: claim))
        XCTAssertNotNil(lifecycle.ledger.commit(session))

        let outcomes = lifecycle.ledger.closePopup(
            backedBy: [fixture.evidence.profileID]
        )
        lifecycle.retirement.execute(outcomes)
        lifecycle.retirement.execute(outcomes)

        XCTAssertIdentical(webView.uiDelegate, uiDelegate)
        XCTAssertTrue(session.presentationRetired)
    }

    func testCommittedSessionRetirementEndsSidebarTransientPin()
        async throws {
        let fixture = try await makeFixture()
        let lifecycle = makeLifecycle()
        let coordinator = SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: SidebarInteractionState()
        )
        let source = coordinator.preparedPresentationSource(window: nil)
        let token = coordinator.beginSession(
            kind: .extensionActionPopover,
            source: source,
            path: "ExtensionActionPopupSessionLedgerTests.pinLifecycle"
        )
        XCTAssertTrue(coordinator.hasPinnedTransientUI(for: coordinator.windowID))

        let popover = NSPopover()
        let webView = WKWebView()
        let completion = ExtensionActionPopupCompletion { _ in }
        let claim = lifecycle.ledger.reserve(
            evidence: fixture.evidence,
            action: fixture.action,
            popover: popover,
            popupWebView: webView
        )
        XCTAssertNotNil(lifecycle.ledger.activate(
            claim,
            evidence: fixture.evidence,
            completion: completion
        ))
        let session = makeSession(
            fixture: fixture,
            claim: claim,
            popover: popover,
            webView: webView,
            completion: completion,
            sidebarTransientSessionCoordinator: coordinator,
            sidebarTransientSessionToken: token
        )
        XCTAssertTrue(lifecycle.ledger.stage(session, for: claim))
        XCTAssertNotNil(lifecycle.ledger.commit(session))
        XCTAssertTrue(coordinator.hasPinnedTransientUI(for: coordinator.windowID))

        lifecycle.retirement.execute(
            lifecycle.ledger.closePopup(backedBy: [fixture.evidence.profileID])
        )

        XCTAssertFalse(coordinator.hasPinnedTransientUI(for: coordinator.windowID))
    }

    private struct Fixture {
        let evidence: ExtensionActionPopupCallbackEvidence
        let action: WKWebExtension.Action
    }

    private func makeFixture() async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try FileManager.default.removeItem(at: directory)
        }
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Popup Session Ledger",
            "version": "1.0",
            "action": ["default_popup": "popup.html"],
        ]
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: directory.appendingPathComponent("manifest.json"))
        try Data("<!doctype html>".utf8)
            .write(to: directory.appendingPathComponent("popup.html"))

        let webExtension = try await WKWebExtension(resourceBaseURL: directory)
        let context = WKWebExtensionContext(for: webExtension)
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        let profileID = UUID()
        let evidence = ExtensionActionPopupCallbackEvidence(
            runtimeBinding: .init(
                context: context,
                controller: controller,
                profileID: profileID,
                extensionID: "popup-session-ledger",
                controllerBindingRevision: 1,
                contextBindingRevision: 1,
                extensionLoadRevision: ExtensionLoadRevision(generation: 1)
            ),
            installedRecordRevision: 1,
            invocation: nil
        )
        return Fixture(
            evidence: evidence,
            action: try XCTUnwrap(context.action(for: nil))
        )
    }

    private struct Lifecycle {
        let ledger: ExtensionActionPopupSessionLedger
        let retirement: ExtensionActionPopupRetirementService
    }

    private func makeLifecycle() -> Lifecycle {
        let ledger = ExtensionActionPopupSessionLedger()
        let telemetry = ExtensionActionPopupTelemetry(
            manifest: { _ in [:] },
            existingAdapter: { _ in nil },
            isPublished: { _ in false },
            logSession: { _, _, _ in }
        )
        let focusRestorer = ExtensionActionPopupFocusRestorer(
            browser: EmptyActionPopupBrowserProjection()
        )
        return Lifecycle(
            ledger: ledger,
            retirement: ExtensionActionPopupRetirementService(
                sessions: ledger,
                focusRestorer: focusRestorer,
                telemetry: telemetry
            )
        )
    }

    private func makeSession(
        fixture: Fixture,
        claim: ExtensionActionPopupSessionClaim,
        popover: NSPopover,
        webView: WKWebView,
        completion: ExtensionActionPopupCompletion,
        sidebarTransientSessionCoordinator: SidebarTransientSessionCoordinator? = nil,
        sidebarTransientSessionToken: SidebarTransientSessionToken? = nil
    ) -> ExtensionActionPopupSession {
        ExtensionActionPopupSession(
            claim: claim,
            evidence: fixture.evidence,
            action: fixture.action,
            popover: popover,
            popupWebView: webView,
            sourceReceipt: nil,
            focusReceipt: nil,
            telemetrySnapshot: .init(
                evidence: fixture.evidence,
                manifest: [:],
                seesSourceTab: false,
                recordsDiagnostics: false
            ),
            completion: completion,
            sidebarTransientSessionCoordinator: sidebarTransientSessionCoordinator,
            sidebarTransientSessionToken: sidebarTransientSessionToken,
            popoverDidClose: { _, _ in },
            popoverWillClose: { _, _ in }
        )
    }
}

@available(macOS 15.5, *)
@MainActor
private final class EmptyActionPopupBrowserProjection:
    ExtensionActionPopupBrowserProjection {
    func popupWindowState(id: UUID) -> BrowserWindowState? { nil }
    func popupActiveWindow() -> BrowserWindowState? { nil }
    func popupWindow(containing tab: Tab) -> BrowserWindowState? { nil }
    func popupAppKitWindow(for window: BrowserWindowState) -> NSWindow? { nil }
    func popupTab(id: UUID, in window: BrowserWindowState) -> Tab? { nil }
    func popupCurrentTab(in window: BrowserWindowState) -> Tab? { nil }
    func popupProfile(id: UUID) -> Profile? { nil }
    func popupProfileID(for tab: Tab) -> UUID? { nil }
    func popupWindow(
        _ window: BrowserWindowState,
        matches profileID: UUID
    ) -> Bool { false }
    func popupLiveWebView(for tab: Tab) -> WKWebView? { nil }
    func popupFallbackAnchorView(windowID: UUID) -> NSView? { nil }
    func popupAppearance(
        anchorWindow: NSWindow,
        fallback: NSAppearance
    ) -> NSAppearance? { nil }
    func popupTabIsPublished(_ tab: Tab) -> Bool { false }
}

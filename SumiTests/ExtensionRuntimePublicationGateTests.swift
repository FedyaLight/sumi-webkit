import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimePublicationGateTests: XCTestCase {
    func testActiveGateAcceptsOrdinaryBrowserEvents() {
        let gate = ExtensionRuntimePublicationGate()

        XCTAssertTrue(gate.acceptsBrowserEvents)
    }

    func testReloadClaimIsExclusiveUntilFinished() throws {
        let gate = ExtensionRuntimePublicationGate()
        let claim = try XCTUnwrap(gate.beginReload())

        XCTAssertTrue(gate.reloadIsCurrent(claim))
        XCTAssertNil(gate.beginReload())
        XCTAssertFalse(gate.acceptsBrowserEvents)
        XCTAssertTrue(
            gate.finishReload(
                claim,
                publicationIsAvailable: true
            )
        )
        XCTAssertTrue(gate.acceptsBrowserEvents)
    }

    func testTerminalRetirementInvalidatesInFlightReload() throws {
        let gate = ExtensionRuntimePublicationGate()
        let claim = try XCTUnwrap(gate.beginReload())

        XCTAssertTrue(gate.beginTerminalRetirement())
        XCTAssertFalse(gate.reloadIsCurrent(claim))
        XCTAssertFalse(
            gate.finishReload(
                claim,
                publicationIsAvailable: true
            )
        )
        XCTAssertFalse(gate.acceptsBrowserEvents)
    }

    func testReloadHandoffAcceptsEventsWithoutAllowingNestedReload() throws {
        let gate = ExtensionRuntimePublicationGate()
        let claim = try XCTUnwrap(gate.beginReload())

        XCTAssertTrue(gate.beginBrowserEventHandoff(claim))
        XCTAssertTrue(gate.acceptsBrowserEvents)
        XCTAssertTrue(gate.reloadIsCurrent(claim))
        XCTAssertNil(gate.beginReload())
    }

    func testPreHandoffStructuralEventRequestsFollowUpWithoutAdmission()
        throws {
        let gate = ExtensionRuntimePublicationGate()
        let claim = try XCTUnwrap(gate.beginReload())

        XCTAssertFalse(gate.admitStructuralBrowserEvent())
        XCTAssertEqual(
            gate.takeDeferredStructuralEvent(for: claim),
            true
        )
        XCTAssertEqual(
            gate.takeDeferredStructuralEvent(for: claim),
            false
        )
    }

    func testExactTabCloseIsDeferredOnlyBeforeReloadHandoff() throws {
        let gate = ExtensionRuntimePublicationGate()
        XCTAssertEqual(gate.exactTabCloseDisposition(), .perform)
        let claim = try XCTUnwrap(gate.beginReload())

        XCTAssertEqual(
            gate.exactTabCloseDisposition(),
            .deferUntilReloadHandoff
        )
        XCTAssertTrue(gate.beginBrowserEventHandoff(claim))
        XCTAssertEqual(gate.exactTabCloseDisposition(), .perform)
    }

    func testExactTabCloseIsRejectedDuringTerminalRetirement() {
        let gate = ExtensionRuntimePublicationGate()

        XCTAssertTrue(gate.beginTerminalRetirement())

        XCTAssertEqual(gate.exactTabCloseDisposition(), .reject)
    }

    func testAuxiliaryEventRemainsSynchronousAndRequestsFollowUp() throws {
        let gate = ExtensionRuntimePublicationGate()
        let claim = try XCTUnwrap(gate.beginReload())

        XCTAssertTrue(gate.admitAuxiliaryBrowserEvent())
        XCTAssertEqual(
            gate.takeDeferredStructuralEvent(for: claim),
            true
        )
    }

    func testReloadClaimCannotAuthorizeAnotherGate() throws {
        let firstGate = ExtensionRuntimePublicationGate()
        let secondGate = ExtensionRuntimePublicationGate()
        _ = try XCTUnwrap(firstGate.beginReload())
        let secondClaim = try XCTUnwrap(secondGate.beginReload())

        XCTAssertFalse(firstGate.reloadIsCurrent(secondClaim))
        XCTAssertFalse(firstGate.beginBrowserEventHandoff(secondClaim))
    }

    func testInactiveGateBlocksOrdinaryBrowserEvents() throws {
        let gate = ExtensionRuntimePublicationGate()
        let claim = try XCTUnwrap(gate.beginReload())

        XCTAssertTrue(
            gate.finishReload(
                claim,
                publicationIsAvailable: false
            )
        )
        XCTAssertFalse(gate.acceptsBrowserEvents)
    }

    func testReloadCanReactivateInactiveGate() throws {
        let gate = ExtensionRuntimePublicationGate()
        let initialClaim = try XCTUnwrap(gate.beginReload())
        XCTAssertTrue(
            gate.finishReload(
                initialClaim,
                publicationIsAvailable: false
            )
        )

        let recoveryClaim = try XCTUnwrap(gate.beginReload())
        XCTAssertTrue(gate.reloadIsCurrent(recoveryClaim))
        XCTAssertTrue(
            gate.finishReload(
                recoveryClaim,
                publicationIsAvailable: true
            )
        )
        XCTAssertTrue(gate.acceptsBrowserEvents)
    }

}

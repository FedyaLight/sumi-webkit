@testable import Sumi
import XCTest

final class SpaceCreationSessionTests: XCTestCase {
    @MainActor
    func testWindowStateOwnsSingleSpaceCreationSessionAndReleasesTransientState() {
        let windowState = BrowserWindowState()
        let previousSpaceID = UUID()
        let defaultProfileID = UUID()
        windowState.currentSpaceId = previousSpaceID

        let session = windowState.spaceCreationSession.begin(
            source: windowState.resolveSidebarPresentationSource(in: nil),
            previousSpaceID: windowState.currentSpaceId,
            defaultProfileID: defaultProfileID
        )

        XCTAssertIdentical(windowState.spaceCreationSession.activeSession, session)
        XCTAssertEqual(session.previousSpaceID, previousSpaceID)
        XCTAssertEqual(session.profileID, defaultProfileID)
        XCTAssertEqual(session.resolvedIcon, SumiPersistentGlyph.spaceDefaultIconValue)
        XCTAssertEqual(SumiPersistentGlyph.resolvedSpaceIconPresentation(session.resolvedIcon), .defaultDot)
        XCTAssertFalse(session.canCommit)
        XCTAssertFalse(windowState.sidebarInteractionState.allowsSidebarDragSourceHitTesting)
        XCTAssertFalse(windowState.sidebarInteractionState.allowsSidebarSwipeCapture)

        session.name = "  Research  "

        XCTAssertEqual(session.trimmedName, "Research")
        XCTAssertTrue(session.canCommit)

        session.createsNewProfile = true
        XCTAssertFalse(session.canCommit)

        session.newProfileName = "  Work  "
        session.newProfileIcon = "💼"
        XCTAssertEqual(session.trimmedNewProfileName, "Work")
        XCTAssertEqual(session.resolvedNewProfileIcon, "💼")
        XCTAssertTrue(session.canCommit)

        session.createsNewProfile = false

        let duplicate = windowState.spaceCreationSession.begin(
            source: windowState.resolveSidebarPresentationSource(in: nil),
            previousSpaceID: windowState.currentSpaceId,
            defaultProfileID: UUID()
        )

        XCTAssertIdentical(duplicate, session)

        windowState.spaceCreationSession.finish(session, reason: "SpaceCreationSessionTests")

        XCTAssertNil(windowState.spaceCreationSession.activeSession)
        XCTAssertTrue(windowState.sidebarInteractionState.allowsSidebarDragSourceHitTesting)
        XCTAssertTrue(windowState.sidebarInteractionState.allowsSidebarSwipeCapture)
    }
}

import XCTest
@testable import Sumi

final class SpaceCreationSessionTests: XCTestCase {
    @MainActor
    func testWindowStateOwnsSingleSpaceCreationSessionAndReleasesTransientState() {
        let windowState = BrowserWindowState()
        let previousSpaceID = UUID()
        let defaultProfileID = UUID()
        windowState.currentSpaceId = previousSpaceID

        let session = windowState.beginSpaceCreationSession(
            source: windowState.resolveSidebarPresentationSource(),
            defaultProfileID: defaultProfileID
        )

        XCTAssertTrue(windowState.activeSpaceCreationSession === session)
        XCTAssertEqual(session.previousSpaceID, previousSpaceID)
        XCTAssertEqual(session.profileID, defaultProfileID)
        XCTAssertEqual(session.resolvedIcon, SpaceCreationSession.defaultIcon)
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

        let duplicate = windowState.beginSpaceCreationSession(
            source: windowState.resolveSidebarPresentationSource(),
            defaultProfileID: UUID()
        )

        XCTAssertTrue(duplicate === session)

        windowState.finishSpaceCreationSession(session, reason: "SpaceCreationSessionTests")

        XCTAssertNil(windowState.activeSpaceCreationSession)
        XCTAssertTrue(windowState.sidebarInteractionState.allowsSidebarDragSourceHitTesting)
        XCTAssertTrue(windowState.sidebarInteractionState.allowsSidebarSwipeCapture)
    }
}

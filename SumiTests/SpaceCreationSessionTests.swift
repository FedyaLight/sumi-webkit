@testable import Sumi
import SumiDomain
import XCTest

final class SpaceCreationSessionTests: XCTestCase {
    @MainActor
    func testWindowStateOwnsSingleSpaceCreationSessionAndReleasesTransientState() {
        let windowState = BrowserWindowState()
        let previousSpaceID = UUID()
        let reservedSpaceID = UUID()
        let defaultProfileID = UUID()
        let initialWorkspaceTheme = WorkspaceTheme(
            gradientTheme: .incognito
        )
        let originalWorkspaceTheme = WorkspaceTheme(
            gradientTheme: .default
        )
        windowState.currentSpaceId = previousSpaceID

        let session = windowState.spaceCreationSession.begin(
            source: windowState.resolveSidebarPresentationSource(in: nil),
            previousSpaceID: windowState.currentSpaceId,
            reservedSpaceID: reservedSpaceID,
            defaultProfileID: defaultProfileID,
            workspaceTheme: initialWorkspaceTheme,
            originalWorkspaceTheme: originalWorkspaceTheme
        )

        XCTAssertIdentical(windowState.spaceCreationSession.activeSession, session)
        XCTAssertEqual(session.previousSpaceID, previousSpaceID)
        XCTAssertEqual(session.reservedSpaceID, reservedSpaceID)
        XCTAssertEqual(session.profileID, defaultProfileID)
        XCTAssertTrue(session.workspaceTheme.visuallyEquals(initialWorkspaceTheme))
        XCTAssertTrue(session.originalWorkspaceTheme.visuallyEquals(originalWorkspaceTheme))
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
        XCTAssertEqual(session.trimmedNewProfileName, "Work")
        XCTAssertTrue(session.canCommit)

        session.createsNewProfile = false

        let duplicate = windowState.spaceCreationSession.begin(
            source: windowState.resolveSidebarPresentationSource(in: nil),
            previousSpaceID: windowState.currentSpaceId,
            reservedSpaceID: UUID(),
            defaultProfileID: UUID(),
            workspaceTheme: .default,
            originalWorkspaceTheme: .default
        )

        XCTAssertIdentical(duplicate, session)
        XCTAssertEqual(duplicate.reservedSpaceID, reservedSpaceID)
        XCTAssertTrue(duplicate.workspaceTheme.visuallyEquals(initialWorkspaceTheme))

        windowState.spaceCreationSession.finish(session, reason: "SpaceCreationSessionTests")

        XCTAssertNil(windowState.spaceCreationSession.activeSession)
        XCTAssertTrue(windowState.sidebarInteractionState.allowsSidebarDragSourceHitTesting)
        XCTAssertTrue(windowState.sidebarInteractionState.allowsSidebarSwipeCapture)
    }
}

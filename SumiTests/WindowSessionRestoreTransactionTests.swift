import Foundation
import XCTest

@testable import Sumi

@MainActor
final class WindowSessionRestoreTransactionTests: XCTestCase {
    func testCancelledPreparationCannotBeConsumedByReplacementObject() throws {
        let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
        let sessionKey = "SumiTests.windowSession.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }
        let delegate = TestWindowSessionDelegate(tabManager: tabManager)
        let service = delegate.makeRestoreService(
            lastWindowSessionKey: sessionKey
        )
        var archivedSession = makeSessionRecoveryWindowSession(
            isShowingEmptyState: true
        )
        let archivedProfileID = UUID()
        archivedSession.currentProfileId = archivedProfileID
        let preparedWindow = BrowserWindowState()

        service.prepareArchivedWindow(
            LastSessionWindowSnapshot(
                id: UUID(),
                session: archivedSession
            ),
            forRegistration: preparedWindow
        )

        XCTAssertTrue(
            service.cancelPreparedWindowRegistration(preparedWindow)
        )
        XCTAssertFalse(
            service.cancelPreparedWindowRegistration(preparedWindow)
        )

        let replacementWindow = BrowserWindowState(id: preparedWindow.id)
        service.restoreRegisteredWindow(
            replacementWindow,
            currentProfile: Profile(name: "Current")
        )

        XCTAssertNil(replacementWindow.restoredSessionWindowId)
        XCTAssertNotEqual(replacementWindow.currentProfileId, archivedProfileID)
        XCTAssertFalse(replacementWindow.isAwaitingInitialSessionResolution)
    }
}

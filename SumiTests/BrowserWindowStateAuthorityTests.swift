import Foundation
import Observation
import XCTest

@testable import Sumi

@MainActor
final class BrowserWindowStateAuthorityTests: XCTestCase {
    func testRuntimePresentationDoesNotInvalidateDurableSelectionObservation() {
        let windowState = BrowserWindowState()
        let durableChange = WindowStateObservationFlag()

        withObservationTracking {
            _ = windowState.currentTabId
        } onChange: {
            durableChange.markChanged()
        }

        windowState.presentationState.isCommandPaletteVisible = true
        windowState.presentationState.isDownloadsPopoverPresented = true
        windowState.presentationState.urlBarFrame = CGRect(x: 1, y: 2, width: 3, height: 4)

        XCTAssertFalse(durableChange.didChange)

        windowState.currentTabId = UUID()

        XCTAssertTrue(durableChange.didChange)
    }

    func testDurableSelectionDoesNotInvalidatePresentationObservation() {
        let windowState = BrowserWindowState()
        let presentationChange = WindowStateObservationFlag()

        withObservationTracking {
            _ = windowState.presentationState.isCommandPaletteVisible
        } onChange: {
            presentationChange.markChanged()
        }

        windowState.currentTabId = UUID()
        windowState.currentSpaceId = UUID()
        windowState.isSidebarVisible.toggle()

        XCTAssertFalse(presentationChange.didChange)

        windowState.presentationState.isCommandPaletteVisible = true

        XCTAssertTrue(presentationChange.didChange)
    }

    func testRuntimeAuthoritiesDoNotChangeDurableWindowSnapshot() {
        let baseline = BrowserWindowState()
        baseline.commandPalettePresentationReason = .keyboard

        let transientlyPresented = BrowserWindowState()
        transientlyPresented.commandPalettePresentationReason = .keyboard
        transientlyPresented.presentationState.isCommandPaletteVisible = true
        transientlyPresented.presentationState.isDownloadsPopoverPresented = true
        transientlyPresented.presentationState.urlBarFrame = CGRect(
            x: 10,
            y: 20,
            width: 300,
            height: 40
        )
        transientlyPresented.presentationState.visibility = SumiWindowVisibilityState(
            hasAttachedWindow: true,
            isVisible: false,
            isMiniaturized: true,
            isOccluded: true
        )
        transientlyPresented.presentationState.pendingSplitGroupFocusRequest =
            SplitGroupFocusRequest(
                groupID: UUID(),
                preferredMemberID: nil,
                targetSpaceID: UUID()
            )
        transientlyPresented.restorationState.restoredSessionWindowID = UUID()
        transientlyPresented.restorationState.isAwaitingInitialResolution = true
        transientlyPresented.restorationState.pendingSplitSelection =
            PendingWindowSplitSelection(
                groupID: UUID(),
                preferredMemberID: nil
            )

        let snapshotFactory = WindowSessionSnapshotFactory(
            glanceManager: GlanceManager()
        )

        XCTAssertEqual(
            snapshotFactory.make(for: transientlyPresented),
            snapshotFactory.make(for: baseline)
        )
    }
}

private final class WindowStateObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false

    var didChange: Bool {
        lock.withLock { changed }
    }

    func markChanged() {
        lock.withLock {
            changed = true
        }
    }
}

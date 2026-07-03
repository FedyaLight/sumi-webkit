import CoreGraphics
import Foundation
import XCTest

@testable import Sumi

@MainActor
final class SplitPreviewStateOwnerTests: XCTestCase {
    private final class Recorder {
        var activeWindowId: UUID?
        var notifyCount = 0
        var refreshedWindowIds: [UUID] = []
    }

    private func makeOwner(recorder: Recorder) -> SplitPreviewStateOwner {
        SplitPreviewStateOwner(
            activeWindowId: { recorder.activeWindowId },
            notifyActiveWindowPreviewChanged: { recorder.notifyCount += 1 },
            refreshWindow: { recorder.refreshedWindowIds.append($0) }
        )
    }

    func testBeginUpdateEndPreviewLifecycle() {
        let recorder = Recorder()
        let owner = makeOwner(recorder: recorder)
        let windowId = UUID()
        recorder.activeWindowId = windowId

        XCTAssertFalse(owner.isPreviewActive(for: windowId))

        owner.beginPreview(targetRect: CGRect(x: 0, y: 0, width: 10, height: 10), style: .center, for: windowId)
        XCTAssertTrue(owner.isPreviewActive(for: windowId))
        XCTAssertEqual(
            owner.previewState(for: windowId),
            SplitPreviewStateOwner.WindowSplitPreviewState(
                isActive: true,
                targetRect: CGRect(x: 0, y: 0, width: 10, height: 10),
                style: .center
            )
        )
        XCTAssertEqual(recorder.refreshedWindowIds, [windowId])

        owner.updatePreview(targetRect: CGRect(x: 5, y: 5, width: 20, height: 20), style: .edge, for: windowId)
        XCTAssertEqual(owner.previewState(for: windowId).targetRect, CGRect(x: 5, y: 5, width: 20, height: 20))
        XCTAssertEqual(owner.previewState(for: windowId).style, .edge)

        owner.endPreview(for: windowId)
        XCTAssertFalse(owner.isPreviewActive(for: windowId))
        XCTAssertEqual(owner.previewState(for: windowId), SplitPreviewStateOwner.WindowSplitPreviewState())
        XCTAssertEqual(recorder.refreshedWindowIds, [windowId, windowId])
    }

    func testUpdatePreviewIsIgnoredWhenNoPreviewIsActive() {
        let recorder = Recorder()
        let owner = makeOwner(recorder: recorder)
        let windowId = UUID()

        owner.updatePreview(targetRect: CGRect(x: 1, y: 1, width: 2, height: 2), style: .center, for: windowId)

        XCTAssertFalse(owner.isPreviewActive(for: windowId))
        XCTAssertNil(owner.previewState(for: windowId).targetRect)
    }

    func testEndPreviewWithoutActivePreviewDoesNotRefreshWindow() {
        let recorder = Recorder()
        let owner = makeOwner(recorder: recorder)

        owner.endPreview(for: UUID())

        XCTAssertTrue(recorder.refreshedWindowIds.isEmpty)
        XCTAssertEqual(recorder.notifyCount, 0)
    }

    func testPublishedStateNotifiesOnlyForActiveWindowAndOnChange() {
        let recorder = Recorder()
        let owner = makeOwner(recorder: recorder)
        let activeWindowId = UUID()
        let backgroundWindowId = UUID()
        recorder.activeWindowId = activeWindowId

        owner.beginPreview(targetRect: nil, style: .edge, for: backgroundWindowId)
        XCTAssertEqual(recorder.notifyCount, 0, "Background window previews must not publish.")

        owner.beginPreview(targetRect: nil, style: .edge, for: activeWindowId)
        XCTAssertEqual(recorder.notifyCount, 1)

        owner.syncPublishedStateIfNeeded(for: activeWindowId)
        XCTAssertEqual(recorder.notifyCount, 1, "Unchanged state must not re-publish.")

        owner.syncPublishedStateIfNeeded(for: activeWindowId, forceNotify: true)
        XCTAssertEqual(recorder.notifyCount, 2)
    }

    func testCleanupWindowClearsTransientStateAndSyncs() {
        let recorder = Recorder()
        let owner = makeOwner(recorder: recorder)
        let windowId = UUID()
        recorder.activeWindowId = windowId

        owner.beginPreview(targetRect: CGRect(x: 0, y: 0, width: 4, height: 4), style: .center, for: windowId)
        XCTAssertTrue(owner.isPreviewActive(for: windowId))

        owner.cleanupWindow(windowId)

        XCTAssertFalse(owner.isPreviewActive(for: windowId))
        XCTAssertEqual(owner.previewState(for: windowId), SplitPreviewStateOwner.WindowSplitPreviewState())
    }
}

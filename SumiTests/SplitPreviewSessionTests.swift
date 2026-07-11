import CoreGraphics
import Foundation
import XCTest

@testable import Sumi

@MainActor
final class SplitPreviewSessionTests: XCTestCase {
    func testBeginUpdateAndEndAreWindowScoped() {
        let recorder = Recorder()
        let session = makeSession(recorder)
        let windowID = UUID()
        recorder.activeWindowID = windowID

        session.begin(
            targetRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            style: .center,
            in: windowID
        )
        XCTAssertEqual(
            session.state(for: windowID),
            SplitPreviewSession.WindowState(
                isActive: true,
                targetRect: CGRect(x: 0, y: 0, width: 10, height: 10),
                style: .center
            )
        )

        session.update(
            targetRect: CGRect(x: 5, y: 5, width: 20, height: 20),
            style: .edge,
            in: windowID
        )
        XCTAssertEqual(
            session.state(for: windowID).targetRect,
            CGRect(x: 5, y: 5, width: 20, height: 20)
        )

        session.end(in: windowID)
        XCTAssertEqual(session.state(for: windowID), .init())
        XCTAssertEqual(recorder.refreshedWindowIDs, [windowID, windowID])
    }

    func testInactiveUpdateAndEndAreNoOps() {
        let recorder = Recorder()
        let session = makeSession(recorder)
        let windowID = UUID()

        session.update(targetRect: .zero, style: .center, in: windowID)
        session.end(in: windowID)

        XCTAssertEqual(session.state(for: windowID), .init())
        XCTAssertTrue(recorder.refreshedWindowIDs.isEmpty)
        XCTAssertEqual(recorder.publishCount, 0)
    }

    func testOnlyActiveWindowPublishesChangedState() {
        let recorder = Recorder()
        let session = makeSession(recorder)
        let activeWindowID = UUID()
        let backgroundWindowID = UUID()
        recorder.activeWindowID = activeWindowID

        session.begin(targetRect: nil, style: .edge, in: backgroundWindowID)
        XCTAssertEqual(recorder.publishCount, 0)

        session.begin(targetRect: nil, style: .edge, in: activeWindowID)
        XCTAssertEqual(recorder.publishCount, 1)

        session.syncPublishedState(for: activeWindowID)
        XCTAssertEqual(recorder.publishCount, 1)

        session.syncPublishedState(for: activeWindowID, force: true)
        XCTAssertEqual(recorder.publishCount, 2)
    }

    func testRemovingWindowDropsTransientState() {
        let recorder = Recorder()
        let session = makeSession(recorder)
        let windowID = UUID()
        recorder.activeWindowID = windowID
        session.begin(targetRect: .zero, style: .center, in: windowID)

        session.removeWindow(windowID)

        XCTAssertEqual(session.state(for: windowID), .init())
        XCTAssertEqual(recorder.publishCount, 2)
    }

    private func makeSession(_ recorder: Recorder) -> SplitPreviewSession {
        SplitPreviewSession(
            activeWindowID: { recorder.activeWindowID },
            publishActiveWindowChange: { recorder.publishCount += 1 },
            refreshWindow: { recorder.refreshedWindowIDs.append($0) }
        )
    }
}

@MainActor
private final class Recorder {
    var activeWindowID: UUID?
    var publishCount = 0
    var refreshedWindowIDs: [UUID] = []
}

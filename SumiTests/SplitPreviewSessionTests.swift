import CoreGraphics
import Combine
import Foundation
import XCTest

@testable import Sumi

@MainActor
final class SplitPreviewSessionTests: XCTestCase {
    func testWindowUpdateStreamDeliversOnlyMatchingWindow() {
        let channel = SplitWindowUpdateStream.makeChannel()
        let trackedWindowID = UUID()
        var deliveryCount = 0
        let subscription = channel.stream.updates(for: trackedWindowID).sink {
            deliveryCount += 1
        }

        channel.emitter.publish(windowID: UUID())
        channel.emitter.publish(windowID: trackedWindowID)
        channel.emitter.publish(windowID: UUID())

        XCTAssertEqual(deliveryCount, 1)
        withExtendedLifetime(subscription) {}
    }

    func testBeginUpdateAndEndAreWindowScoped() {
        let recorder = Recorder()
        let session = makeSession(recorder)
        let windowID = UUID()

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
        XCTAssertEqual(
            recorder.publishedWindowIDs,
            [windowID, windowID, windowID]
        )
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

    func testEachChangedWindowPublishesItsOwnIdentity() {
        let recorder = Recorder()
        let session = makeSession(recorder)
        let firstWindowID = UUID()
        let secondWindowID = UUID()

        session.begin(targetRect: nil, style: .edge, in: firstWindowID)
        session.begin(targetRect: nil, style: .edge, in: secondWindowID)
        session.update(targetRect: .zero, style: .center, in: firstWindowID)

        XCTAssertEqual(
            recorder.publishedWindowIDs,
            [firstWindowID, secondWindowID, firstWindowID]
        )
    }

    func testRemovingWindowDropsTransientState() {
        let recorder = Recorder()
        let session = makeSession(recorder)
        let windowID = UUID()
        session.begin(targetRect: .zero, style: .center, in: windowID)

        session.removeWindow(windowID)

        XCTAssertEqual(session.state(for: windowID), .init())
        XCTAssertEqual(recorder.publishedWindowIDs, [windowID, windowID])
    }

    private func makeSession(_ recorder: Recorder) -> SplitPreviewSession {
        SplitPreviewSession(
            publishWindowChange: {
                recorder.publishedWindowIDs.append($0)
            },
            refreshWindow: { recorder.refreshedWindowIDs.append($0) }
        )
    }
}

@MainActor
private final class Recorder {
    var publishedWindowIDs: [UUID] = []
    var publishCount: Int { publishedWindowIDs.count }
    var refreshedWindowIDs: [UUID] = []
}

import Foundation
import XCTest

@testable import Sumi

@MainActor
final class EmptySplitSessionTests: XCTestCase {
    func testReplaceConsumesExactWindowPlaceholderAndRemovesOldTab() {
        let windowState = BrowserWindowState()
        let placeholderID = UUID()
        let incoming = Tab(url: URL(string: "https://incoming.example")!)
        let recorder = Recorder()
        let session = makeSession(recorder)
        session.register(tabID: placeholderID, in: windowState.id)

        XCTAssertTrue(session.replace(with: incoming, in: windowState))

        XCTAssertEqual(recorder.replacements.count, 1)
        XCTAssertIdentical(recorder.replacements[0].tab, incoming)
        XCTAssertEqual(
            recorder.replacements[0].placeholderTabID,
            placeholderID
        )
        XCTAssertIdentical(recorder.replacements[0].windowState, windowState)
        XCTAssertEqual(recorder.removedTabIDs, [placeholderID])
        XCTAssertFalse(session.replace(with: incoming, in: windowState))
    }

    func testFailedReplacementKeepsRegistrationForRetry() {
        let windowState = BrowserWindowState()
        let placeholderID = UUID()
        let incoming = Tab(url: URL(string: "https://incoming.example")!)
        let recorder = Recorder()
        recorder.replacementResults = [false, true]
        let session = makeSession(recorder)
        session.register(tabID: placeholderID, in: windowState.id)

        XCTAssertFalse(session.replace(with: incoming, in: windowState))
        XCTAssertTrue(session.replace(with: incoming, in: windowState))

        XCTAssertEqual(recorder.replacements.count, 2)
        XCTAssertEqual(recorder.removedTabIDs, [placeholderID])
    }

    func testReplacingPlaceholderWithSameTabDoesNotRemoveIt() {
        let windowState = BrowserWindowState()
        let tab = Tab(url: URL(string: "https://same.example")!)
        let recorder = Recorder()
        let session = makeSession(recorder)
        session.register(tabID: tab.id, in: windowState.id)

        XCTAssertTrue(session.replace(with: tab, in: windowState))
        XCTAssertTrue(recorder.removedTabIDs.isEmpty)
    }

    func testCommitConsumesOnlyMatchingPlaceholder() {
        let windowID = UUID()
        let placeholderID = UUID()
        let recorder = Recorder()
        let session = makeSession(recorder)
        session.register(tabID: placeholderID, in: windowID)

        session.commit(tabID: UUID(), in: windowID)
        let windowState = BrowserWindowState(id: windowID)
        XCTAssertTrue(
            session.replace(
                with: Tab(url: URL(string: "https://retry.example")!),
                in: windowState
            )
        )

        session.register(tabID: placeholderID, in: windowID)
        session.commit(tabID: placeholderID, in: windowID)
        XCTAssertFalse(session.cancel(in: windowState))
    }

    func testCancelRemovesPlaceholderExactlyOnce() {
        let windowState = BrowserWindowState()
        let placeholderID = UUID()
        let recorder = Recorder()
        let session = makeSession(recorder)
        session.register(tabID: placeholderID, in: windowState.id)

        XCTAssertTrue(session.cancel(in: windowState))
        XCTAssertFalse(session.cancel(in: windowState))
        XCTAssertEqual(recorder.removedTabIDs, [placeholderID])
    }

    func testRemovingWindowForgetsRegistrationWithoutClosingTab() {
        let windowState = BrowserWindowState()
        let recorder = Recorder()
        let session = makeSession(recorder)
        session.register(tabID: UUID(), in: windowState.id)

        session.removeWindow(windowState.id)

        XCTAssertFalse(session.cancel(in: windowState))
        XCTAssertTrue(recorder.removedTabIDs.isEmpty)
    }

    private func makeSession(_ recorder: Recorder) -> EmptySplitSession {
        EmptySplitSession(
            replacePlaceholder: { tab, placeholderTabID, windowState in
                recorder.replacements.append(
                    (tab, placeholderTabID, windowState)
                )
                return recorder.replacementResults.isEmpty
                    ? true
                    : recorder.replacementResults.removeFirst()
            },
            removeTab: { recorder.removedTabIDs.append($0) }
        )
    }
}

@MainActor
private final class Recorder {
    var replacements: [(
        tab: Tab,
        placeholderTabID: UUID,
        windowState: BrowserWindowState
    )] = []
    var replacementResults: [Bool] = []
    var removedTabIDs: [UUID] = []
}

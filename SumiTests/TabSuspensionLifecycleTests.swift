import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabSuspensionLifecycleTests: XCTestCase {
    func testMarkSuspendedUpdatesRuntimeStateAndPublishesLifecycle() {
        let tab = makeTab()
        let selectedAt = Date(timeIntervalSince1970: 100)
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        tab.loadingState = .didStartProvisionalNavigation
        let recorder = TabSuspensionLifecycleRecorder(observing: tab)

        tab.markSuspended(at: selectedAt)

        XCTAssertTrue(tab.suspensionState.isSuspended)
        XCTAssertFalse(tab.suspensionState.isRestoreInProgress)
        XCTAssertEqual(tab.suspensionState.lastSuspendedURL, tab.url)
        XCTAssertEqual(tab.lastSelectedAt, selectedAt)
        XCTAssertEqual(tab.loadingState, .idle)
        XCTAssertFalse(tab.audioState.isPlayingAudio)
        XCTAssertEqual(tab.mediaRuntime.lastMediaActivityAt, .distantPast)
        XCTAssertEqual(recorder.count, 1)
        XCTAssertIdentical(recorder.firstObject, tab)
        XCTAssertFalse(recorder.firstNotificationHasUserInfo)
    }

    func testMarkSuspendedKeepsExistingLastSelectedAt() {
        let tab = makeTab()
        let existingDate = Date(timeIntervalSince1970: 50)
        tab.lastSelectedAt = existingDate

        tab.markSuspended(at: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(tab.lastSelectedAt, existingDate)
    }

    func testInteractionStateIsKeptForOnlyOneSameRunRestore() {
        let tab = makeTab()
        let interactionState = Data([1, 2, 3])

        tab.markSuspended(interactionStateData: interactionState)

        XCTAssertEqual(
            tab.suspensionState.takeInteractionStateForRestore(),
            interactionState
        )
        XCTAssertNil(tab.suspensionState.takeInteractionStateForRestore())
    }

    func testSuspendedRestoreFinishesOnlyAfterWebViewExists() {
        let tab = makeTab()
        tab.suspensionState.isSuspended = true
        let recorder = TabSuspensionLifecycleRecorder(observing: tab)

        tab.beginSuspendedRestoreIfNeeded()
        tab.finishSuspendedRestoreIfNeeded()

        XCTAssertTrue(tab.suspensionState.isSuspended)
        XCTAssertTrue(tab.suspensionState.isRestoreInProgress)
        XCTAssertEqual(recorder.count, 0)

        tab.replaceUntrackedWebView(WKWebView())
        tab.finishSuspendedRestoreIfNeeded()

        XCTAssertFalse(tab.suspensionState.isSuspended)
        XCTAssertFalse(tab.suspensionState.isRestoreInProgress)
        XCTAssertEqual(recorder.count, 1)
        XCTAssertIdentical(recorder.firstObject, tab)
    }

    private func makeTab() -> Tab {
        Tab(
            url: URL(string: "https://example.com/page")!,
            name: "Example",
            loadsCachedFaviconOnInit: false
        )
    }
}

private final class TabSuspensionLifecycleRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var notifications: [Notification] = []
    private var observer: NSObjectProtocol?

    @MainActor
    init(observing tab: Tab) {
        observer = NotificationCenter.default.addObserver(
            forName: .sumiTabLifecycleDidChange,
            object: tab,
            queue: nil
        ) { [weak self] notification in
            self?.append(notification)
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func append(_ notification: Notification) {
        lock.withLock {
            notifications.append(notification)
        }
    }

    var count: Int {
        lock.withLock { notifications.count }
    }

    var firstObject: AnyObject? {
        lock.withLock { notifications.first?.object as? AnyObject }
    }

    var firstNotificationHasUserInfo: Bool {
        lock.withLock { notifications.first?.userInfo != nil }
    }
}

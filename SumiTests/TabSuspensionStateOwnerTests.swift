import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabSuspensionStateOwnerTests: XCTestCase {
    func testMarkSuspendedUpdatesRuntimeStateAndPublishesLifecycle() {
        let tab = makeTab()
        let selectedAt = Date(timeIntervalSince1970: 100)
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        tab.loadingState = .didStartProvisionalNavigation
        let recorder = TabSuspensionLifecycleRecorder(observing: tab)

        tab.markSuspended(at: selectedAt)

        XCTAssertTrue(tab.isSuspended)
        XCTAssertFalse(tab.isSuspensionRestoreInProgress)
        XCTAssertEqual(tab.lastSuspendedURL, tab.url)
        XCTAssertEqual(tab.lastSelectedAt, selectedAt)
        XCTAssertEqual(tab.loadingState, .idle)
        XCTAssertFalse(tab.audioState.isPlayingAudio)
        XCTAssertEqual(tab.lastMediaActivityAt, .distantPast)
        XCTAssertEqual(recorder.count, 1)
        XCTAssertTrue(recorder.firstObject === tab)
        XCTAssertNil(recorder.firstUserInfo)
    }

    func testMarkSuspendedKeepsExistingLastSelectedAt() {
        let tab = makeTab()
        let existingDate = Date(timeIntervalSince1970: 50)
        tab.lastSelectedAt = existingDate

        tab.markSuspended(at: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(tab.lastSelectedAt, existingDate)
    }

    func testSuspendedRestoreFinishesOnlyAfterWebViewExists() {
        let tab = makeTab()
        tab.isSuspended = true
        let recorder = TabSuspensionLifecycleRecorder(observing: tab)

        tab.beginSuspendedRestoreIfNeeded()
        tab.finishSuspendedRestoreIfNeeded()

        XCTAssertTrue(tab.isSuspended)
        XCTAssertTrue(tab.isSuspensionRestoreInProgress)
        XCTAssertEqual(recorder.count, 0)

        tab._webView = WKWebView()
        tab.finishSuspendedRestoreIfNeeded()

        XCTAssertFalse(tab.isSuspended)
        XCTAssertFalse(tab.isSuspensionRestoreInProgress)
        XCTAssertEqual(recorder.count, 1)
        XCTAssertTrue(recorder.firstObject === tab)
    }

    func testResetPageSuspensionRuntimeStateClearsEligibilityFlagsOnly() {
        let tab = makeTab()
        let selectedAt = Date(timeIntervalSince1970: 25)
        tab.pageSuspensionVeto = .pageReportedUnableToSuspend
        tab.hasPictureInPictureVideo = true
        tab.isDisplayingPDFDocument = true
        tab.isSuspended = true
        tab.lastSelectedAt = selectedAt

        tab.resetPageSuspensionRuntimeState()

        XCTAssertEqual(tab.pageSuspensionVeto, .none)
        XCTAssertFalse(tab.hasPictureInPictureVideo)
        XCTAssertFalse(tab.isDisplayingPDFDocument)
        XCTAssertTrue(tab.isSuspended)
        XCTAssertEqual(tab.lastSelectedAt, selectedAt)
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

    var firstUserInfo: [AnyHashable: Any]? {
        lock.withLock { notifications.first?.userInfo }
    }
}

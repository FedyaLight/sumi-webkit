import WebKit
import SumiWebRuntime
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

    func testInteractionStateIsNotConsumedBeforeNativeRestoreBinding() {
        let tab = makeTab()
        let residence = WebViewResidence.untracked(tabID: tab.id)
        let snapshot = PageSessionSnapshot(
            residence: residence,
            residenceGeneration: 1,
            profileID: nil,
            dataStoreIdentity: PageSessionDataStoreIdentity(
                WKWebsiteDataStore.default()
            ),
            committedRevision: tab.mainFrameLoads.currentIntent.revision,
            destination: tab.url,
            data: Data([1, 2, 3])
        )
        tab.markSuspended(sessionSnapshots: [snapshot])
        tab.beginSuspendedRestoreIfNeeded()

        let firstCandidate = tab.suspensionState.candidate(
            residence: residence,
            residenceGeneration: tab.webViewSession.generation,
            profileID: nil,
            dataStoreIdentity: snapshot.dataStoreIdentity,
            intentRevision: snapshot.committedRevision,
            destination: tab.url
        )
        let secondCandidate = tab.suspensionState.candidate(
            residence: residence,
            residenceGeneration: tab.webViewSession.generation,
            profileID: nil,
            dataStoreIdentity: snapshot.dataStoreIdentity,
            intentRevision: snapshot.committedRevision,
            destination: tab.url
        )

        XCTAssertEqual(firstCandidate, snapshot)
        XCTAssertEqual(secondCandidate, snapshot)

        XCTAssertTrue(tab.suspensionState.bind(
            snapshot,
            webViewID: ObjectIdentifier(NSObject()),
            navigationID: ObjectIdentifier(NSObject())
        ))
        XCTAssertTrue(tab.suspensionState.snapshots.isEmpty)
    }

    func testSuspendedRestoreFinishesOnlyAfterBoundNavigationCommits() {
        let tab = makeTab()
        tab.markSuspended()
        let recorder = TabSuspensionLifecycleRecorder(observing: tab)

        tab.beginSuspendedRestoreIfNeeded()
        tab.replaceUntrackedWebView(WKWebView())

        XCTAssertTrue(tab.suspensionState.isSuspended)
        XCTAssertTrue(tab.suspensionState.isRestoreInProgress)
        XCTAssertEqual(recorder.count, 0)

        let webView = WKWebView()
        let navigationID = ObjectIdentifier(NSObject())
        XCTAssertTrue(tab.suspensionState.beginFallback(
            webViewID: ObjectIdentifier(webView)
        ))
        XCTAssertTrue(tab.commitSuspendedRestoreIfMatching(
            webView: webView,
            navigationID: navigationID
        ))

        XCTAssertFalse(tab.suspensionState.isSuspended)
        XCTAssertFalse(tab.suspensionState.isRestoreInProgress)
        XCTAssertEqual(recorder.count, 1)
        XCTAssertIdentical(recorder.firstObject, tab)
    }

    func testSessionRestoreRejectsWrongAuthorityAndFallsBackExactlyOnce() {
        let tab = makeTab()
        let residence = WebViewResidence.untracked(tabID: tab.id)
        let dataStoreIdentity = PageSessionDataStoreIdentity(
            WKWebsiteDataStore.default()
        )
        let snapshot = PageSessionSnapshot(
            residence: residence,
            residenceGeneration: tab.webViewSession.generation,
            profileID: nil,
            dataStoreIdentity: dataStoreIdentity,
            committedRevision: tab.mainFrameLoads.currentIntent.revision,
            destination: tab.url,
            data: Data([4, 5, 6])
        )
        tab.markSuspended(sessionSnapshots: [snapshot])
        tab.beginSuspendedRestoreIfNeeded()

        XCTAssertNil(tab.suspensionState.candidate(
            residence: residence,
            residenceGeneration: tab.webViewSession.generation &+ 1,
            profileID: nil,
            dataStoreIdentity: dataStoreIdentity,
            intentRevision: snapshot.committedRevision,
            destination: tab.url
        ))
        XCTAssertNil(tab.suspensionState.candidate(
            residence: residence,
            residenceGeneration: tab.webViewSession.generation,
            profileID: UUID(),
            dataStoreIdentity: dataStoreIdentity,
            intentRevision: snapshot.committedRevision,
            destination: tab.url
        ))
        XCTAssertNil(tab.suspensionState.candidate(
            residence: residence,
            residenceGeneration: tab.webViewSession.generation,
            profileID: nil,
            dataStoreIdentity: PageSessionDataStoreIdentity(
                WKWebsiteDataStore.nonPersistent()
            ),
            intentRevision: snapshot.committedRevision,
            destination: tab.url
        ))
        XCTAssertNil(tab.suspensionState.candidate(
            residence: residence,
            residenceGeneration: tab.webViewSession.generation,
            profileID: nil,
            dataStoreIdentity: dataStoreIdentity,
            intentRevision: snapshot.committedRevision &+ 1,
            destination: tab.url
        ))
        XCTAssertNil(tab.suspensionState.candidate(
            residence: residence,
            residenceGeneration: tab.webViewSession.generation,
            profileID: nil,
            dataStoreIdentity: dataStoreIdentity,
            intentRevision: snapshot.committedRevision,
            destination: URL(string: "https://example.com/other")!
        ))
        let webViewID = ObjectIdentifier(NSObject())
        XCTAssertTrue(tab.suspensionState.beginFallback(webViewID: webViewID))
        XCTAssertFalse(tab.suspensionState.beginFallback(webViewID: webViewID))
        XCTAssertTrue(tab.suspensionState.failFallback())
        XCTAssertEqual(tab.suspensionState.phase, .failed)
    }

    func testPerResidenceSnapshotsRemainIndependentUntilExactBinding() {
        let tab = makeTab()
        let firstResidence = WebViewResidence.window(.init(
            tabID: tab.id,
            windowID: UUID()
        ))
        let secondResidence = WebViewResidence.window(.init(
            tabID: tab.id,
            windowID: UUID()
        ))
        let storeIdentity = PageSessionDataStoreIdentity(
            WKWebsiteDataStore.default()
        )
        let revision = tab.mainFrameLoads.currentIntent.revision
        let snapshots = [firstResidence, secondResidence].enumerated().map {
            offset,
            residence in
            PageSessionSnapshot(
                residence: residence,
                residenceGeneration: tab.webViewSession.generation,
                profileID: nil,
                dataStoreIdentity: storeIdentity,
                committedRevision: revision,
                destination: tab.url,
                data: Data([UInt8(offset)])
            )
        }
        tab.markSuspended(sessionSnapshots: snapshots)
        tab.beginSuspendedRestoreIfNeeded()
        let candidate = tab.suspensionState.candidate(
            residence: firstResidence,
            residenceGeneration: tab.webViewSession.generation,
            profileID: nil,
            dataStoreIdentity: storeIdentity,
            intentRevision: revision,
            destination: tab.url
        )

        XCTAssertEqual(candidate, snapshots[0])
        XCTAssertTrue(tab.suspensionState.bind(
            snapshots[0],
            webViewID: ObjectIdentifier(NSObject()),
            navigationID: ObjectIdentifier(NSObject())
        ))
        XCTAssertNil(tab.suspensionState.snapshots[firstResidence])
        XCTAssertEqual(tab.suspensionState.snapshots[secondResidence], snapshots[1])
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

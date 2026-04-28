import XCTest

@testable import Sumi

@MainActor
final class SumiBlockedPopupStoreTests: XCTestCase {
    func testRecordsBlockedPopupWithRequiredSessionFields() {
        let store = SumiBlockedPopupStore()
        let popup = blockedPopup(
            id: "popup-a",
            targetURL: URL(string: "https://popup.example/window"),
            userActivation: .none,
            reason: .blockedByDefault,
            canOpenLater: true,
            metadata: ["navigationType": "other"]
        )

        let stored = store.record(popup)

        XCTAssertEqual(stored.id, "popup-a")
        XCTAssertEqual(stored.tabId, "tab-a")
        XCTAssertEqual(stored.pageId, "tab-a:1")
        XCTAssertEqual(stored.requestingOrigin.identity, "https://popup.example")
        XCTAssertEqual(stored.topOrigin.identity, "https://top.example")
        XCTAssertEqual(stored.targetURL, URL(string: "https://popup.example/window"))
        XCTAssertEqual(stored.sourceURL, URL(string: "https://top.example/source"))
        XCTAssertEqual(stored.createdAt, fixedDate)
        XCTAssertEqual(stored.userActivation, .none)
        XCTAssertEqual(stored.reason, .blockedByDefault)
        XCTAssertTrue(stored.canOpenLater)
        XCTAssertEqual(stored.navigationActionMetadata["navigationType"], "other")
        XCTAssertEqual(store.records(forPageId: "tab-a:1"), [stored])
    }

    func testDuplicateBlockedPopupIncrementsAttemptCountInsteadOfAppending() {
        let store = SumiBlockedPopupStore()
        let first = store.record(blockedPopup(id: "popup-a", lastBlockedAt: fixedDate))
        let second = store.record(blockedPopup(id: "popup-b", lastBlockedAt: laterDate))

        XCTAssertEqual(first.id, "popup-a")
        XCTAssertEqual(second.id, "popup-a")
        XCTAssertEqual(second.attemptCount, 2)
        XCTAssertEqual(second.lastBlockedAt, laterDate)
        XCTAssertEqual(store.records(forPageId: "tab-a:1").count, 1)
    }

    func testSnapshotsAreScopedByPageAndClearOnNavigationOrTabCleanup() {
        let store = SumiBlockedPopupStore()
        store.record(blockedPopup(id: "popup-a", pageId: "tab-a:1"))
        store.record(blockedPopup(id: "popup-b", pageId: "tab-a:2"))
        store.record(blockedPopup(id: "popup-c", tabId: "tab-b", pageId: "tab-b:1"))

        XCTAssertEqual(store.records(forPageId: "tab-a:1").map(\.id), ["popup-a"])

        XCTAssertEqual(store.clear(pageId: "tab-a:1"), 1)
        XCTAssertTrue(store.records(forPageId: "tab-a:1").isEmpty)
        XCTAssertEqual(store.records(forPageId: "tab-a:2").map(\.id), ["popup-b"])

        XCTAssertEqual(store.clear(tabId: "tab-a"), 1)
        XCTAssertTrue(store.records(forPageId: "tab-a:2").isEmpty)
        XCTAssertEqual(store.records(forPageId: "tab-b:1").map(\.id), ["popup-c"])
    }

    func testReopenEligibilityRequiresSafeKnownTargetURL() {
        let store = SumiBlockedPopupStore()
        store.record(blockedPopup(id: "safe", targetURL: URL(string: "https://popup.example/window"), canOpenLater: true))
        store.record(blockedPopup(id: "blank", targetURL: URL(string: "about:blank"), canOpenLater: false))
        store.record(blockedPopup(id: "empty", targetURL: nil, canOpenLater: false))

        XCTAssertEqual(store.reopenableRecord(id: "safe", pageId: "tab-a:1")?.id, "safe")
        XCTAssertNil(store.reopenableRecord(id: "blank", pageId: "tab-a:1"))
        XCTAssertNil(store.reopenableRecord(id: "empty", pageId: "tab-a:1"))
    }

    private func blockedPopup(
        id: String,
        tabId: String = "tab-a",
        pageId: String = "tab-a:1",
        targetURL: URL? = URL(string: "https://popup.example/window"),
        sourceURL: URL? = URL(string: "https://top.example/source"),
        lastBlockedAt: Date = fixedDate,
        userActivation: SumiPopupUserActivationState = .none,
        reason: SumiBlockedPopupRecord.Reason = .blockedByDefault,
        canOpenLater: Bool = true,
        metadata: [String: String] = [:]
    ) -> SumiBlockedPopupRecord {
        SumiBlockedPopupRecord(
            id: id,
            tabId: tabId,
            pageId: pageId,
            requestingOrigin: SumiPermissionOrigin(string: "https://popup.example"),
            topOrigin: SumiPermissionOrigin(string: "https://top.example"),
            targetURL: targetURL,
            sourceURL: sourceURL,
            createdAt: fixedDate,
            lastBlockedAt: lastBlockedAt,
            userActivation: userActivation,
            reason: reason,
            canOpenLater: canOpenLater,
            navigationActionMetadata: metadata,
            attemptCount: 1
        )
    }
}

private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
private let laterDate = Date(timeIntervalSince1970: 1_800_000_060)

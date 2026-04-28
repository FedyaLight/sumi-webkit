import XCTest

@testable import Sumi

@MainActor
final class SumiExternalSchemeSessionStoreTests: XCTestCase {
    func testRecordStoresExternalSchemeAttemptFieldsByPage() {
        let store = SumiExternalSchemeSessionStore()
        let record = externalSessionRecord()

        store.record(record)

        let records = store.records(forPageId: "TAB-A:1")
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, "attempt-a")
        XCTAssertEqual(records.first?.tabId, "tab-a")
        XCTAssertEqual(records.first?.pageId, "tab-a:1")
        XCTAssertEqual(records.first?.requestingOrigin.identity, "https://request.example")
        XCTAssertEqual(records.first?.topOrigin.identity, "https://top.example")
        XCTAssertEqual(records.first?.scheme, "mailto")
        XCTAssertEqual(records.first?.redactedTargetURLString, "mailto:test@example.com")
        XCTAssertEqual(records.first?.appDisplayName, "Mail")
        XCTAssertEqual(records.first?.userActivation, .navigationAction)
        XCTAssertEqual(records.first?.result, .blockedPendingUI)
        XCTAssertEqual(records.first?.reason, SumiExternalSchemePendingStrategy.blockUntilPromptUIExists.reason)
        XCTAssertEqual(records.first?.attemptCount, 1)
    }

    func testDuplicateAttemptsIncrementAttemptCountWithoutAddingRows() {
        let store = SumiExternalSchemeSessionStore()
        let first = externalSessionRecord(id: "attempt-a", lastAttemptAt: externalSessionDate)
        let second = externalSessionRecord(id: "attempt-b", lastAttemptAt: externalSessionDate.addingTimeInterval(30))

        store.record(first)
        let recorded = store.record(second)

        let records = store.records(forPageId: "tab-a:1")
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(recorded.id, "attempt-a")
        XCTAssertEqual(recorded.attemptCount, 2)
        XCTAssertEqual(recorded.lastAttemptAt, externalSessionDate.addingTimeInterval(30))
    }

    func testClearByPageAndTabRemovesSessionOnlyAttempts() {
        let store = SumiExternalSchemeSessionStore()
        store.record(externalSessionRecord(pageId: "tab-a:1"))
        store.record(externalSessionRecord(id: "attempt-b", pageId: "tab-a:2"))
        store.record(externalSessionRecord(id: "attempt-c", tabId: "tab-b", pageId: "tab-b:1"))

        XCTAssertEqual(store.clear(pageId: "TAB-A:1"), 1)
        XCTAssertTrue(store.records(forPageId: "tab-a:1").isEmpty)
        XCTAssertEqual(store.records(forPageId: "tab-a:2").count, 1)

        XCTAssertEqual(store.clear(tabId: "TAB-A"), 1)
        XCTAssertTrue(store.records(forPageId: "tab-a:2").isEmpty)
        XCTAssertEqual(store.records(forPageId: "tab-b:1").count, 1)
    }

    func testRedactedDisplayStringStripsQueryAndFragment() {
        let redacted = SumiExternalSchemePermissionRequest.redactedDisplayString(
            for: URL(string: "zoommtg://join/123?token=secret#access-token")!
        )

        XCTAssertEqual(redacted, "zoommtg://join/123")
        XCTAssertFalse(redacted?.contains("secret") == true)
        XCTAssertFalse(redacted?.contains("access-token") == true)
    }
}

private let externalSessionDate = Date(timeIntervalSince1970: 1_800_000_000)

private func externalSessionRecord(
    id: String = "attempt-a",
    tabId: String = "tab-a",
    pageId: String = "tab-a:1",
    lastAttemptAt: Date = externalSessionDate
) -> SumiExternalSchemeAttemptRecord {
    SumiExternalSchemeAttemptRecord(
        id: id,
        tabId: tabId,
        pageId: pageId,
        requestingOrigin: SumiPermissionOrigin(string: "https://request.example"),
        topOrigin: SumiPermissionOrigin(string: "https://top.example"),
        scheme: "mailto",
        redactedTargetURLString: "mailto:test@example.com",
        appDisplayName: "Mail",
        createdAt: externalSessionDate,
        lastAttemptAt: lastAttemptAt,
        userActivation: .navigationAction,
        result: .blockedPendingUI,
        reason: SumiExternalSchemePendingStrategy.blockUntilPromptUIExists.reason,
        navigationActionMetadata: ["path": "navigationResponder"],
        attemptCount: 1
    )
}

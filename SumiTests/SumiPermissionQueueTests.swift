import XCTest

@testable import Sumi

final class SumiPermissionQueueTests: XCTestCase {
    func testOneActiveRequestPerPageId() async {
        let queue = SumiPermissionQueue()
        _ = await queue.enqueue(request("one", pageId: "page-a", type: .camera))
        let second = await queue.enqueue(request("two", pageId: "page-a", type: .geolocation))

        guard case .queued(_, let position) = second else {
            XCTFail("Expected second request to queue")
            return
        }
        XCTAssertEqual(position, 1)
        let active = await queue.activeRequest(forPageId: "page-a")
        let queued = await queue.queuedRequests(forPageId: "page-a")
        XCTAssertEqual(active?.request.id, "one")
        XCTAssertEqual(queued.map(\.request.id), ["two"])
    }

    func testFIFOQueueAdvancement() async {
        let queue = SumiPermissionQueue()
        _ = await queue.enqueue(request("one", pageId: "page-a", type: .camera))
        _ = await queue.enqueue(request("two", pageId: "page-a", type: .geolocation))
        _ = await queue.enqueue(request("three", pageId: "page-a", type: .notifications))

        let firstAdvance = await queue.finishActiveRequest(pageId: "page-a")
        let secondAdvance = await queue.finishActiveRequest(pageId: "page-a")

        XCTAssertEqual(firstAdvance.completedRequestIds, ["one"])
        XCTAssertEqual(firstAdvance.nextActive?.request.id, "two")
        XCTAssertEqual(secondAdvance.completedRequestIds, ["two"])
        XCTAssertEqual(secondAdvance.nextActive?.request.id, "three")
    }

    func testDuplicateCoalescing() async {
        let queue = SumiPermissionQueue()
        _ = await queue.enqueue(request("one", pageId: "page-a", type: .camera))
        let duplicate = await queue.enqueue(request("two", pageId: "page-a", type: .camera))

        guard case .coalesced(let entry) = duplicate else {
            XCTFail("Expected duplicate request to coalesce")
            return
        }
        XCTAssertEqual(entry.allRequestIds, ["one", "two"])
        let active = await queue.activeRequest(forPageId: "page-a")
        let queued = await queue.queuedRequests(forPageId: "page-a")
        XCTAssertEqual(active?.allRequestIds, ["one", "two"])
        XCTAssertTrue(queued.isEmpty)
    }

    func testCancelOneRequest() async {
        let queue = SumiPermissionQueue()
        _ = await queue.enqueue(request("one", pageId: "page-a", type: .camera))
        _ = await queue.enqueue(request("two", pageId: "page-a", type: .geolocation))

        let cancellation = await queue.cancel(requestId: "two")

        XCTAssertEqual(cancellation.cancelledRequestIds, ["two"])
        XCTAssertNil(cancellation.promotedActive)
        let active = await queue.activeRequest(forPageId: "page-a")
        let queued = await queue.queuedRequests(forPageId: "page-a")
        XCTAssertEqual(active?.request.id, "one")
        XCTAssertTrue(queued.isEmpty)
    }

    func testCancelAllRequestsForPageId() async {
        let queue = SumiPermissionQueue()
        _ = await queue.enqueue(request("one", pageId: "page-a", type: .camera))
        _ = await queue.enqueue(request("two", pageId: "page-a", type: .geolocation))

        let cancellation = await queue.cancel(pageId: "page-a")
        let snapshot = await queue.snapshot(forPageId: "page-a")

        XCTAssertEqual(cancellation.cancelledRequestIds, ["one", "two"])
        XCTAssertNil(snapshot.active)
        XCTAssertTrue(snapshot.queued.isEmpty)
    }

    private func request(
        _ id: String,
        pageId: String,
        type: SumiPermissionType
    ) -> SumiPermissionRequest {
        SumiPermissionRequest(
            id: id,
            tabId: "tab-a",
            pageId: pageId,
            frameId: "frame-a",
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
            topOrigin: SumiPermissionOrigin(string: "https://example.com"),
            permissionTypes: [type],
            hasUserGesture: true,
            requestedAt: ISO8601DateFormatter().date(from: "2026-04-28T10:00:00Z")!,
            profilePartitionId: "profile-a"
        )
    }
}

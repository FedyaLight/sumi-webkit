import XCTest
import WebKit

@testable import Sumi

@MainActor
final class PageMaterializationRequestLedgerTests: XCTestCase {
    func testLatestRequestOwnsWindowMaterializationAcrossABASelection() throws {
        let ledger = PageMaterializationRequestLedger()
        let windowID = UUID()
        let pageA = UUID()
        let pageB = UUID()
        let destinationA = try XCTUnwrap(URL(string: "https://example.com/a"))
        let destinationB = try XCTUnwrap(URL(string: "https://example.com/b"))

        let firstAdmission = ledger.beginActivation(
            [PageMaterializationRequestSeed(
                pageID: pageA,
                residenceGeneration: 4,
                destination: destinationA
            )],
            windowID: windowID
        )
        let firstA = try XCTUnwrap(firstAdmission.requests.first)
        XCTAssertTrue(firstAdmission.superseded.isEmpty)
        XCTAssertTrue(ledger.owns(firstA))

        let selectionBAdmission = ledger.beginActivation(
            [PageMaterializationRequestSeed(
                pageID: pageB,
                residenceGeneration: 4,
                destination: destinationB
            )],
            windowID: windowID
        )
        let selectionB = try XCTUnwrap(selectionBAdmission.requests.first)
        XCTAssertEqual(selectionBAdmission.superseded.first?.request, firstA)
        XCTAssertEqual(selectionBAdmission.superseded.first?.result, .superseded)
        XCTAssertFalse(ledger.owns(firstA))

        let secondAAdmission = ledger.beginActivation(
            [PageMaterializationRequestSeed(
                pageID: pageA,
                residenceGeneration: 5,
                destination: destinationA
            )],
            windowID: windowID
        )
        let secondA = try XCTUnwrap(secondAAdmission.requests.first)
        XCTAssertEqual(selectionB.selectionRevision + 1,
                       secondA.selectionRevision)
        XCTAssertFalse(ledger.owns(selectionB))
        XCTAssertTrue(ledger.owns(secondA))
        XCTAssertNotEqual(firstA, secondA)

        let owner = TabMainFramePendingAttemptOwner(
            intent: TabMainFrameNavigationIntent(
                revision: 1,
                targetURL: destinationA
            ),
            documentGeneration: 1,
            participantID: UUID(),
            webViewID: ObjectIdentifier(WKWebView()),
            phase: .submitted
        )
        let completion = ledger.settle(secondA, as: .transferred(owner))
        XCTAssertEqual(completion?.request, secondA)
        XCTAssertEqual(completion?.result, .transferred(owner))
        XCTAssertNil(
            ledger.settle(
                secondA,
                as: .failed(.residenceUnavailable)
            )
        )
        XCTAssertNil(ledger.currentRequest(in: windowID))
    }

    func testSplitPaneRequestsShareActivationButSettleIndependently() throws {
        let ledger = PageMaterializationRequestLedger()
        let windowID = UUID()
        let firstPageID = UUID()
        let secondPageID = UUID()
        let firstURL = try XCTUnwrap(URL(string: "https://example.com/one"))
        let secondURL = try XCTUnwrap(URL(string: "https://example.com/two"))
        let admission = ledger.beginActivation(
            [
                PageMaterializationRequestSeed(
                    pageID: firstPageID,
                    residenceGeneration: 1,
                    destination: firstURL
                ),
                PageMaterializationRequestSeed(
                    pageID: secondPageID,
                    residenceGeneration: 8,
                    destination: secondURL
                ),
            ],
            windowID: windowID
        )

        XCTAssertEqual(admission.requests.count, 2)
        XCTAssertEqual(
            Set(admission.requests.map(\.selectionRevision)).count,
            1
        )
        let first = try XCTUnwrap(admission.requests.first {
            $0.pageID == firstPageID
        })
        let second = try XCTUnwrap(admission.requests.first {
            $0.pageID == secondPageID
        })

        XCTAssertEqual(
            ledger.settle(
                first,
                as: .failed(.residenceUnavailable)
            )?.result,
            .failed(.residenceUnavailable)
        )
        XCTAssertFalse(ledger.owns(first))
        XCTAssertTrue(ledger.owns(second))
        XCTAssertEqual(
            ledger.currentRequest(for: secondPageID, in: windowID),
            second
        )
    }

    func testSamePageRetryAfterFailureCreatesANewExactRequest() throws {
        let ledger = PageMaterializationRequestLedger()
        let windowID = UUID()
        let pageID = UUID()
        let destination = try XCTUnwrap(
            URL(string: "https://example.com/retry")
        )
        let first = ledger.begin(
            pageID: pageID,
            windowID: windowID,
            residenceGeneration: 3,
            destination: destination
        ).request
        _ = ledger.settle(
            first,
            as: .failed(.initialSubmissionUnavailable)
        )

        let retry = ledger.begin(
            pageID: pageID,
            windowID: windowID,
            residenceGeneration: 4,
            destination: destination
        ).request

        XCTAssertNotEqual(first.id, retry.id)
        XCTAssertGreaterThan(retry.selectionRevision, first.selectionRevision)
        XCTAssertTrue(ledger.owns(retry))
    }
}

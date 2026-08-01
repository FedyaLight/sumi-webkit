import Foundation
import XCTest

@testable import Sumi

final class ExtensionContentScriptBindingPolicyTests: XCTestCase {
    func testDocumentWithoutCommitDoesNotNeedRebind() {
        XCTAssertFalse(
            needsRebind(
                documentSequence: 0,
                committedURL: nil,
                openNotifiedDocumentSequence: nil,
                readiness: .missing,
                controllerNeedsRuntimeRebuild: true
            )
        )
    }

    func testNonInjectableCommittedDocumentDoesNotNeedRebind() {
        for url in [
            URL(string: "about:blank")!,
            URL(string: "sumi://history")!,
            URL(string: "data:text/plain,hello")!,
        ] {
            XCTAssertFalse(
                needsRebind(
                    committedURL: url,
                    openNotifiedDocumentSequence: nil,
                    readiness: .missing,
                    controllerNeedsRuntimeRebuild: true
                ),
                "Unexpected rebind for \(url)"
            )
        }
    }

    func testMissingContextAtOpenNeedsRebind() {
        XCTAssertTrue(
            needsRebind(
                openNotifiedDocumentSequence: 0,
                readiness: .missing
            )
        )
    }

    func testOtherContextReadinessStatesDoNotByThemselvesNeedRebind() {
        for readiness in [
            TabExtensionContextReadiness.notNotified,
            .unknown,
            .loaded,
        ] {
            XCTAssertFalse(
                needsRebind(
                    openNotifiedDocumentSequence: 0,
                    readiness: readiness
                )
            )
        }
    }

    func testChangedContextBindingGenerationNeedsRebind() {
        XCTAssertTrue(
            needsRebind(
                openNotifiedDocumentSequence: 0,
                openNotifiedContextBindingGeneration: 3,
                currentContextBindingGeneration: 4
            )
        )
    }

    func testUnknownContextGenerationDoesNotInventMismatch() {
        XCTAssertFalse(
            needsRebind(
                openNotifiedDocumentSequence: 0,
                openNotifiedContextBindingGeneration: 3,
                currentContextBindingGeneration: nil
            )
        )
    }

    func testMissingOpenContextGenerationDoesNotInventMismatch() {
        XCTAssertFalse(
            needsRebind(
                openNotifiedDocumentSequence: 0,
                openNotifiedContextBindingGeneration: nil,
                currentContextBindingGeneration: 4
            )
        )
    }

    func testControllerRuntimeMismatchNeedsRebind() {
        XCTAssertTrue(
            needsRebind(
                openNotifiedDocumentSequence: 0,
                controllerNeedsRuntimeRebuild: true
            )
        )
    }

    func testMissingOpenNotificationNeedsRebind() {
        XCTAssertTrue(needsRebind(openNotifiedDocumentSequence: nil))
    }

    func testOpenAfterCommitNeedsRebind() {
        XCTAssertTrue(needsRebind(openNotifiedDocumentSequence: 1))
    }

    func testOpenImmediatelyBeforeCommitDoesNotNeedRebind() {
        for url in [
            URL(string: "http://example.com")!,
            URL(string: "https://example.com")!,
            URL(fileURLWithPath: "/tmp/page.html"),
        ] {
            XCTAssertFalse(
                needsRebind(
                    committedURL: url,
                    openNotifiedDocumentSequence: 0,
                    openNotifiedContextBindingGeneration: 7,
                    currentContextBindingGeneration: 7
                ),
                "Unexpected rebind for \(url)"
            )
        }
    }

    func testLaterCommitWithoutAnotherOpenNeedsRebind() {
        XCTAssertTrue(
            needsRebind(
                documentSequence: 2,
                openNotifiedDocumentSequence: 0
            )
        )
    }

    private func needsRebind(
        documentSequence: UInt64 = 1,
        committedURL: URL? = URL(string: "https://example.com")!,
        openNotifiedDocumentSequence: UInt64?,
        openNotifiedContextBindingGeneration: UInt64? = 1,
        readiness: TabExtensionContextReadiness = .loaded,
        currentContextBindingGeneration: UInt64? = 1,
        controllerNeedsRuntimeRebuild: Bool = false
    ) -> Bool {
        ExtensionContentScriptBindingPolicy.needsRebind(
            documentBinding: TabExtensionDocumentBindingSnapshot(
                documentSequence: documentSequence,
                committedMainDocumentURL: committedURL,
                openNotifiedDocumentSequence: openNotifiedDocumentSequence,
                openNotifiedContextBindingGeneration: openNotifiedContextBindingGeneration,
                openNotifiedContextReadiness: readiness
            ),
            currentContextBindingGeneration: currentContextBindingGeneration,
            controllerNeedsRuntimeRebuild: controllerNeedsRuntimeRebuild
        )
    }
}

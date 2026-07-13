import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupCompletionTests: XCTestCase {
    func testSettlementInvokesWebKitCompletionExactlyOnce() {
        var results: [Error?] = []
        let completion = ExtensionActionPopupCompletion { results.append($0) }

        completion.settle(nil)
        completion.settle(CancellationError())

        XCTAssertEqual(results.count, 1)
        XCTAssertNil(results[0])
    }

    func testReentrantSettlementCannotInvokeWebKitCompletionTwice() {
        var results = 0
        var completion: ExtensionActionPopupCompletion!
        completion = ExtensionActionPopupCompletion { _ in
            results += 1
            completion.settle(CancellationError())
        }

        completion.settle(nil)

        XCTAssertEqual(results, 1)
    }
}

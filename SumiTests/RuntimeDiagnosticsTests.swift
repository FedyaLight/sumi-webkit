import XCTest

@testable import Sumi

final class RuntimeDiagnosticsTests: XCTestCase {
    func testLazyEmitDoesNotEvaluateClosureWhenVerboseLoggingIsDisabled() throws {
        try XCTSkipIf(
            RuntimeDiagnostics.isVerboseEnabled,
            "This assertion only holds when verbose runtime logging is disabled."
        )

        var evaluated = false

        RuntimeDiagnostics.emit {
            evaluated = true
            return "should not log"
        }

        XCTAssertFalse(evaluated)
    }
}

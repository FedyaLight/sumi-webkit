import SwiftData
import XCTest

@testable import Sumi

final class RuntimeDiagnosticsTests: XCTestCase {
    func testLazyDebugDoesNotEvaluateClosureWhenVerboseLoggingIsDisabled() throws {
        try XCTSkipIf(
            RuntimeDiagnostics.isVerboseEnabled,
            "This assertion only holds when verbose runtime logging is disabled."
        )

        var evaluated = false

        RuntimeDiagnostics.debug(category: "RuntimeDiagnosticsTests") {
            evaluated = true
            return "should not log"
        }

        XCTAssertFalse(evaluated)
    }

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

    func testLazySwipeTraceDoesNotEvaluateClosureWhenSwipeTracingIsDisabled() throws {
        try XCTSkipIf(
            RuntimeDiagnostics.isSwipeTraceEnabled,
            "This assertion only holds when swipe tracing is disabled."
        )

        var evaluated = false

        RuntimeDiagnostics.swipeTrace({
            evaluated = true
            return "should not log"
        }())

        XCTAssertFalse(evaluated)
    }

    @MainActor
    @available(macOS 15.5, *)
    func testExtensionRuntimeTraceDoesNotEvaluateClosureWhenVerboseLoggingIsDisabled() throws {
        try XCTSkipIf(
            RuntimeDiagnostics.isVerboseEnabled,
            "This assertion only holds when verbose runtime logging is disabled."
        )

        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: Profile(name: "Tests")
        )

        var evaluated = false

        manager.extensionRuntimeTrace {
            evaluated = true
            return "should not log"
        }

        XCTAssertFalse(evaluated)
    }
}

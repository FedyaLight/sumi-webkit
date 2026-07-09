import Foundation
import OSLog

/// Package-local diagnostics. Keeps SumiWebRuntime closed without
/// depending on app-target `RuntimeDiagnostics` / `PerformanceTrace`.
enum SumiWebRuntimeDiagnostics {
    static let subsystem = "com.sumi.browser"

    private static let performanceSignposter = OSSignposter(
        logger: Logger(subsystem: subsystem, category: "PerformanceTrace")
    )

    static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    static func protectedWebViewTrace(_ message: @autoclosure () -> String) {
        #if DEBUG
        let resolved = message()
        logger(category: "ProtectedWebView").debug("\(resolved, privacy: .public)")
        #else
        _ = message()
        #endif
    }

    static func debug(
        category: String,
        _ message: @autoclosure () -> String
    ) {
        #if DEBUG
        let resolved = message()
        logger(category: category).debug("\(resolved, privacy: .public)")
        #else
        _ = message()
        #endif
    }

    static func debug(
        category: String,
        _ message: () -> String
    ) {
        #if DEBUG
        let resolved = message()
        logger(category: category).debug("\(resolved, privacy: .public)")
        #else
        _ = message()
        #endif
    }

    static func emitPerformanceEvent(_ name: StaticString) {
        #if DEBUG
        performanceSignposter.emitEvent(name)
        #else
        _ = name
        #endif
    }

    static func beginInterval(_ name: StaticString) -> OSSignpostIntervalState {
        performanceSignposter.beginInterval(name)
    }

    static func endInterval(
        _ name: StaticString,
        _ state: OSSignpostIntervalState
    ) {
        performanceSignposter.endInterval(name, state)
    }
}

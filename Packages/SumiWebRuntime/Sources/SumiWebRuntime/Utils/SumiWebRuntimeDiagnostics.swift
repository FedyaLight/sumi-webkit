import Foundation
import OSLog

/// Package-local diagnostics. Keeps SumiWebRuntime closed without
/// depending on app-target `RuntimeDiagnostics` / `PerformanceTrace`.
enum SumiWebRuntimeDiagnostics {
    static let subsystem = "com.sumi.browser"

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

    static func emitPerformanceEvent(_ name: StaticString) {
        #if DEBUG
        let signposter = OSSignposter(logger: logger(category: "PerformanceTrace"))
        signposter.emitEvent(name)
        #else
        _ = name
        #endif
    }
}

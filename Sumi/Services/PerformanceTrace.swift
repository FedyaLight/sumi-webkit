import OSLog

enum PerformanceTrace {
    static let category = "PerformanceTrace"
    private static let signposter = OSSignposter(
        logger: .sumi(category: category)
    )

    @inline(__always)
    static func beginInterval(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name)
    }

    @inline(__always)
    static func endInterval(
        _ name: StaticString,
        _ state: OSSignpostIntervalState
    ) {
        signposter.endInterval(name, state)
    }

    @inline(__always)
    static func emitEvent(_ name: StaticString) {
        signposter.emitEvent(name)
    }

    @discardableResult
    @inline(__always)
    static func withInterval<T>(
        _ name: StaticString,
        _ operation: () throws -> T
    ) rethrows -> T {
        let state = beginInterval(name)
        defer { endInterval(name, state) }
        return try operation()
    }

}

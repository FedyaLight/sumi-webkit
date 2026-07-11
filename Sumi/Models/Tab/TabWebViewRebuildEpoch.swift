/// Monotonic identity for physical WebView replacement work. Async rebuilds
/// must still carry the current epoch when they are ready to mutate the tab.
@MainActor
final class TabWebViewRebuildEpoch {
    private(set) var current: UInt64 = 0

    @discardableResult
    func advance() -> UInt64 {
        current &+= 1
        return current
    }

    func isCurrent(_ candidate: UInt64) -> Bool {
        current == candidate
    }
}

import AppKit

enum SumiFaviconPresentationMetrics {
    static func defaultBackingScale() -> CGFloat {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                NSScreen.main?.backingScaleFactor ?? 2
            }
        }
        return 2
    }
}

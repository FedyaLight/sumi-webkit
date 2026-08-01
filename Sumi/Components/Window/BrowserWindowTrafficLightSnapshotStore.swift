import AppKit

/// AppKit-measured geometry for the inactive sidebar stand-in.
///
/// SwiftUI owns only the placeholder pixels. Button size, spacing, and titlebar insets continue to
/// come from the user's native standard window controls.
struct BrowserWindowTrafficLightClusterSnapshot: Equatable {
    let size: CGSize
    let buttonFrames: [CGRect]
    let leadingInset: CGFloat
    let topInset: CGFloat
}

/// One process-local measurement of AppKit's standard window-button geometry.
///
/// The temporary window exists only on the first lookup. The cached value is a handful of points
/// and rects: there are no bitmap pixels, observers, timers, polling, or retained AppKit views.
@MainActor
enum BrowserWindowTrafficLightSnapshotStore {
    private static var cachedSnapshot: BrowserWindowTrafficLightClusterSnapshot?

    static func snapshot() -> BrowserWindowTrafficLightClusterSnapshot? {
        if let cachedSnapshot {
            return cachedSnapshot
        }

        guard let snapshot = makeSystemSnapshot() else { return nil }
        cachedSnapshot = snapshot
        return snapshot
    }

    private static func makeSystemSnapshot() -> BrowserWindowTrafficLightClusterSnapshot? {
        let probeWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false
        )
        SumiBrowserChromeConfiguration.applyTitlebar(to: probeWindow)

        let buttons = BrowserWindowTrafficLightAction.allCases.compactMap {
            probeWindow.standardWindowButton($0.buttonType)
        }
        guard buttons.count == BrowserWindowTrafficLightAction.allCases.count,
              let titlebarView = buttons.first?.superview,
              buttons.allSatisfy({ $0.superview === titlebarView })
        else { return nil }

        let nativeFrames = buttons.map(\.frame)
        let clusterBounds = nativeFrames.reduce(CGRect.null) { $0.union($1) }
        guard !clusterBounds.isNull,
              clusterBounds.width > 0,
              clusterBounds.height > 0
        else { return nil }

        let leadingInset = probeWindow.windowTitlebarLayoutDirection == .rightToLeft
            ? titlebarView.bounds.maxX - clusterBounds.maxX
            : clusterBounds.minX - titlebarView.bounds.minX
        let topInset = titlebarView.isFlipped
            ? clusterBounds.minY - titlebarView.bounds.minY
            : titlebarView.bounds.maxY - clusterBounds.maxY
        let buttonFrames = buttons.map { button in
            CGRect(
                x: button.frame.minX - clusterBounds.minX,
                y: titlebarView.isFlipped
                    ? button.frame.minY - clusterBounds.minY
                    : clusterBounds.maxY - button.frame.maxY,
                width: button.frame.width,
                height: button.frame.height
            )
        }

        return BrowserWindowTrafficLightClusterSnapshot(
            size: clusterBounds.size,
            buttonFrames: buttonFrames,
            leadingInset: leadingInset,
            topInset: topInset
        )
    }
}

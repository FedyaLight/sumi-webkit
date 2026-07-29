import AppKit

/// A rendered stand-in for the window's standard buttons, used while the sidebar travels.
struct BrowserWindowTrafficLightClusterSnapshot {
    let image: NSImage
    let size: CGSize
}

/// One button's contribution to a cluster snapshot: the live button, plus where it sits inside the
/// cluster's bounds with `y` measured from the top.
struct BrowserWindowTrafficLightSnapshotItem {
    let button: NSButton
    let frame: CGRect
}

/// Demand-driven cache of cluster snapshots, shared by windows that are currently travelling.
///
/// The buttons look identical in every window, so one cache serves all of them. The snapshot is a
/// picture of the *real* buttons rather than a redrawn approximation, which is the whole point:
/// hand-picked colours cannot match an inactive window, a Graphite accent, Increase Contrast, or a
/// macOS release that retunes the cluster, and a placeholder that does not match is exactly what
/// makes the swap visible.
///
/// Key-window appearance and backing scale both affect the pixels. Environment observers exist
/// only while at least one placement is actually showing a placeholder.
@MainActor
enum BrowserWindowTrafficLightSnapshotStore {
    private struct Entry {
        let snapshot: BrowserWindowTrafficLightClusterSnapshot
        let isFallback: Bool
    }

    private struct Key: Hashable {
        let isKeyWindow: Bool
        let scale: Int

        init(isKeyWindow: Bool, scale: CGFloat) {
            self.isKeyWindow = isKeyWindow
            self.scale = Int((max(scale, 1) * 1_000).rounded())
        }

        var resolvedScale: CGFloat {
            CGFloat(scale) / 1_000
        }
    }

    private static var cache: [Key: Entry] = [:]
    private static var demandCount = 0
    private static var environmentObserver: EnvironmentObserver?

    static func acquireDemand() {
        demandCount += 1
        installEnvironmentObserverIfNeeded()
    }

    static func releaseDemand() {
        guard demandCount > 0 else { return }
        demandCount -= 1
        guard demandCount == 0 else { return }
        cache.removeAll()
        environmentObserver = nil
    }

    /// Falls back only across key-window appearance at the same backing scale.
    static func snapshot(
        isKeyWindow: Bool,
        scale: CGFloat
    ) -> BrowserWindowTrafficLightClusterSnapshot? {
        let key = Key(isKeyWindow: isKeyWindow, scale: scale)
        if let exact = cache[key]?.snapshot {
            return exact
        }
        if let liveOtherState = cache[Key(
            isKeyWindow: !isKeyWindow,
            scale: scale
        )]?.snapshot {
            return liveOtherState
        }

        prepareFallback(isKeyWindow: isKeyWindow, scale: scale)
        return cache[key]?.snapshot
    }

    /// Replaces a detached fallback with a live capture while the native buttons are still present.
    static func warm(
        isKeyWindow: Bool,
        items: [BrowserWindowTrafficLightSnapshotItem],
        size: CGSize,
        scale: CGFloat
    ) {
        let key = Key(isKeyWindow: isKeyWindow, scale: scale)

        guard demandCount > 0,
              cache[key]?.isFallback != false,
              let image = render(items: items, size: size, scale: scale)
        else { return }

        cache[key] = Entry(
            snapshot: BrowserWindowTrafficLightClusterSnapshot(image: image, size: size),
            isFallback: false
        )
    }

    /// Prepares a native cold-start placeholder without laying out the live window. AppKit's
    /// detached standard buttons use the same drawing code as the titlebar controls and avoid a
    /// second hand-drawn traffic-light implementation.
    private static func prepareFallback(isKeyWindow: Bool, scale: CGFloat) {
        let key = Key(isKeyWindow: isKeyWindow, scale: scale)
        guard cache[key] == nil else { return }

        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let geometry = BrowserWindowTrafficLightGeometry.fallback
        let indexedActions = BrowserWindowTrafficLightAction.allCases.enumerated()
        let items: [BrowserWindowTrafficLightSnapshotItem] = indexedActions.compactMap { index, action in
            guard let button = NSWindow.standardWindowButton(
                action.buttonType,
                for: styleMask
            ) else { return nil }
            return BrowserWindowTrafficLightSnapshotItem(
                button: button,
                frame: CGRect(
                    x: CGFloat(index) * geometry.centerSpacing,
                    y: 0,
                    width: button.frame.width,
                    height: button.frame.height
                )
            )
        }
        guard items.count == BrowserWindowTrafficLightAction.allCases.count else { return }

        let bounds = items.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        guard let image = render(items: items, size: bounds.size, scale: scale) else { return }
        cache[key] = Entry(
            snapshot: BrowserWindowTrafficLightClusterSnapshot(image: image, size: bounds.size),
            isFallback: true
        )
    }

    private static func refreshForEnvironmentChange() {
        let keys = Array(cache.keys)
        cache.removeAll()
        for key in keys {
            prepareFallback(
                isKeyWindow: key.isKeyWindow,
                scale: key.resolvedScale
            )
        }
    }

    // MARK: - Rendering

    private static func render(
        items: [BrowserWindowTrafficLightSnapshotItem],
        size: CGSize,
        scale: CGFloat
    ) -> NSImage? {
        guard items.isEmpty == false, size.width > 0, size.height > 0 else { return nil }

        let resolvedScale = max(scale, 1)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((size.width * resolvedScale).rounded(.up)),
            pixelsHigh: Int((size.height * resolvedScale).rounded(.up)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        rep.size = size

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        var didDrawAnything = false
        for item in items {
            let bounds = item.button.bounds
            guard bounds.width > 0, bounds.height > 0,
                  let buttonRep = item.button.bitmapImageRepForCachingDisplay(in: bounds)
            else { continue }

            item.button.cacheDisplay(in: bounds, to: buttonRep)
            // `item.frame` measures from the top of the cluster; the bitmap context does not.
            buttonRep.draw(in: CGRect(
                x: item.frame.minX,
                y: size.height - item.frame.maxY,
                width: item.frame.width,
                height: item.frame.height
            ))
            didDrawAnything = true
        }

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard didDrawAnything else { return nil }

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: - Environment invalidation

    private static func installEnvironmentObserverIfNeeded() {
        guard environmentObserver == nil else { return }
        environmentObserver = EnvironmentObserver()
    }

    /// Everything that changes how AppKit draws the buttons, watched by event rather than polled.
    @MainActor
    private final class EnvironmentObserver: NSObject {
        private var appearanceObservation: NSKeyValueObservation?

        override init() {
            super.init()

            appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { _, _ in
                MainActor.assumeIsolated {
                    BrowserWindowTrafficLightSnapshotStore.refreshForEnvironmentChange()
                }
            }

            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(handleEnvironmentChange(_:)),
                name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil
            )

            // Accent colour, including the Graphite setting that greys the cluster outright.
            DistributedNotificationCenter.default.addObserver(
                self,
                selector: #selector(handleEnvironmentChange(_:)),
                name: Notification.Name("AppleColorPreferencesChangedNotification"),
                object: nil
            )
        }

        isolated deinit {
            NSWorkspace.shared.notificationCenter.removeObserver(self)
            DistributedNotificationCenter.default.removeObserver(self)
        }

        @objc private func handleEnvironmentChange(_ notification: Notification) {
            _ = notification
            BrowserWindowTrafficLightSnapshotStore.refreshForEnvironmentChange()
        }
    }
}

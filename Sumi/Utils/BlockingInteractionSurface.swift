import AppKit

@MainActor
protocol SidebarTransientInteractionDisarmable: AnyObject {
    func setTransientInteractionEnabled(_ isEnabled: Bool)
}

@MainActor
final class SidebarTransientInteractionHandle {
    weak var view: NSView?

    func attach(_ view: NSView) {
        self.view = view
    }

    func disarm() {
        (view as? SidebarTransientInteractionDisarmable)?.setTransientInteractionEnabled(false)
    }
}

// MARK: - Hit-testing recovery after transient AppKit UI (NSMenu, NSPopover)

@MainActor
enum SidebarTransientUIHitTestingRecovery {
    /// Walks superviews from `leaf` and forces layout so `NSHostingView` hit-testing recovers after menus/popovers.
    static func invalidateLayoutChain(from leaf: NSView?) {
        guard var view = leaf else { return }
        RuntimeDiagnostics.emit(
            "🧭 Sidebar hit-testing recovery invalidate leaf=\(String(describing: type(of: view)))"
        )
        while true {
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            guard let superview = view.superview else { break }
            view = superview
        }
    }
}

@MainActor
protocol SidebarHostRecoveryHandling: AnyObject {
    func sync(anchor: NSView, window: NSWindow?)
    func unregister(anchor: NSView)
    func recover(in window: NSWindow?)
    func recover(anchor: NSView?)
}

@MainActor
final class SidebarHostRecoveryCoordinator: SidebarHostRecoveryHandling {
    private struct WeakAnchor {
        weak var view: NSView?
    }

    private final class WindowBucket {
        weak var window: NSWindow?
        var anchors: [ObjectIdentifier: WeakAnchor] = [:]

        init(window: NSWindow) {
            self.window = window
        }
    }

    static let shared = SidebarHostRecoveryCoordinator()

    private let invalidateAnchor: @MainActor (NSView?) -> Void
    private var buckets: [ObjectIdentifier: WindowBucket] = [:]
    private var anchorWindowIDs: [ObjectIdentifier: ObjectIdentifier] = [:]

    init(
        invalidateAnchor: @escaping @MainActor (NSView?) -> Void = {
            SidebarTransientUIHitTestingRecovery.invalidateLayoutChain(from: $0)
        }
    ) {
        self.invalidateAnchor = invalidateAnchor
    }

    func sync(anchor: NSView, window: NSWindow?) {
        pruneStaleState()

        let anchorID = ObjectIdentifier(anchor)
        let currentWindowID = window.map(ObjectIdentifier.init)

        if let previousWindowID = anchorWindowIDs[anchorID],
           previousWindowID != currentWindowID
        {
            removeAnchor(anchorID, fromWindowID: previousWindowID)
            anchorWindowIDs.removeValue(forKey: anchorID)
        }

        guard let window else { return }

        let windowID = ObjectIdentifier(window)
        let bucket = buckets[windowID] ?? WindowBucket(window: window)
        bucket.window = window
        bucket.anchors[anchorID] = WeakAnchor(view: anchor)
        buckets[windowID] = bucket
        anchorWindowIDs[anchorID] = windowID
    }

    func unregister(anchor: NSView) {
        pruneStaleState()

        let anchorID = ObjectIdentifier(anchor)
        guard let windowID = anchorWindowIDs.removeValue(forKey: anchorID) else {
            return
        }

        removeAnchor(anchorID, fromWindowID: windowID)
    }

    func recover(in window: NSWindow?) {
        guard let window else { return }

        performImmediateRecovery(on: registeredAnchors(in: window))
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.performImmediateRecovery(on: self.registeredAnchors(in: window))
        }
    }

    func recover(anchor: NSView?) {
        guard let anchor else { return }

        invalidateAnchor(anchor)
        DispatchQueue.main.async { [weak self, weak anchor] in
            guard let self else { return }
            self.invalidateAnchor(anchor)
        }
    }

    func registeredAnchors(in window: NSWindow) -> [NSView] {
        pruneStaleState()

        let windowID = ObjectIdentifier(window)
        guard let bucket = buckets[windowID] else { return [] }

        bucket.window = window
        let anchors = bucket.anchors.values.compactMap(\.view)
        if anchors.isEmpty {
            buckets.removeValue(forKey: windowID)
        }
        return anchors
    }

    private func performImmediateRecovery(on anchors: [NSView]) {
        guard !anchors.isEmpty else { return }
        anchors.forEach { anchor in
            invalidateAnchor(anchor)
            anchor.needsDisplay = true
        }
    }

    private func removeAnchor(_ anchorID: ObjectIdentifier, fromWindowID windowID: ObjectIdentifier) {
        guard let bucket = buckets[windowID] else { return }

        bucket.anchors.removeValue(forKey: anchorID)
        if bucket.anchors.isEmpty {
            buckets.removeValue(forKey: windowID)
        }
    }

    private func pruneStaleState() {
        for (windowID, bucket) in buckets {
            guard bucket.window != nil else {
                buckets.removeValue(forKey: windowID)
                continue
            }

            bucket.anchors = bucket.anchors.filter { $0.value.view != nil }
            if bucket.anchors.isEmpty {
                buckets.removeValue(forKey: windowID)
            }
        }

        anchorWindowIDs = anchorWindowIDs.filter { anchorID, windowID in
            guard let bucket = buckets[windowID] else { return false }
            return bucket.anchors[anchorID]?.view != nil
        }
    }
}

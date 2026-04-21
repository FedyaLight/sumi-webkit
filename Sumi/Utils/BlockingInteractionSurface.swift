import AppKit
import SwiftUI

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

final class BlockingInteractionSurfaceContainer<Content: View>: NSView, SidebarTransientInteractionDisarmable {
    private let hostingView: NSHostingView<Content>
    var onBackgroundClick: (() -> Void)?
    private(set) var isInteractive: Bool

    init(
        rootView: Content,
        onBackgroundClick: (() -> Void)? = nil,
        isInteractive: Bool = true
    ) {
        self.hostingView = NSHostingView(rootView: rootView)
        self.onBackgroundClick = onBackgroundClick
        self.isInteractive = isInteractive
        super.init(frame: .zero)
        commonInit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        isInteractive
    }

    override var intrinsicContentSize: NSSize {
        hostingView.fittingSize
    }

    func update(
        rootView: Content,
        onBackgroundClick: (() -> Void)?,
        isInteractive: Bool
    ) {
        hostingView.rootView = rootView
        self.onBackgroundClick = onBackgroundClick
        setTransientInteractionEnabled(isInteractive)
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isInteractive, bounds.contains(point) else { return nil }

        let pointInHostedContent = convert(point, to: hostingView)
        if let target = hostingView.hitTest(pointInHostedContent) {
            return target
        }

        // Without a background handler, returning `self` would swallow mouse downs in empty
        // `NSHostingView` regions (e.g. after NSMenu / NSPopover) while SwiftUI hover can still update.
        if onBackgroundClick != nil {
            return self
        }

        return nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isInteractive else { return }
        addCursorRect(bounds, cursor: .arrow)
    }

    override func mouseDown(with event: NSEvent) {
        guard isInteractive else { return }
        if let onBackgroundClick {
            onBackgroundClick()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isInteractive else { return }
        if let onBackgroundClick {
            onBackgroundClick()
        } else {
            super.rightMouseDown(with: event)
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        guard isInteractive else { return }
        if let onBackgroundClick {
            onBackgroundClick()
        } else {
            super.otherMouseDown(with: event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard isInteractive else { return }
        NSCursor.arrow.set()
    }

    override func mouseEntered(with event: NSEvent) {
        guard isInteractive else { return }
        NSCursor.arrow.set()
    }

    override func scrollWheel(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDragged(with event: NSEvent) {}
    override func otherMouseDragged(with event: NSEvent) {}

    func setTransientInteractionEnabled(_ isEnabled: Bool) {
        if !isEnabled {
            onBackgroundClick = nil
        }

        guard isInteractive != isEnabled else {
            window?.invalidateCursorRects(for: self)
            return
        }

        isInteractive = isEnabled
        needsLayout = true
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }
}

struct BlockingInteractionSurface<Content: View>: NSViewRepresentable {
    private let content: Content
    var onBackgroundClick: (() -> Void)? = nil
    var isInteractive: Bool = true
    var handle: SidebarTransientInteractionHandle? = nil

    init(
        isInteractive: Bool = true,
        handle: SidebarTransientInteractionHandle? = nil,
        onBackgroundClick: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.isInteractive = isInteractive
        self.handle = handle
        self.onBackgroundClick = onBackgroundClick
        self.content = content()
    }

    func makeNSView(context: Context) -> NSView {
        let view = BlockingInteractionSurfaceContainer(
            rootView: content,
            onBackgroundClick: onBackgroundClick,
            isInteractive: isInteractive
        )
        handle?.attach(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let container = nsView as? BlockingInteractionSurfaceContainer<Content> else { return }
        container.update(
            rootView: content,
            onBackgroundClick: onBackgroundClick,
            isInteractive: isInteractive
        )
        handle?.attach(container)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        guard let container = nsView as? BlockingInteractionSurfaceContainer<Content> else { return }
        container.setTransientInteractionEnabled(false)
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

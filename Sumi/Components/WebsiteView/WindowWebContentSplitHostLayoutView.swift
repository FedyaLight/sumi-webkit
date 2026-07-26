import AppKit
import SumiDomain
import WebKit

@MainActor
private func hasVisibleHostedWebView(in root: NSView) -> Bool {
    for subview in root.subviews {
        guard !subview.isHidden else { continue }
        if subview is SumiWebViewContainerView || subview is WKWebView {
            return true
        }
        if hasVisibleHostedWebView(in: subview) {
            return true
        }
    }
    return false
}

// MARK: - Split Host Layout View

final class WindowWebContentSplitHostLayoutView: NSView, WindowWebContentVisualHandoffCoverContainer {
    enum PaneLayout: Equatable {
        case single
        case split(WindowSplitPresentation)
    }

    let singlePaneView = PaneContainerView()
    private let surfaceShadowView = BrowserContentViewportShadowView(frame: .zero)
    private let surfaceClipView: BrowserContentViewportClipView
    private let splitRootView = SplitRootView()
    private let visualHandoffOverlayView = VisualHandoffOverlayView()
    private var splitDropCaptureView: SplitDropCaptureView?
    private var paneLayout: PaneLayout = .single
    private var surfaceStyle: BrowserContentSurfaceStyle
    private let splitLayout: SplitLayoutService
    private let splitDrops: SplitDropService
    private let splitDropTargets: SplitDropTargetService
    private let splitPreviews: SplitPreviewSession
    private let sidebarDragState: SidebarDragState
    private weak var windowState: BrowserWindowState?
    private let resolveDragTab: (SumiDragItem) -> Tab?
    private let windowID: UUID

    var hasHostedSplitWebViews: Bool {
        splitRootView.hasHostedWebViews
    }

    init(
        splitLayout: SplitLayoutService,
        splitDrops: SplitDropService,
        splitDropTargets: SplitDropTargetService,
        splitPreviews: SplitPreviewSession,
        sidebarDragState: SidebarDragState,
        windowState: BrowserWindowState,
        resolveDragTab: @escaping (SumiDragItem) -> Tab?,
        surfaceStyle: BrowserContentSurfaceStyle
    ) {
        self.surfaceStyle = surfaceStyle
        self.surfaceClipView = BrowserContentViewportClipView(style: surfaceStyle)
        self.splitLayout = splitLayout
        self.splitDrops = splitDrops
        self.splitDropTargets = splitDropTargets
        self.splitPreviews = splitPreviews
        self.sidebarDragState = sidebarDragState
        self.windowState = windowState
        self.resolveDragTab = resolveDragTab
        self.windowID = windowState.id
        super.init(frame: .zero)

        singlePaneView.identifier = CompositorPaneDestination.single.viewIdentifier
        surfaceShadowView.isHidden = true
        addSubview(surfaceShadowView)
        addSubview(surfaceClipView)
        surfaceClipView.addSubview(singlePaneView)
        surfaceClipView.addSubview(splitRootView)
        visualHandoffOverlayView.isHidden = true
        surfaceClipView.addSubview(visualHandoffOverlayView)
        applyPanePresentation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layoutSurface()
        let contentBounds = surfaceClipView.bounds
        switch paneLayout {
        case .single:
            singlePaneView.frame = contentBounds
            splitRootView.frame = .zero
        case .split:
            singlePaneView.frame = .zero
            splitRootView.frame = contentBounds
        }
        visualHandoffOverlayView.frame = contentBounds
        if let splitDropCaptureView,
           splitDropCaptureView.superview === surfaceClipView {
            splitDropCaptureView.frame = contentBounds
        }
    }

    func setPaneLayout(_ layout: PaneLayout) {
        guard paneLayout != layout else { return }
        paneLayout = layout
        applyPanePresentation()
        needsLayout = true
    }

    func setSurfaceStyle(_ style: BrowserContentSurfaceStyle) {
        guard surfaceStyle != style else { return }
        surfaceStyle = style
        surfaceClipView.apply(style: style)
        layoutSurface()
    }

    func contentVisibilityDidChange() {
        updateSurfaceShadowVisibility()
    }

    func setSplitDropCaptureActive(
        _ isActive: Bool
    ) {
        if isActive {
            guard let splitDropCaptureView = activeSplitDropCaptureView()
            else { return }
            if splitDropCaptureView.superview !== surfaceClipView {
                surfaceClipView.addSubview(splitDropCaptureView, positioned: .above, relativeTo: nil)
            }
            splitDropCaptureView.frame = surfaceClipView.bounds
        } else if let splitDropCaptureView {
            splitDropCaptureView.cancelActiveDragPreview()
            if splitDropCaptureView.superview === surfaceClipView {
                splitDropCaptureView.removeFromSuperview()
            }
            self.splitDropCaptureView = nil
        }
    }

    func configureSplitControls(
        in paneView: PaneContainerView,
        tab: Tab,
        windowState: BrowserWindowState
    ) {
        paneView.configureSplitControls(
            tab: tab,
            splitLayout: splitLayout,
            windowState: windowState,
            sidebarDragState: sidebarDragState
        )
    }

    func paneView(for tabId: UUID) -> PaneContainerView? {
        splitRootView.paneView(for: tabId)
    }

    func clearSplitTree() {
        splitRootView.clear()
    }

    func placeVisualHandoffCover(
        _ host: SumiWebViewContainerView,
        frameInContainer: NSRect
    ) {
        host.prepareForSuperviewTransferPreservingDisplayedContent()
        visualHandoffOverlayView.addSubview(host)
        host.frame = frameInContainer
        host.autoresizingMask = []
        host.isHidden = false
        visualHandoffOverlayView.isHidden = false
        updateSurfaceShadowVisibility()
    }

    func removeVisualHandoffCover(_ host: SumiWebViewContainerView) {
        if host.superview === visualHandoffOverlayView {
            host.removeFromSuperview()
        }
        visualHandoffOverlayView.isHidden = visualHandoffOverlayView.subviews.isEmpty
        updateSurfaceShadowVisibility()
    }

    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let target = super.hitTest(point)
        return target === self ? nil : target
    }

    override func resetCursorRects() {}

    private func applyPanePresentation() {
        switch paneLayout {
        case .single:
            singlePaneView.isHidden = false
            splitRootView.isHidden = true

        case .split(let presentation):
            singlePaneView.isHidden = true
            splitRootView.isHidden = false
            splitRootView.configure(
                presentation: presentation,
                onResize: { [weak self] path, sizes in
                    guard let self else { return }
                    self.splitLayout.updateWeights(
                        expectedGroup: presentation.group,
                        path: path,
                        weights: sizes,
                        in: self.windowID
                    )
                }
            )
        }
        updateSurfaceShadowVisibility()
    }

    private func layoutSurface() {
        let outset = BrowserContentViewportShadowView.shadowOutset
        surfaceShadowView.frame = bounds.insetBy(dx: -outset, dy: -outset)
        surfaceShadowView.apply(
            viewportRect: NSRect(
                x: outset,
                y: outset,
                width: bounds.width,
                height: bounds.height
            ),
            cornerRadii: surfaceStyle.geometry.contentCornerRadii
        )
        surfaceClipView.frame = bounds
    }

    private func updateSurfaceShadowVisibility() {
        surfaceShadowView.isHidden = !hasVisibleHostedWebView(in: surfaceClipView)
    }

    private func activeSplitDropCaptureView() -> SplitDropCaptureView? {
        if let splitDropCaptureView {
            return splitDropCaptureView
        }
        guard let windowState else { return nil }
        let view = SplitDropCaptureView(
            frame: .zero,
            splitDrops: splitDrops,
            splitDropTargets: splitDropTargets,
            splitPreviews: splitPreviews,
            sidebarDragState: sidebarDragState,
            windowState: windowState,
            resolveDragTab: resolveDragTab
        )
        splitDropCaptureView = view
        return view
    }
}

private final class VisualHandoffOverlayView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class SplitRootView: NSView {
    private var paneViewsByTabId: [UUID: PaneContainerView] = [:]
    private var rootView: NSView?
    private var currentPresentation: WindowSplitPresentation?
    private var onResize: (([Int], [Double]) -> Void)?
    private var layoutGeneration: UInt = 0

    var hasHostedWebViews: Bool {
        rootView.map { hasVisibleHostedWebView(in: $0) } ?? false
    }

    override var acceptsFirstResponder: Bool { false }

    func configure(
        presentation: WindowSplitPresentation,
        onResize: @escaping ([Int], [Double]) -> Void
    ) {
        self.onResize = onResize
        if let currentPresentation,
           currentPresentation.group.layoutTree.hasSameStructure(
               as: presentation.group.layoutTree
           ),
           currentPresentation.liveTabIDByMemberID
               == presentation.liveTabIDByMemberID {
            self.currentPresentation = presentation
            rootView?.frame = bounds
            applyStoredSizes(
                from: presentation.group.layoutTree,
                to: rootView
            )
            return
        }

        rootView?.removeFromSuperview()
        paneViewsByTabId.removeAll(keepingCapacity: true)
        currentPresentation = presentation
        layoutGeneration &+= 1
        let view = makeView(
            for: presentation.group.layoutTree,
            presentation: presentation,
            path: [],
            generation: layoutGeneration
        )
        rootView = view
        addSubview(view)
        needsLayout = true
    }

    func clear() {
        currentPresentation = nil
        layoutGeneration &+= 1
        paneViewsByTabId.values.forEach { $0.clearSplitControls() }
        rootView?.removeFromSuperview()
        rootView = nil
        paneViewsByTabId.removeAll(keepingCapacity: true)
    }

    func paneView(for tabId: UUID) -> PaneContainerView? {
        paneViewsByTabId[tabId]
    }

    override func layout() {
        super.layout()
        rootView?.frame = bounds
    }

    private func makeView(
        for tree: SumiDomain.SplitLayoutTree,
        presentation: WindowSplitPresentation,
        path: [Int],
        generation: UInt
    ) -> NSView {
        switch tree {
        case .leaf(let member, _):
            guard let tabId = presentation.tabID(
                for: member.memberID
            ) else {
                preconditionFailure(
                    "Validated split presentation lost a member mapping"
                )
            }
            let pane = PaneContainerView()
            pane.identifier = NSUserInterfaceItemIdentifier("split-pane-\(tabId.uuidString)")
            paneViewsByTabId[tabId] = pane
            return pane

        case .split(let axis, _, let children):
            let split = NativeSplitTreeView(
                axis: axis,
                path: path,
                sizes: children.map(\.weightInParent)
            )
            split.resizeHandler = { [weak self] resizePath, sizes in
                guard let self, generation == self.layoutGeneration else { return }
                self.onResize?(resizePath, sizes)
            }
            for (index, child) in children.enumerated() {
                split.addSubview(makeView(
                    for: child,
                    presentation: presentation,
                    path: path + [index],
                    generation: generation
                ))
            }
            return split
        }
    }

    private func applyStoredSizes(
        from tree: SumiDomain.SplitLayoutTree,
        to view: NSView?
    ) {
        guard let view else { return }
        switch tree {
        case .leaf:
            return
        case .split(_, _, let children):
            if let splitView = view as? NativeSplitTreeView {
                splitView.updateStoredSizes(children.map(\.weightInParent))
            }
            for (childTree, childView) in zip(children, view.subviews) {
                applyStoredSizes(from: childTree, to: childView)
            }
        }
    }
}

final class PaneContainerView: NSView {
    private var splitControlsView: SplitPaneControlsView?
    private var paneTrackingArea: NSTrackingArea?
    private var isPointerInside = false

    override var acceptsFirstResponder: Bool { false }

    func placeContentHost(_ host: SumiWebViewContainerView) {
        addSubview(host)
        if let splitControlsView {
            addSubview(splitControlsView, positioned: .above, relativeTo: host)
        }
    }

    func configureSplitControls(
        tab: Tab,
        splitLayout: SplitLayoutService,
        windowState: BrowserWindowState,
        sidebarDragState: SidebarDragState
    ) {
        let controls = splitControlsView ?? SplitPaneControlsView(
            frame: NSRect(origin: .zero, size: SplitPaneControlsView.preferredSize)
        )
        splitControlsView = controls
        controls.configure(
            tab: tab,
            splitLayout: splitLayout,
            windowState: windowState,
            sidebarDragState: sidebarDragState
        )
        controls.setSplitDropShieldHandler { [weak self] isActive in
            self?.enclosingSplitHostLayoutView?.setSplitDropCaptureActive(isActive)
        }
        if controls.superview !== self {
            addSubview(controls, positioned: .above, relativeTo: nil)
        }
        controls.setVisible(isPointerInside, animated: false)
        needsLayout = true
    }

    func clearSplitControls() {
        splitControlsView?.removeFromSuperview()
        splitControlsView = nil
        isPointerInside = false
    }

    func removeHostedSubviews(
        keeping keepView: NSView?,
        shouldRemove: (NSView) -> Bool = { _ in true }
    ) {
        for subview in subviews
            where subview !== keepView && subview !== splitControlsView {
            if shouldRemove(subview) {
                subview.removeFromSuperview()
            }
        }
        keepView?.isHidden = false
    }

    override func layout() {
        super.layout()
        layoutSplitControls()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let paneTrackingArea {
            removeTrackingArea(paneTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInActiveApp, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        paneTrackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isPointerInside = true
        splitControlsView?.setVisible(true, animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isPointerInside = false
        splitControlsView?.setVisible(false, animated: true)
    }

    private func layoutSplitControls() {
        guard let controls = splitControlsView else { return }
        let size = controls.intrinsicContentSize
        controls.frame = NSRect(
            x: max(0, (bounds.width - size.width) / 2),
            y: max(0, bounds.height - size.height),
            width: size.width,
            height: size.height
        )
    }

    private var enclosingSplitHostLayoutView: WindowWebContentSplitHostLayoutView? {
        var view = superview
        while let current = view {
            if let container = current as? WindowWebContentSplitHostLayoutView {
                return container
            }
            view = current.superview
        }
        return nil
    }
}

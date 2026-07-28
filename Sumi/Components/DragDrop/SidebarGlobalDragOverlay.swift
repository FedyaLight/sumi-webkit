import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarGlobalDragOverlay: NSViewRepresentable {
    let transactionPort: SidebarDragTransactionPort
    let dragAutoscrollRegistry: SidebarTabListDragAutoscrollRegistry
    @EnvironmentObject private var dragState: SidebarDragState
    @Environment(BrowserWindowState.self) var windowState
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sumiSettings) private var sumiSettings

    func makeNSView(context: Context) -> SidebarDragNSView {
        let view = SidebarDragNSView(
            dragState: dragState,
            dragAutoscrollRegistry: dragAutoscrollRegistry
        )
        view.transactionPort = transactionPort
        view.windowState = windowState
        applyIndicatorAppearance(to: view)
        return view
    }

    func updateNSView(_ nsView: SidebarDragNSView, context: Context) {
        nsView.transactionPort = transactionPort
        nsView.dragState = dragState
        nsView.dragAutoscrollRegistry = dragAutoscrollRegistry
        nsView.windowState = windowState
        applyIndicatorAppearance(to: nsView)
    }

    private func applyIndicatorAppearance(to view: SidebarDragNSView) {
        view.applyIndicatorAccent(
            primaryColorHex: themeContext.gradient.primaryColorHex,
            isDarkChrome: themeContext.chromeColorScheme == .dark
        )
        view.dropIndicatorPresenter.pairingPreviewColor =
            NSColor(
                themeContext.tokens(settings: sumiSettings).fieldBackgroundHover
            )
        view.dropIndicatorPresenter.prefersReducedMotion =
            SumiChromeMotionPolicy.currentMode(
                reduceMotion: reduceMotion,
                energySaverReducesMotion: sumiSettings.shouldReduceChromeMotion
            ) == .reducedMotion
    }
}

class SidebarDragNSView: NSView {
    private struct DragContext {
        let pasteboardChangeCount: Int
        let draggedItem: SumiDragItem?
        let scope: SidebarDragScope?
        let hasDroppedURL: Bool

        var dragOperation: NSDragOperation {
            draggedItem == nil ? .copy : .move
        }

        var canResolveDrop: Bool {
            draggedItem != nil || hasDroppedURL
        }
    }

    /// Everything a drag sample's outcome depends on. While the pointer sits
    /// still and no geometry moved underneath it (periodic dragging updates
    /// fire regardless), re-resolving would reproduce the same resolution —
    /// skip the whole pipeline, like Zen's `animLastScreenPos` early-out.
    private struct DragUpdateSignature: Equatable {
        let location: CGPoint
        let scrollRevision: UInt64
        let structuralRevision: UInt64
        let pasteboardChangeCount: Int
        let deferredTargetRevision: UInt64
    }

    var transactionPort: SidebarDragTransactionPort?
    var windowState: BrowserWindowState?
    var dragState: SidebarDragState
    var dragAutoscrollRegistry: SidebarTabListDragAutoscrollRegistry
    let dropIndicatorPresenter = SidebarDropIndicatorPresenter()
    private var cachedDragContext: DragContext?
    private var lastUpdateSignature: DragUpdateSignature?
    private var lastUpdateAccepted = false
    private var appliedAccentKey: IndicatorAccentKey?

    private struct IndicatorAccentKey: Equatable {
        let primaryColorHex: String
        let isDarkChrome: Bool
    }

    /// Zen's indicator color: the space's primary color mixed 50/50 toward
    /// near-black (light chrome) or near-white (dark chrome). `updateNSView`
    /// fires on every drag-state publish, so the hex-parse/blend only runs
    /// when the theme inputs actually change.
    func applyIndicatorAccent(primaryColorHex: String, isDarkChrome: Bool) {
        let key = IndicatorAccentKey(
            primaryColorHex: primaryColorHex,
            isDarkChrome: isDarkChrome
        )
        guard key != appliedAccentKey else { return }
        appliedAccentKey = key
        let primary = NSColor(Color(hex: primaryColorHex))
        let mixin: NSColor = isDarkChrome ? .white : .black
        dropIndicatorPresenter.accentColor =
            primary.blended(withFraction: 0.5, of: mixin) ?? primary
    }

    init(
        frame frameRect: NSRect = .zero,
        dragState: SidebarDragState,
        dragAutoscrollRegistry: SidebarTabListDragAutoscrollRegistry
    ) {
        self.dragState = dragState
        self.dragAutoscrollRegistry = dragAutoscrollRegistry
        super.init(frame: frameRect)
        wantsLayer = true
        if let layer {
            dropIndicatorPresenter.attach(to: layer)
        }
        registerForDraggedTypes([
            .string,
            .URL,
            .fileURL,
            NSPasteboard.PasteboardType.sumiSidebarDragPayload,
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil // Pass through all normal mouse events
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        cachedDragContext = nil
        lastUpdateSignature = nil
        let context = dragContext(for: sender)

        if let item = context.draggedItem {
            guard context.scope != nil else {
                dragState.clearHoverState()
                return []
            }
            if dragState.isInternalDragSession {
                dragState.activeDragItemId = item.tabId
            } else {
                dragState.beginExternalDragSession(itemId: item.tabId)
            }
        } else if !dragState.isInternalDragSession {
            guard context.hasDroppedURL else {
                dragState.resetInteractionState()
                return []
            }
            dragState.beginExternalDragSession(itemId: nil)
        }
        return updateDragSlot(sender: sender)
            ? context.dragOperation
            : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let context = dragContext(for: sender)
        guard context.canResolveDrop else {
            return []
        }
        dragAutoscrollRegistry.autoscrollIfNeeded(
            sender: sender,
            in: self,
            dragState: dragState
        )
        let signature = DragUpdateSignature(
            location: sender.draggingLocation,
            scrollRevision: dragState.geometry.geometrySnapshot.scrollRevision,
            structuralRevision: dragState.geometry.geometrySnapshot.structuralRevision,
            pasteboardChangeCount: sender.draggingPasteboard.changeCount,
            deferredTargetRevision: dragState.deferredDropTargetRevision
        )
        if signature == lastUpdateSignature {
            return lastUpdateAccepted ? context.dragOperation : []
        }
        let accepted = updateDragSlot(sender: sender)
        lastUpdateSignature = signature
        lastUpdateAccepted = accepted
        return accepted ? context.dragOperation : []
    }

    override func wantsPeriodicDraggingUpdates() -> Bool {
        true
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropIndicatorPresenter.hide()
        lastUpdateSignature = nil
        if dragState.isInternalDragSession {
            dragState.clearHoverState()
        } else {
            dragState.resetInteractionState()
        }
        cachedDragContext = nil
        dragAutoscrollRegistry.stop()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropIndicatorPresenter.hide()
        lastUpdateSignature = nil
        defer {
            runWithoutDropAnimations {
                dragState.resetInteractionState()
            }
            cachedDragContext = nil
            dragAutoscrollRegistry.stop()
        }

        guard let transactionPort,
              let resolution = dragState.beginDropCommit(
                refreshingIfEmpty: { [self] in
                    resolveDropResolution(sender: sender)
                }
              ) else { return false }
        return runWithoutDropAnimations {
            transactionPort.commit(
                pasteboard: sender.draggingPasteboard,
                resolution: resolution,
                windowState: windowState
            )
        }
    }

    private func runWithoutDropAnimations<T>(_ operation: () -> T) -> T {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        return withTransaction(transaction, operation)
    }

    private func updateDragSlot(sender: NSDraggingInfo) -> Bool {
        guard let resolution = resolveDropResolution(sender: sender) else {
            presentDropIndicator(for: nil)
            return false
        }
        presentDropIndicator(for: resolution)
        return resolution.slot != .empty
    }

    /// Positions the drop-indicator line for the resolved slot. The geometry
    /// rect arrives in scroll-normalized SwiftUI-global space; strip the
    /// autoscroll delta, flip into window coordinates, then into view space.
    private func presentDropIndicator(for resolution: SidebarDropResolution?) {
        guard let resolution, let window else {
            dropIndicatorPresenter.hide()
            return
        }

        if let target = resolution.splitPairingTarget {
            if target.presentation == .existingGroupRow {
                // Existing groups render the containment cue behind their
                // content, exactly like folder rows.
                dropIndicatorPresenter.hide()
                return
            }
            let scrollOffset =
                -dragState.geometry.geometrySnapshot.cumulativeScrollDeltaY
            let presentedRect = target.rect.offsetBy(dx: 0, dy: scrollOffset)
            let windowRect = SidebarDragLocationMapper.windowRect(
                fromSwiftUITopLeftRect: presentedRect,
                in: window
            )
            dropIndicatorPresenter.updatePairingTarget(
                rect: convert(windowRect, from: nil),
                target: target
            )
            return
        }

        guard var lineRect = resolution.indicatorLineRect else {
            dropIndicatorPresenter.hide()
            return
        }
        lineRect.origin.y -= dragState.geometry.geometrySnapshot.cumulativeScrollDeltaY
        let windowRect = SidebarDragLocationMapper.windowRect(
            fromSwiftUITopLeftRect: lineRect,
            in: window
        )
        dropIndicatorPresenter.update(
            lineRect: convert(windowRect, from: nil),
            slotKey: resolution.slot
        )
    }

    @discardableResult
    private func resolveDropResolution(
        sender: NSDraggingInfo
    ) -> SidebarDropResolution? {
        guard let swiftUILocation = resolvedSwiftUILocation(for: sender) else { return nil }
        let previewLocation = resolvedSwiftUIPreviewLocation(for: sender)
        let context = dragContext(for: sender)
        return SidebarDropCoordinator.resolveDropResolution(
            pasteboard: sender.draggingPasteboard,
            swiftUILocation: swiftUILocation,
            previewLocation: previewLocation,
            dragState: dragState,
            windowState: windowState,
            draggedItem: context.draggedItem,
            scope: context.scope
        )
    }

    private func dragContext(for sender: NSDraggingInfo) -> DragContext {
        let pasteboard = sender.draggingPasteboard
        if let cachedDragContext,
           cachedDragContext.pasteboardChangeCount == pasteboard.changeCount {
            return cachedDragContext
        }

        let item = SidebarDropCoordinator.draggedItem(from: pasteboard)
        let scope = item.flatMap {
            SidebarDropCoordinator.validatedScope(
                for: $0,
                pasteboard: pasteboard,
                windowState: windowState
            )
        }
        let context = DragContext(
            pasteboardChangeCount: pasteboard.changeCount,
            draggedItem: item,
            scope: scope,
            hasDroppedURL: item == nil && pasteboard.sumiDroppedURL != nil
        )
        cachedDragContext = context
        return context
    }

    private func resolvedSwiftUILocation(for sender: NSDraggingInfo) -> CGPoint? {
        SidebarDragLocationMapper.swiftUIGlobalPoint(
            fromWindowPoint: sender.draggingLocation,
            in: self
        )
    }

    private func resolvedSwiftUIPreviewLocation(for sender: NSDraggingInfo) -> CGPoint? {
        SidebarDragLocationMapper.swiftUIPreviewPoint(
            fromWindowPoint: sender.draggingLocation,
            in: self
        )
    }
}

enum SidebarTabListAutoscrollDirection: Equatable {
    case up
    case down
}

enum SidebarTabListAutoscrollPolicy {
    static let edgeBandHeight: CGFloat = 32
    static let minimumStep: CGFloat = 8
    static let maximumStep: CGFloat = 28

    static func direction(
        for location: CGPoint,
        in viewport: CGRect,
        edgeBandHeight: CGFloat = Self.edgeBandHeight
    ) -> SidebarTabListAutoscrollDirection? {
        guard viewport.contains(location), edgeBandHeight > 0 else { return nil }

        let topDistance = viewport.maxY - location.y
        let bottomDistance = location.y - viewport.minY
        let effectiveBandHeight = min(edgeBandHeight, viewport.height / 2)

        if topDistance <= effectiveBandHeight, topDistance < bottomDistance {
            return .up
        }
        if bottomDistance <= effectiveBandHeight, bottomDistance < topDistance {
            return .down
        }
        return nil
    }

    static func step(
        for location: CGPoint,
        in viewport: CGRect,
        direction: SidebarTabListAutoscrollDirection,
        edgeBandHeight: CGFloat = Self.edgeBandHeight
    ) -> CGFloat {
        let effectiveBandHeight = max(1, min(edgeBandHeight, viewport.height / 2))
        let distance: CGFloat
        switch direction {
        case .up:
            distance = max(0, viewport.maxY - location.y)
        case .down:
            distance = max(0, location.y - viewport.minY)
        }

        let proximity = max(0, min(1, 1 - (distance / effectiveBandHeight)))
        return minimumStep + ((maximumStep - minimumStep) * proximity)
    }
}

@MainActor
final class SidebarTabListDragAutoscrollRegistry {
    private static let autoscrollTimerInterval: TimeInterval = 1.0 / 60.0

    private final class WeakScrollView {
        weak var scrollView: NSScrollView?
        var lastReportedBoundaries: (hasContentAbove: Bool, hasContentBelow: Bool)?

        init(_ scrollView: NSScrollView) {
            self.scrollView = scrollView
        }
    }

    private var scrollViewsByIdentifier: [ObjectIdentifier: WeakScrollView] = [:]
    private var autoscrollTimer: Timer?
    private weak var activeDragWindow: NSWindow?
    private weak var activeDragState: SidebarDragState?

    init() {}

    func register(_ scrollView: NSScrollView) {
        cleanupReleasedScrollViews()
        scrollViewsByIdentifier[ObjectIdentifier(scrollView)] = WeakScrollView(scrollView)
    }

    func unregister(_ scrollView: NSScrollView) {
        scrollViewsByIdentifier[ObjectIdentifier(scrollView)] = nil
    }

    func updateBoundaries(
        for scrollView: NSScrollView,
        hasContentAbove: Bool,
        hasContentBelow: Bool
    ) {
        cleanupReleasedScrollViews()
        scrollViewsByIdentifier[ObjectIdentifier(scrollView)]?.lastReportedBoundaries = (
            hasContentAbove: hasContentAbove,
            hasContentBelow: hasContentBelow
        )
    }

    func stop() {
        stopAutoscrollTimer()
        activeDragWindow = nil
        activeDragState = nil
    }

    func registeredScrollView(
        containingWindowPoint locationInWindow: CGPoint,
        in window: NSWindow?
    ) -> NSScrollView? {
        cleanupReleasedScrollViews()

        var selectedScrollView: NSScrollView?
        var selectedViewportArea = CGFloat.greatestFiniteMagnitude

        for weakScrollView in scrollViewsByIdentifier.values {
            guard let scrollView = weakScrollView.scrollView,
                  scrollView.window === window else { continue }

            let viewport = scrollView.contentView.convert(scrollView.contentView.bounds, to: nil)
            guard viewport.contains(locationInWindow) else { continue }

            let viewportArea = viewport.width * viewport.height
            guard viewportArea < selectedViewportArea else { continue }

            selectedScrollView = scrollView
            selectedViewportArea = viewportArea
        }

        return selectedScrollView
    }

    @discardableResult
    func autoscrollIfNeeded(
        sender: NSDraggingInfo,
        in destinationView: NSView,
        dragState: SidebarDragState
    ) -> Bool {
        cleanupReleasedScrollViews()

        let locationInWindow = sender.draggingLocation
        let window = destinationView.window
        activeDragWindow = window
        activeDragState = dragState

        let hasAutoscrolled = performAutoscrollStep(
            locationInWindow: locationInWindow,
            window: window,
            dragState: dragState
        )

        if hasAutoscrolled {
            startAutoscrollTimer(window: window)
        } else {
            stopAutoscrollTimer()
        }

        return hasAutoscrolled
    }

    private func startAutoscrollTimer(window: NSWindow?) {
        guard window != nil else { return }
        guard autoscrollTimer == nil else { return }

        let timer = Timer(timeInterval: Self.autoscrollTimerInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.performAutoscrollTimerStep()
            }
        }
        autoscrollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func performAutoscrollTimerStep() {
        guard let window = activeDragWindow,
              let dragState = activeDragState else {
            stopAutoscrollTimer()
            return
        }
        let mouseLocation = window.mouseLocationOutsideOfEventStream
        let scrolled = performAutoscrollStep(
            locationInWindow: mouseLocation,
            window: window,
            dragState: dragState
        )
        if !scrolled {
            stopAutoscrollTimer()
        }
    }

    private func stopAutoscrollTimer() {
        autoscrollTimer?.invalidate()
        autoscrollTimer = nil
    }

    private func performAutoscrollStep(
        locationInWindow: CGPoint,
        window: NSWindow?,
        dragState: SidebarDragState
    ) -> Bool {
        var selectedCandidate: (
            scrollView: NSScrollView,
            viewport: CGRect,
            direction: SidebarTabListAutoscrollDirection
        )?
        var selectedViewportArea = CGFloat.greatestFiniteMagnitude

        for weakScrollView in scrollViewsByIdentifier.values {
            guard let scrollView = weakScrollView.scrollView,
                  scrollView.window === window else { continue }

            let viewport = scrollView.contentView.convert(scrollView.contentView.bounds, to: nil)
            guard let direction = SidebarTabListAutoscrollPolicy.direction(
                for: locationInWindow,
                in: viewport
            ) else {
                continue
            }

            let viewportArea = viewport.width * viewport.height
            guard viewportArea < selectedViewportArea else { continue }

            selectedCandidate = (scrollView, viewport, direction)
            selectedViewportArea = viewportArea
        }

        guard let candidate = selectedCandidate else { return false }
        if isPinned(candidate.scrollView, in: candidate.direction) {
            return false
        }
        return autoscroll(
            candidate.scrollView,
            locationInWindow: locationInWindow,
            viewport: candidate.viewport,
            direction: candidate.direction,
            dragState: dragState
        )
    }

    private func autoscroll(
        _ scrollView: NSScrollView,
        locationInWindow: CGPoint,
        viewport: CGRect,
        direction: SidebarTabListAutoscrollDirection,
        dragState: SidebarDragState
    ) -> Bool {
        let contentView = scrollView.contentView
        guard let documentView = scrollView.documentView else { return false }

        if isPinned(scrollView, in: direction) {
            return false
        }

        let step = SidebarTabListAutoscrollPolicy.step(
            for: locationInWindow,
            in: viewport,
            direction: direction
        )
        let visualDelta: CGFloat = {
            switch direction {
            case .up:
                return -step
            case .down:
                return step
            }
        }()
        let signedDelta = documentView.isFlipped ? visualDelta : -visualDelta
        let currentOrigin = contentView.bounds.origin
        let proposedOrigin = CGPoint(
            x: currentOrigin.x,
            y: currentOrigin.y + signedDelta
        )
        let constrainedOrigin = constrainedScrollOrigin(
            proposedOrigin,
            in: contentView
        )

        let actualDeltaY = constrainedOrigin.y - currentOrigin.y
        guard abs(actualDeltaY) > 0.5 else {
            return false
        }

        contentView.scroll(to: constrainedOrigin)
        scrollView.reflectScrolledClipView(contentView)
        scrollView.flashScrollers()

        let geometryDelta = documentView.isFlipped ? actualDeltaY : -actualDeltaY
        dragState.adjustGeometryStoreScrollDelta(deltaY: geometryDelta)
        return true
    }

    private func isPinned(
        _ scrollView: NSScrollView,
        in direction: SidebarTabListAutoscrollDirection,
        tolerance: CGFloat = 1.0
    ) -> Bool {
        if let boundaries = scrollViewsByIdentifier[ObjectIdentifier(scrollView)]?.lastReportedBoundaries {
            switch direction {
            case .up:
                if !boundaries.hasContentAbove { return true }
            case .down:
                if !boundaries.hasContentBelow { return true }
            }
        }

        let contentView = scrollView.contentView
        guard let documentView = scrollView.documentView else { return true }

        let documentRect = contentView.documentRect
        let visibleHeight = contentView.bounds.height
        let minimumOriginY = documentRect.minY
        let maximumOriginY = max(documentRect.minY, documentRect.maxY - visibleHeight)
        guard maximumOriginY - minimumOriginY > tolerance else { return true }

        let originY = contentView.bounds.origin.y

        switch direction {
        case .up:
            return documentView.isFlipped
                ? originY <= minimumOriginY + tolerance
                : originY >= maximumOriginY - tolerance
        case .down:
            return documentView.isFlipped
                ? originY >= maximumOriginY - tolerance
                : originY <= minimumOriginY + tolerance
        }
    }

    private func constrainedScrollOrigin(
        _ origin: CGPoint,
        in contentView: NSClipView
    ) -> CGPoint {
        let documentRect = contentView.documentRect
        let visibleSize = contentView.bounds.size
        let maxX = max(documentRect.minX, documentRect.maxX - visibleSize.width)
        let maxY = max(documentRect.minY, documentRect.maxY - visibleSize.height)

        return CGPoint(
            x: min(max(origin.x, documentRect.minX), maxX),
            y: min(max(origin.y, documentRect.minY), maxY)
        )
    }

    private func cleanupReleasedScrollViews() {
        scrollViewsByIdentifier = scrollViewsByIdentifier.filter { _, weakScrollView in
            weakScrollView.scrollView != nil
        }
    }
}

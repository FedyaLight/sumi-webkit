import AppKit
import QuartzCore
import SwiftUI

final class CollapsedSidebarPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class CollapsedSidebarDragPreviewOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum CollapsedSidebarPanelFrameResolver {
    static func panelFrame(
        parentContentScreenFrame: NSRect,
        sidebarWidth: CGFloat,
        sidebarPosition: SidebarPosition
    ) -> NSRect {
        let width = min(max(sidebarWidth, 0), parentContentScreenFrame.width)
        let originX = sidebarPosition.shellEdge.isLeft
            ? parentContentScreenFrame.minX
            : parentContentScreenFrame.maxX - width

        return NSRect(
            x: originX,
            y: parentContentScreenFrame.minY,
            width: width,
            height: parentContentScreenFrame.height
        )
    }

    static func hiddenContentOffset(
        for sidebarWidth: CGFloat,
        sidebarPosition: SidebarPosition
    ) -> CGFloat {
        sidebarPosition.shellEdge.isLeft ? -sidebarWidth : sidebarWidth
    }

    @MainActor
    static func parentContentScreenFrame(in parentWindow: NSWindow) -> NSRect? {
        guard let contentView = parentWindow.contentView else { return nil }
        let contentWindowFrame = contentView.convert(contentView.bounds, to: nil)
        return parentWindow.convertToScreen(contentWindowFrame)
    }

    @MainActor
    static func panelFrame(
        in parentWindow: NSWindow,
        sidebarWidth: CGFloat,
        sidebarPosition: SidebarPosition
    ) -> NSRect? {
        guard let contentScreenFrame = parentContentScreenFrame(in: parentWindow) else {
            return nil
        }
        return panelFrame(
            parentContentScreenFrame: contentScreenFrame,
            sidebarWidth: sidebarWidth,
            sidebarPosition: sidebarPosition
        )
    }
}

enum CollapsedSidebarDragPreviewOverlayFrameResolver {
    @MainActor
    static func overlayFrame(in parentWindow: NSWindow) -> NSRect? {
        CollapsedSidebarPanelFrameResolver.parentContentScreenFrame(in: parentWindow)
    }
}

private enum CollapsedSidebarPanelAnimation {
    static let revealDuration: TimeInterval = 0.25
    static let hideDuration: TimeInterval = 0.15
    static let contentOffsetAnimationKey = "sumi.collapsedSidebarPanel.contentOffset"
    static var hideTimingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)
    }
    static let revealProgress: [CGFloat] = [
        0, 0.002748, 0.010544, 0.022757, 0.038804, 0.058151,
        0.080308, 0.104828, 0.131301, 0.159358, 0.188662,
        0.21891, 0.249828, 0.281172, 0.312724, 0.344288,
        0.375693, 0.40679, 0.437447, 0.467549, 0.497,
        0.525718, 0.553633, 0.580688, 0.60684, 0.632052,
        0.656298, 0.679562, 0.701831, 0.723104, 0.743381,
        0.76267, 0.780983, 0.798335, 0.814744, 0.830233,
        0.844826, 0.858549, 0.87143, 0.883498, 0.894782,
        0.905314, 0.915125, 0.924247, 0.93271, 0.940547,
        0.947787, 0.954463, 0.960603, 0.966239, 0.971397,
        0.976106, 0.980394, 0.984286, 0.987808, 0.990984,
        0.993837, 0.99639, 0.998664, 1.000679, 1.002456,
        1.004011, 1.005363, 1.006528, 1.007522, 1.008359,
        1.009054, 1.009618, 1.010065, 1.010405, 1.010649,
        1.010808, 1.01089, 1.010904, 1.010857, 1.010757,
        1.010611, 1.010425, 1.010205, 1.009955, 1.009681,
        1.009387, 1.009077, 1.008754, 1.008422, 1.008083,
        1.00774, 1.007396, 1.007052, 1.00671, 1.006372,
        1.00604, 1.005713, 1.005394, 1.005083, 1.004782,
        1.004489, 1.004207, 1.003935, 1.003674, 1
    ]
    static let revealKeyTimes: [NSNumber] = (0...100).map {
        NSNumber(value: Double($0) / 100.0)
    }
}

private enum CollapsedSidebarPanelFrameSync {
    // Child NSPanel frame notifications can trail live resize/move event tracking.
    static let interval: TimeInterval = 1.0 / 120.0
    static let tolerance: TimeInterval = 1.0 / 240.0
    static let animationCompletionGrace: TimeInterval = 0.05
    static let liveResizeBurstDuration: TimeInterval = 0.25
    static let revealAnimationReason = "reveal-animation"
    static let hideAnimationReason = "hide-animation"
    static let liveResizeReason = "live-resize"
}

@MainActor
final class CollapsedSidebarPanelController {
    private var panelWindow: CollapsedSidebarPanelWindow?
    private var dragPreviewOverlayWindow: CollapsedSidebarDragPreviewOverlayWindow?
    private let sidebarController = SidebarColumnViewController(usesCollapsedPanelRoot: true)
    private let dragPreviewOverlayController = NSHostingController(rootView: AnyView(EmptyView()))
    private weak var attachedParentWindow: NSWindow?
    private weak var dragPreviewOverlayParentWindow: NSWindow?
    private weak var observedParentWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var currentSidebarWidth: CGFloat = BrowserWindowState.sidebarDefaultWidth
    private var currentSidebarPosition: SidebarPosition = .left
    private var isPanelRevealed = false
    private var panelPresentationGeneration: UInt64 = 0
    private var frameSyncTimer: Timer?
    private var frameSyncBurstDeadline: TimeInterval?
    private var frameSyncBurstReason: String?
    private var isLiveResizeFrameSyncActive = false

    private var isPanelAttached: Bool {
        guard let panelWindow, let attachedParentWindow else { return false }
        return attachedParentWindow.childWindows?.contains(panelWindow) == true
    }

    func update<Content: View>(
        parentWindow: NSWindow?,
        root: Content,
        width: CGFloat,
        presentationContext: SidebarPresentationContext,
        contextMenuController: SidebarContextMenuController?,
        isHostRequested: Bool,
        onPointerDown: (() -> Void)? = nil
    ) {
        currentSidebarWidth = width
        currentSidebarPosition = presentationContext.sidebarPosition

        guard isHostRequested,
              presentationContext.isCollapsedOverlay,
              let parentWindow
        else {
            orderOutAndDetach(teardownHostedContent: true, destroyWindow: true)
            return
        }

        let panel = ensurePanelWindow()
        bindParentWindow(parentWindow)
        configure(panel, for: parentWindow)

        if panel.contentViewController !== sidebarController {
            panel.contentViewController = sidebarController
        }

        sidebarController.updateHostedSidebar(
            root: root,
            width: width,
            contextMenuController: contextMenuController,
            capturesPanelBackgroundPointerEvents: presentationContext.capturesPanelBackgroundPointerEvents,
            isCollapsedPanelHitTestingEnabled: presentationContext.mode == .collapsedVisible,
            onPointerDown: onPointerDown
        )

        if presentationContext.mode == .collapsedVisible {
            reveal(panel, in: parentWindow)
        } else {
            hideAndDetach(panel)
        }
    }

    func updateDragPreviewOverlay<Content: View>(
        parentWindow: NSWindow?,
        root: Content,
        isPresented: Bool
    ) {
        guard isPresented,
              let parentWindow
        else {
            orderOutAndDetachDragPreviewOverlay(destroyWindow: true)
            return
        }

        let overlay = ensureDragPreviewOverlayWindow()
        configureDragPreviewOverlay(overlay, for: parentWindow)
        dragPreviewOverlayController.rootView = AnyView(root)
        if overlay.contentViewController !== dragPreviewOverlayController {
            overlay.contentViewController = dragPreviewOverlayController
        }
        syncDragPreviewOverlayFrame()
        attachAndShowDragPreviewOverlay(overlay, to: parentWindow)
    }

    func syncFrame() {
        if let panelWindow,
           let visibleFrame = currentVisiblePanelFrame()
        {
            setFrameIfNeeded(panelWindow, to: visibleFrame, display: panelWindow.isVisible)
            syncSidebarContentOffsetForCurrentFrameIfNeeded()
        }

        syncDragPreviewOverlayFrame()
    }

    func teardown() {
        orderOutAndDetachDragPreviewOverlay(destroyWindow: true)
        orderOutAndDetach(teardownHostedContent: true, destroyWindow: true)
        unbindParentWindow()
    }

    deinit {
        MainActor.assumeIsolated {
            teardown()
        }
    }

    private func ensurePanelWindow() -> CollapsedSidebarPanelWindow {
        if let panelWindow {
            return panelWindow
        }

        let panel = CollapsedSidebarPanelWindow(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.worksWhenModal = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .fullScreenAuxiliary,
            .moveToActiveSpace,
            .ignoresCycle,
        ]
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.masksToBounds = true
        panelWindow = panel
        return panel
    }

    private func ensureDragPreviewOverlayWindow() -> CollapsedSidebarDragPreviewOverlayWindow {
        if let dragPreviewOverlayWindow {
            return dragPreviewOverlayWindow
        }

        let overlay = CollapsedSidebarDragPreviewOverlayWindow(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        overlay.isReleasedWhenClosed = false
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.hidesOnDeactivate = false
        overlay.isFloatingPanel = false
        overlay.becomesKeyOnlyIfNeeded = false
        overlay.worksWhenModal = true
        overlay.animationBehavior = .none
        overlay.collectionBehavior = [
            .fullScreenAuxiliary,
            .moveToActiveSpace,
            .ignoresCycle,
        ]
        overlay.acceptsMouseMovedEvents = false
        overlay.ignoresMouseEvents = true
        overlay.contentView?.wantsLayer = true
        overlay.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        overlay.contentView?.layer?.isOpaque = false
        dragPreviewOverlayWindow = overlay
        return overlay
    }

    private func configure(
        _ panel: CollapsedSidebarPanelWindow,
        for parentWindow: NSWindow
    ) {
        panel.level = parentWindow.level
        panel.appearance = parentWindow.effectiveAppearance
        panel.acceptsMouseMovedEvents = true
        preparePanelContentClipping(panel)
    }

    private func configureDragPreviewOverlay(
        _ overlay: CollapsedSidebarDragPreviewOverlayWindow,
        for parentWindow: NSWindow
    ) {
        overlay.level = parentWindow.level
        overlay.appearance = parentWindow.effectiveAppearance
        overlay.ignoresMouseEvents = true
        overlay.acceptsMouseMovedEvents = false
    }

    private func currentVisiblePanelFrame() -> NSRect? {
        guard let parentWindow = observedParentWindow ?? attachedParentWindow else {
            return nil
        }
        return CollapsedSidebarPanelFrameResolver.panelFrame(
            in: parentWindow,
            sidebarWidth: currentSidebarWidth,
            sidebarPosition: currentSidebarPosition
        )
    }

    private var currentSidebarContentOffset: CGFloat {
        isPanelRevealed ? 0 : hiddenSidebarContentOffset
    }

    private var hiddenSidebarContentOffset: CGFloat {
        CollapsedSidebarPanelFrameResolver.hiddenContentOffset(
            for: currentVisiblePanelFrame()?.width ?? currentSidebarWidth,
            sidebarPosition: currentSidebarPosition
        )
    }

    private var isSidebarContentOffsetAnimationActive: Bool {
        let animatedView = sidebarController.collapsedPanelAnimatedContentView ?? sidebarController.view
        return animatedView.layer?.animation(
            forKey: CollapsedSidebarPanelAnimation.contentOffsetAnimationKey
        ) != nil
    }

    private var hasAttachedFrameSyncSurface: Bool {
        let panelNeedsSync = panelWindow?.isVisible == true
            && attachedParentWindow != nil
        let dragPreviewNeedsSync = dragPreviewOverlayWindow?.isVisible == true
            && dragPreviewOverlayParentWindow != nil
        return panelNeedsSync || dragPreviewNeedsSync
    }

    private func syncSidebarContentOffsetForCurrentFrameIfNeeded() {
        guard !isPanelRevealed,
              !isSidebarContentOffsetAnimationActive
        else { return }

        setSidebarContentOffset(currentSidebarContentOffset, animated: false)
    }

    private func setFrameIfNeeded(_ window: NSWindow, to frame: NSRect, display: Bool) {
        guard !NSEqualRects(window.frame, frame) else { return }
        window.setFrame(frame, display: display)
    }

    private func startFrameSyncBurst(duration: TimeInterval, reason: String) {
        guard hasAttachedFrameSyncSurface else {
            stopFrameSyncTimer()
            return
        }

        guard duration > 0 else {
            syncFrame()
            stopFrameSyncTimer()
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let requestedDeadline = now + duration
        if frameSyncTimer == nil
            || (frameSyncBurstDeadline ?? 0) <= now
            || reason == CollapsedSidebarPanelFrameSync.liveResizeReason
            || frameSyncBurstReason != reason
        {
            frameSyncBurstDeadline = requestedDeadline
            frameSyncBurstReason = reason
        }

        startFrameSyncTimerIfNeeded()
    }

    private func startFrameSyncTimerIfNeeded() {
        guard frameSyncTimer == nil else { return }

        let timer = Timer(
            timeInterval: CollapsedSidebarPanelFrameSync.interval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleFrameSyncTimerFired()
            }
        }
        timer.tolerance = CollapsedSidebarPanelFrameSync.tolerance
        RunLoop.main.add(timer, forMode: .common)
        frameSyncTimer = timer
    }

    private func stopFrameSyncTimer() {
        frameSyncTimer?.invalidate()
        frameSyncTimer = nil
        frameSyncBurstDeadline = nil
        frameSyncBurstReason = nil
    }

    private func stopFrameSyncBurst(reason: String) {
        guard frameSyncBurstReason == reason else { return }
        stopFrameSyncTimer()
    }

    private func stopFrameSyncTimerIfNoSurfaceNeedsSync() {
        guard !hasAttachedFrameSyncSurface else { return }
        stopFrameSyncTimer()
    }

    private func handleFrameSyncTimerFired() {
        guard hasAttachedFrameSyncSurface,
              let deadline = frameSyncBurstDeadline
        else {
            stopFrameSyncTimer()
            return
        }

        syncFrame()

        guard ProcessInfo.processInfo.systemUptime < deadline else {
            stopFrameSyncTimer()
            return
        }
    }

    private func preparePanelContentClipping(_ panel: CollapsedSidebarPanelWindow) {
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.masksToBounds = true
        sidebarController.view.wantsLayer = true
        sidebarController.view.layer?.masksToBounds = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sidebarController.view.layer?.transform = CATransform3DIdentity
        CATransaction.commit()
        sidebarController.collapsedPanelAnimatedContentView?.wantsLayer = true
        sidebarController.collapsedPanelAnimatedContentView?.layer?.masksToBounds = false
    }

    private func reveal(
        _ panel: CollapsedSidebarPanelWindow,
        in parentWindow: NSWindow
    ) {
        panelPresentationGeneration &+= 1

        guard let visibleFrame = CollapsedSidebarPanelFrameResolver.panelFrame(
            in: parentWindow,
            sidebarWidth: currentSidebarWidth,
            sidebarPosition: currentSidebarPosition
        ) else {
            isPanelRevealed = true
            attachAndShow(panel, to: parentWindow)
            return
        }

        let wasAlreadyRevealed = isPanelRevealed
            && panel.isVisible
            && attachedParentWindow === parentWindow

        preparePanelContentClipping(panel)
        panel.setFrame(visibleFrame, display: false)
        let initialContentOffset = hiddenSidebarContentOffset
        if !panel.isVisible || attachedParentWindow !== parentWindow {
            setSidebarContentOffset(initialContentOffset, animated: false)
        }

        isPanelRevealed = true
        panel.ignoresMouseEvents = false
        attachAndShow(panel, to: parentWindow)

        let didScheduleRevealAnimation = setSidebarContentOffset(
            0,
            animated: !wasAlreadyRevealed,
            startingOffset: wasAlreadyRevealed ? nil : initialContentOffset
        )
        if didScheduleRevealAnimation {
            startFrameSyncBurst(
                duration: CollapsedSidebarPanelAnimation.revealDuration
                    + CollapsedSidebarPanelFrameSync.animationCompletionGrace,
                reason: CollapsedSidebarPanelFrameSync.revealAnimationReason
            )
        }
    }

    private func hideAndDetach(_ panel: CollapsedSidebarPanelWindow) {
        if !isPanelRevealed,
           panel.isVisible,
           attachedParentWindow != nil,
           isSidebarContentOffsetAnimationActive
        {
            syncFrame()
            return
        }

        panelPresentationGeneration &+= 1
        let generation = panelPresentationGeneration
        isPanelRevealed = false
        orderOutAndDetachDragPreviewOverlay(destroyWindow: false)
        panel.ignoresMouseEvents = true

        guard let visibleFrame = currentVisiblePanelFrame() else {
            detachFromParent()
            panel.orderOut(nil)
            return
        }

        preparePanelContentClipping(panel)
        panel.setFrame(visibleFrame, display: panel.isVisible)
        guard panel.isVisible,
              attachedParentWindow != nil
        else {
            setSidebarContentOffset(hiddenSidebarContentOffset, animated: false)
            detachFromParent()
            panel.orderOut(nil)
            return
        }

        let didScheduleHideAnimation = setSidebarContentOffset(hiddenSidebarContentOffset, animated: true) { [weak self, weak panel] in
            guard let self,
                  self.panelPresentationGeneration == generation,
                  self.isPanelRevealed == false,
                  let panel,
                  self.panelWindow === panel
            else { return }

            self.detachFromParent()
            panel.orderOut(nil)
        }
        if didScheduleHideAnimation {
            startFrameSyncBurst(
                duration: CollapsedSidebarPanelAnimation.hideDuration
                    + CollapsedSidebarPanelFrameSync.animationCompletionGrace,
                reason: CollapsedSidebarPanelFrameSync.hideAnimationReason
            )
        }
    }

    @discardableResult
    private func setSidebarContentOffset(
        _ offset: CGFloat,
        animated: Bool,
        startingOffset: CGFloat? = nil,
        completion: (@MainActor () -> Void)? = nil
    ) -> Bool {
        let animatedView = sidebarController.collapsedPanelAnimatedContentView ?? sidebarController.view
        animatedView.wantsLayer = true
        animatedView.layoutSubtreeIfNeeded()

        guard let layer = animatedView.layer else {
            completion?()
            return false
        }

        let transform = CATransform3DMakeTranslation(offset, 0, 0)
        let startTransform = startingOffset.map { CATransform3DMakeTranslation($0, 0, 0) }
            ?? layer.presentation()?.transform
            ?? layer.transform
        layer.removeAnimation(forKey: CollapsedSidebarPanelAnimation.contentOffsetAnimationKey)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = transform
        CATransaction.commit()

        guard animated,
              !CATransform3DEqualToTransform(startTransform, transform)
        else {
            completion?()
            return false
        }

        let animation = makeSidebarContentOffsetAnimation(
            from: startTransform,
            to: transform,
            isReveal: offset == 0
        )

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            Task { @MainActor in
                completion?()
            }
        }
        layer.add(animation, forKey: CollapsedSidebarPanelAnimation.contentOffsetAnimationKey)
        CATransaction.commit()
        return true
    }

    private func makeSidebarContentOffsetAnimation(
        from startTransform: CATransform3D,
        to targetTransform: CATransform3D,
        isReveal: Bool
    ) -> CAAnimation {
        if isReveal {
            let startX = startTransform.m41
            let targetX = targetTransform.m41
            let distance = targetX - startX
            let animation = CAKeyframeAnimation(keyPath: "transform")
            animation.values = CollapsedSidebarPanelAnimation.revealProgress.map { progress in
                NSValue(caTransform3D: CATransform3DMakeTranslation(startX + distance * progress, 0, 0))
            }
            animation.keyTimes = CollapsedSidebarPanelAnimation.revealKeyTimes
            animation.duration = CollapsedSidebarPanelAnimation.revealDuration
            animation.calculationMode = .linear
            animation.isRemovedOnCompletion = true
            return animation
        }

        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: startTransform)
        animation.toValue = NSValue(caTransform3D: targetTransform)
        animation.duration = CollapsedSidebarPanelAnimation.hideDuration
        animation.timingFunction = CollapsedSidebarPanelAnimation.hideTimingFunction
        animation.isRemovedOnCompletion = true
        return animation
    }

    private func attachAndShow(
        _ panel: CollapsedSidebarPanelWindow,
        to parentWindow: NSWindow
    ) {
        if attachedParentWindow !== parentWindow {
            detachFromParent()
        }

        if parentWindow.childWindows?.contains(panel) != true {
            parentWindow.addChildWindow(panel, ordered: .above)
        }

        attachedParentWindow = parentWindow
        panel.orderFront(nil)
        syncFrame()
    }

    private func attachAndShowDragPreviewOverlay(
        _ overlay: CollapsedSidebarDragPreviewOverlayWindow,
        to parentWindow: NSWindow
    ) {
        if dragPreviewOverlayParentWindow !== parentWindow {
            detachDragPreviewOverlayFromParent()
        }

        if parentWindow.childWindows?.contains(overlay) != true {
            parentWindow.addChildWindow(overlay, ordered: .above)
        }

        dragPreviewOverlayParentWindow = parentWindow
        overlay.orderFront(nil)
        syncDragPreviewOverlayFrame()
    }

    private func orderOutAndDetach(
        teardownHostedContent: Bool,
        destroyWindow: Bool
    ) {
        panelPresentationGeneration &+= 1
        isPanelRevealed = false
        setSidebarContentOffset(hiddenSidebarContentOffset, animated: false)
        orderOutAndDetachDragPreviewOverlay(destroyWindow: destroyWindow)
        detachFromParent()
        panelWindow?.orderOut(nil)
        stopFrameSyncTimer()

        if teardownHostedContent {
            sidebarController.teardownSidebarHosting()
        }

        if destroyWindow {
            panelWindow?.contentViewController = nil
            panelWindow = nil
        }
    }

    private func orderOutAndDetachDragPreviewOverlay(destroyWindow: Bool) {
        detachDragPreviewOverlayFromParent()
        dragPreviewOverlayWindow?.orderOut(nil)
        dragPreviewOverlayController.rootView = AnyView(EmptyView())
        stopFrameSyncTimerIfNoSurfaceNeedsSync()

        if destroyWindow {
            dragPreviewOverlayWindow?.contentViewController = nil
            dragPreviewOverlayWindow = nil
        }
    }

    private func detachFromParent() {
        guard let panelWindow,
              let attachedParentWindow
        else {
            self.attachedParentWindow = nil
            return
        }

        if attachedParentWindow.childWindows?.contains(panelWindow) == true {
            attachedParentWindow.removeChildWindow(panelWindow)
        }
        self.attachedParentWindow = nil
        stopFrameSyncTimerIfNoSurfaceNeedsSync()
    }

    private func detachDragPreviewOverlayFromParent() {
        guard let dragPreviewOverlayWindow,
              let dragPreviewOverlayParentWindow
        else {
            self.dragPreviewOverlayParentWindow = nil
            return
        }

        if dragPreviewOverlayParentWindow.childWindows?.contains(dragPreviewOverlayWindow) == true {
            dragPreviewOverlayParentWindow.removeChildWindow(dragPreviewOverlayWindow)
        }
        self.dragPreviewOverlayParentWindow = nil
        stopFrameSyncTimerIfNoSurfaceNeedsSync()
    }

    private func syncDragPreviewOverlayFrame() {
        guard let dragPreviewOverlayWindow,
              let parentWindow = observedParentWindow ?? dragPreviewOverlayParentWindow ?? attachedParentWindow,
              let frame = CollapsedSidebarDragPreviewOverlayFrameResolver.overlayFrame(in: parentWindow)
        else { return }

        setFrameIfNeeded(dragPreviewOverlayWindow, to: frame, display: dragPreviewOverlayWindow.isVisible)
    }

    private func handleCollapsedSidebarDismissalRequest() {
        guard let panelWindow,
              panelWindow.isVisible || isPanelAttached
        else { return }

        sidebarController.setCollapsedPanelHitTestingEnabled(false)
        sidebarController.teardownSidebarHosting()
        hideAndDetach(panelWindow)
    }

    private func handleParentWindowGeometryChange(_ notificationName: Notification.Name) {
        syncFrame()
        if notificationName == NSWindow.didResizeNotification,
           isLiveResizeFrameSyncActive {
            startFrameSyncBurst(
                duration: CollapsedSidebarPanelFrameSync.liveResizeBurstDuration,
                reason: CollapsedSidebarPanelFrameSync.liveResizeReason
            )
        }
    }

    private func handleParentWindowWillStartLiveResize() {
        isLiveResizeFrameSyncActive = true
        syncFrame()
        startFrameSyncBurst(
            duration: CollapsedSidebarPanelFrameSync.liveResizeBurstDuration,
            reason: CollapsedSidebarPanelFrameSync.liveResizeReason
        )
    }

    private func handleParentWindowDidEndLiveResize() {
        isLiveResizeFrameSyncActive = false
        syncFrame()
        stopFrameSyncBurst(reason: CollapsedSidebarPanelFrameSync.liveResizeReason)
    }

    private func bindParentWindow(_ parentWindow: NSWindow) {
        guard observedParentWindow !== parentWindow else { return }
        unbindParentWindow()
        observedParentWindow = parentWindow

        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
        ]

        observers = names.map { name in
            center.addObserver(
                forName: name,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleParentWindowGeometryChange(name)
                }
            }
        }

        observers.append(
            center.addObserver(
                forName: NSWindow.willStartLiveResizeNotification,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleParentWindowWillStartLiveResize()
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: NSWindow.didEndLiveResizeNotification,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleParentWindowDidEndLiveResize()
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.teardown()
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: .sumiShouldHideCollapsedSidebarOverlay,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleCollapsedSidebarDismissalRequest()
                }
            }
        )

        if let contentView = parentWindow.contentView {
            contentView.postsFrameChangedNotifications = true
            observers.append(
                center.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: contentView,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.syncFrame()
                    }
                }
            )
        }
    }

    private func unbindParentWindow() {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers = []
        observedParentWindow = nil
        isLiveResizeFrameSyncActive = false
    }
}

final class CollapsedSidebarPanelAnchorView: NSView {
    var onWindowChanged: ((NSWindow?) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChanged?(window)
    }
}

struct CollapsedSidebarPanelHost: NSViewRepresentable {
    @ObservedObject var browserManager: BrowserManager
    @ObservedObject private var sidebarDragState = SidebarDragState.shared
    var windowState: BrowserWindowState
    var windowRegistry: WindowRegistry
    var commandPalette: CommandPalette
    var sumiSettings: SumiSettingsService
    var resolvedThemeContext: ResolvedThemeContext
    var chromeBackgroundResolvedThemeContext: ResolvedThemeContext
    var presentationContext: SidebarPresentationContext
    var isHostRequested: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> CollapsedSidebarPanelAnchorView {
        let view = CollapsedSidebarPanelAnchorView(frame: .zero)
        view.onWindowChanged = { [weak controller = context.coordinator.controller] _ in
            MainActor.assumeIsolated {
                controller?.syncFrame()
            }
        }
        return view
    }

    func updateNSView(_ nsView: CollapsedSidebarPanelAnchorView, context: Context) {
        guard isHostRequested else {
            context.coordinator.controller.update(
                parentWindow: nsView.window ?? windowState.window,
                root: EmptyView(),
                width: presentationContext.sidebarWidth,
                presentationContext: presentationContext,
                contextMenuController: nil,
                isHostRequested: false
            )
            context.coordinator.controller.updateDragPreviewOverlay(
                parentWindow: nsView.window ?? windowState.window,
                root: EmptyView(),
                isPresented: false
            )
            return
        }

        let root = SidebarColumnHostedRoot.view(
            browserManager: browserManager,
            windowState: windowState,
            windowRegistry: windowRegistry,
            commandPalette: commandPalette,
            sumiSettings: sumiSettings,
            resolvedThemeContext: resolvedThemeContext,
            chromeBackgroundResolvedThemeContext: chromeBackgroundResolvedThemeContext,
            presentationContext: presentationContext
        )

        context.coordinator.controller.update(
            parentWindow: nsView.window ?? windowState.window,
            root: root,
            width: presentationContext.sidebarWidth,
            presentationContext: presentationContext,
            contextMenuController: windowState.sidebarContextMenuController,
            isHostRequested: isHostRequested,
            onPointerDown: { [weak browserManager] in
                browserManager?.dismissWorkspaceThemePickerIfNeededCommitting()
            }
        )

        let dragPreviewRoot = SidebarFloatingDragPreview()
            .environmentObject(browserManager)
            .environment(windowState)
            .environment(\.sumiSettings, sumiSettings)
            .environment(\.resolvedThemeContext, resolvedThemeContext)

        context.coordinator.controller.updateDragPreviewOverlay(
            parentWindow: nsView.window ?? windowState.window,
            root: dragPreviewRoot,
            isPresented: SidebarDragVisualSurfacePolicy.shouldPresentCollapsedPanelPreviewOverlay(
                presentationContext: presentationContext,
                isDragging: sidebarDragState.isDragging,
                isInternalDragGeometryArmed: sidebarDragState.isInternalDragGeometryArmed
            )
        )
    }

    static func dismantleNSView(_ nsView: CollapsedSidebarPanelAnchorView, coordinator: Coordinator) {
        nsView.onWindowChanged = nil
        coordinator.controller.teardown()
    }

    @MainActor
    final class Coordinator {
        let controller = CollapsedSidebarPanelController()
    }
}

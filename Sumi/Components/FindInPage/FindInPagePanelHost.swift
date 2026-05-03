import AppKit
import QuartzCore
import SwiftUI

private enum FindInPagePanelAnimation {
    static let revealDuration: TimeInterval = 0.22
    static let hideDuration: TimeInterval = 0.14
    static let contentOffsetAnimationKey = "sumi.findInPagePanel.contentOffset"
    static let revealTimingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.82, 0.2, 1.0)
    static let hideTimingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)
}

@MainActor
final class FindInPagePanelController {
    private static let panelHeight = FindInPageChromeLayout.stripHeight

    private var panelWindow: TransientChromePanelWindow?
    private let hostingController = NSHostingController(rootView: AnyView(EmptyView()))
    private weak var anchorView: NSView?
    private weak var attachedParentWindow: NSWindow?
    private weak var observedParentWindow: NSWindow?
    private weak var observedContentView: NSView?
    private var observers: [NSObjectProtocol] = []
    private var currentRoot = AnyView(EmptyView())
    private var currentIsPresented = false
    private var currentAllowsDismissalAnimation = true
    private var isSuspendedForParentSheet = false
    private var isPanelRevealed = false
    private var panelPresentationGeneration: UInt64 = 0

    var panelWindowForTesting: TransientChromePanelWindow? {
        panelWindow
    }

    var isPanelAttachedForTesting: Bool {
        guard let panelWindow, let attachedParentWindow else { return false }
        return attachedParentWindow.childWindows?.contains(panelWindow) == true
    }

    var shouldKeepHostedChromeMounted: Bool {
        panelWindow?.isVisible == true || isPanelRevealed || isPanelContentOffsetAnimationActive
    }

    func update(
        parentWindow: NSWindow?,
        anchorView: NSView,
        root: AnyView,
        isPresented: Bool,
        allowsDismissalAnimation: Bool
    ) {
        self.anchorView = anchorView
        currentRoot = root
        currentIsPresented = isPresented
        currentAllowsDismissalAnimation = allowsDismissalAnimation

        guard isPresented, let parentWindow else {
            if let panelWindow {
                hideAndDetach(
                    panelWindow,
                    destroyWindow: true,
                    animated: allowsDismissalAnimation
                )
            } else {
                orderOutAndDetach(destroyWindow: true)
            }
            return
        }

        bindParentWindow(parentWindow)

        if isSuspendedForParentSheet || !parentWindow.sheets.isEmpty {
            isSuspendedForParentSheet = true
            if let panelWindow {
                hideAndDetach(
                    panelWindow,
                    destroyWindow: false,
                    animated: false,
                    restoreParentKey: false
                )
            } else {
                orderOutAndDetach(destroyWindow: false, restoreParentKey: false)
            }
            return
        }

        let panel = ensurePanelWindow()
        TransientChromePanelConfiguration.configure(panel, for: parentWindow)

        hostingController.rootView = root
        if panel.contentViewController !== hostingController {
            panel.contentViewController = hostingController
        }

        syncFrame()
        reveal(panel, in: parentWindow)
    }

    func parentWindowDidChange(_ parentWindow: NSWindow?, anchorView: NSView) {
        update(
            parentWindow: parentWindow,
            anchorView: anchorView,
            root: currentRoot,
            isPresented: currentIsPresented,
            allowsDismissalAnimation: currentAllowsDismissalAnimation
        )
    }

    func teardown() {
        orderOutAndDetach(destroyWindow: true)
        unbindParentWindow()
    }

    deinit {
        MainActor.assumeIsolated {
            teardown()
        }
    }

    private func ensurePanelWindow() -> TransientChromePanelWindow {
        if let panelWindow {
            return panelWindow
        }
        let panel = TransientChromePanelConfiguration.makePanel()
        panelWindow = panel
        return panel
    }

    private func syncFrame() {
        guard let panelWindow,
              let frame = currentVisiblePanelFrame()
        else { return }

        guard panelWindow.frame != frame else { return }
        panelWindow.setFrame(frame, display: panelWindow.isVisible)
    }

    private func currentVisiblePanelFrame() -> NSRect? {
        guard let anchorView else { return nil }
        return TransientChromePanelFrameResolver.topStripFrame(
            in: anchorView,
            fallbackWindow: observedParentWindow ?? attachedParentWindow,
            height: Self.panelHeight
        )
    }

    private var hiddenPanelContentOffset: CGFloat {
        max(currentVisiblePanelFrame()?.height ?? Self.panelHeight, 0)
    }

    private var isPanelContentOffsetAnimationActive: Bool {
        hostingController.view.layer?.animation(
            forKey: FindInPagePanelAnimation.contentOffsetAnimationKey
        ) != nil
    }

    private func preparePanelContentClipping(_ panel: TransientChromePanelWindow) {
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.isOpaque = false
        panel.contentView?.layer?.masksToBounds = true
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.masksToBounds = false
    }

    private func reveal(
        _ panel: TransientChromePanelWindow,
        in parentWindow: NSWindow
    ) {
        panelPresentationGeneration &+= 1

        let wasAlreadyRevealed = isPanelRevealed
            && panel.isVisible
            && attachedParentWindow === parentWindow

        preparePanelContentClipping(panel)
        if let visibleFrame = currentVisiblePanelFrame() {
            panel.setFrame(visibleFrame, display: false)
        }

        let initialContentOffset = hiddenPanelContentOffset
        if !wasAlreadyRevealed {
            setPanelContentOffset(initialContentOffset, animated: false)
        }

        isPanelRevealed = true
        panel.ignoresMouseEvents = false
        attachAndShow(panel, to: parentWindow)

        setPanelContentOffset(
            0,
            animated: !wasAlreadyRevealed,
            startingOffset: wasAlreadyRevealed ? nil : initialContentOffset
        )
    }

    private func hideAndDetach(
        _ panel: TransientChromePanelWindow,
        destroyWindow: Bool,
        animated: Bool,
        restoreParentKey: Bool = true
    ) {
        if !isPanelRevealed,
           panel.isVisible,
           attachedParentWindow != nil,
           isPanelContentOffsetAnimationActive
        {
            syncFrame()
            return
        }

        panelPresentationGeneration &+= 1
        let generation = panelPresentationGeneration
        isPanelRevealed = false
        panel.ignoresMouseEvents = true

        guard animated else {
            orderOutAndDetach(destroyWindow: destroyWindow, restoreParentKey: restoreParentKey)
            return
        }

        guard let visibleFrame = currentVisiblePanelFrame() else {
            orderOutAndDetach(destroyWindow: destroyWindow, restoreParentKey: restoreParentKey)
            return
        }

        preparePanelContentClipping(panel)
        panel.setFrame(visibleFrame, display: panel.isVisible)
        guard panel.isVisible,
              attachedParentWindow != nil
        else {
            setPanelContentOffset(hiddenPanelContentOffset, animated: false)
            orderOutAndDetach(destroyWindow: destroyWindow, restoreParentKey: restoreParentKey)
            return
        }

        setPanelContentOffset(hiddenPanelContentOffset, animated: true) { [weak self, weak panel] in
            guard let self,
                  self.panelPresentationGeneration == generation,
                  self.isPanelRevealed == false,
                  let panel,
                  self.panelWindow === panel
            else { return }

            self.orderOutAndDetach(
                destroyWindow: destroyWindow,
                restoreParentKey: restoreParentKey
            )
        }
    }

    @discardableResult
    private func setPanelContentOffset(
        _ offset: CGFloat,
        animated: Bool,
        startingOffset: CGFloat? = nil,
        completion: (@MainActor () -> Void)? = nil
    ) -> Bool {
        let animatedView = hostingController.view
        animatedView.wantsLayer = true
        animatedView.layoutSubtreeIfNeeded()

        guard let layer = animatedView.layer else {
            completion?()
            return false
        }

        let transform = CATransform3DMakeTranslation(0, offset, 0)
        let startTransform = startingOffset.map { CATransform3DMakeTranslation(0, $0, 0) }
            ?? layer.presentation()?.transform
            ?? layer.transform
        layer.removeAnimation(forKey: FindInPagePanelAnimation.contentOffsetAnimationKey)

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

        let animation = makePanelContentOffsetAnimation(
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
        layer.add(animation, forKey: FindInPagePanelAnimation.contentOffsetAnimationKey)
        CATransaction.commit()
        return true
    }

    private func makePanelContentOffsetAnimation(
        from startTransform: CATransform3D,
        to targetTransform: CATransform3D,
        isReveal: Bool
    ) -> CAAnimation {
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: startTransform)
        animation.toValue = NSValue(caTransform3D: targetTransform)
        animation.duration = isReveal
            ? FindInPagePanelAnimation.revealDuration
            : FindInPagePanelAnimation.hideDuration
        animation.timingFunction = isReveal
            ? FindInPagePanelAnimation.revealTimingFunction
            : FindInPagePanelAnimation.hideTimingFunction
        animation.isRemovedOnCompletion = true
        return animation
    }

    private func attachAndShow(_ panel: TransientChromePanelWindow, to parentWindow: NSWindow) {
        if attachedParentWindow !== parentWindow {
            detachFromParent()
        }

        if parentWindow.childWindows?.contains(panel) != true {
            parentWindow.addChildWindow(panel, ordered: .above)
        }

        attachedParentWindow = parentWindow
        panel.orderFront(nil)
        panel.makeKey()
        syncFrame()
    }

    private func orderOutAndDetach(destroyWindow: Bool, restoreParentKey: Bool = true) {
        panelPresentationGeneration &+= 1
        isPanelRevealed = false
        setPanelContentOffset(hiddenPanelContentOffset, animated: false)
        let parentWindow = attachedParentWindow
        detachFromParent()
        panelWindow?.orderOut(nil)
        hostingController.rootView = AnyView(EmptyView())
        if restoreParentKey {
            parentWindow?.makeKey()
        }

        if destroyWindow {
            panelWindow?.contentViewController = nil
            panelWindow = nil
            unbindParentWindow()
        }
    }

    private func detachFromParent() {
        guard let panelWindow, let attachedParentWindow else {
            self.attachedParentWindow = nil
            return
        }

        if attachedParentWindow.childWindows?.contains(panelWindow) == true {
            attachedParentWindow.removeChildWindow(panelWindow)
        }
        self.attachedParentWindow = nil
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
                    self?.syncFrame()
                }
            }
        }

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
                forName: NSWindow.willBeginSheetNotification,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.suspendForParentSheet()
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: NSWindow.didEndSheetNotification,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.resumeAfterParentSheet()
                }
            }
        )

        if let contentView = parentWindow.contentView {
            contentView.postsFrameChangedNotifications = true
            observedContentView = contentView
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

    private func suspendForParentSheet() {
        isSuspendedForParentSheet = true
        orderOutAndDetach(destroyWindow: false, restoreParentKey: false)
    }

    private func resumeAfterParentSheet() {
        isSuspendedForParentSheet = false
        guard let anchorView else { return }
        update(
            parentWindow: observedParentWindow ?? attachedParentWindow,
            anchorView: anchorView,
            root: currentRoot,
            isPresented: currentIsPresented,
            allowsDismissalAnimation: currentAllowsDismissalAnimation
        )
    }

    private func unbindParentWindow() {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers = []
        observedParentWindow = nil
        observedContentView = nil
        isSuspendedForParentSheet = false
    }
}

struct FindInPagePanelHost: NSViewRepresentable {
    @ObservedObject var browserManager: BrowserManager
    @ObservedObject var findManager: FindManager
    var windowRegistry: WindowRegistry
    var windowState: BrowserWindowState
    var sumiSettings: SumiSettingsService
    var resolvedThemeContext: ResolvedThemeContext
    var colorScheme: ColorScheme

    private var shouldPresent: Bool {
        windowRegistry.activeWindow?.id == windowState.id
            && findManager.isFindBarVisible
            && !isModalSuppressed
    }

    private var isModalSuppressed: Bool {
        browserManager.dialogManager.isPresented(in: windowState.window)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TransientChromePanelAnchorView {
        let view = TransientChromePanelAnchorView(frame: .zero)
        view.onWindowChanged = { [weak controller = context.coordinator.controller] window in
            MainActor.assumeIsolated {
                controller?.parentWindowDidChange(window, anchorView: view)
            }
        }
        return view
    }

    func updateNSView(_ nsView: TransientChromePanelAnchorView, context: Context) {
        let isPresented = shouldPresent
        let allowsDismissalAnimation = !isModalSuppressed
        let keepsChromeMounted = isPresented
            || (allowsDismissalAnimation && context.coordinator.controller.shouldKeepHostedChromeMounted)
        context.coordinator.controller.update(
            parentWindow: nsView.window ?? windowState.window,
            anchorView: nsView,
            root: rootView(
                keepsChromeMounted: keepsChromeMounted,
                isInteractive: isPresented
            ),
            isPresented: isPresented,
            allowsDismissalAnimation: allowsDismissalAnimation
        )
    }

    static func dismantleNSView(_ nsView: TransientChromePanelAnchorView, coordinator: Coordinator) {
        coordinator.controller.teardown()
    }

    private func rootView(
        keepsChromeMounted: Bool,
        isInteractive: Bool
    ) -> AnyView {
        AnyView(
            FindInPageChromeHitTestingWrapper(
                findManager: findManager,
                windowStateID: windowState.id,
                themeContext: resolvedThemeContext,
                keepsChromeMounted: keepsChromeMounted,
                isInteractive: isInteractive
            )
            .environmentObject(browserManager)
            .environment(windowRegistry)
            .environment(\.sumiSettings, sumiSettings)
            .environment(\.resolvedThemeContext, resolvedThemeContext)
            .environment(\.colorScheme, colorScheme)
        )
    }

    @MainActor
    final class Coordinator {
        let controller = FindInPagePanelController()
    }
}

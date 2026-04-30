import AppKit
import SwiftUI

enum BrowserWindowControlsAccessibilityIdentifiers {
    static let closeButton = "browser-window-close-button"
    static let minimizeButton = "browser-window-minimize-button"
    static let zoomButton = "browser-window-zoom-button"
    static let miniBrowserWindow = "mini-browser-window"

    static let allButtonIdentifiers: Set<String> = [
        closeButton,
        minimizeButton,
        zoomButton,
    ]

    static func identifier(for buttonType: NSWindow.ButtonType) -> String? {
        switch buttonType {
        case .closeButton:
            return closeButton
        case .miniaturizeButton:
            return minimizeButton
        case .zoomButton:
            return zoomButton
        default:
            return nil
        }
    }
}

enum BrowserWindowTrafficLightMetrics {
    static var buttonDiameter: CGFloat {
        if #available(macOS 26.0, *) {
            return 14
        } else {
            return 12
        }
    }

    static let buttonCenterSpacing: CGFloat = 20
    static var buttonSpacing: CGFloat {
        buttonCenterSpacing - buttonDiameter
    }
    static let clusterHeight: CGFloat = 30
    static let clusterTrailingInset: CGFloat = 14
    static let placeholderHorizontalOffset: CGFloat = -1

    static var clusterWidth: CGFloat {
        buttonDiameter * 3 + buttonSpacing * 2
    }

    static var sidebarReservedWidth: CGFloat {
        clusterWidth + clusterTrailingInset
    }
}

@MainActor
final class BrowserWindowTrafficLightRenderState: ObservableObject {
    @Published var isNativeClusterVisible = false
}

struct BrowserWindowNativeTrafficLightSpacer: View {
    var isVisible: Bool = true

    var body: some View {
        Color.clear
            .frame(
                width: isVisible ? BrowserWindowTrafficLightMetrics.sidebarReservedWidth : 0,
                height: BrowserWindowTrafficLightMetrics.clusterHeight
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct BrowserWindowTrafficLightPlaceholderCluster: View {
    @ObservedObject var renderState: BrowserWindowTrafficLightRenderState
    var isVisible: Bool = true

    private var shouldDrawPlaceholder: Bool {
        isVisible && renderState.isNativeClusterVisible == false
    }

    var body: some View {
        HStack(spacing: BrowserWindowTrafficLightMetrics.buttonSpacing) {
            placeholderCircle(color: Color(nsColor: .systemRed))
            placeholderCircle(color: Color(nsColor: .systemYellow))
            placeholderCircle(color: Color(nsColor: .systemGreen))
        }
        .frame(
            width: isVisible ? BrowserWindowTrafficLightMetrics.sidebarReservedWidth : 0,
            height: BrowserWindowTrafficLightMetrics.clusterHeight,
            alignment: .leading
        )
        .offset(x: BrowserWindowTrafficLightMetrics.placeholderHorizontalOffset)
        .opacity(shouldDrawPlaceholder ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func placeholderCircle(color: Color) -> some View {
        Circle()
            .fill(color)
            .overlay {
                Circle()
                    .stroke(Color.black.opacity(0.14), lineWidth: 0.75)
            }
            .frame(
                width: BrowserWindowTrafficLightMetrics.buttonDiameter,
                height: BrowserWindowTrafficLightMetrics.buttonDiameter
            )
    }
}

struct BrowserWindowNativeTrafficLightVisibilityBridge: NSViewRepresentable {
    let window: NSWindow?
    let renderState: BrowserWindowTrafficLightRenderState
    let visibleOutsideFullScreen: Bool
    var horizontalOffset: CGFloat = 0
    var verticalOffset: CGFloat = 0
    var revealDelay: TimeInterval = 0

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> BrowserWindowNativeTrafficLightVisibilityView {
        let view = BrowserWindowNativeTrafficLightVisibilityView()
        view.coordinator = context.coordinator
        context.coordinator.attach(to: window ?? view.window)
        context.coordinator.update(
            renderState: renderState,
            visibleOutsideFullScreen: visibleOutsideFullScreen,
            horizontalOffset: horizontalOffset,
            verticalOffset: verticalOffset,
            revealDelay: revealDelay
        )
        return view
    }

    func updateNSView(
        _ nsView: BrowserWindowNativeTrafficLightVisibilityView,
        context: Context
    ) {
        nsView.coordinator = context.coordinator
        context.coordinator.attach(to: window ?? nsView.window)
        context.coordinator.update(
            renderState: renderState,
            visibleOutsideFullScreen: visibleOutsideFullScreen,
            horizontalOffset: horizontalOffset,
            verticalOffset: verticalOffset,
            revealDelay: revealDelay
        )
    }

    static func dismantleNSView(
        _ nsView: BrowserWindowNativeTrafficLightVisibilityView,
        coordinator: Coordinator
    ) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        private enum Timing {
            static let resizeStabilizationDelay: TimeInterval = 0.06
            static let fullScreenExitStabilizationDelay: TimeInterval = 0.28
            static let fullScreenExitTransitionHideDuration: TimeInterval = 0.48
            static let hiddenMaintenanceDelays: [TimeInterval] = [
                0,
                0.016,
                0.033,
                0.066,
                0.10,
                0.16,
                0.24,
                0.34,
                0.48,
            ]
        }

        private weak var window: NSWindow?
        private weak var renderState: BrowserWindowTrafficLightRenderState?
        private var observers: [NSObjectProtocol] = []
        private var visibleOutsideFullScreen = true
        private var horizontalOffset: CGFloat = 0
        private var verticalOffset: CGFloat = 0
        private var revealDelay: TimeInterval = 0
        private var revealGeneration: UInt = 0
        private var isFinishingFullScreenExit = false

        func attach(to window: NSWindow?) {
            guard self.window !== window else { return }

            detach()
            self.window = window
            installWindowChromeObservers(for: window)
            applyVisibilityPolicy()
        }

        func update(
            renderState: BrowserWindowTrafficLightRenderState,
            visibleOutsideFullScreen: Bool,
            horizontalOffset: CGFloat,
            verticalOffset: CGFloat,
            revealDelay: TimeInterval
        ) {
            self.renderState = renderState

            guard self.visibleOutsideFullScreen != visibleOutsideFullScreen
                    || self.horizontalOffset != horizontalOffset
                    || self.verticalOffset != verticalOffset
                    || self.revealDelay != revealDelay
            else {
                return
            }

            self.visibleOutsideFullScreen = visibleOutsideFullScreen
            self.horizontalOffset = horizontalOffset
            self.verticalOffset = verticalOffset
            self.revealDelay = revealDelay
            applyVisibilityPolicy()
        }

        func detach() {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
            revealGeneration &+= 1
            isFinishingFullScreenExit = false
            renderState?.isNativeClusterVisible = false
            renderState = nil
            window = nil
        }

        private func installWindowChromeObservers(for window: NSWindow?) {
            guard let window else { return }

            let center = NotificationCenter.default
            for name in [
                NSWindow.willEnterFullScreenNotification,
                NSWindow.didEnterFullScreenNotification,
                NSWindow.willExitFullScreenNotification,
                NSWindow.didExitFullScreenNotification,
                NSWindow.willStartLiveResizeNotification,
                NSWindow.didResizeNotification,
                NSWindow.didEndLiveResizeNotification,
            ] {
                observers.append(
                    center.addObserver(
                        forName: name,
                        object: window,
                        queue: .main
                    ) { [weak self] notification in
                        Task { @MainActor in
                            self?.handleWindowChromeNotification(notification)
                        }
                    }
                )
            }
        }

        private func handleWindowChromeNotification(_ notification: Notification) {
            let name = notification.name

            switch name {
            case NSWindow.willEnterFullScreenNotification,
                NSWindow.didEnterFullScreenNotification:
                showNativeButtonsImmediatelyForFullScreen()
            case NSWindow.willExitFullScreenNotification:
                beginFullScreenExitPlaceholderGate()
            case NSWindow.didExitFullScreenNotification:
                beginDelayedNativeReveal(delay: Timing.fullScreenExitStabilizationDelay)
            case NSWindow.willStartLiveResizeNotification,
                NSWindow.didResizeNotification,
                 NSWindow.didEndLiveResizeNotification:
                beginDelayedNativeReveal(
                    delay: isFinishingFullScreenExit
                        ? Timing.fullScreenExitStabilizationDelay
                        : Timing.resizeStabilizationDelay
                )
            default:
                applyVisibilityPolicy()
            }
        }

        private func applyVisibilityPolicy() {
            guard let window else {
                renderState?.isNativeClusterVisible = false
                return
            }

            if window.styleMask.contains(.fullScreen) && isFinishingFullScreenExit == false {
                showNativeButtonsImmediatelyForFullScreen()
                return
            }

            guard visibleOutsideFullScreen else {
                hideNativeButtonsAndCancelReveal()
                return
            }

            let delay = revealDelay
            beginDelayedNativeReveal(delay: delay)
        }

        private func beginDelayedNativeReveal(delay: TimeInterval) {
            guard let window else {
                renderState?.isNativeClusterVisible = false
                return
            }

            if window.styleMask.contains(.fullScreen) && isFinishingFullScreenExit == false {
                showNativeButtonsImmediatelyForFullScreen()
                return
            }

            guard visibleOutsideFullScreen else {
                hideNativeButtonsAndCancelReveal()
                return
            }

            revealGeneration &+= 1
            let generation = revealGeneration

            window.setNativeStandardWindowButtonsForBrowserChromeVisible(
                false,
                horizontalOffset: horizontalOffset,
                verticalOffset: verticalOffset
            )
            renderState?.isNativeClusterVisible = false
            if isFinishingFullScreenExit {
                scheduleNativeButtonHiddenMaintenance(
                    generation: generation,
                    duration: max(delay, Timing.fullScreenExitStabilizationDelay)
                )
            }

            DispatchQueue.main.async { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.finishDelayedNativeReveal(generation: generation, delay: delay)
                }
            }
        }

        private func finishDelayedNativeReveal(generation: UInt, delay: TimeInterval) {
            let deadline = DispatchTime.now() + .nanoseconds(Int(max(delay, 0) * 1_000_000_000))
            DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
                guard let self else { return }
                self.showNativeButtonsIfRevealIsCurrent(generation: generation)
            }
        }

        private func showNativeButtonsIfRevealIsCurrent(generation: UInt) {
            guard generation == revealGeneration,
                  visibleOutsideFullScreen,
                  let window,
                  window.styleMask.contains(.fullScreen) == false
            else { return }

            isFinishingFullScreenExit = false
            window.setNativeStandardWindowButtonsForBrowserChromeVisible(
                true,
                horizontalOffset: horizontalOffset,
                verticalOffset: verticalOffset
            )
            renderState?.isNativeClusterVisible = true
        }

        private func showNativeButtonsImmediatelyForFullScreen() {
            isFinishingFullScreenExit = false
            revealGeneration &+= 1
            window?.setNativeStandardWindowButtonsForBrowserChromeVisible(
                true,
                horizontalOffset: horizontalOffset,
                verticalOffset: verticalOffset
            )
            renderState?.isNativeClusterVisible = true
        }

        private func beginFullScreenExitPlaceholderGate() {
            isFinishingFullScreenExit = true
            revealGeneration &+= 1
            let generation = revealGeneration
            window?.setNativeStandardWindowButtonsForBrowserChromeVisible(
                false,
                horizontalOffset: horizontalOffset,
                verticalOffset: verticalOffset
            )
            renderState?.isNativeClusterVisible = false
            scheduleNativeButtonHiddenMaintenance(
                generation: generation,
                duration: Timing.fullScreenExitTransitionHideDuration
            )
        }

        private func hideNativeButtonsAndCancelReveal() {
            isFinishingFullScreenExit = false
            revealGeneration &+= 1
            window?.setNativeStandardWindowButtonsForBrowserChromeVisible(
                false,
                horizontalOffset: horizontalOffset,
                verticalOffset: verticalOffset
            )
            renderState?.isNativeClusterVisible = false
        }

        private func scheduleNativeButtonHiddenMaintenance(
            generation: UInt,
            duration: TimeInterval
        ) {
            for delay in Timing.hiddenMaintenanceDelays where delay <= duration {
                let deadline = DispatchTime.now() + .nanoseconds(Int(delay * 1_000_000_000))
                DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
                    self?.keepNativeButtonsHiddenIfTransitionIsCurrent(generation: generation)
                }
            }
        }

        private func keepNativeButtonsHiddenIfTransitionIsCurrent(generation: UInt) {
            guard generation == revealGeneration,
                  isFinishingFullScreenExit
            else { return }

            window?.setNativeStandardWindowButtonsForBrowserChromeVisible(
                false,
                horizontalOffset: horizontalOffset,
                verticalOffset: verticalOffset
            )
            renderState?.isNativeClusterVisible = false
        }
    }
}

final class BrowserWindowNativeTrafficLightVisibilityView: NSView {
    weak var coordinator: BrowserWindowNativeTrafficLightVisibilityBridge.Coordinator?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        coordinator?.attach(to: window)
    }
}

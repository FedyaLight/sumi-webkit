import AppKit
import SwiftUI

enum BrowserWindowControlsAccessibilityIdentifiers {
    static let closeButton = "browser-window-close-button"
    static let minimizeButton = "browser-window-minimize-button"
    static let zoomButton = "browser-window-zoom-button"
}

/// Geometry AppKit measured from the live standard buttons. It reserves the right amount of room
/// in SwiftUI while AppKit remains the only authority for button sizes and spacing.
enum BrowserWindowTrafficLightGeometry {
    struct Fallback: Equatable {
        let diameter: CGFloat
        let centerSpacing: CGFloat

        var clusterWidth: CGFloat {
            diameter + centerSpacing * 2
        }
    }

    @MainActor static var learnedClusterWidth: CGFloat?

    @MainActor
    static var resolvedClusterWidth: CGFloat {
        learnedClusterWidth ?? fallback.clusterWidth
    }

    static var fallback: Fallback {
        if #available(macOS 26.0, *) {
            return Fallback(
                diameter: 14,
                centerSpacing: 23
            )
        }
        return Fallback(
            diameter: 12,
            centerSpacing: 20
        )
    }

    static func measuredClusterWidth(fromNativeFrames frames: [CGRect]) -> CGFloat? {
        guard frames.count == 3,
              frames.allSatisfy({ $0.width > 0 && $0.height > 0 })
        else { return nil }

        let firstSpacing = frames[1].midX - frames[0].midX
        let secondSpacing = frames[2].midX - frames[1].midX
        guard firstSpacing > 0, secondSpacing > 0 else { return nil }

        let bounds = frames.reduce(CGRect.null) { $0.union($1) }
        guard !bounds.isNull else { return nil }

        return bounds.width
    }
}

enum BrowserWindowTrafficLightMetrics {
    @MainActor static var clusterWidth: CGFloat {
        BrowserWindowTrafficLightGeometry.resolvedClusterWidth
    }

    static let clusterHeight: CGFloat = 30
    static let clusterTrailingInset: CGFloat = 14
    static let clusterHorizontalOffset: CGFloat = -1

    /// 18pt sidebar padding with the existing 1pt optical correction.
    static let chromeLeading = SidebarChromeMetrics.controlLeadingPadding + clusterHorizontalOffset

    @MainActor static var sidebarReservedWidth: CGFloat { clusterWidth + clusterTrailingInset }

    @MainActor
    static func sidebarReservedWidth(for rendering: BrowserWindowTrafficLightRendering) -> CGFloat {
        rendering.reservesSidebarWidth ? sidebarReservedWidth : 0
    }

    @MainActor
    static var travelDistance: CGFloat {
        sidebarReservedWidth + SidebarChromeMetrics.controlLeadingPadding
    }
}

enum BrowserWindowTrafficLightAction: CaseIterable, Hashable {
    case close
    case minimize
    case zoom

    var buttonType: NSWindow.ButtonType {
        switch self {
        case .close: .closeButton
        case .minimize: .miniaturizeButton
        case .zoom: .zoomButton
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .close: BrowserWindowControlsAccessibilityIdentifiers.closeButton
        case .minimize: BrowserWindowControlsAccessibilityIdentifiers.minimizeButton
        case .zoom: BrowserWindowControlsAccessibilityIdentifiers.zoomButton
        }
    }
}

/// Reserves the visual slot in the sidebar. During travel a cached image rides the sidebar; after
/// it settles, the native titlebar buttons replace that image at the same visual origin.
struct BrowserWindowTrafficLights: View {
    let presentation: BrowserWindowTrafficLightPresentation

    var body: some View {
        Color.clear
            .frame(
                width: BrowserWindowTrafficLightMetrics.sidebarReservedWidth(
                    for: presentation.rendering
                ),
                height: BrowserWindowTrafficLightMetrics.clusterHeight
            )
            .overlay(alignment: .leading) {
                BrowserWindowTrafficLightPlaceholder(rendering: presentation.rendering)
            }
            .offset(x: BrowserWindowTrafficLightMetrics.clusterHorizontalOffset + travelOffset)
            .accessibilityHidden(true)
    }

    private var travelOffset: CGFloat {
        guard presentation.carriesOwnTravel else { return 0 }
        let progress = min(max(presentation.travelProgress, 0), 1)
        return -BrowserWindowTrafficLightMetrics.travelDistance * (1 - progress)
    }
}

private struct BrowserWindowTrafficLightPlaceholder: View {
    let rendering: BrowserWindowTrafficLightRendering
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if rendering.showsPlaceholder {
            Group {
                if let snapshot = BrowserWindowTrafficLightSnapshotStore.snapshot(
                    isKeyWindow: controlActiveState == .key,
                    scale: displayScale
                ) {
                    Image(nsImage: snapshot.image)
                        .frame(width: snapshot.size.width, height: snapshot.size.height)
                        .accessibilityHidden(true)
                }
            }
            .onAppear {
                BrowserWindowTrafficLightSnapshotStore.acquireDemand()
            }
            .onDisappear {
                BrowserWindowTrafficLightSnapshotStore.releaseDemand()
            }
        }
    }
}

/// The single stable SwiftUI/AppKit adapter for a window's native titlebar controls. It is rooted
/// beside `BrowserWindowBridge`, never inside either sidebar host.
@MainActor
struct BrowserWindowTrafficLightPlacementBridge: NSViewRepresentable {
    let state: BrowserWindowTrafficLightPlacementState
    let displayFramesDidElapse: (UInt64) -> Void

    func makeNSView(context _: Context) -> BrowserWindowTrafficLightPlacementView {
        let view = BrowserWindowTrafficLightPlacementView()
        view.update(
            state: state,
            displayFramesDidElapse: displayFramesDidElapse
        )
        return view
    }

    func updateNSView(_ nsView: BrowserWindowTrafficLightPlacementView, context _: Context) {
        nsView.update(
            state: state,
            displayFramesDidElapse: displayFramesDidElapse
        )
    }

    static func dismantleNSView(_ nsView: BrowserWindowTrafficLightPlacementView, coordinator _: Void) {
        nsView.resignPlacement()
    }
}

@MainActor
final class BrowserWindowTrafficLightPlacementView: NSView {
    private var state = BrowserWindowTrafficLightPlacementState(
        rendering: .hidden,
        isLeadingSidebarChrome: false,
        displayFrameRequest: nil
    )
    private var displayFramesDidElapse: ((UInt64) -> Void)?
    private weak var placement: BrowserWindowTrafficLightPlacement?
    private var placementSyncTask: Task<Void, Never>?
    private var displayLink: CADisplayLink?
    private var activeDisplayFrameRequestID: UInt64?
    private var remainingDisplayFrames = 0

    isolated deinit {
        placementSyncTask?.cancel()
        displayLink?.invalidate()
    }

    override var mouseDownCanMoveWindow: Bool { false }

    init() {
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        schedulePlacementSync()
    }

    func update(
        state: BrowserWindowTrafficLightPlacementState,
        displayFramesDidElapse: @escaping (UInt64) -> Void
    ) {
        self.displayFramesDidElapse = displayFramesDidElapse
        guard self.state != state else { return }
        self.state = state
        schedulePlacementSync()
    }

    func resignPlacement() {
        placementSyncTask?.cancel()
        placementSyncTask = nil
        stopDisplayFrameConfirmation()
        placement?.resign()
        placement = nil
    }

    /// `updateNSView` runs inside SwiftUI/AppKit layout. Titlebar geometry must be applied on the
    /// next actor turn or AppKit detects a recursive layout pass.
    private func schedulePlacementSync() {
        placementSyncTask?.cancel()
        placementSyncTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.syncPlacement()
        }
    }

    private func syncPlacement() {
        placementSyncTask = nil
        guard let window else {
            resignPlacement()
            return
        }

        let resolved = window.browserTrafficLightPlacement
        if placement !== resolved {
            placement?.resign()
            placement = resolved
        }
        resolved.apply(
            rendering: state.rendering,
            isLeadingSidebarChrome: state.isLeadingSidebarChrome
        )
        syncDisplayFrameConfirmation(in: window)
    }

    private func syncDisplayFrameConfirmation(in window: NSWindow) {
        guard let request = state.displayFrameRequest else {
            stopDisplayFrameConfirmation()
            return
        }
        guard activeDisplayFrameRequestID != request.id else { return }

        stopDisplayFrameConfirmation()
        guard request.frameCount > 0 else { return }
        let displayLink = window.displayLink(
            target: self,
            selector: #selector(handleDisplayFrame(_:))
        )

        activeDisplayFrameRequestID = request.id
        remainingDisplayFrames = request.frameCount
        self.displayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    private func stopDisplayFrameConfirmation() {
        displayLink?.invalidate()
        displayLink = nil
        activeDisplayFrameRequestID = nil
        remainingDisplayFrames = 0
    }

    @objc
    private func handleDisplayFrame(_ displayLink: CADisplayLink) {
        _ = displayLink
        guard let requestID = activeDisplayFrameRequestID else { return }
        remainingDisplayFrames -= 1
        guard remainingDisplayFrames <= 0 else { return }

        stopDisplayFrameConfirmation()
        displayFramesDidElapse?(requestID)
    }
}

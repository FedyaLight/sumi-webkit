import AppKit
import SwiftUI

enum BrowserWindowControlsAccessibilityIdentifiers {
    static let closeButton = "browser-window-close-button"
    static let minimizeButton = "browser-window-minimize-button"
    static let zoomButton = "browser-window-zoom-button"
}

enum BrowserWindowTrafficLightMetrics {
    static let clusterHeight: CGFloat = 30
    static let clusterTrailingInset: CGFloat = 4
    static let placeholderOpacity: Double = 0.16

    @MainActor
    static var clusterWidth: CGFloat {
        BrowserWindowTrafficLightSnapshotStore.snapshot()?.size.width ?? 0
    }

    @MainActor
    static var sidebarReservedWidth: CGFloat {
        clusterWidth + clusterTrailingInset
    }

    @MainActor
    static func sidebarReservedWidth(for rendering: BrowserWindowTrafficLightRendering) -> CGFloat {
        rendering.reservesSidebarWidth ? sidebarReservedWidth : 0
    }

    static func sidebarReservedWidth(
        for rendering: BrowserWindowTrafficLightRendering,
        clusterWidth: CGFloat
    ) -> CGFloat {
        rendering.reservesSidebarWidth ? clusterWidth + clusterTrailingInset : 0
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

/// A stable sidebar slot containing the permanent inactive system placeholder.
///
/// The slot is part of the sidebar hierarchy, so its pixels inherit docked and collapsed motion
/// without a second progress value or offset animation. The real buttons cover these pixels only
/// while the sidebar has settled at the leading window edge.
struct BrowserWindowTrafficLights: View {
    let presentation: BrowserWindowTrafficLightPresentation

    var body: some View {
        let snapshot = BrowserWindowTrafficLightSnapshotStore.snapshot()
        Color.clear
            .frame(
                width: BrowserWindowTrafficLightMetrics.sidebarReservedWidth(
                    for: presentation.rendering,
                    clusterWidth: snapshot?.size.width ?? 0
                ),
                height: BrowserWindowTrafficLightMetrics.clusterHeight
            )
            .overlay(alignment: .leading) {
                BrowserWindowTrafficLightPlaceholder(
                    snapshot: snapshot,
                    isVisible: presentation.rendering.showsPlaceholder
                )
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

struct BrowserWindowTrafficLightPlaceholderShape: Shape {
    let nativeButtonFrames: [CGRect]

    func path(in _: CGRect) -> Path {
        var path = Path()
        for frame in nativeButtonFrames {
            let diameter = min(frame.width, frame.height)
            path.addEllipse(in: CGRect(
                x: frame.midX - diameter / 2,
                y: frame.midY - diameter / 2,
                width: diameter,
                height: diameter
            ))
        }
        return path
    }
}

private struct BrowserWindowTrafficLightPlaceholder: View {
    let snapshot: BrowserWindowTrafficLightClusterSnapshot?
    let isVisible: Bool
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        if let snapshot {
            BrowserWindowTrafficLightPlaceholderShape(
                nativeButtonFrames: snapshot.buttonFrames
            )
                .fill(Color.primary.opacity(
                    isVisible ? BrowserWindowTrafficLightMetrics.placeholderOpacity : 0
                ))
                .frame(width: snapshot.size.width, height: snapshot.size.height)
                .offset(
                    x: horizontalOffset(for: snapshot),
                    y: snapshot.topInset
                        - (SidebarChromeMetrics.controlStripHeight - snapshot.size.height) / 2
                )
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }

    private func horizontalOffset(
        for snapshot: BrowserWindowTrafficLightClusterSnapshot
    ) -> CGFloat {
        let leadingOffset = snapshot.leadingInset - SidebarChromeMetrics.controlLeadingPadding
        return layoutDirection == .rightToLeft ? -leadingOffset : leadingOffset
    }
}

/// The stable SwiftUI/AppKit adapter for one window's native titlebar controls.
@MainActor
struct BrowserWindowTrafficLightPlacementBridge: NSViewRepresentable {
    let state: BrowserWindowTrafficLightPlacementState

    func makeNSView(context _: Context) -> BrowserWindowTrafficLightPlacementView {
        let view = BrowserWindowTrafficLightPlacementView()
        view.update(state: state)
        return view
    }

    func updateNSView(_ nsView: BrowserWindowTrafficLightPlacementView, context _: Context) {
        nsView.update(state: state)
    }

    static func dismantleNSView(_ nsView: BrowserWindowTrafficLightPlacementView, coordinator _: Void) {
        nsView.resignPlacement()
    }
}

@MainActor
final class BrowserWindowTrafficLightPlacementView: NSView {
    private var state = BrowserWindowTrafficLightPlacementState(
        rendering: .hidden,
        isLeadingSidebarChrome: false
    )
    private weak var placement: BrowserWindowTrafficLightPlacement?
    private var placementSyncTask: Task<Void, Never>?

    isolated deinit {
        placementSyncTask?.cancel()
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

    func update(state: BrowserWindowTrafficLightPlacementState) {
        guard self.state != state else { return }
        self.state = state
        schedulePlacementSync()
    }

    func resignPlacement() {
        placementSyncTask?.cancel()
        placementSyncTask = nil
        placement?.resign()
        placement = nil
    }

    /// `updateNSView` can run during SwiftUI/AppKit layout. Apply visibility on the next actor turn
    /// to avoid entering AppKit's titlebar update recursively.
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
    }
}

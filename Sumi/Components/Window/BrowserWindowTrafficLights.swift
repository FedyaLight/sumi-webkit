import AppKit
import SwiftUI

enum BrowserWindowControlsAccessibilityIdentifiers {
    static let closeButton = "browser-window-close-button"
    static let minimizeButton = "browser-window-minimize-button"
    static let zoomButton = "browser-window-zoom-button"

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
    /// Diameter and pitch come from AppKit's own layout of the live buttons, so the cluster matches
    /// system chrome on every macOS release instead of drifting whenever Apple retunes it.
    @MainActor
    static var buttonDiameter: CGFloat {
        BrowserWindowTrafficLightCustodian.resolvedGeometry.diameter
    }

    @MainActor
    static var buttonCenterSpacing: CGFloat {
        BrowserWindowTrafficLightCustodian.resolvedGeometry.centerSpacing
    }

    @MainActor
    static var buttonSpacing: CGFloat {
        buttonCenterSpacing - buttonDiameter
    }
    static let clusterHeight: CGFloat = 30
    static let clusterTrailingInset: CGFloat = 14
    static let clusterHorizontalOffset: CGFloat = -1

    @MainActor
    static var clusterWidth: CGFloat {
        buttonDiameter * 3 + buttonSpacing * 2
    }

    @MainActor
    static var sidebarReservedWidth: CGFloat {
        clusterWidth + clusterTrailingInset
    }

    @MainActor
    static func sidebarReservedWidth(
        for presentation: BrowserWindowTrafficLightPresentation
    ) -> CGFloat {
        presentation.isAttached ? sidebarReservedWidth : 0
    }
}

/// How the cluster participates in the sidebar's current state.
///
/// The distinction between `attached` and `interactive` is what lets the buttons ride the sidebar's
/// show/hide animation: they stay mounted and move with the panel while it travels, but stop
/// responding the moment the sidebar is no longer usable.
enum BrowserWindowTrafficLightPresentation: Equatable {
    /// The sidebar is not on screen (or the window is fullscreen): custody returns to the titlebar.
    case hidden
    /// The sidebar is on screen but travelling in or out: rendered and moving, not clickable.
    case attached
    /// The sidebar is settled and usable.
    case interactive

    var isAttached: Bool { self != .hidden }
    var isInteractive: Bool { self == .interactive }
}

enum BrowserWindowTrafficLightAction: CaseIterable, Hashable {
    case close
    case minimize
    case zoom

    var buttonType: NSWindow.ButtonType {
        switch self {
        case .close:
            return .closeButton
        case .minimize:
            return .miniaturizeButton
        case .zoom:
            return .zoomButton
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .close:
            return BrowserWindowControlsAccessibilityIdentifiers.closeButton
        case .minimize:
            return BrowserWindowControlsAccessibilityIdentifiers.minimizeButton
        case .zoom:
            return BrowserWindowControlsAccessibilityIdentifiers.zoomButton
        }
    }

}

struct BrowserWindowTrafficLights: View {
    var presentation: BrowserWindowTrafficLightPresentation
    /// 1 while the sidebar is fully extended, 0 once it has fully travelled away. The collapsed
    /// overlay translates its whole panel and therefore leaves this at 1; the docked column is
    /// pinned to the leading edge and clipped from the trailing side, so the cluster has to carry
    /// the travel itself or it would shrink-clip in place instead of sliding out.
    var travelProgress: CGFloat = 1

    init(
        presentation: BrowserWindowTrafficLightPresentation,
        travelProgress: CGFloat = 1
    ) {
        self.presentation = presentation
        self.travelProgress = travelProgress
    }

    var body: some View {
        BrowserWindowStandardTrafficLightCluster(
            presentation: presentation
        )
        .frame(
            width: BrowserWindowTrafficLightMetrics.sidebarReservedWidth(for: presentation),
            height: BrowserWindowTrafficLightMetrics.clusterHeight,
            alignment: .leading
        )
        .offset(x: BrowserWindowTrafficLightMetrics.clusterHorizontalOffset + travelOffset)
        .opacity(presentation.isAttached ? 1 : 0)
        .accessibilityElement(children: .contain)
        .accessibilityHidden(!presentation.isInteractive)
    }

    private var travelOffset: CGFloat {
        guard presentation.isAttached else { return 0 }
        let travelDistance = BrowserWindowTrafficLightMetrics.sidebarReservedWidth
            + SidebarChromeMetrics.controlLeadingPadding
        return -travelDistance * (1 - min(max(travelProgress, 0), 1))
    }
}

@MainActor
private struct BrowserWindowStandardTrafficLightCluster: NSViewRepresentable {
    var presentation: BrowserWindowTrafficLightPresentation

    func makeNSView(context: Context) -> BrowserWindowStandardTrafficLightClusterView {
        let view = BrowserWindowStandardTrafficLightClusterView()
        view.update(presentation: presentation)
        return view
    }

    func updateNSView(_ nsView: BrowserWindowStandardTrafficLightClusterView, context: Context) {
        nsView.update(presentation: presentation)
    }

    static func dismantleNSView(
        _ nsView: BrowserWindowStandardTrafficLightClusterView,
        coordinator: Void
    ) {
        nsView.releaseCustody()
    }
}

// Hosts the window's LIVE standard window buttons (close, minimize, zoom) instead of copies:
// `window.standardWindowButton(_:)` returns "the window button of a given kind in the window's view
// hierarchy", so AppKit keeps driving their active/inactive dimming and hover glyphs for free.
//
// The view owns none of that. Parentage, frames and button state belong to
// `BrowserWindowTrafficLightCustodian`, which is per-window rather than per-view — the sidebar can
// have more than one cluster alive while it swaps between its docked column and collapsed overlay,
// and three shared buttons cannot answer to several views at once. This view only claims custody,
// releases it, and reports its own layout passes.
@MainActor
private final class BrowserWindowStandardTrafficLightClusterView: NSView {
    private var presentation: BrowserWindowTrafficLightPresentation = .hidden
    private var custodian: BrowserWindowTrafficLightCustodian?

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    init() {
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncCustody()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard presentation.isInteractive, isHidden == false else { return nil }

        let hitView = super.hitTest(point)
        return hitView === self ? nil : hitView
    }

    override func layout() {
        super.layout()
        custodian?.enforce(host: self)
    }

    func update(presentation: BrowserWindowTrafficLightPresentation) {
        self.presentation = presentation
        setAccessibilityElement(presentation.isInteractive)
        syncCustody()
    }

    /// Gives the buttons up without touching `presentation`: that is the caller's state, and the
    /// view is asked to release custody while still off-window (SwiftUI configures it before it is
    /// inserted into a hierarchy) long before the caller has changed its mind about presentation.
    func releaseCustody() {
        custodian?.detach(host: self)
        custodian = nil
    }

    private func syncCustody() {
        guard let window else {
            releaseCustody()
            return
        }

        let resolvedCustodian = window.browserTrafficLightCustodian
        if custodian !== resolvedCustodian {
            custodian?.detach(host: self)
            custodian = resolvedCustodian
        }
        resolvedCustodian.attach(
            host: self,
            presentation: presentation
        )
        needsLayout = true
    }
}

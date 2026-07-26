import CoreGraphics

/// Maps sidebar state onto how the traffic-light cluster should present itself.
///
/// The rule the sidebar cares about is "the buttons belong to the panel": they stay mounted for as
/// long as the panel is physically on screen and travel out with it, rather than disappearing the
/// moment the sidebar state flips and leaving the panel to animate away without them.
enum SidebarTrafficLightPresentationPolicy {
    static func presentation(
        isBrowserWindowFullScreen: Bool,
        mode: SidebarPresentationMode,
        isSidebarVisible: Bool,
        overlayUsesTravel: Bool
    ) -> BrowserWindowTrafficLightPresentation {
        guard isBrowserWindowFullScreen == false else { return .hidden }

        switch mode {
        case .docked:
            // The docked column outlives `isSidebarVisible` by the length of its collapse
            // animation, so an invisible sidebar here means "still on screen, on its way out".
            return isSidebarVisible ? .interactive : .attached
        case .collapsedVisible:
            return .interactive
        case .collapsedHidden:
            // With travel the overlay slides the whole panel — and the buttons inside it — off
            // screen. Without it the panel just disappears in place, so there is nothing to ride.
            return overlayUsesTravel ? .attached : .hidden
        }
    }

    /// Only a left-docked column needs the cluster to carry its own travel. The collapsed overlay
    /// translates its entire panel, and a right-docked column is pinned to its trailing edge, so in
    /// both of those cases the container is already moving the cluster. A left-docked column is
    /// pinned to the leading edge and clipped from the trailing side, which would otherwise leave
    /// the cluster standing still while the sidebar collapses around it.
    static func travelProgress(
        mode: SidebarPresentationMode,
        shellEdge: SidebarShellEdge,
        isSidebarVisible: Bool
    ) -> CGFloat {
        guard mode == .docked, shellEdge.isLeft else { return 1 }
        return isSidebarVisible ? 1 : 0
    }
}

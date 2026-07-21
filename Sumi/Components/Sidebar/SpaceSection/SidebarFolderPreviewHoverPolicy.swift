import Foundation

/// Pure hover-transition rules for the collapsed-folder preview.
///
/// Timings match Zen's `zen.folders.search.hover-delay` (500ms) and the 200ms
/// grace its `mouseleave` handler waits before hiding the panel.
enum SidebarFolderPreviewHoverPolicy {
    static let showDelayNanoseconds: UInt64 = 500_000_000
    static let closeGraceNanoseconds: UInt64 = 200_000_000

    /// Conditions under which a hover may open the preview.
    ///
    /// `isSidebarDragging` is Sumi's equivalent of Zen's
    /// `gBrowser.tabContainer.hasAttribute("movingtab")` guard; `isHeaderPressed`
    /// extends it to the press that precedes a drag, so the panel never appears
    /// between the pointer and a folder the user is about to move.
    /// `isTextEntryActive` mirrors Zen's `gURLBar.focused || zen-renaming-tab`
    /// bail-out, since opening focuses the panel's search field.
    static func allowsOpen(
        isSidebarDragging: Bool,
        isHeaderPressed: Bool,
        isTextEntryActive: Bool
    ) -> Bool {
        !isSidebarDragging && !isHeaderPressed && !isTextEntryActive
    }

    /// Whether a hover report may arm the show timer.
    ///
    /// Zen arms inside a real `mouseenter` on `.tab-group-label-container`, and a
    /// folder collapsing does not re-fire that event on the same element. Sumi's
    /// tracking view also reports the hover it infers from the pointer's current
    /// position whenever layout, tracking areas, or the enable flag change —
    /// collapsing a folder under a parked pointer is exactly that — and inferring
    /// a hover-in is not the user performing one.
    static func allowsArmingOpen(hoverSource: SidebarHoverChangeSource) -> Bool {
        hoverSource == .pointer
    }

    /// The panel stays up while the pointer is over either the folder header or
    /// the panel itself — Zen re-checks both `:hover` states after the grace.
    static func shouldStayOpen(
        anchorHovered: Bool,
        panelHovered: Bool
    ) -> Bool {
        anchorHovered || panelHovered
    }
}

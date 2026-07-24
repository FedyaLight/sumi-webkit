//
//  SpaceTabSeparatorVisibility.swift
//  Sumi
//

import CoreGraphics

/// Shared rule for the pinned/regular separator so the live view and the frozen
/// transition snapshot never drift.
enum SpaceTabSeparatorVisibility {
    /// Zen parity (`hide-separator`): the pinned/regular separator shows only
    /// while the space has at least one regular tab, independent of pinned
    /// content. Mirrors Zen counting the normal-tabs container (its new-tab
    /// periphery / empty-tab placeholder are excluded — Sumi's `tabs` array
    /// already excludes the New-Tab affordance row).
    static func shouldShow(regularTabCount: Int) -> Bool {
        regularTabCount > 0
    }
}

/// Shared vertical spacing around the pinned/regular separator. Kept next to the
/// visibility rule so the live view and the transition snapshot compute identical
/// gaps. Zen parity: the last-pinned→New-Tab gap collapses to the row rhythm when
/// the separator is hidden, so the New-Tab button hugs the pinned section.
/// Single owner of the vertical spacing at the pinned↔regular boundary. The
/// regular section applies these; the pinned section contributes nothing, so the
/// gap is deterministic and symmetric. Shared with the transition snapshot so the
/// two bake identical heights.
enum SpaceTabSeparatorLayout {
    /// Visible hairline thickness.
    static let line: CGFloat = 1
    /// Symmetric gap on each side of the line when the separator is shown
    /// (last-pinned→line == line→first-regular). Deliberately larger than the
    /// row rhythm so the line has breathing room.
    static let separatorPadding: CGFloat = 10

    /// Gap between the last pinned row and the separator line (when shown), or the
    /// single gap to the New-Tab button when the line is hidden. Without pinned
    /// content it's zero — the content sits directly under the title.
    static func topPad(hasPinnedContent: Bool, showsSeparator: Bool) -> CGFloat {
        guard hasPinnedContent else { return 0 }
        return showsSeparator ? separatorPadding : SidebarRowLayout.rowGap
    }

    /// Height of the separator line band (0 when hidden, so it collapses fully).
    static func lineHeight(showsSeparator: Bool) -> CGFloat {
        showsSeparator ? line : 0
    }

    /// Gap below the line to the first regular row / New-Tab button.
    static func bottomPad(showsSeparator: Bool) -> CGFloat {
        showsSeparator ? separatorPadding : 0
    }
}

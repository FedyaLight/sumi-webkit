import CoreGraphics
import SumiDomain

/// Resolves keyboard/menu insertion into the same explicit target semantics as
/// pointer drops: the first split creates a group, while later commands split
/// the active pane instead of implicitly cutting the whole group root.
enum SplitInsertionTargetResolver {
    static func target(
        memberID: SplitMemberID,
        side: SplitDropSide,
        memberIsGrouped: Bool
    ) -> SplitDropTarget {
        SplitDropTarget(
            targetMemberID: memberID,
            side: side,
            targetRect: .zero,
            intent: memberIsGrouped ? .siblingEdge : .firstSplit
        )
    }
}

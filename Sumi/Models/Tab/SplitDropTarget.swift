import CoreGraphics
import Foundation
import SumiDomain

enum SplitDropTargetScope: String, Codable, Hashable, Sendable {
    case pane
    case plane
    case group
}

enum SplitDropPreviewStyle: String, Codable, Hashable, Sendable {
    case edge
    case center
}

enum SplitDropTargetIntent: String, Codable, Hashable, Sendable {
    case firstSplit
    case rootEdge
    case planeEdge
    case siblingEdge
    case flatThreePair
    case flatFourPair
    case flatFourReorder
    case mixedThreeOnePair
    case fullGroupPanePair
    case paneCenter
}

/// UI hit-test result expressed entirely in durable split-member identity.
/// Runtime tab IDs are projected only after a structural drop commits.
struct SplitDropTarget: Equatable {
    let targetMemberID: SplitMemberID
    let side: SplitDropSide
    let targetRect: CGRect
    let scope: SplitDropTargetScope
    let previewStyle: SplitDropPreviewStyle
    let planePath: [Int]
    let intent: SplitDropTargetIntent
    let resolvedLayoutTree: SplitLayoutTree?

    init(
        targetMemberID: SplitMemberID,
        side: SplitDropSide,
        targetRect: CGRect,
        scope: SplitDropTargetScope = .pane,
        previewStyle: SplitDropPreviewStyle = .edge,
        planePath: [Int] = [],
        intent: SplitDropTargetIntent? = nil,
        resolvedLayoutTree: SplitLayoutTree? = nil
    ) {
        self.targetMemberID = targetMemberID
        self.side = side
        self.targetRect = targetRect
        self.scope = scope
        self.previewStyle = previewStyle
        self.planePath = planePath
        self.intent = intent ?? {
            switch (scope, previewStyle) {
            case (_, .center):
                return .paneCenter
            case (.group, _):
                return .rootEdge
            case (.plane, _), (.pane, _):
                return .planeEdge
            }
        }()
        self.resolvedLayoutTree = resolvedLayoutTree
    }

    func resolving(
        targetRect: CGRect,
        resolvedLayoutTree: SplitLayoutTree
    ) -> SplitDropTarget {
        SplitDropTarget(
            targetMemberID: targetMemberID,
            side: side,
            targetRect: targetRect,
            scope: scope,
            previewStyle: previewStyle,
            planePath: planePath,
            intent: intent,
            resolvedLayoutTree: resolvedLayoutTree
        )
    }
}

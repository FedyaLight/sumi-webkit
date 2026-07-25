//
//  SidebarDisclosureMotion.swift
//  Sumi
//

import SwiftUI

struct SidebarDisclosureTarget<Item: Hashable>: Equatable {
    let isRevealed: Bool
    let items: [Item]
    let topPadding: CGFloat
    let bottomPadding: CGFloat

    init(
        isRevealed: Bool,
        items: [Item],
        topPadding: CGFloat = 0,
        bottomPadding: CGFloat = 0
    ) {
        self.isRevealed = isRevealed
        self.items = items
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
    }
}

struct SidebarDisclosurePresentation<Item: Hashable> {
    let items: [Item]
    let sourceOrder: [Int]
    let destinationOrder: [Int]
    let sourceTopPadding: CGFloat
    let sourceBottomPadding: CGFloat
    let destinationTopPadding: CGFloat
    let destinationBottomPadding: CGFloat
    let progress: CGFloat

    private let sourceItems: Set<Item>
    private let destinationItems: Set<Item>

    init(
        plan: SidebarDisclosureTrackPlan<Item>,
        sourceTarget: SidebarDisclosureTarget<Item>,
        destinationTarget: SidebarDisclosureTarget<Item>,
        progress: CGFloat
    ) {
        items = plan.items
        sourceOrder = plan.sourceOrder
        destinationOrder = plan.destinationOrder
        sourceTopPadding = sourceTarget.topPadding
        sourceBottomPadding = sourceTarget.bottomPadding
        destinationTopPadding = destinationTarget.topPadding
        destinationBottomPadding = destinationTarget.bottomPadding
        self.progress = progress
        sourceItems = plan.sourceItems
        destinationItems = plan.destinationItems
    }

    func crossfadeOpacity(for item: Item) -> Double {
        let resolvedProgress = Double(min(max(progress, 0), 1))
        switch (
            sourceItems.contains(item),
            destinationItems.contains(item)
        ) {
        case (true, false):
            return 1 - resolvedProgress
        case (false, true):
            return resolvedProgress
        case (true, true):
            return 1
        case (false, false):
            return 0
        }
    }
}

/// Retains both disclosure targets so one stable row identity can move
/// through an interruptible, clipped layout transition.
struct SidebarDisclosureHost<Item: Hashable, Content: View>: View {
    let target: SidebarDisclosureTarget<Item>
    let disclosureAnimation: Animation?
    let layoutAnimation: Animation?
    let content: (
        SidebarDisclosurePresentation<Item>,
        Bool
    ) -> Content

    @State private var requestedTarget: SidebarDisclosureTarget<Item>
    @State private var sourceTarget: SidebarDisclosureTarget<Item>
    @State private var destinationTarget: SidebarDisclosureTarget<Item>
    @State private var trackPlan: SidebarDisclosureTrackPlan<Item>
    @State private var transitionProgress: CGFloat = 0
    @State private var animationTargetProgress: CGFloat = 0
    @State private var isTransitioning = false
    @State private var transitionGeneration: UInt64 = 0

    init(
        target: SidebarDisclosureTarget<Item>,
        disclosureAnimation: Animation?,
        layoutAnimation: Animation?,
        @ViewBuilder content: @escaping (
            SidebarDisclosurePresentation<Item>,
            Bool
        ) -> Content
    ) {
        self.target = target
        self.disclosureAnimation = disclosureAnimation
        self.layoutAnimation = layoutAnimation
        self.content = content
        _requestedTarget = State(initialValue: target)
        _sourceTarget = State(initialValue: target)
        _destinationTarget = State(initialValue: target)
        _trackPlan = State(
            initialValue: SidebarDisclosureTrackPlan.resolve(
                sourceItems: target.items,
                destinationItems: target.items
            )
        )
    }

    var body: some View {
        content(
            SidebarDisclosurePresentation(
                plan: trackPlan,
                sourceTarget: sourceTarget,
                destinationTarget: destinationTarget,
                progress: transitionProgress
            ),
            !isTransitioning
        )
        .allowsHitTesting(!isTransitioning)
        .accessibilityHidden(isTransitioning)
        .onChange(of: target) { _, newTarget in
            updatePresentation(to: newTarget)
        }
    }

    private func updatePresentation(
        to newTarget: SidebarDisclosureTarget<Item>
    ) {
        let revealChanged = newTarget.isRevealed != requestedTarget.isRevealed
        requestedTarget = newTarget

        guard revealChanged || isTransitioning else {
            transitionGeneration &+= 1
            withAnimation(layoutAnimation) {
                sourceTarget = newTarget
                destinationTarget = newTarget
                refreshTrackPlan()
            }
            return
        }

        let destinationProgress: CGFloat = newTarget.isRevealed
            == sourceTarget.isRevealed ? 0 : 1

        if isTransitioning,
           destinationProgress == animationTargetProgress {
            SidebarMotionTransaction.withoutAnimation {
                if destinationProgress == 0 {
                    sourceTarget = newTarget
                } else {
                    destinationTarget = newTarget
                }
                refreshTrackPlan()
            }
            return
        }

        transitionGeneration &+= 1
        let generation = transitionGeneration

        SidebarMotionTransaction.withoutAnimation {
            isTransitioning = true
            animationTargetProgress = destinationProgress
            if destinationProgress == 0 {
                sourceTarget = newTarget
            } else {
                destinationTarget = newTarget
            }
            refreshTrackPlan()
        }

        guard let disclosureAnimation else {
            settle(generation: generation)
            return
        }

        withAnimation(
            disclosureAnimation,
            completionCriteria: .logicallyComplete
        ) {
            transitionProgress = destinationProgress
        } completion: {
            settle(generation: generation)
        }
    }

    private func settle(
        generation: UInt64
    ) {
        guard generation == transitionGeneration else { return }
        let settledTarget = requestedTarget

        SidebarMotionTransaction.withoutAnimation {
            sourceTarget = settledTarget
            destinationTarget = settledTarget
            refreshTrackPlan()
            transitionProgress = 0
            animationTargetProgress = 0
            isTransitioning = false
        }
    }

    private func refreshTrackPlan() {
        trackPlan = SidebarDisclosureTrackPlan.resolve(
            sourceItems: sourceTarget.items,
            destinationItems: destinationTarget.items
        )
    }
}

struct SidebarDisclosureTrackGeometry: Equatable {
    let height: CGFloat
    let itemOffsetsY: [CGFloat]

    static func resolve(
        itemHeights: [CGFloat],
        sourceOrder: [Int],
        destinationOrder: [Int],
        sourceTopPadding: CGFloat = 0,
        sourceBottomPadding: CGFloat = 0,
        destinationTopPadding: CGFloat = 0,
        destinationBottomPadding: CGFloat = 0,
        itemSpacing: CGFloat = 0,
        progress: CGFloat
    ) -> Self {
        let resolvedProgress = min(max(progress, 0), 1)
        let source = offsets(
            itemHeights: itemHeights,
            order: sourceOrder,
            topPadding: sourceTopPadding,
            bottomPadding: sourceBottomPadding,
            itemSpacing: itemSpacing
        )
        let destination = offsets(
            itemHeights: itemHeights,
            order: destinationOrder,
            topPadding: destinationTopPadding,
            bottomPadding: destinationBottomPadding,
            itemSpacing: itemSpacing
        )
        let itemOffsetsY = itemHeights.indices.map { index in
            switch (
                source.itemOffsets[index],
                destination.itemOffsets[index]
            ) {
            case (.some(let sourceOffset), .some(let destinationOffset)):
                return sourceOffset
                    + ((destinationOffset - sourceOffset) * resolvedProgress)
            case (.some(let sourceOffset), .none):
                return sourceOffset - (source.height * resolvedProgress)
            case (.none, .some(let destinationOffset)):
                return destinationOffset
                    - (destination.height * (1 - resolvedProgress))
            case (.none, .none):
                return 0
            }
        }

        return Self(
            height: source.height
                + ((destination.height - source.height) * resolvedProgress),
            itemOffsetsY: itemOffsetsY
        )
    }

    private static func offsets(
        itemHeights: [CGFloat],
        order: [Int],
        topPadding: CGFloat,
        bottomPadding: CGFloat,
        itemSpacing: CGFloat
    ) -> (height: CGFloat, itemOffsets: [CGFloat?]) {
        var cursor = topPadding
        var itemOffsets = Array<CGFloat?>(
            repeating: nil,
            count: itemHeights.count
        )
        for (position, index) in order.enumerated() {
            itemOffsets[index] = cursor
            cursor += itemHeights[index]
            if position < order.count - 1 {
                cursor += itemSpacing
            }
        }
        return (cursor + bottomPadding, itemOffsets)
    }
}

struct SidebarDisclosureTrackPlan<Item: Hashable>: Equatable {
    let items: [Item]
    let sourceOrder: [Int]
    let destinationOrder: [Int]
    fileprivate let sourceItems: Set<Item>
    fileprivate let destinationItems: Set<Item>

    static func resolve(
        sourceItems: [Item],
        destinationItems: [Item]
    ) -> Self {
        var items = sourceItems
        var itemIndices = Dictionary(
            uniqueKeysWithValues: sourceItems.enumerated().map {
                ($0.element, $0.offset)
            }
        )
        for item in destinationItems where itemIndices[item] == nil {
            itemIndices[item] = items.count
            items.append(item)
        }

        return Self(
            items: items,
            sourceOrder: sourceItems.compactMap { itemIndices[$0] },
            destinationOrder: destinationItems.compactMap { itemIndices[$0] },
            sourceItems: Set(sourceItems),
            destinationItems: Set(destinationItems)
        )
    }
}

struct SidebarDisclosureTrackLayout: Layout {
    struct Cache {
        var proposalWidth: CGFloat?
        var sizes: [CGSize] = []
        var geometryKey: GeometryKey?
        var geometry: SidebarDisclosureTrackGeometry?
    }

    struct GeometryKey: Equatable {
        let progress: CGFloat
        let sourceOrder: [Int]
        let destinationOrder: [Int]
        let sourceTopPadding: CGFloat
        let sourceBottomPadding: CGFloat
        let destinationTopPadding: CGFloat
        let destinationBottomPadding: CGFloat
        let itemSpacing: CGFloat
        let itemHeights: [CGFloat]
    }

    var progress: CGFloat
    let sourceOrder: [Int]
    let destinationOrder: [Int]
    let sourceTopPadding: CGFloat
    let sourceBottomPadding: CGFloat
    let destinationTopPadding: CGFloat
    let destinationBottomPadding: CGFloat
    let itemSpacing: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = min(max(newValue, 0), 1) }
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = Cache()
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let sizes = measuredSizes(
            width: proposal.width,
            subviews: subviews,
            cache: &cache
        )
        let geometry = resolvedGeometry(sizes: sizes, cache: &cache)
        return CGSize(
            width: sizes.lazy.map(\.width).max() ?? 0,
            height: geometry.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let sizes = measuredSizes(
            width: bounds.width,
            subviews: subviews,
            cache: &cache
        )
        let geometry = resolvedGeometry(sizes: sizes, cache: &cache)

        for index in subviews.indices {
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX,
                    y: bounds.minY + geometry.itemOffsetsY[index]
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(
                    width: bounds.width,
                    height: sizes[index].height
                )
            )
        }
    }

    private func measuredSizes(
        width: CGFloat?,
        subviews: Subviews,
        cache: inout Cache
    ) -> [CGSize] {
        guard cache.proposalWidth != width
                || cache.sizes.count != subviews.count
        else {
            return cache.sizes
        }

        cache.proposalWidth = width
        cache.sizes = subviews.map {
            $0.sizeThatFits(
                ProposedViewSize(width: width, height: nil)
            )
        }
        cache.geometryKey = nil
        cache.geometry = nil
        return cache.sizes
    }

    private func resolvedGeometry(
        sizes: [CGSize],
        cache: inout Cache
    ) -> SidebarDisclosureTrackGeometry {
        let key = GeometryKey(
            progress: progress,
            sourceOrder: sourceOrder,
            destinationOrder: destinationOrder,
            sourceTopPadding: sourceTopPadding,
            sourceBottomPadding: sourceBottomPadding,
            destinationTopPadding: destinationTopPadding,
            destinationBottomPadding: destinationBottomPadding,
            itemSpacing: itemSpacing,
            itemHeights: sizes.map(\.height)
        )
        if cache.geometryKey == key, let geometry = cache.geometry {
            return geometry
        }

        let geometry = SidebarDisclosureTrackGeometry.resolve(
            itemHeights: key.itemHeights,
            sourceOrder: key.sourceOrder,
            destinationOrder: key.destinationOrder,
            sourceTopPadding: key.sourceTopPadding,
            sourceBottomPadding: key.sourceBottomPadding,
            destinationTopPadding: key.destinationTopPadding,
            destinationBottomPadding: key.destinationBottomPadding,
            itemSpacing: key.itemSpacing,
            progress: key.progress
        )
        cache.geometryKey = key
        cache.geometry = geometry
        return geometry
    }
}

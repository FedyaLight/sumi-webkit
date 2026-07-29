import SwiftUI

/// The structural target for one sidebar track.
///
/// Payload is deliberately excluded from `Structure`: live row metadata may
/// change without starting a structural transition. Callers use
/// `contentRevision` only when the payload's shape changes for the same ID.
struct SidebarListScene<ID: Hashable, Payload> {
    struct Layout: Equatable {
        let id: ID
        let targetExtent: CGFloat
        let targetOpacity: Double
        let overflowBleed: CGFloat
        let contentRevision: AnyHashable
        let placement: PresentedSidebarElementPlacement
    }

    struct Element {
        let layout: Layout
        let payload: Payload

        init(
            id: ID,
            payload: Payload,
            targetExtent: CGFloat,
            targetOpacity: Double = 1,
            overflowBleed: CGFloat = 0,
            contentRevision: AnyHashable = 0,
            placement: PresentedSidebarElementPlacement = .inert
        ) {
            layout = Layout(
                id: id,
                targetExtent: targetExtent,
                targetOpacity: targetOpacity,
                overflowBleed: overflowBleed,
                contentRevision: contentRevision,
                placement: placement
            )
            self.payload = payload
        }

        func addingTrailingExtent(_ extent: CGFloat) -> Self {
            Self(
                id: layout.id,
                payload: payload,
                targetExtent: layout.targetExtent + extent,
                targetOpacity: layout.targetOpacity,
                overflowBleed: layout.overflowBleed,
                contentRevision: layout.contentRevision,
                placement: layout.placement
            )
        }
    }

    struct Structure: Equatable {
        let layouts: [Layout]
    }

    let structure: Structure
    fileprivate let payloadByID: [ID: Payload]

    init(elements: [Element]) {
        let payloadByID = Dictionary(
            uniqueKeysWithValues: elements.map { ($0.layout.id, $0.payload) }
        )
        precondition(
            payloadByID.count == elements.count,
            "Sidebar list element IDs must be unique"
        )

        structure = Structure(layouts: elements.map(\.layout))
        self.payloadByID = payloadByID
    }

    private init(
        structure: Structure,
        payloadByID: [ID: Payload]
    ) {
        self.structure = structure
        self.payloadByID = payloadByID
    }

    /// Gives one target element the source element's presentation identity
    /// for the duration of a container-transfer animation.
    fileprivate func replacingID(_ id: ID, with replacementID: ID) -> Self? {
        guard id != replacementID,
              let payload = payloadByID[id],
              payloadByID[replacementID] == nil else {
            return nil
        }

        var payloads = payloadByID
        payloads[id] = nil
        payloads[replacementID] = payload
        let layouts = structure.layouts.map { layout in
            guard layout.id == id else { return layout }
            return Layout(
                id: replacementID,
                targetExtent: layout.targetExtent,
                targetOpacity: layout.targetOpacity,
                overflowBleed: layout.overflowBleed,
                contentRevision: layout.contentRevision,
                placement: layout.placement
            )
        }
        return Self(
            structure: Structure(layouts: layouts),
            payloadByID: payloads
        )
    }
}

enum SidebarListElementPhase: Equatable {
    case stable
    case entering
    case leaving
}

/// One container transfer in flight. The row a drop retires lends its
/// presentation identity to the row that replaces it, so a move between the
/// pinned and regular sections animates as a slide instead of a collapse in
/// one section and a growth in the other.
struct SidebarListIdentityTransfer<ID: Hashable> {
    /// True only for the row the drop is retiring. Without this the diff
    /// would fuse any coincident removal with any coincident insertion.
    let isSource: (ID) -> Bool
    /// True for rows that may lend or adopt a transferred identity.
    let isTransferable: (ID) -> Bool

    init(
        isSource: @escaping (ID) -> Bool,
        isTransferable: @escaping (ID) -> Bool
    ) {
        self.isSource = isSource
        self.isTransferable = isTransferable
    }
}

/// Owns the transient union of the last rendered scene and the latest target.
/// Browser commands intentionally do not cross this Interface.
struct SidebarListPresentationState<ID: Hashable, Payload> {
    struct Item: Identifiable {
        let id: ID
        var extent: CGFloat
        var opacity: Double
        var overflowBleed: CGFloat
        var phase: SidebarListElementPhase
        var placement: PresentedSidebarElementPlacement
        var reportsAnimatedExtent: Bool
    }

    struct Transition {
        let generation: UInt64
        let target: SidebarListScene<ID, Payload>
        let settledTarget: SidebarListScene<ID, Payload>
    }

    /// A row rendering under another row's identity for the duration of a
    /// container transfer.
    private struct BorrowedIdentity {
        let presented: ID
        let settled: ID
    }

    private(set) var items: [Item]
    private(set) var generation: UInt64 = 0
    private var payloadByID: [ID: Payload]
    private var borrowedIdentity: BorrowedIdentity?

    init(scene: SidebarListScene<ID, Payload>) {
        items = scene.structure.layouts.map {
            Item(
                id: $0.id,
                extent: $0.targetExtent,
                opacity: $0.targetOpacity,
                overflowBleed: $0.overflowBleed,
                phase: .stable,
                placement: $0.placement,
                reportsAnimatedExtent: false
            )
        }
        payloadByID = scene.payloadByID
    }

    func payload(for id: ID) -> Payload {
        guard let payload = payloadByID[id] else {
            preconditionFailure("Presented sidebar item has no payload")
        }
        return payload
    }

    /// Current target metadata wins for identities that still exist; retained
    /// presentation metadata is used only by a row that is leaving.
    func payload(
        for id: ID,
        targeting scene: SidebarListScene<ID, Payload>
    ) -> Payload {
        scene.payloadByID[id] ?? payload(for: id)
    }

    mutating func synchronize(to scene: SidebarListScene<ID, Payload>) {
        generation &+= 1
        borrowedIdentity = nil
        items = scene.structure.layouts.map {
            Item(
                id: $0.id,
                extent: $0.targetExtent,
                opacity: $0.targetOpacity,
                overflowBleed: $0.overflowBleed,
                phase: .stable,
                placement: $0.placement,
                reportsAnimatedExtent: false
            )
        }
        payloadByID = scene.payloadByID
    }

    mutating func prepareTransition(
        to scene: SidebarListScene<ID, Payload>
    ) -> Transition {
        reclaimBorrowedIdentity()
        return prepareTransition(to: scene, settlingTo: scene, borrowing: nil)
    }

    mutating func prepareTransition(
        to scene: SidebarListScene<ID, Payload>,
        transferring transfer: SidebarListIdentityTransfer<ID>
    ) -> Transition {
        reclaimBorrowedIdentity()

        let currentIDs = Set(
            items.lazy
                .filter { $0.phase != .leaving }
                .map(\.id)
                .filter(transfer.isTransferable)
        )
        let targetIDs = Set(
            scene.structure.layouts.lazy
                .map(\.id)
                .filter(transfer.isTransferable)
        )
        let removed = currentIDs.subtracting(targetIDs)
        let inserted = targetIDs.subtracting(currentIDs)

        guard removed.count == 1,
              inserted.count == 1,
              let sourceID = removed.first,
              transfer.isSource(sourceID),
              let targetID = inserted.first,
              let animatedScene = scene.replacingID(
                  targetID,
                  with: sourceID
              ) else {
            return prepareTransition(
                to: scene,
                settlingTo: scene,
                borrowing: nil
            )
        }
        return prepareTransition(
            to: animatedScene,
            settlingTo: scene,
            borrowing: BorrowedIdentity(
                presented: sourceID,
                settled: targetID
            )
        )
    }

    /// Hands a borrowed identity back before the next diff is computed. A
    /// transfer whose settle was superseded would otherwise keep the retired
    /// source's identity on screen, where nothing retires it and the next
    /// transfer adopts it again.
    private mutating func reclaimBorrowedIdentity() {
        guard let borrowed = borrowedIdentity else { return }
        borrowedIdentity = nil
        guard let index = items.firstIndex(
            where: { $0.id == borrowed.presented }
        ) else { return }

        let presented = items[index]
        items[index] = Item(
            id: borrowed.settled,
            extent: presented.extent,
            opacity: presented.opacity,
            overflowBleed: presented.overflowBleed,
            phase: presented.phase,
            placement: presented.placement,
            reportsAnimatedExtent: presented.reportsAnimatedExtent
        )
        if let payload = payloadByID.removeValue(forKey: borrowed.presented) {
            payloadByID[borrowed.settled] = payload
        }
    }

    private mutating func prepareTransition(
        to scene: SidebarListScene<ID, Payload>,
        settlingTo settledScene: SidebarListScene<ID, Payload>,
        borrowing borrowed: BorrowedIdentity?
    ) -> Transition {
        generation &+= 1
        borrowedIdentity = borrowed
        let transition = Transition(
            generation: generation,
            target: scene,
            settledTarget: settledScene
        )
        let targetIDs = Set(scene.structure.layouts.map(\.id))
        let targetByID = Dictionary(
            uniqueKeysWithValues: scene.structure.layouts.map { ($0.id, $0) }
        )

        let staleDepartureIDs = Set(items.compactMap { item in
            item.phase == .leaving && !targetIDs.contains(item.id)
                ? item.id
                : nil
        })
        if !staleDepartureIDs.isEmpty {
            items.removeAll { staleDepartureIDs.contains($0.id) }
            staleDepartureIDs.forEach { payloadByID.removeValue(forKey: $0) }
        }

        for (id, payload) in scene.payloadByID {
            payloadByID[id] = payload
        }

        for index in items.indices {
            guard targetIDs.contains(items[index].id) else {
                items[index].phase = .leaving
                items[index].reportsAnimatedExtent =
                    items[index].reportsAnimatedExtent
                    || items[index].extent != 0
                continue
            }
            if let target = targetByID[items[index].id] {
                items[index].reportsAnimatedExtent =
                    items[index].reportsAnimatedExtent
                    || items[index].extent != target.targetExtent
            }
            if items[index].phase == .leaving {
                items[index].phase = .entering
            }
        }

        // A pure reorder must keep the currently rendered order until the
        // animated phase. Moving these stable identities here would leave
        // SwiftUI with no positional change to interpolate inside
        // `withAnimation`.
        if items.count == targetIDs.count,
           items.allSatisfy({ targetIDs.contains($0.id) }) {
            return transition
        }

        let currentByID = Dictionary(
            uniqueKeysWithValues: items.map { ($0.id, $0) }
        )
        items = Self.merge(
            targetLayouts: scene.structure.layouts,
            previousItems: items
        ) { layout in
            currentByID[layout.id]
                ?? Item(
                    id: layout.id,
                    extent: 0,
                    opacity: 0,
                    overflowBleed: layout.overflowBleed,
                    phase: .entering,
                    placement: layout.placement,
                    reportsAnimatedExtent: layout.targetExtent != 0
                )
        }

        return transition
    }

    mutating func animate(_ transition: Transition) {
        guard transition.generation == generation else { return }

        let targetLayouts = transition.target.structure.layouts
        let currentByID = Dictionary(
            uniqueKeysWithValues: items.map { ($0.id, $0) }
        )
        items = Self.merge(
            targetLayouts: targetLayouts,
            previousItems: items
        ) { layout in
            guard var item = currentByID[layout.id] else { return nil }
            item.extent = layout.targetExtent
            item.opacity = layout.targetOpacity
            item.overflowBleed = layout.overflowBleed
            item.placement = layout.placement
            return item
        } leaving: { item in
            var item = item
            item.extent = 0
            item.opacity = 0
            item.phase = .leaving
            return item
        }
    }

    mutating func settle(_ transition: Transition) {
        guard transition.generation == generation else { return }
        synchronize(to: transition.settledTarget)
    }

    /// Builds the transient union in O(previous + target). Departing rows stay
    /// immediately before their nearest surviving successor, which preserves
    /// visual continuity without repeated searches or array insertions.
    private static func merge(
        targetLayouts: [SidebarListScene<ID, Payload>.Layout],
        previousItems: [Item],
        targetItem: (SidebarListScene<ID, Payload>.Layout) -> Item?,
        leaving: (Item) -> Item = { $0 }
    ) -> [Item] {
        let targetIDs = Set(targetLayouts.map(\.id))
        var departuresBefore: [ID: [Item]] = [:]
        var pendingDepartures: [Item] = []

        for item in previousItems {
            if targetIDs.contains(item.id) {
                if !pendingDepartures.isEmpty {
                    departuresBefore[item.id] = pendingDepartures
                    pendingDepartures.removeAll(keepingCapacity: true)
                }
            } else {
                pendingDepartures.append(leaving(item))
            }
        }

        var result: [Item] = []
        result.reserveCapacity(targetLayouts.count + pendingDepartures.count)
        for layout in targetLayouts {
            if let departures = departuresBefore[layout.id] {
                result.append(contentsOf: departures)
            }
            if let item = targetItem(layout) {
                result.append(item)
            }
        }
        result.append(contentsOf: pendingDepartures)
        return result
    }
}

/// One lazy vertical presentation surface. It owns interruption, animated
/// extents, temporary departing payloads, and logical-completion cleanup.
struct SidebarListSurface<ID: Hashable, Payload, Content: View>: View {
    let scene: SidebarListScene<ID, Payload>
    let animation: Animation?
    let identityTransfer: SidebarListIdentityTransfer<ID>?
    let presentedSpaceID: UUID?
    let geometryGeneration: Int
    @ViewBuilder let content: (
        Payload,
        SidebarListElementPhase
    ) -> Content

    @State private var presentation: SidebarListPresentationState<ID, Payload>
    @State private var presentedGeometryCache =
        SidebarPresentedGeometryCache()
    @EnvironmentObject private var dragGeometry: SidebarDragGeometryModule

    init(
        scene: SidebarListScene<ID, Payload>,
        animation: Animation?,
        identityTransfer: SidebarListIdentityTransfer<ID>? = nil,
        presentedSpaceID: UUID? = nil,
        geometryGeneration: Int = 0,
        @ViewBuilder content: @escaping (
            Payload,
            SidebarListElementPhase
        ) -> Content
    ) {
        self.scene = scene
        self.animation = animation
        self.identityTransfer = identityTransfer
        self.presentedSpaceID = presentedSpaceID
        self.geometryGeneration = geometryGeneration
        self.content = content
        _presentation = State(
            initialValue: SidebarListPresentationState(scene: scene)
        )
    }

    var body: some View {
        let observesPresentedGeometry = presentedSpaceID.map {
            dragGeometry.shouldCollectDetailedGeometry(
                spaceId: $0,
                profileId: nil
            )
        } ?? false

        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(presentation.items) { item in
                SidebarListPresentedElement(
                    item: item,
                    payload: presentation.payload(
                        for: item.id,
                        targeting: scene
                    ),
                    reportsPresentedExtent: observesPresentedGeometry,
                    reportsAnimatedExtent: item.reportsAnimatedExtent,
                    content: content
                )
            }
        }
        .background {
            if observesPresentedGeometry {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: SidebarPresentedGeometryPreference.self,
                        value: .init(
                            rootFrame: proxy.frame(in: .global)
                        )
                    )
                }
            }
        }
        .onPreferenceChange(SidebarPresentedGeometryPreference.self) {
            preference in
            guard observesPresentedGeometry else { return }
            presentedGeometryCache.value = preference
            reportPresentedLayout(preference)
        }
        .onChange(of: scene.structure) { _, _ in
            transitionToCurrentScene()
        }
        .onChange(of: observesPresentedGeometry) { wasObserving, isObserving in
            if wasObserving, !isObserving {
                removePresentedLayout()
            }
        }
    }

    private func transitionToCurrentScene() {
        guard let animation else {
            SidebarMotionTransaction.withoutAnimation {
                presentation.synchronize(to: scene)
            }
            reportPresentedLayout(presentedGeometryCache.value)
            return
        }

        let transition: SidebarListPresentationState<ID, Payload>.Transition =
            SidebarMotionTransaction.withoutAnimation {
                if let identityTransfer {
                    presentation.prepareTransition(
                        to: scene,
                        transferring: identityTransfer
                    )
                } else {
                    presentation.prepareTransition(to: scene)
                }
            }

        withAnimation(
            animation,
            completionCriteria: .logicallyComplete
        ) {
            presentation.animate(transition)
        } completion: {
            SidebarMotionTransaction.withoutAnimation {
                presentation.settle(transition)
            }
        }
        reportPresentedLayout(presentedGeometryCache.value)
    }

    private func reportPresentedLayout(
        _ preference: SidebarPresentedGeometryPreference.Value
    ) {
        guard let spaceID = presentedSpaceID,
              dragGeometry.shouldCollectDetailedGeometry(
                  spaceId: spaceID,
                  profileId: nil
              ),
              let rootFrame = preference.rootFrame else {
            return
        }

        let items = presentation.items.map { item in
            PresentedSidebarLayout.Item(
                extent: preference.extents[AnyHashable(item.id)]
                    ?? item.extent,
                phase: item.phase,
                placement: item.placement
            )
        }
        dragGeometry.report(
            .presentedSpaceList(
                PresentedSidebarLayout.resolve(
                    spaceID: spaceID,
                    rootFrame: rootFrame,
                    items: items
                )
            ),
            generation: geometryGeneration
        )
    }

    private func removePresentedLayout() {
        guard let spaceID = presentedSpaceID else { return }
        presentedGeometryCache.value = .init()
        dragGeometry.report(
            .removePresentedSpaceList(spaceID: spaceID),
            generation: geometryGeneration
        )
    }
}

private struct SidebarListPresentedElement<
    ID: Hashable,
    Payload,
    Content: View
>: View {
    let item: SidebarListPresentationState<ID, Payload>.Item
    let payload: Payload
    let reportsPresentedExtent: Bool
    let reportsAnimatedExtent: Bool
    @ViewBuilder let content: (
        Payload,
        SidebarListElementPhase
    ) -> Content

    var body: some View {
        VStack(spacing: 0) {
            content(payload, item.phase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(item.opacity)
        .modifier(
            SidebarPresentedExtentReporter(
                id: AnyHashable(item.id),
                extent: item.extent,
                isEnabled: reportsPresentedExtent && reportsAnimatedExtent
            )
        )
        .clipShape(
            SidebarListVerticalOverflowClipShape(
                verticalBleed: item.overflowBleed
            )
        )
        .allowsHitTesting(item.phase == .stable)
        .accessibilityHidden(item.phase != .stable)
    }
}

private struct SidebarPresentedExtentReporter: @preconcurrency AnimatableModifier {
    let id: AnyHashable
    var extent: CGFloat
    let isEnabled: Bool

    var animatableData: CGFloat {
        get { extent }
        set { extent = newValue }
    }

    func body(content: Content) -> some View {
        content
            .frame(height: max(extent, 0), alignment: .top)
            .background {
                if isEnabled {
                    Color.clear.preference(
                        key: SidebarPresentedGeometryPreference.self,
                        value: .init(
                            extents: [id: max(extent, 0)]
                        )
                    )
                }
            }
    }
}

@MainActor
private final class SidebarPresentedGeometryCache {
    var value = SidebarPresentedGeometryPreference.Value()
}

private enum SidebarPresentedGeometryPreference: PreferenceKey {
    struct Value: Equatable, @unchecked Sendable {
        var rootFrame: CGRect?
        var extents: [AnyHashable: CGFloat] = [:]
    }

    static let defaultValue = Value()

    static func reduce(value: inout Value, nextValue: () -> Value) {
        let next = nextValue()
        if let rootFrame = next.rootFrame {
            value.rootFrame = rootFrame
        }
        value.extents.merge(next.extents) { _, new in new }
    }
}

private struct SidebarListVerticalOverflowClipShape: Shape {
    let verticalBleed: CGFloat

    func path(in rect: CGRect) -> Path {
        // Keep clipping vertical animation overflow without constraining row content horizontally.
        let horizontalOverflow = max(rect.width, 1)

        return Path(
            CGRect(
                x: rect.minX - horizontalOverflow,
                y: rect.minY - verticalBleed,
                width: rect.width + (horizontalOverflow * 2),
                height: rect.height + (verticalBleed * 2)
            )
        )
    }
}

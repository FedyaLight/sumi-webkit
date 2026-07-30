import SwiftUI

struct SidebarListSurface<ID: Hashable, Payload, Content: View>: View {
    let scene: SidebarListScene<ID, Payload>
    let animation: Animation?
    let identityTransfer: SidebarListIdentityTransfer<ID>?
    let presentedSpaceID: UUID?
    let geometryGeneration: Int
    let autofocusTarget: (ID) -> SidebarScrollTargetID?
    @ViewBuilder let content: (
        Payload,
        SidebarListElementPhase
    ) -> Content

    @State private var presentation: SidebarListPresentationState<ID, Payload>
    @State private var presentedGeometryCache =
        SidebarPresentedGeometryCache()
    @EnvironmentObject private var dragGeometry: SidebarDragGeometryModule
    @Environment(\.sidebarSelectedItemRevealOwner) private var revealOwner

    init(
        scene: SidebarListScene<ID, Payload>,
        animation: Animation?,
        identityTransfer: SidebarListIdentityTransfer<ID>? = nil,
        presentedSpaceID: UUID? = nil,
        geometryGeneration: Int = 0,
        autofocusTarget: @escaping (ID) -> SidebarScrollTargetID? = {
            _ in nil
        },
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
        self.autofocusTarget = autofocusTarget
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
        .onAppear {
            publishAutofocusLayout()
        }
        .onChange(of: observesPresentedGeometry) { wasObserving, isObserving in
            if wasObserving, !isObserving {
                removePresentedLayout()
            }
        }
    }

    /// Resolves row coordinates from the same ordered extents that drive the
    /// LazyVStack. Callers invoke this only at presentation lifecycle edges;
    /// scrolling itself produces no row work or environment updates.
    private func publishAutofocusLayout() {
        guard let revealOwner else { return }

        var minY: CGFloat = 0
        var targets: [
            SidebarScrollTargetID: SidebarAutofocusLayout.Target
        ] = [:]

        for item in presentation.items {
            let extent = max(item.extent, 0)
            defer { minY += extent }
            guard item.phase != .leaving,
                  let targetID = autofocusTarget(item.id) else {
                continue
            }

            let previous = targets.updateValue(
                .init(
                    minY: minY,
                    maxY: minY + min(extent, SidebarRowLayout.rowHeight)
                ),
                forKey: targetID
            )
            precondition(
                previous == nil,
                "Sidebar autofocus target IDs must be unique"
            )
        }

        revealOwner.updateAutofocusLayout(
            SidebarAutofocusLayout(
                targets: targets
            )
        )
    }

    private func transitionToCurrentScene() {
        guard let animation else {
            SidebarMotionTransaction.withoutAnimation {
                presentation.synchronize(to: scene)
            }
            publishAutofocusLayout()
            reportPresentedLayout(presentedGeometryCache.value)
            return
        }

        revealOwner?.updateAutofocusLayout(nil)

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
            publishAutofocusLayout()
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
    /// Keeps semantic zero-extent markers visible to `LazyVStack` materialization.
    private static let materializationFloor = CGFloat.ulpOfOne

    let id: AnyHashable
    var extent: CGFloat
    let isEnabled: Bool

    var animatableData: CGFloat {
        get { extent }
        set { extent = newValue }
    }

    func body(content: Content) -> some View {
        content
            .frame(
                height: max(extent, Self.materializationFloor),
                alignment: .top
            )
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

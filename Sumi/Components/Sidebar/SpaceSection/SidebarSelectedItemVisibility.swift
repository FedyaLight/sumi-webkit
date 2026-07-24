import AppKit
import Observation
import SwiftUI

/// Stable identity for one direct lazy-list scroll target. Folder targets let
/// a reveal progress through unmaterialized nested lists before reaching the
/// selected visual row.
enum SidebarScrollTargetID: Hashable {
    case folder(UUID)
    case regularTab(UUID)
    case launcher(UUID)
    case splitGroup(UUID)
    case liveFolderItem(folderID: UUID, itemID: String)
}

struct SidebarSelectedItemRevealPath: Equatable {
    let targets: [SidebarScrollTargetID]

    init(_ targets: [SidebarScrollTargetID]) {
        precondition(!targets.isEmpty)
        self.targets = targets
    }
}

/// Publishes selection and hover as repeatable reveal requests. The scroll
/// surface resolves them through SwiftUI's identity-aware lazy-list path.
@MainActor
@Observable
final class SidebarSelectedItemRevealOwner {
    struct Request: Equatable {
        enum Purpose: Equatable {
            case materializePath
            case revealSelection
        }

        let targetID: SidebarScrollTargetID
        let purpose: Purpose
        let generation: Int
    }

    private(set) var request: Request?
    @ObservationIgnored private var nextGeneration = 0
    @ObservationIgnored private(set) var isSurfaceReady = false
    @ObservationIgnored private var mountedTargets: Set<SidebarScrollTargetID> = []
    @ObservationIgnored private var pendingTargets: [SidebarScrollTargetID] = []

    func reveal(_ targetID: SidebarScrollTargetID) {
        reveal(SidebarSelectedItemRevealPath([targetID]))
    }

    func reveal(_ path: SidebarSelectedItemRevealPath) {
        pendingTargets = path.targets
        advanceReveal()
    }

    func cancelReveal() {
        pendingTargets.removeAll()
    }

    func surfaceDidBecomeReady() {
        guard !isSurfaceReady else { return }
        isSurfaceReady = true
        advanceReveal()
    }

    func targetDidAppear(_ targetID: SidebarScrollTargetID) {
        mountedTargets.insert(targetID)
        guard isSurfaceReady else { return }
        guard pendingTargets.first == targetID else { return }
        pendingTargets.removeFirst()
        advanceReveal()
    }

    func targetDidDisappear(_ targetID: SidebarScrollTargetID) {
        mountedTargets.remove(targetID)
    }

    private func advanceReveal() {
        guard isSurfaceReady else { return }

        while pendingTargets.count > 1,
              let targetID = pendingTargets.first,
              mountedTargets.contains(targetID) {
            pendingTargets.removeFirst()
        }

        guard let targetID = pendingTargets.first else { return }
        let purpose: Request.Purpose
        if pendingTargets.count == 1 {
            pendingTargets.removeAll()
            purpose = .revealSelection
        } else {
            purpose = .materializePath
        }
        nextGeneration &+= 1
        request = Request(
            targetID: targetID,
            purpose: purpose,
            generation: nextGeneration
        )
    }
}

extension EnvironmentValues {
    @Entry var sidebarSelectedItemRevealOwner: SidebarSelectedItemRevealOwner?
}

private struct SidebarSelectedItemSelectionRequest: Equatable {
    let revealPath: SidebarSelectedItemRevealPath?
    let selection: SidebarWindowSelectionSnapshot
    let isEnabled: Bool
}

private struct SidebarSelectedItemSurfaceGeometry: Equatable {
    let contentOffsetY: CGFloat
    let viewportHeight: CGFloat
    let contentHeight: CGFloat

    var hasUsableLayout: Bool {
        viewportHeight > 0 && contentHeight > 0
    }

    var maximumOffset: CGFloat {
        max(contentHeight - viewportHeight, 0)
    }

    var scrollViewport: SpaceSidebarSnapshotViewport {
        SpaceSidebarSnapshotViewport(
            contentOffsetY: contentOffsetY,
            contentHeight: contentHeight,
            viewportHeight: viewportHeight
        )
    }
}

private enum SidebarScrollRestorationTarget: Equatable {
    case automatic
    case top
    case bottom
    case point(CGFloat)

    init(viewport: SpaceSidebarSnapshotViewport?) {
        guard let viewport else {
            self = .automatic
            return
        }

        let offset = viewport.clampedOffset()
        let maximumOffset = max(
            viewport.contentHeight - viewport.viewportHeight,
            0
        )
        let tolerance: CGFloat = 1
        if offset <= tolerance {
            self = .top
        } else if maximumOffset - offset <= tolerance {
            self = .bottom
        } else {
            self = .point(offset)
        }
    }

    var initialScrollPosition: ScrollPosition {
        switch self {
        case .automatic:
            ScrollPosition(idType: SidebarScrollTargetID.self)
        case .top, .bottom, .point:
            ScrollPosition(
                idType: SidebarScrollTargetID.self,
                edge: .top
            )
        }
    }

    func matches(_ geometry: SidebarSelectedItemSurfaceGeometry) -> Bool {
        guard geometry.hasUsableLayout else { return false }
        let tolerance: CGFloat = 1

        switch self {
        case .automatic:
            return true
        case .top:
            return abs(geometry.contentOffsetY) <= tolerance
        case .bottom:
            return abs(geometry.contentOffsetY - geometry.maximumOffset) <= tolerance
        case .point(let offset):
            let reachableOffset = min(offset, geometry.maximumOffset)
            return abs(geometry.contentOffsetY - reachableOffset) <= tolerance
        }
    }
}

/// Owns programmatic scrolling for one sidebar scroll surface. Saved viewport
/// intent is applied to the first usable layout and clamped to its reachable
/// extent; identity scrolling then reveals rows with nearest-edge semantics.
struct SidebarSelectedItemVisibilityScope<Content: View>: View {
    let revealPath: SidebarSelectedItemRevealPath?
    let selection: SidebarWindowSelectionSnapshot
    let isEnabled: Bool
    let motionMode: SidebarMotionPolicy.Mode
    let onCommittedViewportChange: (SpaceSidebarSnapshotViewport) -> Void
    @ViewBuilder let content: () -> Content

    @State private var revealOwner = SidebarSelectedItemRevealOwner()
    @State private var scrollPosition: ScrollPosition
    @State private var restoredSurfaceReceipt: SidebarSelectedItemSurfaceGeometry?
    @State private var didRequestDeferredRestoration = false
    @State private var restorationTarget: SidebarScrollRestorationTarget

    init(
        revealPath: SidebarSelectedItemRevealPath?,
        selection: SidebarWindowSelectionSnapshot,
        isEnabled: Bool,
        motionMode: SidebarMotionPolicy.Mode,
        restoredViewport: SpaceSidebarSnapshotViewport?,
        onCommittedViewportChange: @escaping (SpaceSidebarSnapshotViewport) -> Void = { _ in },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.revealPath = revealPath
        self.selection = selection
        self.isEnabled = isEnabled
        self.motionMode = motionMode
        self.onCommittedViewportChange = onCommittedViewportChange
        self.content = content
        let restorationTarget = SidebarScrollRestorationTarget(
            viewport: restoredViewport
        )
        _restorationTarget = State(initialValue: restorationTarget)
        _scrollPosition = State(
            initialValue: restorationTarget.initialScrollPosition
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            content()
                .scrollPosition($scrollPosition)
                .environment(\.sidebarSelectedItemRevealOwner, revealOwner)
                .onScrollGeometryChange(
                    for: SidebarSelectedItemSurfaceGeometry.self
                ) { geometry in
                    SidebarSelectedItemSurfaceGeometry(
                        contentOffsetY: geometry.contentOffset.y,
                        viewportHeight: geometry.visibleRect.height,
                        contentHeight: geometry.contentSize.height
                    )
                } action: { _, geometry in
                    guard isEnabled else { return }
                    if revealOwner.isSurfaceReady {
                        onCommittedViewportChange(geometry.scrollViewport)
                        return
                    }
                    if !didRequestDeferredRestoration {
                        switch restorationTarget {
                        case .bottom:
                            guard geometry.hasUsableLayout else { return }
                            didRequestDeferredRestoration = true
                            scrollPosition.scrollTo(edge: .bottom)
                            restoredSurfaceReceipt = nil
                            return
                        case .point(let offset):
                            guard geometry.hasUsableLayout else { return }
                            didRequestDeferredRestoration = true
                            scrollPosition.scrollTo(y: offset)
                            restoredSurfaceReceipt = nil
                            return
                        case .automatic, .top:
                            break
                        }
                    }
                    restoredSurfaceReceipt = restorationTarget.matches(geometry)
                        ? geometry
                        : nil
                }
                .task(id: restoredSurfaceReceipt) {
                    guard isEnabled, restoredSurfaceReceipt != nil else {
                        return
                    }

                    // The receipt comes from post-layout scroll geometry. A
                    // new actor turn lets that restored frame commit before
                    // the pending reveal starts its animation transaction.
                    await Task.yield()
                    guard !Task.isCancelled, isEnabled else { return }
                    revealOwner.surfaceDidBecomeReady()
                    if let restoredSurfaceReceipt {
                        onCommittedViewportChange(
                            restoredSurfaceReceipt.scrollViewport
                        )
                    }
                }
                .task(id: selectionRequest) {
                    guard isEnabled, let revealPath else {
                        revealOwner.cancelReveal()
                        return
                    }
                    revealOwner.reveal(revealPath)
                }
                .onChange(of: revealOwner.request) { _, request in
                    guard isEnabled, let request else { return }
                    reveal(request, with: proxy)
                }
        }
    }

    private var selectionRequest: SidebarSelectedItemSelectionRequest {
        SidebarSelectedItemSelectionRequest(
            revealPath: revealPath,
            selection: selection,
            isEnabled: isEnabled
        )
    }

    /// Path materialization is layout work; only the final selected target gets
    /// the user-visible nearest-edge animation.
    private func reveal(
        _ request: SidebarSelectedItemRevealOwner.Request,
        with proxy: ScrollViewProxy
    ) {
        let animation = request.purpose == .revealSelection
            ? SidebarMotionPolicy.selectedItemRevealAnimation(for: motionMode)
            : nil
        if let animation {
            withAnimation(animation) {
                proxy.scrollTo(request.targetID)
            }
        } else {
            proxy.scrollTo(request.targetID)
        }
    }
}

private struct SidebarSelectedItemVisibilityModifier: ViewModifier {
    let itemID: SidebarScrollTargetID
    let isSelected: Bool
    let isEnabled: Bool

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sidebarPresentationContext) private var presentationContext
    @Environment(\.sidebarSelectedItemRevealOwner) private var revealOwner

    private var installsSelectedHoverRegion: Bool {
        isSelected && isEnabled && presentationContext.allowsInteractiveWork
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if installsSelectedHoverRegion {
                    SidebarSelectedItemHoverRevealBridge(
                        session: windowState.sidebarInteractionState.hoverSession,
                        itemID: itemID,
                        revealOwner: revealOwner
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
    }
}

extension View {
    func sidebarSelectedItemVisibility(
        _ itemID: SidebarScrollTargetID,
        isSelected: Bool,
        isEnabled: Bool
    ) -> some View {
        modifier(
            SidebarSelectedItemVisibilityModifier(
                itemID: itemID,
                isSelected: isSelected,
                isEnabled: isEnabled
            )
        )
    }
}

private struct SidebarScrollTargetModifier: ViewModifier {
    let targetID: SidebarScrollTargetID

    @Environment(\.sidebarSelectedItemRevealOwner) private var revealOwner

    func body(content: Content) -> some View {
        content
            .id(targetID)
            .onAppear {
                revealOwner?.targetDidAppear(targetID)
            }
            .onDisappear {
                revealOwner?.targetDidDisappear(targetID)
            }
    }
}

extension View {
    /// Must be installed on the direct child emitted by a LazyVStack. An ID
    /// nested inside that child cannot materialize the slot while off-screen,
    /// and SwiftUI reveals this outermost frame — not one nested inside it.
    func sidebarScrollTarget(_ targetID: SidebarScrollTargetID) -> some View {
        modifier(SidebarScrollTargetModifier(targetID: targetID))
    }
}

private struct SidebarSelectedItemHoverRevealBridge: NSViewRepresentable {
    let session: SidebarHoverSession
    let itemID: SidebarScrollTargetID
    let revealOwner: SidebarSelectedItemRevealOwner?

    func makeCoordinator() -> SidebarSelectedItemHoverRevealCoordinator {
        SidebarSelectedItemHoverRevealCoordinator()
    }

    func makeNSView(context: Context) -> SidebarHoverTrackingView {
        let view = SidebarHoverTrackingView(frame: .zero)
        context.coordinator.update(
            view: view,
            session: session,
            itemID: itemID,
            revealOwner: revealOwner
        )
        return view
    }

    func updateNSView(
        _ nsView: SidebarHoverTrackingView,
        context: Context
    ) {
        context.coordinator.update(
            view: nsView,
            session: session,
            itemID: itemID,
            revealOwner: revealOwner
        )
    }

    static func dismantleNSView(
        _ nsView: SidebarHoverTrackingView,
        coordinator: SidebarSelectedItemHoverRevealCoordinator
    ) {
        coordinator.detach()
    }
}

@MainActor
final class SidebarSelectedItemHoverRevealCoordinator {
    private let hoverRegistration = SidebarHoverRegistration()

    func update(
        view: SidebarHoverTrackingView,
        session: SidebarHoverSession,
        itemID: SidebarScrollTargetID,
        revealOwner: SidebarSelectedItemRevealOwner?
    ) {
        hoverRegistration.update(
            view: view,
            session: session,
            isEnabled: revealOwner != nil
        ) { [weak revealOwner] isHovering, _ in
            if isHovering {
                revealOwner?.reveal(itemID)
            }
        }
    }

    func detach() {
        hoverRegistration.disconnect()
    }
}

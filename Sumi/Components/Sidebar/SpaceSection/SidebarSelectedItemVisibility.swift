import AppKit
import Observation
import SwiftUI

/// Semantic identity of one selectable row in the sidebar's visual scene.
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

/// Settled, scroll-content-local geometry produced by the unified list.
/// Its absence withholds autofocus during an in-flight reflow.
struct SidebarAutofocusLayout: Equatable {
    struct Target: Equatable {
        let minY: CGFloat
        let maxY: CGFloat
    }

    let targets: [SidebarScrollTargetID: Target]
    let contentHeight: CGFloat
}

struct SidebarSelectedItemSurfaceGeometry: Equatable {
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

private extension SidebarAutofocusLayout.Target {
    /// Uses the nearest edge and preserves one full row gap beside it, keeping
    /// the selected row shadow clear of the viewport clip.
    func revealOffset(
        in geometry: SidebarSelectedItemSurfaceGeometry
    ) -> CGFloat? {
        guard geometry.hasUsableLayout else { return nil }

        let tolerance: CGFloat = 0.5
        let currentOffset = min(
            max(geometry.contentOffsetY, 0),
            geometry.maximumOffset
        )
        let revealInset = SidebarRowLayout.rowGap
        let preferredTop = max(minY - revealInset, 0)
        if preferredTop < currentOffset - tolerance {
            return min(preferredTop, geometry.maximumOffset)
        }

        let visibleMaxY = currentOffset + geometry.viewportHeight
        let preferredBottom = min(
            maxY + revealInset,
            geometry.contentHeight
        )
        if preferredBottom > visibleMaxY + tolerance {
            return min(
                max(preferredBottom - geometry.viewportHeight, 0),
                geometry.maximumOffset
            )
        }

        return nil
    }
}

/// Resolves selection and hover into repeatable scroll commands. The unified
/// sidebar emits one exact offset from settled presentation geometry. Identity
/// resolution remains available to small standalone lazy-list surfaces.
@MainActor
@Observable
final class SidebarSelectedItemRevealOwner {
    enum TargetResolution: Equatable {
        case lazyIdentity
        case presentedLayout
    }

    struct Request: Equatable {
        enum Purpose: Equatable {
            case materializePath
            case revealSelection
        }

        let targetID: SidebarScrollTargetID
        let purpose: Purpose
        let destinationY: CGFloat?
        let generation: Int
    }

    private(set) var request: Request?
    @ObservationIgnored private let targetResolution: TargetResolution
    @ObservationIgnored private var nextGeneration = 0
    private(set) var isSurfaceReady = false
    @ObservationIgnored private var mountedTargets: Set<SidebarScrollTargetID> = []
    @ObservationIgnored private var pendingTargets: [SidebarScrollTargetID] = []
    @ObservationIgnored private var autofocusLayout: SidebarAutofocusLayout?
    @ObservationIgnored private var surfaceGeometry:
        SidebarSelectedItemSurfaceGeometry?

    init(targetResolution: TargetResolution = .lazyIdentity) {
        self.targetResolution = targetResolution
    }

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

    func updateAutofocusLayout(_ layout: SidebarAutofocusLayout?) {
        guard targetResolution == .presentedLayout else { return }
        guard autofocusLayout != layout else { return }
        autofocusLayout = layout
        advanceReveal()
    }

    func updateSurfaceGeometry(
        _ geometry: SidebarSelectedItemSurfaceGeometry
    ) {
        surfaceGeometry = geometry
        guard !pendingTargets.isEmpty else { return }
        advanceReveal()
    }

    func targetDidAppear(_ targetID: SidebarScrollTargetID) {
        guard targetResolution == .lazyIdentity else { return }
        mountedTargets.insert(targetID)
        guard isSurfaceReady, pendingTargets.first == targetID else { return }
        pendingTargets.removeFirst()
        advanceReveal()
    }

    func targetDidDisappear(_ targetID: SidebarScrollTargetID) {
        guard targetResolution == .lazyIdentity else { return }
        mountedTargets.remove(targetID)
    }

    private func advanceReveal() {
        guard isSurfaceReady else { return }

        switch targetResolution {
        case .lazyIdentity:
            advanceIdentityReveal()
        case .presentedLayout:
            advancePresentedLayoutReveal()
        }
    }

    private func advanceIdentityReveal() {
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
            destinationY: nil,
            generation: nextGeneration
        )
    }

    private func advancePresentedLayoutReveal() {
        guard let autofocusLayout,
              let targetID = pendingTargets.last,
              let target = autofocusLayout.targets[targetID],
              let surfaceGeometry,
              surfaceGeometry.contentHeight + 1
                >= autofocusLayout.contentHeight else {
            return
        }

        pendingTargets.removeAll()
        guard let destinationY = target.revealOffset(
            in: surfaceGeometry
        ) else {
            return
        }

        nextGeneration &+= 1
        request = Request(
            targetID: targetID,
            purpose: .revealSelection,
            destinationY: destinationY,
            generation: nextGeneration
        )
    }
}

extension EnvironmentValues {
    @Entry var sidebarSelectedItemRevealOwner: SidebarSelectedItemRevealOwner?
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
        content.overlay {
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
    /// Install on the direct child emitted by a LazyVStack so SwiftUI can
    /// materialize and reveal the full off-screen slot.
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

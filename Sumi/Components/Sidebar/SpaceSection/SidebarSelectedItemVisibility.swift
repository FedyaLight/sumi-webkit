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

extension SidebarAutofocusLayout.Target {
    /// Why one reveal evaluation produced no scroll command. The distinction
    /// decides whether pending reveal intent may be discarded: unusable facts
    /// keep the intent alive, a genuinely visible target consumes it.
    enum Disposition: Equatable {
        case unusableGeometry
        case alreadyVisible
        case reveal(destinationY: CGFloat)
    }

    /// Uses the nearest edge and preserves one full row gap beside it, keeping
    /// the selected row shadow clear of the viewport clip.
    func revealDisposition(
        in geometry: SidebarSelectedItemSurfaceGeometry
    ) -> Disposition {
        guard geometry.hasUsableLayout else { return .unusableGeometry }

        let tolerance: CGFloat = 0.5
        let currentOffset = min(
            max(geometry.contentOffsetY, 0),
            geometry.maximumOffset
        )
        let revealInset = SidebarRowLayout.rowGap
        let preferredTop = max(minY - revealInset, 0)
        if preferredTop < currentOffset - tolerance {
            return .reveal(
                destinationY: min(preferredTop, geometry.maximumOffset)
            )
        }

        let visibleMaxY = currentOffset + geometry.viewportHeight
        let targetFitsDocument = maxY <= geometry.contentHeight + tolerance
        let preferredBottom = min(
            maxY + revealInset,
            geometry.contentHeight
        )
        if preferredBottom > visibleMaxY + tolerance {
            return .reveal(
                destinationY: min(
                    max(preferredBottom - geometry.viewportHeight, 0),
                    geometry.maximumOffset
                )
            )
        }

        // Reaching the temporary native document edge does not prove that a
        // farther lazy row is visible. Keep the intent live for later growth.
        guard targetFitsDocument else { return .unusableGeometry }
        return .alreadyVisible
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
            /// Re-anchoring after an explicit relayout signal; always instant.
            case relayoutAdjustment

            var usesSelectionAnimation: Bool {
                self == .revealSelection
            }
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
    @ObservationIgnored private var pendingPurpose: Request.Purpose =
        .revealSelection
    @ObservationIgnored private var autofocusLayout: SidebarAutofocusLayout?
    @ObservationIgnored private var surfaceGeometry:
        SidebarSelectedItemSurfaceGeometry?
    private struct IssuedReveal {
        let targetID: SidebarScrollTargetID
        let purpose: Request.Purpose
        let contentHeight: CGFloat
        let maximumOffset: CGFloat
        let remainingReachabilityCorrections: Int
    }

    /// The command most recently issued against native geometry. It remains
    /// live until fresh geometry confirms that the target is visible.
    @ObservationIgnored private var issuedReveal: IssuedReveal?
    /// Prevents a resize animation from publishing a command on every frame.
    /// Real document growth replenishes the budget because it represents new
    /// lazy content rather than repeated work against the same document.
    private static let maximumReachabilityCorrections = 3
    /// Returns the freshest native scroll geometry without waiting for the
    /// coalesced delivery hop, mirroring Zen's read-layout-right-before-scroll.
    @ObservationIgnored private var geometryProvider:
        (@MainActor () -> SidebarSelectedItemSurfaceGeometry?)?
    /// Retained so viewport resize and fullscreen changes can re-run the last
    /// selection reveal without a new activation.
    @ObservationIgnored private var lastRevealPath: SidebarSelectedItemRevealPath?
    init(targetResolution: TargetResolution = .lazyIdentity) {
        self.targetResolution = targetResolution
    }

    func setGeometryProvider(
        _ provider: (@MainActor () -> SidebarSelectedItemSurfaceGeometry?)?
    ) {
        geometryProvider = provider
    }

    func reveal(_ targetID: SidebarScrollTargetID) {
        reveal(SidebarSelectedItemRevealPath([targetID]))
    }

    func reveal(_ path: SidebarSelectedItemRevealPath) {
        pendingTargets = path.targets
        pendingPurpose = .revealSelection
        issuedReveal = nil
        lastRevealPath = path
        advanceReveal()
    }

    /// Re-runs the most recent selection reveal without animation, for signals
    /// that change geometry without changing selection (Zen's instant variants).
    func revealLastSelectionWithoutAnimation() {
        guard isSurfaceReady,
              targetResolution == .presentedLayout,
              let lastRevealPath else { return }
        pendingTargets = lastRevealPath.targets
        pendingPurpose = .relayoutAdjustment
        issuedReveal = nil
        advanceReveal()
    }

    func cancelReveal() {
        pendingTargets.removeAll()
        issuedReveal = nil
        lastRevealPath = nil
        pendingPurpose = .revealSelection
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
        if !pendingTargets.isEmpty {
            advanceReveal()
            return
        }
        verifyIssuedReveal()
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

    /// Freshest known native geometry: the synchronous provider wins over the
    /// coalesced delivery, which can trail the live scroll position by a hop.
    @discardableResult
    private func refreshSurfaceGeometry() -> SidebarSelectedItemSurfaceGeometry? {
        if let fresh = geometryProvider?() {
            surfaceGeometry = fresh
        }
        return surfaceGeometry
    }

    private func advancePresentedLayoutReveal() {
        guard let targetID = pendingTargets.last,
              let autofocusLayout,
              let target = autofocusLayout.targets[targetID],
              let surfaceGeometry = refreshSurfaceGeometry() else {
            // Facts are missing; the intent stays pending for the next layout
            // or geometry delivery.
            return
        }

        switch target.revealDisposition(in: surfaceGeometry) {
        case .unusableGeometry:
            // Stale or collapsed geometry must not consume the intent.
            return
        case .alreadyVisible:
            pendingTargets.removeAll()
            issuedReveal = nil
            return
        case .reveal(let destinationY):
            pendingTargets.removeAll()
            issuePresentedReveal(
                targetID: targetID,
                purpose: pendingPurpose,
                destinationY: destinationY,
                geometry: surfaceGeometry,
                remainingReachabilityCorrections:
                    Self.maximumReachabilityCorrections
            )
        }
    }

    private func issuePresentedReveal(
        targetID: SidebarScrollTargetID,
        purpose: Request.Purpose,
        destinationY: CGFloat,
        geometry: SidebarSelectedItemSurfaceGeometry,
        remainingReachabilityCorrections: Int
    ) {
        issuedReveal = IssuedReveal(
            targetID: targetID,
            purpose: purpose,
            contentHeight: geometry.contentHeight,
            maximumOffset: geometry.maximumOffset,
            remainingReachabilityCorrections:
                remainingReachabilityCorrections
        )
        nextGeneration &+= 1
        request = Request(
            targetID: targetID,
            purpose: purpose,
            destinationY: destinationY,
            generation: nextGeneration
        )
    }

    /// Confirms an issued command actually satisfied its target. A command
    /// that landed short while lazy content was growing is re-issued against
    /// fresher geometry instead of being silently lost (the old one-shot rule).
    private func verifyIssuedReveal() {
        guard let issuedReveal,
              let autofocusLayout,
              let target = autofocusLayout.targets[issuedReveal.targetID],
              let surfaceGeometry = refreshSurfaceGeometry() else {
            return
        }

        switch target.revealDisposition(in: surfaceGeometry) {
        case .alreadyVisible:
            self.issuedReveal = nil
        case .unusableGeometry:
            break
        case .reveal(let destinationY):
            // Only re-issue when the scroll surface itself became more
            // capable since issuance (lazy growth or a viewport change that
            // raised the reachable offset); otherwise the issued command may
            // simply still be in flight.
            let contentHeightGrew = surfaceGeometry.contentHeight
                > issuedReveal.contentHeight + 0.5
            let maximumOffsetGrew = surfaceGeometry.maximumOffset
                > issuedReveal.maximumOffset + 0.5
            guard contentHeightGrew || maximumOffsetGrew else {
                return
            }

            let availableCorrections = contentHeightGrew
                ? Self.maximumReachabilityCorrections
                : issuedReveal.remainingReachabilityCorrections
            guard availableCorrections > 0 else { return }

            issuePresentedReveal(
                targetID: issuedReveal.targetID,
                purpose: issuedReveal.purpose,
                destinationY: destinationY,
                geometry: surfaceGeometry,
                remainingReachabilityCorrections: availableCorrections - 1
            )
        }
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

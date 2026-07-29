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

/// Settled, scroll-content-local geometry produced by the unified list
/// presentation. Its absence withholds autofocus during an in-flight reflow.
struct SidebarAutofocusLayout: Equatable {
    struct Target: Equatable {
        let minY: CGFloat
        let maxY: CGFloat
    }

    let targets: [SidebarScrollTargetID: Target]
}

fileprivate struct SidebarSelectedItemSurfaceGeometry: Equatable {
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
    /// Preserves nearest-edge behavior while reserving one complete row gap
    /// beside either revealing edge. The full 4pt rhythm also keeps the
    /// selected row's 3pt shadow out of the viewport clip.
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
/// sidebar supplies complete settled geometry, so production autofocus emits
/// one exact offset instead of materializing an ancestor chain. The identity
/// mode remains available to small standalone lazy-list surfaces.
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
        autofocusLayout = layout
        advanceReveal()
    }

    fileprivate func updateSurfaceGeometry(
        _ geometry: SidebarSelectedItemSurfaceGeometry
    ) {
        surfaceGeometry = geometry
        guard !pendingTargets.isEmpty else { return }
        advanceReveal()
    }

    func targetDidAppear(_ targetID: SidebarScrollTargetID) {
        guard targetResolution == .lazyIdentity else { return }
        mountedTargets.insert(targetID)
        guard isSurfaceReady else { return }
        guard pendingTargets.first == targetID else { return }
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
              let surfaceGeometry else {
            return
        }

        pendingTargets.removeAll()
        guard let destinationY = target.revealOffset(in: surfaceGeometry) else {
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

private struct SidebarSelectedItemSelectionRequest: Equatable {
    let revealPath: SidebarSelectedItemRevealPath?
    let selection: SidebarWindowSelectionSnapshot
    let isEnabled: Bool
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

    var mountScrollPosition: ScrollPosition {
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
/// intent is applied to its first usable geometry before a frame is presented.
/// The unified sidebar then reveals from settled presentation geometry;
/// standalone lazy lists can use the identity adapter.
struct SidebarSelectedItemVisibilityScope<Content: View>: View {
    let revealPath: SidebarSelectedItemRevealPath?
    let selection: SidebarWindowSelectionSnapshot
    let isEnabled: Bool
    let motionMode: SidebarMotionPolicy.Mode
    let targetResolution: SidebarSelectedItemRevealOwner.TargetResolution
    let onCommittedViewportChange: (SpaceSidebarSnapshotViewport) -> Void
    @ViewBuilder let content: () -> Content

    private let restorationTarget: SidebarScrollRestorationTarget
    @State private var revealOwner: SidebarSelectedItemRevealOwner
    @State private var scrollPosition: ScrollPosition
    @State private var restorationReceipt: SidebarSelectedItemSurfaceGeometry?
    @State private var didApplyRestorationIntent = false

    init(
        revealPath: SidebarSelectedItemRevealPath?,
        selection: SidebarWindowSelectionSnapshot,
        isEnabled: Bool,
        motionMode: SidebarMotionPolicy.Mode,
        targetResolution: SidebarSelectedItemRevealOwner.TargetResolution =
            .lazyIdentity,
        restoredViewport: SpaceSidebarSnapshotViewport?,
        onCommittedViewportChange: @escaping (SpaceSidebarSnapshotViewport) -> Void = { _ in },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.revealPath = revealPath
        self.selection = selection
        self.isEnabled = isEnabled
        self.motionMode = motionMode
        self.targetResolution = targetResolution
        self.onCommittedViewportChange = onCommittedViewportChange
        self.content = content
        let restorationTarget = SidebarScrollRestorationTarget(
            viewport: restoredViewport
        )
        self.restorationTarget = restorationTarget
        _revealOwner = State(
            initialValue: SidebarSelectedItemRevealOwner(
                targetResolution: targetResolution
            )
        )
        _scrollPosition = State(
            initialValue: restorationTarget.mountScrollPosition
        )
    }

    @ViewBuilder
    var body: some View {
        switch targetResolution {
        case .presentedLayout:
            visibilitySurface(proxy: nil)
        case .lazyIdentity:
            ScrollViewReader { proxy in
                visibilitySurface(proxy: proxy)
            }
        }
    }

    private func visibilitySurface(
        proxy: ScrollViewProxy?
    ) -> some View {
        content()
            .scrollPosition($scrollPosition)
            .environment(\.sidebarSelectedItemRevealOwner, revealOwner)
            .background {
                if isEnabled,
                   restorationReceipt != nil,
                   !revealOwner.isSurfaceReady {
                    SidebarSurfacePresentationReceiptBridge(
                        onFirstDisplay: acknowledgePresentedSurface
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onScrollGeometryChange(
                for: SidebarSelectedItemSurfaceGeometry.self
            ) { geometry in
                SidebarSelectedItemSurfaceGeometry(
                    contentOffsetY: geometry.contentOffset.y,
                    viewportHeight: geometry.visibleRect.height,
                    contentHeight: geometry.contentSize.height
                )
            } action: { _, geometry in
                handleSurfaceGeometry(geometry)
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

    private func handleSurfaceGeometry(
        _ geometry: SidebarSelectedItemSurfaceGeometry
    ) {
        revealOwner.updateSurfaceGeometry(geometry)
        guard !applyRestorationIntentIfNeeded(to: geometry) else { return }

        if !revealOwner.isSurfaceReady {
            restorationReceipt = restorationTarget.matches(geometry)
                ? geometry
                : nil
        }

        guard isEnabled, revealOwner.isSurfaceReady else { return }
        onCommittedViewportChange(geometry.scrollViewport)
    }

    /// Returns true when restoration issued a scroll command and the surface
    /// must wait for the resulting geometry before accepting a display receipt.
    private func applyRestorationIntentIfNeeded(
        to geometry: SidebarSelectedItemSurfaceGeometry
    ) -> Bool {
        guard !didApplyRestorationIntent, geometry.hasUsableLayout else {
            return false
        }
        didApplyRestorationIntent = true

        switch restorationTarget {
        case .bottom:
            SidebarMotionTransaction.withoutAnimation {
                scrollPosition.scrollTo(edge: .bottom)
            }
        case .point(let offset):
            SidebarMotionTransaction.withoutAnimation {
                scrollPosition.scrollTo(y: offset)
            }
        case .automatic, .top:
            return false
        }

        restorationReceipt = nil
        return true
    }

    private func acknowledgePresentedSurface() {
        guard isEnabled,
              !revealOwner.isSurfaceReady,
              let restorationReceipt else {
            return
        }

        revealOwner.surfaceDidBecomeReady()
        onCommittedViewportChange(restorationReceipt.scrollViewport)
    }

    private var selectionRequest: SidebarSelectedItemSelectionRequest {
        SidebarSelectedItemSelectionRequest(
            revealPath: revealPath,
            selection: selection,
            isEnabled: isEnabled
        )
    }

    private func reveal(
        _ request: SidebarSelectedItemRevealOwner.Request,
        with proxy: ScrollViewProxy?
    ) {
        if let destinationY = request.destinationY {
            let animation = SidebarMotionPolicy.selectedItemRevealAnimation(
                for: motionMode
            )
            if let animation {
                withAnimation(animation) {
                    scrollPosition.scrollTo(y: destinationY)
                }
            } else {
                SidebarMotionTransaction.withoutAnimation {
                    scrollPosition.scrollTo(y: destinationY)
                }
            }
            return
        }

        guard let proxy else { return }
        let animation = request.purpose == .revealSelection
            ? SidebarMotionPolicy.selectedItemRevealAnimation(for: motionMode)
            : nil
        if let animation {
            withAnimation(animation) {
                proxy.scrollTo(request.targetID)
            }
        } else {
            SidebarMotionTransaction.withoutAnimation {
                proxy.scrollTo(request.targetID)
            }
        }
    }
}

/// Receives the first display pass after scroll restoration, keeping the
/// initial reveal out of the surface's mount transaction.
private struct SidebarSurfacePresentationReceiptBridge: NSViewRepresentable {
    let onFirstDisplay: @MainActor () -> Void

    func makeNSView(context: Context) -> SidebarSurfacePresentationReceiptView {
        let view = SidebarSurfacePresentationReceiptView(frame: .zero)
        view.update(onFirstDisplay: onFirstDisplay)
        return view
    }

    func updateNSView(
        _ nsView: SidebarSurfacePresentationReceiptView,
        context: Context
    ) {
        nsView.update(onFirstDisplay: onFirstDisplay)
    }

    static func dismantleNSView(
        _ nsView: SidebarSurfacePresentationReceiptView,
        coordinator: Void
    ) {
        nsView.invalidate()
    }
}

@MainActor
private final class SidebarSurfacePresentationReceiptView: NSView {
    private var onFirstDisplay: @MainActor () -> Void = {}
    private var isValid = true
    private var didDisplay = false
    private var generation = 0

    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(onFirstDisplay: @escaping @MainActor () -> Void) {
        self.onFirstDisplay = onFirstDisplay
        if !didDisplay {
            needsDisplay = true
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            generation &+= 1
            didDisplay = false
            return
        }
        if !didDisplay {
            needsDisplay = true
        }
    }

    override func updateLayer() {
        super.updateLayer()
        guard isValid,
              !didDisplay,
              window != nil,
              !bounds.isEmpty,
              !visibleRect.isEmpty else {
            return
        }

        didDisplay = true
        let displayGeneration = generation
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.generation == displayGeneration,
                  self.isValid,
                  self.window != nil else {
                return
            }
            self.onFirstDisplay()
        }
    }

    func invalidate() {
        generation &+= 1
        isValid = false
        onFirstDisplay = {}
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

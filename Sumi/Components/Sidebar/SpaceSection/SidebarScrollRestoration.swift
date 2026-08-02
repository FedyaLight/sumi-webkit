import AppKit
import Observation
import SwiftUI

enum SidebarScrollRestorationTarget: Equatable {
    case automatic
    case top
    case bottom(restoredOffset: CGFloat)
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
            self = .bottom(restoredOffset: offset)
        } else {
            self = .point(offset)
        }
    }

    var mountScrollPosition: ScrollPosition {
        switch self {
        case .automatic:
            ScrollPosition(idType: SidebarScrollTargetID.self)
        case .top:
            ScrollPosition(
                idType: SidebarScrollTargetID.self,
                edge: .top
            )
        case .bottom(let restoredOffset):
            ScrollPosition(
                idType: SidebarScrollTargetID.self,
                y: restoredOffset
            )
        case .point(let offset):
            ScrollPosition(
                idType: SidebarScrollTargetID.self,
                y: offset
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
            return abs(
                geometry.contentOffsetY - geometry.maximumOffset
            ) <= tolerance
        case .point(let offset):
            let reachableOffset = min(offset, geometry.maximumOffset)
            return abs(
                geometry.contentOffsetY - reachableOffset
            ) <= tolerance
        }
    }

    func matchesRestoredBottomOffset(
        _ geometry: SidebarSelectedItemSurfaceGeometry
    ) -> Bool {
        guard case .bottom(let restoredOffset) = self else { return false }
        return abs(geometry.contentOffsetY - restoredOffset) <= 1
    }

    func reconciliationCommand(
        for geometry: SidebarSelectedItemSurfaceGeometry
    ) -> SidebarScrollRestorationCommand? {
        guard !matches(geometry) else { return nil }

        switch self {
        case .automatic:
            return nil
        case .top:
            return .top
        case .bottom:
            return .bottom(maximumOffset: geometry.maximumOffset)
        case .point(let offset):
            return .point(
                offset: offset,
                reachableOffset: min(offset, geometry.maximumOffset)
            )
        }
    }
}

/// Reachable offsets are part of identity so restoration retries when the
/// scroll document grows during its first layout passes.
enum SidebarScrollRestorationCommand: Hashable {
    case top
    case bottom(maximumOffset: CGFloat)
    case point(offset: CGFloat, reachableOffset: CGFloat)
}

@MainActor
@Observable
final class SidebarScrollRestorationState {
    private(set) var receipt: SidebarSelectedItemSurfaceGeometry?
    private(set) var command: SidebarScrollRestorationCommand?

    @ObservationIgnored private let target: SidebarScrollRestorationTarget

    init(target: SidebarScrollRestorationTarget) {
        self.target = target
    }

    func receive(
        _ geometry: SidebarSelectedItemSurfaceGeometry,
        isSurfaceReady: Bool,
        selectionRevealIsPending: Bool
    ) {
        guard !isSurfaceReady else { return }

        let preservesPresentedStartingPoint = selectionRevealIsPending
            && receipt != nil
        let hasReachedRestorationTarget = target.matches(geometry)
            || (selectionRevealIsPending
                && target.matchesRestoredBottomOffset(geometry))

        guard preservesPresentedStartingPoint
                || hasReachedRestorationTarget else {
            receipt = nil
            command = target.reconciliationCommand(for: geometry)
            return
        }

        guard receipt != geometry || command != nil else { return }
        command = nil
        receipt = geometry
    }
}

struct SidebarScrollRestorationPresentationModifier: ViewModifier {
    let isEnabled: Bool
    let revealOwner: SidebarSelectedItemRevealOwner
    let restorationState: SidebarScrollRestorationState
    @Binding var scrollPosition: ScrollPosition
    let onPresented: @MainActor (SidebarSelectedItemSurfaceGeometry) -> Void

    func body(content: Content) -> some View {
        content
            .background {
                if isEnabled, !revealOwner.isSurfaceReady {
                    if restorationState.receipt != nil {
                        presentationBridge(
                            onFirstDisplay: acknowledgePresentedSurface
                        )
                    } else if let command = restorationState.command {
                        presentationBridge {
                            reconcileRestorationTarget(command)
                        }
                        .id(command)
                    }
                }
            }
    }

    private func reconcileRestorationTarget(
        _ command: SidebarScrollRestorationCommand
    ) {
        guard isEnabled,
              !revealOwner.isSurfaceReady,
              restorationState.command == command else {
            return
        }

        SidebarMotionTransaction.withoutAnimation {
            switch command {
            case .top:
                scrollPosition.scrollTo(edge: .top)
            case .bottom:
                scrollPosition.scrollTo(edge: .bottom)
            case .point(let offset, _):
                scrollPosition.scrollTo(y: offset)
            }
        }
    }

    private func presentationBridge(
        onFirstDisplay: @escaping @MainActor () -> Void
    ) -> some View {
        SidebarSurfacePresentationReceiptBridge(
            onFirstDisplay: onFirstDisplay
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func acknowledgePresentedSurface() {
        guard let receipt = restorationState.receipt else { return }
        onPresented(receipt)
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

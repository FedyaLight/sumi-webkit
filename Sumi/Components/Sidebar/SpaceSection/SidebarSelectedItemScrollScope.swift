import SwiftUI

/// Reference cell carrying the freshest native scroll geometry from the
/// AppKit observer to synchronous reveal decisions.
@MainActor
final class SidebarSurfaceGeometryBox {
    var latest: SidebarSelectedItemSurfaceGeometry?
}

struct SidebarScrollSurfaceObservation {
    let surfaceID: ObjectIdentifier?
    let capturesLiveViewport: Bool
    let onLiveViewportChange: @MainActor (
        SpaceSidebarSnapshotViewport
    ) -> Void
    let onGeometryChange: @MainActor (
        SidebarSelectedItemSurfaceGeometry
    ) -> Void
    let geometryBox: SidebarSurfaceGeometryBox

    static let disabled = SidebarScrollSurfaceObservation(
        surfaceID: nil,
        capturesLiveViewport: false,
        onLiveViewportChange: { _ in },
        onGeometryChange: { _ in },
        geometryBox: SidebarSurfaceGeometryBox()
    )
}

private struct SidebarSelectedItemSelectionRequest: Equatable {
    let revealPath: SidebarSelectedItemRevealPath?
    let isEnabled: Bool
}

private struct SidebarViewportResizeObserver: View {
    let onResize: @MainActor () -> Void

    @State private var observedSize: CGSize?

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .task(id: proxy.size) {
                    guard let observedSize else {
                        self.observedSize = proxy.size
                        return
                    }
                    guard observedSize != proxy.size else { return }
                    self.observedSize = proxy.size
                    onResize()
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Owns programmatic scrolling for one sidebar surface. The same native scroll
/// observer supplies both restoration geometry and the live viewport cache.
struct SidebarSelectedItemVisibilityScope<Content: View>: View {
    let revealPath: SidebarSelectedItemRevealPath?
    let isEnabled: Bool
    let motionMode: SidebarMotionPolicy.Mode
    let targetResolution: SidebarSelectedItemRevealOwner.TargetResolution
    let onViewportChange: @MainActor (
        SpaceSidebarSnapshotViewport
    ) -> Void
    @ViewBuilder let content: (SidebarScrollSurfaceObservation) -> Content

    @State private var revealOwner: SidebarSelectedItemRevealOwner
    @State private var scrollPosition: ScrollPosition
    @State private var restorationState: SidebarScrollRestorationState
    @State private var geometryBox = SidebarSurfaceGeometryBox()

    init(
        revealPath: SidebarSelectedItemRevealPath?,
        isEnabled: Bool,
        motionMode: SidebarMotionPolicy.Mode,
        targetResolution: SidebarSelectedItemRevealOwner.TargetResolution =
            .lazyIdentity,
        restoredViewport: SpaceSidebarSnapshotViewport?,
        onViewportChange: @escaping @MainActor (
            SpaceSidebarSnapshotViewport
        ) -> Void = { _ in },
        @ViewBuilder content: @escaping (
            SidebarScrollSurfaceObservation
        ) -> Content
    ) {
        self.revealPath = revealPath
        self.isEnabled = isEnabled
        self.motionMode = motionMode
        self.targetResolution = targetResolution
        self.onViewportChange = onViewportChange
        self.content = content

        let restorationTarget = SidebarScrollRestorationTarget(
            viewport: restoredViewport
        )
        _revealOwner = State(
            initialValue: SidebarSelectedItemRevealOwner(
                targetResolution: targetResolution
            )
        )
        _scrollPosition = State(
            initialValue: restorationTarget.mountScrollPosition
        )
        _restorationState = State(
            initialValue: SidebarScrollRestorationState(
                target: restorationTarget
            )
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
        content(
            SidebarScrollSurfaceObservation(
                surfaceID: ObjectIdentifier(revealOwner),
                capturesLiveViewport: isEnabled
                    && revealOwner.isSurfaceReady,
                onLiveViewportChange: onViewportChange,
                onGeometryChange: handleSurfaceGeometry,
                geometryBox: geometryBox
            )
        )
        .scrollPosition($scrollPosition)
        .environment(\.sidebarSelectedItemRevealOwner, revealOwner)
        .modifier(
            SidebarScrollRestorationPresentationModifier(
                isEnabled: isEnabled,
                revealOwner: revealOwner,
                restorationState: restorationState,
                scrollPosition: $scrollPosition,
                onPresented: acknowledgePresentedSurface
            )
        )
        .task(id: selectionRequest) {
            revealOwner.setGeometryProvider { [geometryBox] in
                geometryBox.latest
            }
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
        .background {
            if isEnabled {
                SidebarViewportResizeObserver(
                    onResize: handleViewportResize
                )
            }
        }
    }

    private func handleSurfaceGeometry(
        _ geometry: SidebarSelectedItemSurfaceGeometry
    ) {
        revealOwner.updateSurfaceGeometry(geometry)
        restorationState.receive(
            geometry,
            isSurfaceReady: revealOwner.isSurfaceReady,
            selectionRevealIsPending: isEnabled && revealPath != nil
        )

        guard isEnabled, revealOwner.isSurfaceReady else { return }
        onViewportChange(geometry.scrollViewport)
    }

    private func handleViewportResize() {
        guard isEnabled, revealOwner.isSurfaceReady else { return }
        revealOwner.revealLastSelectionWithoutAnimation()
    }

    private func acknowledgePresentedSurface(
        _ restorationReceipt: SidebarSelectedItemSurfaceGeometry
    ) {
        guard isEnabled, !revealOwner.isSurfaceReady else { return }

        revealOwner.surfaceDidBecomeReady()
        onViewportChange(restorationReceipt.scrollViewport)
    }

    private var selectionRequest: SidebarSelectedItemSelectionRequest {
        SidebarSelectedItemSelectionRequest(
            revealPath: revealPath,
            isEnabled: isEnabled
        )
    }

    private func reveal(
        _ request: SidebarSelectedItemRevealOwner.Request,
        with proxy: ScrollViewProxy?
    ) {
        let selectionAnimation = request.purpose.usesSelectionAnimation
            ? SidebarMotionPolicy.selectedItemRevealAnimation(for: motionMode)
            : nil

        if let destinationY = request.destinationY {
            if let animation = selectionAnimation {
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
        if let animation = selectionAnimation {
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

import SwiftUI

struct SidebarScrollSurfaceObservation {
    let surfaceID: ObjectIdentifier?
    let capturesLiveViewport: Bool
    let onLiveViewportChange: @MainActor (
        SpaceSidebarSnapshotViewport
    ) -> Void
    let onGeometryChange: @MainActor (
        SidebarSelectedItemSurfaceGeometry
    ) -> Void

    static let disabled = SidebarScrollSurfaceObservation(
        surfaceID: nil,
        capturesLiveViewport: false,
        onLiveViewportChange: { _ in },
        onGeometryChange: { _ in }
    )
}

private struct SidebarSelectedItemSelectionRequest: Equatable {
    let revealPath: SidebarSelectedItemRevealPath?
    let isEnabled: Bool
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
                onGeometryChange: handleSurfaceGeometry
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
        restorationState.receive(
            geometry,
            isSurfaceReady: revealOwner.isSurfaceReady,
            selectionRevealIsPending: isEnabled && revealPath != nil
        )

        guard isEnabled, revealOwner.isSurfaceReady else { return }
        onViewportChange(geometry.scrollViewport)
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

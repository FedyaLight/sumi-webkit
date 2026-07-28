import Combine
import CoreGraphics
import Foundation
import SumiDomain

enum SidebarDragGeometryFact {
    case presentedSpaceList(PresentedSidebarLayout)
    case removePresentedSpaceList(spaceID: UUID)
    case page(
        spaceId: UUID,
        profileId: UUID?,
        frame: CGRect?,
        renderMode: SidebarPageGeometryRenderMode
    )
    case essentials(SidebarEssentialsLayoutUpdate)
}

@MainActor
final class SidebarDragGeometryRefreshSignal: ObservableObject {
    @Published private(set) var revision = 0

    func publish(_ revision: Int) {
        guard self.revision != revision else { return }
        self.revision = revision
    }
}

/// Window-scoped geometry module. Its small interface accepts layout facts and
/// publishes one immutable snapshot; deferral, coalescing, epochs, scroll
/// normalization and hit-test indices stay inside the implementation.
@MainActor
final class SidebarDragGeometryModule: ObservableObject {
    private struct CollectionContext: Equatable {
        var isDragging = false
        var isInternalDragSession = false
        var activeScope: SidebarDragScope?
        var isArmed = false
        var armedScope: SidebarDragScope?
    }

    // The snapshot is consumed synchronously by hit testing. Publishing every
    // measured frame would invalidate all geometry reporters and create a
    // layout/report feedback loop; only explicit revision and epoch changes
    // are observable by SwiftUI.
    private(set) var geometrySnapshot: SidebarGeometrySnapshot = .empty
    private(set) var geometryRevision = 0
    let refreshSignal = SidebarDragGeometryRefreshSignal()
    @Published private(set) var sidebarGeometryGeneration = 0
    private(set) var activeGeometryGeneration = 0
    private(set) var pendingGeometryGeneration: Int?
    @Published private var collectionContext = CollectionContext()

    private lazy var repository = SidebarDragGeometryRepository(
        geometrySnapshot: geometrySnapshot,
        geometryRevision: geometryRevision,
        generationState: SidebarDragGeometryRepository.GenerationState(
            sidebarGeometryGeneration: sidebarGeometryGeneration,
            activeGeometryGeneration: activeGeometryGeneration,
            pendingGeometryGeneration: pendingGeometryGeneration
        ),
        publishSnapshot: { [weak self] snapshot in
            guard self?.geometrySnapshot != snapshot else { return }
            self?.geometrySnapshot = snapshot
        },
        publishRevision: { [weak self] revision in
            guard self?.geometryRevision != revision else { return }
            self?.geometryRevision = revision
            self?.refreshSignal.publish(revision)
        },
        publishGenerations: { [weak self] state in
            self?.publish(state)
        }
    )

    var isDragging: Bool { collectionContext.isDragging }

    func updateCollectionContext(
        isDragging: Bool,
        isInternalDragSession: Bool,
        activeScope: SidebarDragScope?,
        isArmed: Bool,
        armedScope: SidebarDragScope?
    ) {
        let next = CollectionContext(
            isDragging: isDragging,
            isInternalDragSession: isInternalDragSession,
            activeScope: activeScope,
            isArmed: isArmed,
            armedScope: armedScope
        )
        guard collectionContext != next else { return }
        collectionContext = next
    }

    func shouldCollectDetailedGeometry(
        spaceId: UUID,
        profileId: UUID?
    ) -> Bool {
        if let scope = collectionContext.activeScope {
            return scope.spaceId == spaceId && scope.matches(profileId: profileId)
        }
        if collectionContext.isArmed {
            guard let scope = collectionContext.armedScope else { return true }
            return scope.spaceId == spaceId && scope.matches(profileId: profileId)
        }
        if collectionContext.isDragging {
            return !collectionContext.isInternalDragSession
        }
        return false
    }

    func flushDeferredGeometryForDragStart() {
        repository.flushDeferredGeometryForDragStart()
    }

    func report(_ fact: SidebarDragGeometryFact, generation: Int) {
        switch fact {
        case .presentedSpaceList(let layout):
            repository.schedulePresentedSpaceList(
                layout,
                generation: generation
            )
        case .removePresentedSpaceList(let spaceID):
            repository.schedulePresentedSpaceListRemoval(
                spaceID: spaceID,
                generation: generation
            )
        case .page(let spaceId, let profileId, let frame, let renderMode):
            repository.schedulePageGeometry(
                spaceId: spaceId,
                profileId: profileId,
                frame: frame,
                renderMode: renderMode,
                generation: generation
            )
        case .essentials(let update):
            repository.scheduleEssentialsLayoutMetrics(update, generation: generation)
        }
    }

    func beginPendingGeometryEpoch(expectedSpaceId: UUID?, profileId: UUID?) {
        repository.beginPendingGeometryEpoch(
            expectedSpaceId: expectedSpaceId,
            profileId: profileId
        )
    }

    func requestGeometryRefresh() {
        repository.requestGeometryRefresh()
    }

    func promotePendingGeometryIfReady() {
        repository.promotePendingGeometryIfReady()
    }

    func adjustScroll(deltaY: CGFloat) {
        repository.adjustGeometryStoreScrollDelta(deltaY: deltaY)
    }

    private func publish(_ state: SidebarDragGeometryRepository.GenerationState) {
        if sidebarGeometryGeneration != state.sidebarGeometryGeneration {
            sidebarGeometryGeneration = state.sidebarGeometryGeneration
        }
        if activeGeometryGeneration != state.activeGeometryGeneration {
            activeGeometryGeneration = state.activeGeometryGeneration
        }
        if pendingGeometryGeneration != state.pendingGeometryGeneration {
            pendingGeometryGeneration = state.pendingGeometryGeneration
        }
    }
}

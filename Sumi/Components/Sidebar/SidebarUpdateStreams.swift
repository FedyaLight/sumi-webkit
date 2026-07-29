import Combine
import Foundation
import SwiftUI

struct SidebarProfileRuntimeSnapshot: Equatable {
    let currentProfileID: UUID?
    let isTransitioning: Bool
}

enum SidebarScopedSnapshotDelivery {
    case deferredOnMainRunLoop
    /// The upstream publisher must already be confined to the main actor.
    case mainActorImmediate(
        deferral: SidebarScopedSnapshotDeferral? = nil
    )
}

struct SidebarScopedSnapshotDeferral {
    /// The reader buffers only the fact that a change arrived, then re-reads
    /// current state when the explicit boundary ends.
    let isActive: @MainActor () -> Bool
    let ended: AnyPublisher<SidebarScopedSnapshotDeferralEnd, Never>
}

enum SidebarScopedSnapshotDeferralEnd: Sendable {
    case reached
}

@MainActor
func presentedDropMutationDeferral(
    for dragState: SidebarDragState
) -> SidebarScopedSnapshotDeferral {
    SidebarScopedSnapshotDeferral(
        isActive: { dragState.isApplyingDropMutation },
        ended: dragState.listPresentation.$frame
            .map(\.isApplyingDropMutation)
            .removeDuplicates()
            .dropFirst()
            .filter { !$0 }
            .map { _ in SidebarScopedSnapshotDeferralEnd.reached }
            .eraseToAnyPublisher()
    )
}

/// Exact structural invalidation source. It owns no subscription; mounted
/// snapshot readers subscribe only while their sidebar surface is interactive.
struct SidebarInventoryUpdates {
    let structuralChanges: AnyPublisher<TabStructureChangeScope, Never>
    let livePageResidenceChanges: AnyPublisher<LivePageResidenceScope, Never>

    init(
        structuralChanges: AnyPublisher<TabStructureChangeScope, Never>,
        livePageResidenceChanges: AnyPublisher<
            LivePageResidenceScope,
            Never
        > = Empty(completeImmediately: false).eraseToAnyPublisher()
    ) {
        self.structuralChanges = structuralChanges
        self.livePageResidenceChanges = livePageResidenceChanges
    }

    func pageChanges(
        windowID: UUID,
        spaceID: UUID,
        profileID: UUID?
    ) -> AnyPublisher<TabStructureChangeScope, Never> {
        structuralChanges
            .filter {
                $0.affectsPage(
                    windowID: windowID,
                    spaceID: spaceID,
                    profileID: profileID
                )
            }
            .eraseToAnyPublisher()
    }

    var catalogChanges: AnyPublisher<TabStructureChangeScope, Never> {
        structuralChanges
            .filter(\.affectsSpaceCatalog)
            .eraseToAnyPublisher()
    }

    func launcherResidenceChanges(
        windowID: UUID,
        spaceID: UUID
    ) -> AnyPublisher<LivePageResidenceScope, Never> {
        livePageResidenceChanges
            .filter {
                $0.windowID == windowID && $0.spaceID == spaceID
            }
            .eraseToAnyPublisher()
    }
}

/// Profile collection and selection are separate typed streams because a
/// profile-list edit must not invalidate every rendered tab row.
struct SidebarProfileUpdates {
    let profiles: AnyPublisher<[Profile], Never>
    let runtime: AnyPublisher<SidebarProfileRuntimeSnapshot, Never>
}

/// One demand-scoped value subscription used by narrow SwiftUI reader views.
/// Constructing the model does not subscribe or schedule work.
@MainActor
final class SidebarScopedSnapshotModel<Value>: ObservableObject {
    @Published private(set) var snapshot: Value

    private var current: @MainActor () -> Value
    private var changes: AnyPublisher<Value, Never>
    private var delivery: SidebarScopedSnapshotDelivery
    private var areEquivalent: ((Value, Value) -> Bool)?
    private var cancellable: AnyCancellable?
    private var deferralCancellable: AnyCancellable?
    private var activationGeneration: UInt64 = 0
    private var receivedChangeRevision: UInt64 = 0
    private var hasDeferredChange = false

    init(
        current: @escaping @MainActor () -> Value,
        changes: AnyPublisher<Value, Never>,
        delivery: SidebarScopedSnapshotDelivery = .deferredOnMainRunLoop,
        areEquivalent: ((Value, Value) -> Bool)? = nil
    ) {
        self.current = current
        self.changes = changes
        self.delivery = delivery
        self.areEquivalent = areEquivalent
        snapshot = current()
    }

    /// Rebinds a dynamic reader without replacing the model that owns its
    /// consumer subtree.
    func replaceSource(
        current: @escaping @MainActor () -> Value,
        changes: AnyPublisher<Value, Never>,
        delivery: SidebarScopedSnapshotDelivery,
        areEquivalent: ((Value, Value) -> Bool)?
    ) {
        let wasActive = cancellable != nil
        setActive(false)
        self.current = current
        self.changes = changes
        self.delivery = delivery
        self.areEquivalent = areEquivalent
        if wasActive {
            setActive(true)
        } else {
            publishIfChanged(current())
        }
    }

    func setActive(_ isActive: Bool) {
        guard isActive else {
            activationGeneration &+= 1
            cancellable?.cancel()
            cancellable = nil
            deferralCancellable?.cancel()
            deferralCancellable = nil
            hasDeferredChange = false
            return
        }
        guard cancellable == nil else { return }

        activationGeneration &+= 1
        let generation = activationGeneration
        // Subscribe before the demand-time read so a mutation re-entering that
        // read cannot fall into a read→subscribe gap.
        switch delivery {
        case .deferredOnMainRunLoop:
            cancellable = changes
                .receive(on: RunLoop.main)
                .sink { [weak self] snapshot in
                    guard self?.activationGeneration == generation else { return }
                    self?.publishIfChanged(snapshot)
                }
            publishIfChanged(current())
        case .mainActorImmediate(let deferral):
            if let deferral {
                deferralCancellable = deferral.ended
                    .sink { [weak self] _ in
                        self?.resumeDeferredSnapshot(
                            generation: generation,
                            deferral: deferral
                        )
                    }
            }
            cancellable = changes
                .sink { [weak self] snapshot in
                    self?.receiveImmediateSnapshot(
                        snapshot,
                        generation: generation,
                        deferral: deferral
                    )
                }
            let revisionBeforeRead = receivedChangeRevision
            let currentSnapshot = current()
            if receivedChangeRevision == revisionBeforeRead {
                publishIfChanged(currentSnapshot)
            }
        }
    }

    private func receiveImmediateSnapshot(
        _ newSnapshot: Value,
        generation: UInt64,
        deferral: SidebarScopedSnapshotDeferral?
    ) {
        guard activationGeneration == generation else { return }
        receivedChangeRevision &+= 1

        if let deferral, deferral.isActive() {
            hasDeferredChange = true
            return
        }
        hasDeferredChange = false
        publishIfChanged(newSnapshot)
    }

    private func resumeDeferredSnapshot(
        generation: UInt64,
        deferral: SidebarScopedSnapshotDeferral
    ) {
        guard activationGeneration == generation,
              hasDeferredChange,
              !deferral.isActive() else {
            return
        }
        hasDeferredChange = false
        let revisionBeforeRead = receivedChangeRevision
        let currentSnapshot = current()
        if receivedChangeRevision == revisionBeforeRead {
            publishIfChanged(currentSnapshot)
        }
    }

    private func publishIfChanged(_ newSnapshot: Value) {
        if let areEquivalent, areEquivalent(snapshot, newSnapshot) {
            return
        }
        snapshot = newSnapshot
    }

    isolated deinit {
        cancellable?.cancel()
        deferralCancellable?.cancel()
    }
}

/// Keeps invalidation at the leaf that consumes a typed snapshot. An inactive
/// or offscreen sidebar renders its initial value without installing a Combine
/// subscription.
struct SidebarScopedSnapshotReader<Value, Content: View>: View {
    let isActive: Bool
    @ViewBuilder let content: (Value) -> Content
    /// Changes only when the closures/publisher above this reader capture a
    /// different source. The reader rebinds in place so child state survives.
    private let sourceIdentity: AnyHashable?
    private let current: @MainActor () -> Value
    private let changes: AnyPublisher<Value, Never>
    private let delivery: SidebarScopedSnapshotDelivery
    private let areEquivalent: ((Value, Value) -> Bool)?
    @StateObject private var model: SidebarScopedSnapshotModel<Value>

    init(
        current: @escaping @MainActor () -> Value,
        changes: AnyPublisher<Value, Never>,
        delivery: SidebarScopedSnapshotDelivery = .deferredOnMainRunLoop,
        areEquivalent: ((Value, Value) -> Bool)? = nil,
        sourceIdentity: AnyHashable? = nil,
        isActive: Bool,
        @ViewBuilder content: @escaping (Value) -> Content
    ) {
        self.isActive = isActive
        self.content = content
        self.sourceIdentity = sourceIdentity
        self.current = current
        self.changes = changes
        self.delivery = delivery
        self.areEquivalent = areEquivalent
        _model = StateObject(
            wrappedValue: SidebarScopedSnapshotModel(
                current: current,
                changes: changes,
                delivery: delivery,
                areEquivalent: areEquivalent
            )
        )
    }

    var body: some View {
        content(model.snapshot)
            .onAppear {
                model.setActive(isActive)
            }
            .onChange(of: isActive) { _, isActive in
                model.setActive(isActive)
            }
            .onChange(of: sourceIdentity) { _, _ in
                model.replaceSource(
                    current: current,
                    changes: changes,
                    delivery: delivery,
                    areEquivalent: areEquivalent
                )
            }
            .onDisappear {
                model.setActive(false)
            }
    }
}

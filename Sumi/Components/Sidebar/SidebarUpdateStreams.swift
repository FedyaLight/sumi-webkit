import Combine
import Foundation
import SwiftUI

struct SidebarProfileRuntimeSnapshot: Equatable {
    let currentProfileID: UUID?
    let isTransitioning: Bool
}

/// Exact structural invalidation source. It owns no subscription; mounted
/// snapshot readers subscribe only while their sidebar surface is interactive.
struct SidebarInventoryUpdates {
    let changes: AnyPublisher<TabStructureChangeScope, Never>

    func pageChanges(
        windowID: UUID,
        spaceID: UUID,
        profileID: UUID?
    ) -> AnyPublisher<TabStructureChangeScope, Never> {
        changes
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
        changes
            .filter(\.affectsSpaceCatalog)
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

    private let current: @MainActor () -> Value
    private let changes: AnyPublisher<Value, Never>
    private var cancellable: AnyCancellable?
    private var activationGeneration: UInt64 = 0

    init(
        current: @escaping @MainActor () -> Value,
        changes: AnyPublisher<Value, Never>
    ) {
        self.current = current
        self.changes = changes
        snapshot = current()
    }

    func setActive(_ isActive: Bool) {
        guard isActive else {
            activationGeneration &+= 1
            cancellable?.cancel()
            cancellable = nil
            return
        }
        guard cancellable == nil else { return }

        activationGeneration &+= 1
        let generation = activationGeneration
        // Subscribe before the demand-time read so a mutation re-entering that
        // read cannot fall into a read→subscribe gap. Delivery is scheduled on
        // the main run loop, so the fresh read is installed first and the exact
        // queued mutation wins afterward.
        cancellable = changes
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                guard self?.activationGeneration == generation else { return }
                self?.snapshot = snapshot
            }
        snapshot = current()
    }

    isolated deinit {
        cancellable?.cancel()
    }
}

/// Keeps invalidation at the leaf that consumes a typed snapshot. An inactive
/// or offscreen sidebar renders its initial value without installing a Combine
/// subscription.
struct SidebarScopedSnapshotReader<Value, Content: View>: View {
    let isActive: Bool
    @ViewBuilder let content: (Value) -> Content
    @StateObject private var model: SidebarScopedSnapshotModel<Value>

    init(
        current: @escaping @MainActor () -> Value,
        changes: AnyPublisher<Value, Never>,
        isActive: Bool,
        @ViewBuilder content: @escaping (Value) -> Content
    ) {
        self.isActive = isActive
        self.content = content
        _model = StateObject(
            wrappedValue: SidebarScopedSnapshotModel(
                current: current,
                changes: changes
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
            .onDisappear {
                model.setActive(false)
            }
    }
}

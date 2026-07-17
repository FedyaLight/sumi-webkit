import Combine
import Foundation

@MainActor
final class BrowserTabStructuralRuntimeObserver {
    private let structuralChanges: AnyPublisher<Void, Never>
    private let reconciliation: BrowserTabRuntimeReconcileOwner

    init(
        structuralChanges: AnyPublisher<Void, Never>,
        reconciliation: BrowserTabRuntimeReconcileOwner
    ) {
        self.structuralChanges = structuralChanges
        self.reconciliation = reconciliation
    }

    func attach() -> AnyCancellable {
        structuralChanges
            .receive(on: RunLoop.main)
            .sink { [reconciliation] _ in
                reconciliation.schedule(reason: "tab-structure-changed")
            }
    }
}

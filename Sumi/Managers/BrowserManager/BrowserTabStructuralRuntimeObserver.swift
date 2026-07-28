import Combine
import Foundation

@MainActor
final class BrowserTabStructuralRuntimeObserver {
    private let structuralChanges: AnyPublisher<Void, Never>
    private let pageResidency: BrowserPageResidencyController

    init(
        structuralChanges: AnyPublisher<Void, Never>,
        pageResidency: BrowserPageResidencyController
    ) {
        self.structuralChanges = structuralChanges
        self.pageResidency = pageResidency
    }

    func attach() -> AnyCancellable {
        structuralChanges
            .receive(on: RunLoop.main)
            .sink { [pageResidency] _ in
                pageResidency.schedule(reason: "tab-structure-changed")
            }
    }
}

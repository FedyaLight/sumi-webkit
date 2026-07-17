import Foundation
import Observation
import SumiDomain

/// Runtime receipts for one restore cycle.
/// This state is never encoded back into the durable window snapshot.
@MainActor
@Observable
final class WindowRestorationState {
    var restoredSessionWindowID: UUID?
    var isAwaitingInitialResolution: Bool
    var pendingSplitSelection: PendingWindowSplitSelection?

    init(isAwaitingInitialResolution: Bool = false) {
        self.isAwaitingInitialResolution = isAwaitingInitialResolution
    }
}

import Foundation
import Observation
import SumiDomain

/// Runtime receipts and decode-only migration evidence for one restore cycle.
/// This state is never encoded back into the durable window snapshot.
@MainActor
@Observable
final class WindowRestorationState {
    var restoredSessionWindowID: UUID?
    var isAwaitingInitialResolution: Bool
    var pendingSplitSelection: PendingWindowSplitSelection?
    var pendingLegacySplitGroup: SumiDomain.SplitGroup?

    init(isAwaitingInitialResolution: Bool = false) {
        self.isAwaitingInitialResolution = isAwaitingInitialResolution
    }
}

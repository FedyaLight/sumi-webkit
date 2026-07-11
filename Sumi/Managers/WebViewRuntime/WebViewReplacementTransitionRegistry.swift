import Foundation
import SumiWebRuntime

/// Breaks composition-time cycles while exposing one process-wide abort port
/// to destructive website-data cleanup. It never owns replacement policy.
@MainActor
final class WebViewReplacementTransitionRegistry {
    typealias Abort = @MainActor (
        Set<UUID>,
        WebViewReplacementAbortReason
    ) -> Int

    private var abort: Abort?

    func install(abort: @escaping Abort) {
        precondition(self.abort == nil, "Replacement abort port installed twice")
        self.abort = abort
    }

    @discardableResult
    func abort(
        profileIDs: Set<UUID>,
        reason: WebViewReplacementAbortReason
    ) -> Int {
        abort?(profileIDs, reason) ?? 0
    }
}

import Foundation

@MainActor
final class URLBarHubRefreshCoordinator: ObservableObject {
    @Published private(set) var refreshNonce = 0

    private var coalescedRefreshTask: Task<Void, Never>?

    func scheduleCoalescedRefresh() {
        coalescedRefreshTask?.cancel()
        coalescedRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard !Task.isCancelled else { return }
            refreshNonce += 1
        }
    }

    func cancel() {
        coalescedRefreshTask?.cancel()
        coalescedRefreshTask = nil
    }
}

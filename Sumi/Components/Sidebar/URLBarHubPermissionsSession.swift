import Foundation

@MainActor
final class URLBarHubPermissionsSession {
    private var scheduledPermissionsReloadTask: Task<Void, Never>?

    func reloadImmediately(
        _ reload: @escaping @MainActor () async -> Void
    ) async {
        scheduledPermissionsReloadTask?.cancel()
        scheduledPermissionsReloadTask = nil
        await reload()
    }

    func scheduleReloadAfterStoreChange(
        reload: @escaping @MainActor () async -> Void,
        onDidReload: @escaping @MainActor () -> Void
    ) {
        scheduledPermissionsReloadTask?.cancel()
        scheduledPermissionsReloadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            await reload()
            onDidReload()
            scheduledPermissionsReloadTask = nil
        }
    }

    func cancel() {
        scheduledPermissionsReloadTask?.cancel()
        scheduledPermissionsReloadTask = nil
    }
}

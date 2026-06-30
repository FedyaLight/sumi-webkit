import Foundation

enum TabSelectionLoadPolicy: Equatable {
    case immediate
    case deferred
}

@MainActor
final class WindowTabActivationBatcher {
    struct Activation: Equatable {
        let tabId: UUID
        let loadPolicy: TabSelectionLoadPolicy
    }

    private var pendingActivationsByWindow: [UUID: Activation] = [:]
    private var flushScheduledWindows: Set<UUID> = []

    func requestActivation(
        tabId: UUID,
        in windowId: UUID,
        loadPolicy: TabSelectionLoadPolicy,
        onFlush: @escaping @MainActor (UUID, Activation) -> Void
    ) {
        pendingActivationsByWindow[windowId] = Activation(
            tabId: tabId,
            loadPolicy: loadPolicy
        )

        guard !flushScheduledWindows.contains(windowId) else { return }
        flushScheduledWindows.insert(windowId)

        DispatchQueue.main.async { [weak self] in
            Task { @MainActor [weak self] in
                self?.flushPendingActivation(for: windowId, onFlush: onFlush)
            }
        }
    }

    private func flushPendingActivation(
        for windowId: UUID,
        onFlush: @MainActor (UUID, Activation) -> Void
    ) {
        flushScheduledWindows.remove(windowId)
        guard let activation = pendingActivationsByWindow.removeValue(forKey: windowId) else {
            return
        }

        onFlush(windowId, activation)
    }
}

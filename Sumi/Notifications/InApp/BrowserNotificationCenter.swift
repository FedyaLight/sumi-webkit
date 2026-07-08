import Foundation

/// Owns the per-window in-app notification stack and auto-dismiss timers.
@MainActor
@Observable
final class BrowserNotificationCenter {
    struct PresentedNotification: Identifiable {
        var notification: BrowserNotification
        var pulseToken: Int = 0

        var id: UUID { notification.id }
    }

    private(set) var items: [PresentedNotification] = []

    @ObservationIgnored private var dismissTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var pausedNotificationIDs: Set<UUID> = []

    func pulseToken(for id: UUID) -> Int {
        items.first { $0.id == id }?.pulseToken ?? 0
    }

    func present(_ notification: BrowserNotification) {
        if let index = items.firstIndex(where: { $0.notification.messageKey == notification.messageKey }) {
            let existingID = items[index].id
            items[index].notification = notification.withID(existingID)
            items[index].pulseToken += 1
            scheduleDismiss(for: existingID, duration: notification.duration)
            return
        }

        items.append(PresentedNotification(notification: notification))
        scheduleDismiss(for: notification.id, duration: notification.duration)
    }

    func dismiss(id: UUID) {
        dismissTasks[id]?.cancel()
        dismissTasks.removeValue(forKey: id)
        pausedNotificationIDs.remove(id)
        items.removeAll { $0.id == id }
    }

    func dismissAll() {
        for task in dismissTasks.values {
            task.cancel()
        }
        dismissTasks.removeAll()
        pausedNotificationIDs.removeAll()
        items.removeAll()
    }

    func pauseTimer(id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        pausedNotificationIDs.insert(id)
        dismissTasks[id]?.cancel()
        dismissTasks.removeValue(forKey: id)
    }

    func resumeTimer(id: UUID) {
        guard pausedNotificationIDs.contains(id),
              let item = items.first(where: { $0.id == id })
        else { return }

        pausedNotificationIDs.remove(id)
        scheduleDismiss(for: id, duration: item.notification.duration)
    }

    func restartTimer(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        scheduleDismiss(for: id, duration: item.notification.duration)
    }

    private func scheduleDismiss(for id: UUID, duration: TimeInterval) {
        dismissTasks[id]?.cancel()
        guard !pausedNotificationIDs.contains(id) else { return }

        dismissTasks[id] = Task { [weak self] in
            let nanoseconds = UInt64(duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.dismiss(id: id)
            }
        }
    }
}

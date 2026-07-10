import Foundation

@MainActor
final class TabSuspensionPolicyChangeMonitor {
    private let notificationCenter: NotificationCenter
    private let policyChanged: @MainActor (String) -> Void
    private var observers: [NSObjectProtocol] = []

    init(
        notificationCenter: NotificationCenter = .default,
        policyChanged: @escaping @MainActor (String) -> Void
    ) {
        self.notificationCenter = notificationCenter
        self.policyChanged = policyChanged
    }

    func start() {
        guard observers.isEmpty else { return }
        observers = [
            observe(.sumiMemorySaverPolicyChanged, reason: "memory-saver-policy-changed"),
            observe(.sumiEnergySaverPolicyChanged, reason: "energy-saver-policy-changed"),
        ]
    }

    func stop() {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func observe(_ name: Notification.Name, reason: String) -> NSObjectProtocol {
        notificationCenter.addObserver(
            forName: name,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.policyChanged(reason)
            }
        }
    }
}

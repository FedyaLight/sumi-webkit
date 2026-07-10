import AppKit
import Foundation

/// Owns application lifecycle observation for coalesced metadata durability.
final class SumiFaviconPersistenceLifecycle: @unchecked Sendable {
    private let blobMaintenance: SumiFaviconBlobMaintenance
    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    init(
        blobMaintenance: SumiFaviconBlobMaintenance,
        notificationCenter: NotificationCenter = .default
    ) {
        self.blobMaintenance = blobMaintenance
        self.notificationCenter = notificationCenter
        registerObservers()
    }

    deinit {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
        blobMaintenance.flushPendingPersists()
    }

    private func registerObservers() {
        for name in [
            NSApplication.willTerminateNotification,
            NSApplication.willResignActiveNotification,
        ] {
            observers.append(
                notificationCenter.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.blobMaintenance.flushPendingPersists()
                }
            )
        }
    }
}

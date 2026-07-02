import Combine
import Foundation

@MainActor
final class BrowserManagerInitializationWiringOwner {
    struct Dependencies {
        let attachShellRuntime: @MainActor () -> Void
        let attachRuntimeWiring: @MainActor () -> AnyCancellable
        let handleTabManagerDataLoaded: @MainActor () -> Void
        let scheduleBrowsingDataRetentionCleanup: @MainActor () -> Void
        let beginProtectionRestoreForStartupIfNeeded: @MainActor () -> Void
    }

    private let notificationCenter: NotificationCenter
    private let notificationQueue: OperationQueue?
    private let dependencies: Dependencies
    private var structuralChangeCancellable: AnyCancellable?
    private var tabManagerLoadObserverToken: NSObjectProtocol?
    private var browsingDataRetentionObserverToken: NSObjectProtocol?

    init(
        notificationCenter: NotificationCenter = .default,
        notificationQueue: OperationQueue? = .main,
        dependencies: Dependencies
    ) {
        self.notificationCenter = notificationCenter
        self.notificationQueue = notificationQueue
        self.dependencies = dependencies
    }

    deinit {
        MainActor.assumeIsolated {
            cancel()
        }
    }

    func finishInitializationWiring() {
        dependencies.attachShellRuntime()
        structuralChangeCancellable = dependencies.attachRuntimeWiring()

        tabManagerLoadObserverToken = notificationCenter.addObserver(
            forName: .tabManagerDidLoadInitialData,
            object: nil,
            queue: notificationQueue
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dependencies.handleTabManagerDataLoaded()
            }
        }

        browsingDataRetentionObserverToken = notificationCenter.addObserver(
            forName: .sumiBrowsingDataRetentionChanged,
            object: nil,
            queue: notificationQueue
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dependencies.scheduleBrowsingDataRetentionCleanup()
            }
        }

        dependencies.beginProtectionRestoreForStartupIfNeeded()
    }

    func cancel() {
        structuralChangeCancellable?.cancel()
        structuralChangeCancellable = nil

        if let token = tabManagerLoadObserverToken {
            notificationCenter.removeObserver(token)
            tabManagerLoadObserverToken = nil
        }

        if let token = browsingDataRetentionObserverToken {
            notificationCenter.removeObserver(token)
            browsingDataRetentionObserverToken = nil
        }
    }
}

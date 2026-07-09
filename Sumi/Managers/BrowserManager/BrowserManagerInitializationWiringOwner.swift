import Combine
import Foundation
import SumiBrowserCore

@MainActor
final class BrowserManagerInitializationWiringOwner {
    private let notificationCenter: NotificationCenter
    private let notificationQueue: OperationQueue?
    private let attachShellRuntime: @MainActor () -> Void
    private let attachRuntimeWiring: @MainActor () -> AnyCancellable
    private let handleTabManagerDataLoaded: @MainActor () -> Void
    private let scheduleBrowsingDataRetentionCleanup: @MainActor () -> Void
    private let beginProtectionRestoreForStartupIfNeeded: @MainActor () -> Void
    private let tabStructureEventBus: TabStructureEventBus?
    private var structuralChangeCancellable: AnyCancellable?
    private var initialDataLoadedCancellable: AnyCancellable?
    private var tabManagerLoadObserverToken: NSObjectProtocol?
    private var browsingDataRetentionObserverToken: NSObjectProtocol?

    init(
        notificationCenter: NotificationCenter = .default,
        notificationQueue: OperationQueue? = .main,
        tabStructureEventBus: TabStructureEventBus? = nil,
        attachShellRuntime: @escaping @MainActor () -> Void,
        attachRuntimeWiring: @escaping @MainActor () -> AnyCancellable,
        handleTabManagerDataLoaded: @escaping @MainActor () -> Void,
        scheduleBrowsingDataRetentionCleanup: @escaping @MainActor () -> Void,
        beginProtectionRestoreForStartupIfNeeded: @escaping @MainActor () -> Void
    ) {
        self.notificationCenter = notificationCenter
        self.notificationQueue = notificationQueue
        self.tabStructureEventBus = tabStructureEventBus
        self.attachShellRuntime = attachShellRuntime
        self.attachRuntimeWiring = attachRuntimeWiring
        self.handleTabManagerDataLoaded = handleTabManagerDataLoaded
        self.scheduleBrowsingDataRetentionCleanup = scheduleBrowsingDataRetentionCleanup
        self.beginProtectionRestoreForStartupIfNeeded = beginProtectionRestoreForStartupIfNeeded
    }

    deinit {
        MainActor.assumeIsolated {
            cancel()
        }
    }

    func finishInitializationWiring() {
        attachShellRuntime()
        structuralChangeCancellable = attachRuntimeWiring()

        if let tabStructureEventBus {
            initialDataLoadedCancellable = tabStructureEventBus.initialDataLoadedPublisher
                .receive(on: RunLoop.main)
                .sink { [weak self] in
                    self?.handleTabManagerDataLoaded()
                }
        } else {
            tabManagerLoadObserverToken = notificationCenter.addObserver(
                forName: .tabManagerDidLoadInitialData,
                object: nil,
                queue: notificationQueue
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleTabManagerDataLoaded()
                }
            }
        }

        browsingDataRetentionObserverToken = notificationCenter.addObserver(
            forName: .sumiBrowsingDataRetentionChanged,
            object: nil,
            queue: notificationQueue
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleBrowsingDataRetentionCleanup()
            }
        }

        beginProtectionRestoreForStartupIfNeeded()
    }

    func cancel() {
        structuralChangeCancellable?.cancel()
        structuralChangeCancellable = nil
        initialDataLoadedCancellable?.cancel()
        initialDataLoadedCancellable = nil

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

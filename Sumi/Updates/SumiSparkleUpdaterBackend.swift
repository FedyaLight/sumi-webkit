import Foundation

#if canImport(Combine)
import Combine
#endif

#if canImport(Sparkle)
import Sparkle

@MainActor
final class SumiSparkleUpdaterBackend: SumiUpdaterBackend {
    private weak var service: SumiUpdaterService?
    private let delegate: SumiSparkleUpdaterDelegate
    private let userDriver: SumiSparkleUserDriver
    private let updater: SPUUpdater

    #if canImport(Combine)
    private var cancellables = Set<AnyCancellable>()
    #endif

    init(service: SumiUpdaterService) {
        self.service = service
        self.delegate = SumiSparkleUpdaterDelegate(service: service)
        self.userDriver = SumiSparkleUserDriver(service: service)
        self.updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: delegate
        )
        observeUpdaterState()
    }

    var canCheckForUpdates: Bool {
        updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        updater.automaticallyChecksForUpdates
    }

    var lastUpdateCheckDate: Date? {
        updater.lastUpdateCheckDate
    }

    var feedURL: URL? {
        updater.feedURL
    }

    var isSparkleAvailable: Bool {
        true
    }

    var isConfigured: Bool {
        feedURL != nil
    }

    func start() {
        do {
            try updater.start()
        } catch {
            service?.recordUpdateOperation(
                SumiUpdateOperationNotice(
                    stage: .failed,
                    title: "Updates unavailable",
                    detail: error.localizedDescription,
                    progress: nil
                )
            )
        }
    }

    func checkForUpdateInformation() {
        updater.checkForUpdateInformation()
    }

    func installAvailableUpdate() {
        userDriver.installAvailableUpdate()
        updater.checkForUpdates()
    }

    private func observeUpdaterState() {
        #if canImport(Combine)
        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak service] _ in
                Task { @MainActor in
                    service?.syncStateFromBackend()
                }
            }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak service] _ in
                Task { @MainActor in
                    service?.syncStateFromBackend()
                }
            }
            .store(in: &cancellables)
        #endif
    }
}
#endif

import Foundation

#if canImport(Sparkle)
import Sparkle

final class SumiSparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    private weak var service: SumiUpdaterService?

    init(service: SumiUpdaterService) {
        self.service = service
    }

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let availableUpdate = SumiSparkleAppcastItemMapper.availableUpdate(from: item)
        Task { @MainActor [weak service] in
            service?.recordAvailableUpdate(availableUpdate)
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        let lastUpdateCheckDate = updater.lastUpdateCheckDate
        Task { @MainActor [weak service] in
            service?.recordNoUpdateAvailable(lastCheckedAt: lastUpdateCheckDate)
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        let lastUpdateCheckDate = updater.lastUpdateCheckDate
        Task { @MainActor [weak service] in
            service?.recordNoUpdateAvailable(lastCheckedAt: lastUpdateCheckDate)
        }
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        let errorMessage: String?
        if let error = error as NSError?,
           error.domain == SUSparkleErrorDomain && (error.code == SUError.noUpdateError.rawValue || error.code == 2 || error.code == 1001) {
            errorMessage = nil
        } else {
            errorMessage = error?.localizedDescription
        }
        Task { @MainActor [weak service] in
            service?.recordUpdateCheckFinished(errorMessage: errorMessage)
            service?.syncStateFromBackend()
        }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let errorMessage = error.localizedDescription
        Task { @MainActor [weak service] in
            service?.recordUpdateCheckFinished(errorMessage: errorMessage)
            service?.syncStateFromBackend()
        }
    }
}
#endif

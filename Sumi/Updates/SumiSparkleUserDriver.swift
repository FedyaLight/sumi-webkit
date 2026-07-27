import Foundation

#if canImport(Sparkle)
import Sparkle

@MainActor
final class SumiSparkleUserDriver: NSObject, SPUUserDriver {
    private weak var service: SumiUpdaterService?
    private var shouldInstallNextShownUpdate = false
    private var isInstallingFromSidebar = false
    private var readyToInstallReply: ((SPUUserUpdateChoice) -> Void)?
    private var expectedDownloadLength: UInt64 = 0
    private var downloadedLength: UInt64 = 0
    private var lastReportedDownloadPercentage: Int?

    init(service: SumiUpdaterService) {
        self.service = service
    }

    func installAvailableUpdate() {
        if let readyToInstallReply {
            self.readyToInstallReply = nil
            isInstallingFromSidebar = true
            readyToInstallReply(.install)
            return
        }

        shouldInstallNextShownUpdate = true
        isInstallingFromSidebar = true
        service?.recordUpdateInstallStarted()
    }

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        reply(
            SUUpdatePermissionResponse(
                automaticUpdateChecks: true,
                automaticUpdateDownloading: nil,
                sendSystemProfile: false
            )
        )
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        service?.syncStateFromBackend()
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        let availableUpdate = SumiSparkleAppcastItemMapper.availableUpdate(from: appcastItem)
        service?.recordAvailableUpdate(availableUpdate)

        guard shouldInstallNextShownUpdate, appcastItem.isInformationOnlyUpdate == false else {
            isInstallingFromSidebar = false
            reply(.dismiss)
            return
        }

        shouldInstallNextShownUpdate = false
        reply(.install)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        shouldInstallNextShownUpdate = false
        isInstallingFromSidebar = false
        resetDownloadProgress()
        service?.recordNoUpdateAvailable()
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        shouldInstallNextShownUpdate = false
        isInstallingFromSidebar = false
        readyToInstallReply = nil
        resetDownloadProgress()
        service?.recordUpdateOperation(
            SumiUpdateOperationNotice(
                stage: .failed,
                title: "Update failed",
                detail: error.localizedDescription,
                progress: nil
            )
        )
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        resetDownloadProgress()
        service?.recordUpdateOperation(
            SumiUpdateOperationNotice(
                stage: .downloading,
                title: "Updating Sumi",
                detail: "Downloading update...",
                progress: nil
            )
        )
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        self.expectedDownloadLength = expectedContentLength
        downloadedLength = 0
        lastReportedDownloadPercentage = nil
        publishDownloadProgress()
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        downloadedLength += length
        publishDownloadProgress()
    }

    func showDownloadDidStartExtractingUpdate() {
        resetDownloadProgress()
        service?.recordUpdateOperation(
            SumiUpdateOperationNotice(
                stage: .extracting,
                title: "Preparing update",
                detail: "Verifying and extracting the update...",
                progress: nil
            )
        )
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        service?.recordUpdateOperation(
            SumiUpdateOperationNotice(
                stage: .extracting,
                title: "Preparing update",
                detail: "Extracting update...",
                progress: progress
            )
        )
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        service?.recordUpdateOperation(
            SumiUpdateOperationNotice(
                stage: .readyToInstall,
                title: "Ready to install",
                detail: "Ready to install and restart Sumi.",
                progress: nil
            )
        )

        guard isInstallingFromSidebar else {
            readyToInstallReply = reply
            return
        }
        reply(.install)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        service?.recordUpdateOperation(
            SumiUpdateOperationNotice(
                stage: .installing,
                title: "Installing update",
                detail: "Installing update...",
                progress: nil
            )
        )
    }

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        shouldInstallNextShownUpdate = false
        isInstallingFromSidebar = false
        readyToInstallReply = nil
        resetDownloadProgress()
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        shouldInstallNextShownUpdate = false
        isInstallingFromSidebar = false
        readyToInstallReply = nil
        resetDownloadProgress()
    }

    func showUpdateInFocus() {
        service?.syncStateFromBackend()
    }

    private func publishDownloadProgress() {
        guard expectedDownloadLength > 0 else { return }

        let totalLength = max(expectedDownloadLength, downloadedLength)
        let progress = min(Double(downloadedLength) / Double(totalLength), 1)
        let percentage = Int((progress * 100).rounded(.down))
        guard percentage != lastReportedDownloadPercentage else { return }

        lastReportedDownloadPercentage = percentage
        service?.recordUpdateOperation(
            SumiUpdateOperationNotice(
                stage: .downloading,
                title: "Updating Sumi",
                detail: "Downloading update...",
                progress: progress
            )
        )
    }

    private func resetDownloadProgress() {
        expectedDownloadLength = 0
        downloadedLength = 0
        lastReportedDownloadPercentage = nil
    }
}
#endif

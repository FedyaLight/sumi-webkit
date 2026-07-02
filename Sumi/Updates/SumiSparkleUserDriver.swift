import Foundation

#if canImport(Sparkle)
import Sparkle

@MainActor
final class SumiSparkleUserDriver: NSObject, SPUUserDriver {
    private weak var service: SumiUpdaterService?
    private var shouldInstallNextShownUpdate = false
    private var isInstallingFromSidebar = false
    private var readyToInstallReply: ((SPUUserUpdateChoice) -> Void)?

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
        service?.recordNoUpdateAvailable()
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        shouldInstallNextShownUpdate = false
        isInstallingFromSidebar = false
        readyToInstallReply = nil
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
        service?.recordUpdateOperation(
            SumiUpdateOperationNotice(
                stage: .downloading,
                title: "Updating Sumi",
                detail: "Downloading update...",
                progress: nil
            )
        )
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}

    func showDownloadDidReceiveData(ofLength length: UInt64) {}

    func showDownloadDidStartExtractingUpdate() {
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
        service?.syncStateFromBackend()
    }

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        shouldInstallNextShownUpdate = false
        isInstallingFromSidebar = false
        readyToInstallReply = nil
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        shouldInstallNextShownUpdate = false
        isInstallingFromSidebar = false
        readyToInstallReply = nil
    }

    func showUpdateInFocus() {
        service?.syncStateFromBackend()
    }
}
#endif

import Foundation
import WebKit

/// Restores semantic tab intent after physical WebViews have been blanked for
/// website-data mutation. Replacement WebViews inherit the restore obligation,
/// and failed attempts retry until success or terminal browser shutdown.
@MainActor
final class WebsiteDataCleanupRestoreLoop {
    typealias MutationPermissionWaiter = @MainActor (WKWebView) async -> Bool
    typealias TabRestorer = @MainActor (
        Tab,
        URL
    ) -> WebsiteDataCleanupRestoreCommandReceipt

    private static let initialRetryDelay: Duration = .milliseconds(25)
    private static let maximumRetryDelay: Duration = .seconds(1)

    private let navigationBarrier: WebsiteDataCleanupNavigationBarrier
    private let liveWebViews: @MainActor (Tab) -> [WKWebView]
    private let waitForMutationPermission: MutationPermissionWaiter
    private let restoreTab: TabRestorer
    private let restoreAttemptTimeout: Duration

    init(
        navigationBarrier: WebsiteDataCleanupNavigationBarrier,
        liveWebViews: @escaping @MainActor (Tab) -> [WKWebView],
        waitForMutationPermission: @escaping MutationPermissionWaiter,
        restoreTab: @escaping TabRestorer,
        restoreAttemptTimeout: Duration
    ) {
        self.navigationBarrier = navigationBarrier
        self.liveWebViews = liveWebViews
        self.waitForMutationPermission = waitForMutationPermission
        self.restoreTab = restoreTab
        self.restoreAttemptTimeout = restoreAttemptTimeout
    }

    func restore(
        _ participants: [WebsiteDataCleanupNavigationBarrier.Participant],
        in session: WebsiteDataCleanupNavigationBarrier.Session,
        isTerminallyShutDown: @escaping @MainActor () -> Bool
    ) async -> Bool {
        guard participants.isEmpty == false else { return true }

        var pendingByTabID: [UUID: [WebsiteDataCleanupNavigationBarrier.Participant]] = [:]
        for participant in participants {
            guard navigationBarrier.stillOwns(participant) else {
                navigationBarrier.abandon(participant)
                continue
            }
            pendingByTabID[participant.tab.id, default: []].append(participant)
        }

        var retryDelay = Self.initialRetryDelay
        while pendingByTabID.isEmpty == false {
            guard isTerminallyShutDown() == false else {
                navigationBarrier.abandon(Array(pendingByTabID.values.joined()))
                return false
            }

            var failedByTabID: [UUID: [WebsiteDataCleanupNavigationBarrier.Participant]] = [:]
            for tabParticipants in pendingByTabID.values {
                let stillOwnedParticipants = tabParticipants.filter(
                    navigationBarrier.stillOwns
                )
                guard let tab = stillOwnedParticipants.first?.tab else {
                    navigationBarrier.abandon(tabParticipants)
                    continue
                }

                var canRestore = true
                for participant in stillOwnedParticipants {
                    guard await waitForMutationPermission(participant.webView),
                          navigationBarrier.stillOwns(participant),
                          isTerminallyShutDown() == false else {
                        canRestore = false
                        break
                    }
                }
                guard canRestore else {
                    if isTerminallyShutDown() {
                        navigationBarrier.abandon(stillOwnedParticipants)
                        return false
                    }
                    navigationBarrier.markBlanked(stillOwnedParticipants)
                    failedByTabID[tab.id] = stillOwnedParticipants
                    continue
                }

                let targetURL = tab.mainFrameLoads.currentIntent.targetURL
                navigationBarrier.beginRestoreAttempt(
                    stillOwnedParticipants,
                    targetURL: targetURL,
                    timeout: restoreAttemptTimeout
                )

                let receipt = restoreTab(tab, targetURL)
                for participant in stillOwnedParticipants {
                    navigationBarrier.bindRestoreReceipt(receipt, to: participant)
                }
                if receipt.outcome == .failed || receipt.semanticRevision == nil {
                    navigationBarrier.rejectRestoreAttempt(stillOwnedParticipants)
                }

                var didRestoreTab = true
                for participant in stillOwnedParticipants {
                    let didRestore = await navigationBarrier
                        .awaitRestoreTermination(for: participant)
                    didRestoreTab = didRestoreTab && didRestore
                }
                navigationBarrier.finishRestoreAttempt(
                    stillOwnedParticipants,
                    succeeded: didRestoreTab
                )

                let currentParticipants = navigationBarrier.currentRestoreParticipants(
                    for: tab,
                    liveWebViews: liveWebViews(tab),
                    in: session
                )
                let pendingParticipants = navigationBarrier.pendingRestoreParticipants(
                    among: currentParticipants
                )
                if pendingParticipants.isEmpty == false {
                    navigationBarrier.markBlanked(pendingParticipants)
                    failedByTabID[tab.id] = pendingParticipants
                }
            }

            pendingByTabID = failedByTabID
            guard pendingByTabID.isEmpty == false else { break }
            do {
                try await Task.sleep(for: retryDelay)
            } catch {
                guard isTerminallyShutDown() else {
                    // Caller cancellation cannot cancel post-deletion
                    // compensation; only terminal shutdown may end it.
                    continue
                }
                navigationBarrier.abandon(Array(pendingByTabID.values.joined()))
                return false
            }
            retryDelay = min(retryDelay * 2, Self.maximumRetryDelay)
        }
        return true
    }
}

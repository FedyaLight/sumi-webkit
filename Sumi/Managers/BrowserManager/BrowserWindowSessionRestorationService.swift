import Foundation

@MainActor
protocol BrowserStartupSessionReconciling: AnyObject {
    func reconcileStartupSessionIfPossible()
}

extension BrowserManager: BrowserStartupSessionReconciling {}

/// Resolves a newly registered window before extension-open notification and
/// before the registry's subsequent active-window workflow can run.
@MainActor
final class BrowserWindowSessionRestorationService {
    private struct PendingPublication {
        let windowIdentity: ObjectIdentifier
        var isRegistryCommitted: Bool
    }

    private let restoration: WindowSessionRestoreService
    private let tabResidences: BrowserTabResidenceAuthority
    private let extensionPublication: WindowExtensionPublicationTransaction
    private let currentProfile: BrowserCurrentProfileAuthority
    private weak var startupSessions: (any BrowserStartupSessionReconciling)?
    private var pendingPublicationsByWindowID: [UUID: PendingPublication] = [:]

    init(
        restoration: WindowSessionRestoreService,
        tabResidences: BrowserTabResidenceAuthority,
        extensionPublication: WindowExtensionPublicationTransaction,
        currentProfile: BrowserCurrentProfileAuthority,
        startupSessions: any BrowserStartupSessionReconciling
    ) {
        self.restoration = restoration
        self.tabResidences = tabResidences
        self.extensionPublication = extensionPublication
        self.currentProfile = currentProfile
        self.startupSessions = startupSessions
    }

    /// Standalone atomic entry point used outside WindowRegistry binding.
    /// Registry-backed shell creation calls prepare/commit separately.
    func restore(_ windowState: BrowserWindowState) {
        prepareRegistration(windowState)
        commitRegistration(windowState)
    }

    func prepareRegistration(_ windowState: BrowserWindowState) {
        restoreModels([windowState])
    }

    func commitRegistration(_ windowState: BrowserWindowState) {
        publishCommittedWindows([windowState])
    }

    /// Registration is a two-phase transaction: first every model in the
    /// batch is restored, then extension/startup observers can see the batch.
    /// An observer can therefore never see a half-restored preloaded registry.
    func restoreRegisteredWindows(_ windowStates: [BrowserWindowState]) {
        restoreModels(windowStates)
        publishCommittedWindows(windowStates)
    }

    private func restoreModels(_ windowStates: [BrowserWindowState]) {
        for windowState in windowStates {
            tabResidences.establishResidenceSession(on: windowState)
            extensionPublication.prepareRegistration(windowState)
            if windowState.isIncognito {
                pendingPublicationsByWindowID[windowState.id] =
                    PendingPublication(
                        windowIdentity: ObjectIdentifier(windowState),
                        isRegistryCommitted: false
                    )
                continue
            }

            restoration.restoreRegisteredWindow(
                windowState,
                currentProfile: currentProfile.currentProfile
            )
            pendingPublicationsByWindowID[windowState.id] =
                PendingPublication(
                    windowIdentity: ObjectIdentifier(windowState),
                    isRegistryCommitted: false
                )
        }
    }

    private func publishCommittedWindows(
        _ windowStates: [BrowserWindowState]
    ) {
        var readyForPublication: [BrowserWindowState] = []
        for windowState in windowStates {
            guard var pending = pendingPublicationsByWindowID[windowState.id],
                  pending.windowIdentity == ObjectIdentifier(windowState)
            else {
                continue
            }

            pending.isRegistryCommitted = true
            if windowState.restorationState.isAwaitingInitialResolution {
                pendingPublicationsByWindowID[windowState.id] = pending
            } else {
                pendingPublicationsByWindowID.removeValue(
                    forKey: windowState.id
                )
                readyForPublication.append(windowState)
            }
        }

        publishOpenedWindows(readyForPublication)
        if readyForPublication.contains(where: { $0.isIncognito == false }) {
            startupSessions?.reconcileStartupSessionIfPossible()
        }
    }

    /// Publishes only the exact registered objects that were deferred during
    /// restoration and have now completed initial TabManager reconciliation.
    /// Startup reconciliation remains owned by the data-loaded workflow, so a
    /// whole batch produces one startup transition rather than one per window.
    func completePendingRegistrations(
        registeredWindows: [BrowserWindowState]
    ) {
        var readyForPublication: [BrowserWindowState] = []
        let registeredWindowIDs = Set(registeredWindows.map(\.id))
        let pendingWindowIDs = Array(pendingPublicationsByWindowID.keys)
        extensionPublication.discardRegistrations(
            notIn: registeredWindows
        )

        for windowID in pendingWindowIDs
            where registeredWindowIDs.contains(windowID) == false {
            pendingPublicationsByWindowID.removeValue(forKey: windowID)
        }

        for windowState in registeredWindows {
            guard let pending = pendingPublicationsByWindowID[windowState.id]
            else { continue }
            let windowID = windowState.id
            guard pending.windowIdentity == ObjectIdentifier(windowState) else {
                pendingPublicationsByWindowID.removeValue(forKey: windowID)
                continue
            }
            guard pending.isRegistryCommitted,
                  windowState.isIncognito == false,
                  windowState.restorationState.isAwaitingInitialResolution == false
            else {
                continue
            }

            pendingPublicationsByWindowID.removeValue(forKey: windowID)
            readyForPublication.append(windowState)
        }

        publishOpenedWindows(readyForPublication)
    }

    /// Cancels deferred publication without allowing a replacement object
    /// that happens to reuse the UUID to consume the original registration.
    func discardRegistration(_ windowState: BrowserWindowState) {
        if pendingPublicationsByWindowID[windowState.id]?.windowIdentity
            == ObjectIdentifier(windowState) {
            pendingPublicationsByWindowID.removeValue(
                forKey: windowState.id
            )
        }
        extensionPublication.discardRegistration(windowState)
    }

    private func publishOpenedWindows(
        _ windowStates: [BrowserWindowState]
    ) {
        for windowState in windowStates {
            extensionPublication.commitRegistration(windowState)
        }
    }
}

import Foundation

@MainActor
protocol BrowserStartupSessionReconciling: AnyObject {
    func reconcileStartupSessionIfPossible()
}

extension BrowserManager: BrowserStartupSessionReconciling {}

/// The extension events whose payload depends on a fully resolved window
/// model. Keeping this capability narrow makes publication ordering explicit
/// without exposing the extension module as a general-purpose dependency.
@MainActor
protocol BrowserWindowExtensionLifecycleNotifying: AnyObject {
    func notifyWindowOpenedIfLoaded(_ windowState: BrowserWindowState)
    func notifyWindowFocusedIfLoaded(_ windowState: BrowserWindowState)
}

extension SumiExtensionsModule: BrowserWindowExtensionLifecycleNotifying {}

/// Resolves a newly registered window before extension-open notification and
/// before the registry's subsequent active-window workflow can run.
@MainActor
final class BrowserWindowSessionRestorationService {
    private struct PendingPublication {
        let windowIdentity: ObjectIdentifier
    }

    private let restoration: WindowSessionRestoreService
    private let extensions: any BrowserWindowExtensionLifecycleNotifying
    private weak var profileSupport: (any SumiProfileRoutingSupport)?
    private weak var startupSessions: (any BrowserStartupSessionReconciling)?
    private var pendingPublicationsByWindowID: [UUID: PendingPublication] = [:]

    init(
        restoration: WindowSessionRestoreService,
        extensions: any BrowserWindowExtensionLifecycleNotifying,
        profileSupport: any SumiProfileRoutingSupport,
        startupSessions: any BrowserStartupSessionReconciling
    ) {
        self.restoration = restoration
        self.extensions = extensions
        self.profileSupport = profileSupport
        self.startupSessions = startupSessions
    }

    func restore(_ windowState: BrowserWindowState) {
        restoreRegisteredWindows([windowState])
    }

    /// Registration is a two-phase transaction: first every model in the
    /// batch is restored, then extension/startup observers can see the batch.
    /// An observer can therefore never see a half-restored preloaded registry.
    func restoreRegisteredWindows(_ windowStates: [BrowserWindowState]) {
        var readyForPublication: [BrowserWindowState] = []

        for windowState in windowStates {
            if windowState.isIncognito {
                pendingPublicationsByWindowID.removeValue(
                    forKey: windowState.id
                )
                readyForPublication.append(windowState)
                continue
            }

            restoration.restoreRegisteredWindow(
                windowState,
                currentProfile: profileSupport?.currentProfile
            )
            if windowState.isAwaitingInitialSessionResolution {
                pendingPublicationsByWindowID[windowState.id] =
                    PendingPublication(
                        windowIdentity: ObjectIdentifier(windowState)
                    )
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
            guard windowState.isIncognito == false,
                  windowState.isAwaitingInitialSessionResolution == false
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
        guard pendingPublicationsByWindowID[windowState.id]?.windowIdentity
                == ObjectIdentifier(windowState)
        else {
            return
        }
        pendingPublicationsByWindowID.removeValue(forKey: windowState.id)
    }

    private func publishOpenedWindows(
        _ windowStates: [BrowserWindowState]
    ) {
        for windowState in windowStates {
            extensions.notifyWindowOpenedIfLoaded(windowState)
        }
    }
}

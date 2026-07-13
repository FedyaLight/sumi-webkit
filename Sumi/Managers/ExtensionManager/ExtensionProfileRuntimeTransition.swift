import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
protocol ExtensionInactiveProfileContextRetiring: AnyObject {
    func unloadExtensionContextsForInactiveProfiles(keepingProfileId: UUID)
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionToolbarProfileReloading: AnyObject {
    func reloadPinnedToolbarExtensionsForCurrentProfile()
}

/// Applies one profile switch to the extension runtime, then performs the
/// deferred WebView/UI reconciliation only while its monotonic receipt is
/// still current. Returning to the same profile does not revive older work.
@available(macOS 15.5, *)
@MainActor
final class ExtensionProfileRuntimeTransition {
    struct Receipt: Equatable {
        fileprivate let revision: UInt64
        let profileID: UUID
        fileprivate let controller: WKWebExtensionController?

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.revision == rhs.revision
                && lhs.profileID == rhs.profileID
                && lhs.controller === rhs.controller
        }
    }

    private let installedExtensions: InstalledExtensionCollection
    private let profileRuntime: ExtensionProfileRuntime
    private let runtimeLifecycle: ExtensionRuntimeLifecycleAuthority
    private let browserConfiguration: BrowserConfiguration
    private let controllerProvisioning: any ExtensionControllerProvisioning
    private let inactiveContextRetirement:
        any ExtensionInactiveProfileContextRetiring
    private let actionAnchors: ExtensionActionPopupAnchorStore
    private let toolbarProfiles: any ExtensionToolbarProfileReloading
    private let extensionSupportAvailable: Bool
    private let reconcileProfile: @MainActor (UUID) -> Void
    private let refreshActionSurfaces: @MainActor (UUID) -> Void

    private var revision: UInt64 = 0
    private var pendingReconciliation: Task<Void, Never>?

    init(
        installedExtensions: InstalledExtensionCollection,
        profileRuntime: ExtensionProfileRuntime,
        runtimeLifecycle: ExtensionRuntimeLifecycleAuthority,
        browserConfiguration: BrowserConfiguration,
        controllerProvisioning: any ExtensionControllerProvisioning,
        inactiveContextRetirement: any ExtensionInactiveProfileContextRetiring,
        actionAnchors: ExtensionActionPopupAnchorStore,
        toolbarProfiles: any ExtensionToolbarProfileReloading,
        extensionSupportAvailable: Bool,
        reconcileProfile: @escaping @MainActor (UUID) -> Void,
        refreshActionSurfaces: @escaping @MainActor (UUID) -> Void
    ) {
        self.installedExtensions = installedExtensions
        self.profileRuntime = profileRuntime
        self.runtimeLifecycle = runtimeLifecycle
        self.browserConfiguration = browserConfiguration
        self.controllerProvisioning = controllerProvisioning
        self.inactiveContextRetirement = inactiveContextRetirement
        self.actionAnchors = actionAnchors
        self.toolbarProfiles = toolbarProfiles
        self.extensionSupportAvailable = extensionSupportAvailable
        self.reconcileProfile = reconcileProfile
        self.refreshActionSurfaces = refreshActionSurfaces
    }

    @discardableResult
    func switchProfile(profileID: UUID) -> Receipt {
        let signpostState = PerformanceTrace.beginInterval(
            "ExtensionManager.switchProfile"
        )
        defer {
            PerformanceTrace.endInterval(
                "ExtensionManager.switchProfile",
                signpostState
            )
        }

        pendingReconciliation?.cancel()
        precondition(revision < UInt64.max, "Extension profile transition exhausted")
        revision += 1
        let pendingReceipt = Receipt(
            revision: revision,
            profileID: profileID,
            controller: nil
        )

        let catalogSnapshot = installedExtensions.records
        let enabledExtensionIDs = Set(
            catalogSnapshot.lazy.filter(\.isEnabled).map(\.id)
        )
        let hasEnabledExtensionDemand = enabledExtensionIDs.isEmpty == false
        let runtimeInitialized = profileRuntime.activateProfile(
            profileID,
            hasExtensionDemand: hasEnabledExtensionDemand,
            runtimeIsReadyOrLoading: runtimeLifecycle.isReadyOrLoading
        )
        actionAnchors.clearAnchors(notMatching: profileID)
        toolbarProfiles.reloadPinnedToolbarExtensionsForCurrentProfile()

        guard extensionSupportAvailable, runtimeInitialized else {
            return pendingReceipt
        }
        let controller = controllerProvisioning.ensureExtensionController(
            for: profileID
        )
        browserConfiguration.webViewConfiguration.webExtensionController =
            controller
        let readiness = profileRuntime.readinessContext(
            for: profileID,
            hasEnabledExtensionDemand: hasEnabledExtensionDemand,
            enabledExtensionIDs: enabledExtensionIDs,
            globalRuntimeReady: runtimeLifecycle.isReady
        )
        runtimeLifecycle.updateReadiness(isReady: readiness.isProfileReady)
        inactiveContextRetirement.unloadExtensionContextsForInactiveProfiles(
            keepingProfileId: profileID
        )

        let receipt = Receipt(
            revision: revision,
            profileID: profileID,
            controller: controller
        )
        pendingReconciliation = Task { @MainActor [weak self] in
            await Task.yield()
            guard Task.isCancelled == false else { return }
            self?.settle(receipt)
        }
        return receipt
    }

    func settleImmediately(_ receipt: Receipt) {
        guard isCurrent(receipt) else { return }
        pendingReconciliation?.cancel()
        settle(receipt)
    }

    func isCurrent(_ receipt: Receipt) -> Bool {
        receipt.revision == revision
            && receipt.profileID == profileRuntime.currentProfileId
    }

    private func settle(_ receipt: Receipt) {
        guard let controller = receipt.controller,
              isCurrent(receipt),
              profileRuntime.controller(for: receipt.profileID) === controller,
              browserConfiguration.webViewConfiguration
                .webExtensionController === controller
        else { return }
        reconcileProfile(receipt.profileID)
        guard isCurrent(receipt),
              profileRuntime.controller(for: receipt.profileID) === controller,
              browserConfiguration.webViewConfiguration
                .webExtensionController === controller
        else { return }
        refreshActionSurfaces(receipt.profileID)
    }
}

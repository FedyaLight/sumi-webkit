import Foundation
import WebKit

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
        fileprivate let profileAdmission: ProfileReferenceAdmissionReceipt?

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.revision == rhs.revision
                && lhs.profileID == rhs.profileID
                && lhs.controller === rhs.controller
                && lhs.profileAdmission == rhs.profileAdmission
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
        self.reconcileProfile = reconcileProfile
        self.refreshActionSurfaces = refreshActionSurfaces
    }

    @discardableResult
    func switchProfile(
        profileID: UUID,
        mutationLease suppliedMutationLease: ProfileReferenceMutationLease? = nil
    ) -> Receipt {
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
            controller: nil,
            profileAdmission: nil
        )

        let ownsMutationLease = suppliedMutationLease == nil
        guard let profileAdmission = profileRuntime.admitProfileReference(
            to: profileID
        ), let mutationLease = suppliedMutationLease
            ?? profileRuntime.beginProfileReferenceMutation(to: profileID)
            ?? profileRuntime.beginProfileRetirementMigration(to: profileID),
           profileRuntime.validateProfileReferenceMutation(
            mutationLease,
            profileID: profileID
           ) else { return pendingReceipt }
        defer {
            if ownsMutationLease {
                precondition(profileRuntime.endProfileReferenceMutation(mutationLease))
            }
        }
        let catalogSnapshot = installedExtensions.records
        let enabledExtensionIDs = Set(
            catalogSnapshot.lazy.filter(\.isEnabled).map(\.id)
        )
        let hasEnabledExtensionDemand = enabledExtensionIDs.isEmpty == false
        guard let runtimeInitialized = profileRuntime.activateProfileIfAdmitted(
            profileID,
            hasExtensionDemand: hasEnabledExtensionDemand,
            runtimeIsReadyOrLoading: runtimeLifecycle.isReadyOrLoading,
            mutationLease: mutationLease
        ) else { return pendingReceipt }
        actionAnchors.clearAnchors(notMatching: profileID)
        toolbarProfiles.reloadPinnedToolbarExtensionsForCurrentProfile()

        guard runtimeInitialized else {
            return pendingReceipt
        }
        if let publishedController = browserConfiguration.webViewConfiguration
            .webExtensionController,
           profileRuntime.profileId(for: publishedController) != profileID {
            browserConfiguration.webViewConfiguration.webExtensionController = nil
        }
        guard let controller = controllerProvisioning.controllerIfAdmitted(
            for: profileID,
            mutationLease: mutationLease
        ) else { return pendingReceipt }
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
            controller: controller,
            profileAdmission: profileAdmission
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
        guard let profileAdmission = receipt.profileAdmission else {
            return false
        }
        return receipt.revision == revision
            && receipt.profileID == profileRuntime.currentProfileId
            && profileRuntime.validateProfileReference(profileAdmission)
    }

    private func settle(_ receipt: Receipt) {
        guard let controller = receipt.controller,
              isCurrent(receipt),
              profileRuntime.controller(for: receipt.profileID) === controller,
              publishIfReady(
                profileID: receipt.profileID,
                controller: controller
              )
        else { return }
        refreshActionSurfaces(receipt.profileID)
    }

    @discardableResult
    func publishIfReady(
        profileID: UUID,
        controller: WKWebExtensionController
    ) -> Bool {
        guard profileRuntime.currentProfileId == profileID,
              profileRuntime.controller(for: profileID) === controller
        else { return false }
        let enabledExtensionIDs = Set(
            installedExtensions.records.lazy.filter(\.isEnabled).map(\.id)
        )
        let readiness = profileRuntime.readinessContext(
            for: profileID,
            hasEnabledExtensionDemand: enabledExtensionIDs.isEmpty == false,
            enabledExtensionIDs: enabledExtensionIDs,
            globalRuntimeReady: runtimeLifecycle.isReady
        )
        guard readiness.isProfileReady else { return false }

        browserConfiguration.webViewConfiguration.webExtensionController =
            controller
        reconcileProfile(profileID)
        return profileRuntime.currentProfileId == profileID
            && profileRuntime.controller(for: profileID) === controller
            && browserConfiguration.webViewConfiguration
                .webExtensionController === controller
    }
}

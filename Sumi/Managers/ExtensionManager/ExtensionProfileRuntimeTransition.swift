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

    private let readinessProbe: ExtensionProfileReadinessProbe
    private let transitionLease: ExtensionProfileTransitionLease
    private let profileRuntime: ExtensionProfileRuntime
    private let runtimeLifecycle: ExtensionRuntimeLifecycleAuthority
    private let browserConfiguration: BrowserConfiguration
    private let controllerProvisioning: any ExtensionControllerProvisioning
    private let surfaceHandoff: ExtensionProfileSurfaceHandoff
    private let reconcileProfile: @MainActor (UUID) -> Void
    private let refreshActionSurfaces: @MainActor (UUID) -> Void

    private var revision: UInt64 = 0
    private var pendingReconciliation: Task<Void, Never>?

    init(
        readinessProbe: ExtensionProfileReadinessProbe,
        transitionLease: ExtensionProfileTransitionLease,
        profileRuntime: ExtensionProfileRuntime,
        runtimeLifecycle: ExtensionRuntimeLifecycleAuthority,
        browserConfiguration: BrowserConfiguration,
        controllerProvisioning: any ExtensionControllerProvisioning,
        surfaceHandoff: ExtensionProfileSurfaceHandoff,
        reconcileProfile: @escaping @MainActor (UUID) -> Void,
        refreshActionSurfaces: @escaping @MainActor (UUID) -> Void
    ) {
        self.readinessProbe = readinessProbe
        self.transitionLease = transitionLease
        self.profileRuntime = profileRuntime
        self.runtimeLifecycle = runtimeLifecycle
        self.browserConfiguration = browserConfiguration
        self.controllerProvisioning = controllerProvisioning
        self.surfaceHandoff = surfaceHandoff
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

        guard let grant = transitionLease.acquire(
            profileID: profileID,
            suppliedMutationLease: suppliedMutationLease
        ) else { return pendingReceipt }
        defer { transitionLease.release(grant) }
        let enabledExtensionIDs = readinessProbe.enabledExtensionIDs
        guard let runtimeInitialized = profileRuntime.activateProfileIfAdmitted(
            profileID,
            hasExtensionDemand: enabledExtensionIDs.isEmpty == false,
            runtimeIsReadyOrLoading: runtimeLifecycle.isReadyOrLoading,
            mutationLease: grant.mutationLease
        ) else { return pendingReceipt }
        surfaceHandoff.prepareForActivation(of: profileID)
        guard runtimeInitialized else { return pendingReceipt }
        surfaceHandoff.detachForeignPublishedController(for: profileID)
        guard let controller = controllerProvisioning.controllerIfAdmitted(
            for: profileID,
            mutationLease: grant.mutationLease
        ) else { return pendingReceipt }
        runtimeLifecycle.updateReadiness(
            isReady: readinessProbe.isProfileReady(
                profileID,
                enabledExtensionIDs: enabledExtensionIDs
            )
        )
        surfaceHandoff.retireInactiveProfiles(keeping: profileID)
        let receipt = Receipt(
            revision: revision,
            profileID: profileID,
            controller: controller,
            profileAdmission: grant.profileAdmission
        )
        pendingReconciliation = Task { @MainActor [weak self] in
            await Task.yield()
            guard Task.isCancelled == false else { return }
            self?.settle(receipt)
        }
        return receipt
    }

    /// Makes the Profile-owned data store canonical before a controller or
    /// WebView is provisioned for the profile.
    func rememberProfile(_ profile: Profile) {
        _ = profileRuntime.rememberProfile(profile)
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
        guard readinessProbe.isProfileReady(
            profileID,
            enabledExtensionIDs: readinessProbe.enabledExtensionIDs
        ) else { return false }

        browserConfiguration.webViewConfiguration.webExtensionController =
            controller
        reconcileProfile(profileID)
        return profileRuntime.currentProfileId == profileID
            && profileRuntime.controller(for: profileID) === controller
            && browserConfiguration.webViewConfiguration
                .webExtensionController === controller
    }
}

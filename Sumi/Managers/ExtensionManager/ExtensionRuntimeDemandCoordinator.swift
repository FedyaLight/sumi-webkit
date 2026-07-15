import Foundation
import WebKit

/// Admits explicit extension-runtime demand for one resolved profile.
/// Catalog readiness remains owned by `InstalledExtensionCatalog`.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeDemandCoordinator {
    private enum Admission {
        case existingDemand
        case explicitRuntime
    }

    private let installedExtensions: InstalledExtensionCollection
    private let profileRuntime: ExtensionProfileRuntime
    private let runtimeLifecycle: ExtensionRuntimeLifecycleAuthority
    private let runtimeDemand: ExtensionRuntimeDemandAuthority
    private let controllerProvisioning: any ExtensionControllerProvisioning
    private let runtimeProfileID: @MainActor () -> UUID?
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        installedExtensions: InstalledExtensionCollection,
        profileRuntime: ExtensionProfileRuntime,
        runtimeLifecycle: ExtensionRuntimeLifecycleAuthority,
        runtimeDemand: ExtensionRuntimeDemandAuthority,
        controllerProvisioning: any ExtensionControllerProvisioning,
        runtimeProfileID: @escaping @MainActor () -> UUID?,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.installedExtensions = installedExtensions
        self.profileRuntime = profileRuntime
        self.runtimeLifecycle = runtimeLifecycle
        self.runtimeDemand = runtimeDemand
        self.controllerProvisioning = controllerProvisioning
        self.runtimeProfileID = runtimeProfileID
        self.diagnostics = diagnostics
    }

    @discardableResult
    func requestRuntimeIfDemanded(
        reason: ExtensionRuntimeDemandReason,
        profileId explicitProfileID: UUID? = nil
    ) -> WKWebExtensionController? {
        request(
            reason: reason,
            admission: .existingDemand,
            profileId: explicitProfileID
        )
    }

    @discardableResult
    func requestRuntimeExplicitly(
        reason: ExtensionRuntimeDemandReason,
        profileId explicitProfileID: UUID? = nil
    ) -> WKWebExtensionController? {
        request(
            reason: reason,
            admission: .explicitRuntime,
            profileId: explicitProfileID
        )
    }

    private func request(
        reason: ExtensionRuntimeDemandReason,
        admission: Admission,
        profileId explicitProfileID: UUID?
    ) -> WKWebExtensionController? {
        PerformanceTrace.emitEvent("ExtensionManager.lazyRuntimeRequested")

        guard runtimeLifecycle.state != .unavailable else { return nil }

        let catalogSnapshot = installedExtensions.records
        let enabledExtensionIDs = Set(
            catalogSnapshot.lazy.filter(\.isEnabled).map(\.id)
        )
        if case .existingDemand = admission {
            guard runtimeDemand.hasRuntimeDemand(
                hasEnabledExtensions: enabledExtensionIDs.isEmpty == false
            ) else { return nil }
        }

        let resolvedProfileID = explicitProfileID
            ?? profileRuntime.currentProfileId
            ?? runtimeProfileID()
        guard let resolvedProfileID else { return nil }

        if case .explicitRuntime = admission {
            runtimeDemand.recordRuntimeDemandWithoutEnabledExtensions()
        }

        let controller = controllerProvisioning.ensureExtensionController(
            for: resolvedProfileID
        )
        let readiness = profileRuntime.readinessContext(
            for: resolvedProfileID,
            hasEnabledExtensionDemand: enabledExtensionIDs.isEmpty == false,
            enabledExtensionIDs: enabledExtensionIDs,
            globalRuntimeReady: runtimeLifecycle.isReady
        )
        switch runtimeLifecycle.state {
        case .loading:
            return controller
        case .ready:
            guard readiness.isProfileReady else {
                runtimeLifecycle.beginLoading()
                return controller
            }
            return controller
        case .idle, .unavailable, .failed:
            runtimeLifecycle.beginLoading()
        }

        runtimeLifecycle.updateReadiness(isReady: readiness.isProfileReady)
        diagnostics.trace(
            "lazyRuntime controller-only reason=\(reason.rawValue) profileId=\(resolvedProfileID.uuidString) loadedContexts=\(profileRuntime.countLoadedExtensionContexts())"
        )
        return controller
    }
}

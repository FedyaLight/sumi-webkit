import Foundation
import WebKit

enum ExtensionRuntimeDemandReason: String {
    case webViewConfiguration
    case install
}

/// Admits explicit extension-runtime demand for one resolved profile.
/// Catalog readiness remains owned by `InstalledExtensionCatalog`; this role
/// only provisions a controller and advances runtime state.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeDemandCoordinator {
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
    func request(
        reason: ExtensionRuntimeDemandReason,
        allowWithoutEnabledExtensions: Bool = false,
        profileId explicitProfileID: UUID? = nil
    ) -> WKWebExtensionController? {
        PerformanceTrace.emitEvent("ExtensionManager.lazyRuntimeRequested")

        guard runtimeLifecycle.state != .unavailable else { return nil }

        // One catalog snapshot governs this entire admission. A concurrent
        // install/disable cannot change the meaning halfway through it.
        let catalogSnapshot = installedExtensions.records
        let enabledExtensionIDs = Set(
            catalogSnapshot.lazy.filter(\.isEnabled).map(\.id)
        )
        guard runtimeDemand.admitsRuntime(
            hasEnabledExtensions: enabledExtensionIDs.isEmpty == false,
            allowWithoutEnabledExtensions: allowWithoutEnabledExtensions
        )
        else {
            return nil
        }

        let resolvedProfileID = explicitProfileID
            ?? profileRuntime.currentProfileId
            ?? runtimeProfileID()
        guard let resolvedProfileID else { return nil }

        if allowWithoutEnabledExtensions {
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

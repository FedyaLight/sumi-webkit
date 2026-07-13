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
    private let runtimeSession: ExtensionRuntimeSession
    private let controllerProvisioning: any ExtensionControllerProvisioning
    private let runtimeProfileID: @MainActor () -> UUID?
    private let extensionSupportAvailable: Bool
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        installedExtensions: InstalledExtensionCollection,
        profileRuntime: ExtensionProfileRuntime,
        runtimeSession: ExtensionRuntimeSession,
        controllerProvisioning: any ExtensionControllerProvisioning,
        runtimeProfileID: @escaping @MainActor () -> UUID?,
        extensionSupportAvailable: Bool,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.installedExtensions = installedExtensions
        self.profileRuntime = profileRuntime
        self.runtimeSession = runtimeSession
        self.controllerProvisioning = controllerProvisioning
        self.runtimeProfileID = runtimeProfileID
        self.extensionSupportAvailable = extensionSupportAvailable
        self.diagnostics = diagnostics
    }

    @discardableResult
    func request(
        reason: ExtensionRuntimeDemandReason,
        allowWithoutEnabledExtensions: Bool = false,
        profileId explicitProfileID: UUID? = nil
    ) -> WKWebExtensionController? {
        PerformanceTrace.emitEvent("ExtensionManager.lazyRuntimeRequested")

        guard extensionSupportAvailable else {
            runtimeSession.runtimeState = .unavailable
            return nil
        }

        // One catalog snapshot governs this entire admission. A concurrent
        // install/disable cannot change the meaning halfway through it.
        let catalogSnapshot = installedExtensions.records
        let enabledExtensionIDs = Set(
            catalogSnapshot.lazy.filter(\.isEnabled).map(\.id)
        )
        guard enabledExtensionIDs.isEmpty == false
            || allowWithoutEnabledExtensions
            || runtimeSession.allowsRuntimeWithoutEnabledExtensions
        else {
            return nil
        }

        let resolvedProfileID = explicitProfileID
            ?? profileRuntime.currentProfileId
            ?? runtimeProfileID()
        guard let resolvedProfileID else { return nil }

        if allowWithoutEnabledExtensions {
            runtimeSession.allowsRuntimeWithoutEnabledExtensions = true
        }

        let controller = controllerProvisioning.ensureExtensionController(
            for: resolvedProfileID
        )
        let readiness = profileRuntime.readinessContext(
            for: resolvedProfileID,
            hasEnabledExtensionDemand: enabledExtensionIDs.isEmpty == false,
            enabledExtensionIDs: enabledExtensionIDs,
            globalRuntimeReady: runtimeSession.runtimeState == .ready
        )
        switch runtimeSession.runtimeState {
        case .loading:
            return controller
        case .ready:
            guard readiness.isProfileReady else {
                runtimeSession.runtimeState = .loading
                return controller
            }
            return controller
        case .idle, .unavailable, .failed:
            runtimeSession.runtimeState = .loading
        }

        runtimeSession.runtimeState = readiness.isProfileReady ? .ready : .loading
        diagnostics.trace(
            "lazyRuntime controller-only reason=\(reason.rawValue) profileId=\(resolvedProfileID.uuidString) loadedContexts=\(profileRuntime.countLoadedExtensionContexts())"
        )
        return controller
    }

}

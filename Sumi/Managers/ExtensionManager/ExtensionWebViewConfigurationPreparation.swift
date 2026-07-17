import Foundation
import WebKit

/// Prepares a WKWebViewConfiguration before WKWebView creation. This path is
/// intentionally browser-bridge independent and remains valid for a cold
/// ExtensionManager.
@available(macOS 15.5, *)
@MainActor
final class ExtensionWebViewConfigurationPreparation:
    ExtensionWebViewConfigurationPreparing {
    private weak var provisioning:
        (any ExtensionWebViewConfigurationProvisioning)?
    private weak var preludes: (any ExtensionPreludeInstalling)?
    private let resolveProfileID: @MainActor (UUID?) -> UUID?
    private let requestRuntime: @MainActor (UUID) -> Void
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        provisioning: any ExtensionWebViewConfigurationProvisioning,
        preludes: any ExtensionPreludeInstalling,
        resolveProfileID: @escaping @MainActor (UUID?) -> UUID?,
        requestRuntime: @escaping @MainActor (UUID) -> Void,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.provisioning = provisioning
        self.preludes = preludes
        self.resolveProfileID = resolveProfileID
        self.requestRuntime = requestRuntime
        self.diagnostics = diagnostics
    }

    func prepareWebViewConfigForExtensionRuntime(
        _ configuration: WKWebViewConfiguration,
        profileId: UUID?,
        reason: String
    ) {
        guard let provisioning,
              let resolvedProfileID = resolveProfileID(profileId)
        else { return }

        requestRuntime(resolvedProfileID)
        guard let controller = provisioning.controllerIfAdmitted(
            for: resolvedProfileID,
            mutationLease: nil
        ), let websiteDataStore = provisioning.websiteDataStoreIfAdmitted(
            for: resolvedProfileID,
            mutationLease: nil
        ) else { return }
        let existing = configuration.webExtensionController
        if existing !== controller {
            configuration.webExtensionController = controller
        }
        configuration.websiteDataStore = websiteDataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        preludes?.installPreludes(
            into: configuration.userContentController,
            profileId: resolvedProfileID
        )
        diagnostics.trace(
            "prepareExtensionConfiguration reason=\(reason) profile=\(resolvedProfileID.uuidString.prefix(8)) assigned=\(existing !== controller)"
        )
    }
}

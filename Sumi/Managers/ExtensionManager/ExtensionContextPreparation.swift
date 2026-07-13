import Foundation
import WebKit

/// Prepares one profile-scoped WebExtension context before it is attached to
/// a controller. Policy persistence is the only outward effect.
@available(macOS 15.5, *)
@MainActor
final class ExtensionContextPreparation {
    nonisolated static let webExtensionURLScheme = "safari-web-extension"
    static let registerWebExtensionURLScheme: Void = {
        WKWebExtension.MatchPattern.registerCustomURLScheme(
            webExtensionURLScheme
        )
    }()

    private let siteAccessPolicyStore: SafariExtensionSiteAccessPolicyStore
    private let capabilities: SafariExtensionInstallCapabilityOwner
    private let installedExtensions: InstalledExtensionCollection
    private let permissionDecisions: ExtensionPermissionDecisionStore
    private let siteAccessPolicyDidPersist: @MainActor () -> Void

    init(
        siteAccessPolicyStore: SafariExtensionSiteAccessPolicyStore,
        capabilities: SafariExtensionInstallCapabilityOwner,
        installedExtensions: InstalledExtensionCollection,
        permissionDecisions: ExtensionPermissionDecisionStore,
        siteAccessPolicyDidPersist: @escaping @MainActor () -> Void
    ) {
        self.siteAccessPolicyStore = siteAccessPolicyStore
        self.capabilities = capabilities
        self.installedExtensions = installedExtensions
        self.permissionDecisions = permissionDecisions
        self.siteAccessPolicyDidPersist = siteAccessPolicyDidPersist
    }

    func prepare(
        webExtension: WKWebExtension,
        request: ExtensionContextLoadRequest
    ) -> ExtensionPreparedContext {
        let runtimeIdentifier = Self.runtimeIdentifier(
            extensionID: request.extensionId,
            sourceKind: request.sourceKind,
            sourceBundlePath: request.sourceBundlePath
        )
        let context = WKWebExtensionContext(for: webExtension)
        Self.configureIdentity(
            context,
            extensionID: request.extensionId,
            profileID: request.profileId,
            runtimeIdentifier: runtimeIdentifier
        )

        capabilities.grantRequestedPermissions(
            to: context,
            webExtension: webExtension,
            extensionId: request.extensionId,
            profileId: request.profileId,
            manifest: request.manifest
        )

        let policyResult: SafariExtensionSiteAccessPolicyStore.PolicyResult
        if request.sourceKind == .safariAppExtension {
            policyResult = siteAccessPolicyStore
                .seedSafariAppExtensionDefaultAccessIfNeeded(
                    extensionId: request.extensionId,
                    profileId: request.profileId
                )
        } else {
            policyResult = siteAccessPolicyStore.policy(
                extensionId: request.extensionId,
                profileId: request.profileId
            )
        }
        capabilities.applyConfiguredSiteAccessPolicy(
            to: context,
            webExtension: webExtension,
            input: SafariExtensionInstallCapabilityOwner.SiteAccessApplicationInput(
                extensionId: request.extensionId,
                profileId: request.profileId,
                policy: policyResult.policy,
                installedExtension: installedExtensions.records.first {
                    $0.id == request.extensionId
                },
                manifest: request.manifest
            )
        )
        permissionDecisions.applyStoredExtensionPermissionDecisions(
            to: context,
            extensionId: request.extensionId,
            profileId: request.profileId
        )
        context.isInspectable = RuntimeDiagnostics.isDeveloperInspectionEnabled
        capabilities.prepareExtensionContextForRuntime(
            context,
            extensionId: request.extensionId,
            profileId: request.profileId,
            manifest: request.manifest
        )

        // Publish only after the context is locally complete. Notification
        // observers may synchronously supersede this load; the caller must
        // revalidate authority before performing controller/storage effects.
        if policyResult.didPersistChanges {
            siteAccessPolicyDidPersist()
        }

        return ExtensionPreparedContext(
            context: context,
            runtimeIdentifier: runtimeIdentifier
        )
    }

    static func configureIdentity(
        _ context: WKWebExtensionContext,
        extensionID: String,
        profileID: UUID,
        runtimeIdentifier: String
    ) {
        _ = registerWebExtensionURLScheme
        context.uniqueIdentifier = runtimeIdentifier
        let scopedIdentifier = "\(profileID.uuidString):\(extensionID)"
        let host =
            "ext-"
            + scopedIdentifier.utf8.map { String(format: "%02x", $0) }.joined()
        if let baseURL = URL(
            string: "\(webExtensionURLScheme)://\(host)"
        ) {
            context.baseURL = baseURL
        }
    }

    static func runtimeIdentifier(
        extensionID: String,
        sourceKind: WebExtensionSourceKind,
        sourceBundlePath: String?
    ) -> String {
        SafariWebExtensionRuntimeIdentity.webKitStorageIdentifier(
            extensionId: extensionID,
            sourceKind: sourceKind,
            sourceBundlePath: sourceBundlePath
        )
    }
}

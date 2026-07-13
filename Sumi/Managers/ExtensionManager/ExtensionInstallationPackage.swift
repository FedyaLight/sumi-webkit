import Foundation

/// Owns the package bytes for one installation attempt. Copied directory
/// packages are reversible; Safari app-extension resources remain externally
/// owned and therefore have no filesystem compensation.
@available(macOS 15.5, *)
@MainActor
final class ExtensionInstallationPackage {
    enum Ownership: CaseIterable {
        case copiedDirectory
        case externalSafariBundle
    }

    struct Materialized {
        let root: URL
        let manifest: [String: Any]
    }

    private enum Backing {
        case copied(
            transaction: ExtensionPackageInstallTransaction,
            manifestFingerprint: String,
            manifestPolicy: WebExtensionManifestValidationPolicy
        )
        case external(
            root: URL,
            appexBundleURL: URL,
            bundleIdentifier: String,
            safariRuntimeIdentity: String?,
            manifestFingerprint: String,
            manifestPolicy: WebExtensionManifestValidationPolicy
        )
    }

    let ownership: Ownership
    let manifest: [String: Any]
    let preferredDeclaredExtensionID: String?
    let runtimeOperation: ExtensionInstallationRuntimeActivation.Operation

    private let backing: Backing

    private init(
        ownership: Ownership,
        manifest: [String: Any],
        preferredDeclaredExtensionID: String?,
        runtimeOperation: ExtensionInstallationRuntimeActivation.Operation,
        backing: Backing
    ) {
        self.ownership = ownership
        self.manifest = manifest
        self.preferredDeclaredExtensionID = preferredDeclaredExtensionID
        self.runtimeOperation = runtimeOperation
        self.backing = backing
    }

    static func prepare(
        source: ExtensionInstallSourceResolver.ResolvedInstallSource,
        extensionsDirectory: URL,
        activeGenerations: ExtensionPackageGenerationRegistry
    ) throws -> ExtensionInstallationPackage {
        let policy = WebExtensionManifestValidationPolicy.forSourceKind(
            source.sourceKind
        )
        if source.sourceKind == .safariAppExtension {
            guard let appexBundleURL = source.appexBundleURL,
                  let bundle = Bundle(url: appexBundleURL),
                  let bundleIdentifier = bundle.bundleIdentifier,
                  bundleIdentifier.isEmpty == false else {
                throw ExtensionError.installationFailed(
                    "Installed Safari app extension bundle is unavailable"
                )
            }
            let manifest = try ExtensionUtils.validateManifest(
                at: source.resourcesURL.appendingPathComponent("manifest.json"),
                policy: policy
            )
            try ExtensionInstallSourceResolver.validateMV3Requirements(
                manifest: manifest,
                baseURL: source.resourcesURL
            )
            let safariRuntimeIdentity =
                SafariWebExtensionRuntimeIdentity.composedIdentifier(
                    sourceKind: source.sourceKind,
                    sourceBundlePath: source.sourceBundlePath.path
                )
            return ExtensionInstallationPackage(
                ownership: .externalSafariBundle,
                manifest: manifest,
                preferredDeclaredExtensionID: bundleIdentifier,
                runtimeOperation: .safariAppExtension,
                backing: .external(
                    root: source.resourcesURL,
                    appexBundleURL: appexBundleURL,
                    bundleIdentifier: bundleIdentifier,
                    safariRuntimeIdentity: safariRuntimeIdentity,
                    manifestFingerprint: ExtensionUtils.fingerprint(
                        fileAt: source.resourcesURL
                            .appendingPathComponent("manifest.json")
                    ),
                    manifestPolicy: policy
                )
            )
        }

        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: extensionsDirectory,
            activeGenerations: activeGenerations
        )
        do {
            try transaction.stage(resourcesAt: source.resourcesURL)
            let manifest = try ExtensionUtils.validateManifest(
                at: transaction.stagedPackageRoot
                    .appendingPathComponent("manifest.json"),
                policy: policy
            )
            try ExtensionInstallSourceResolver.validateMV3Requirements(
                manifest: manifest,
                baseURL: transaction.stagedPackageRoot
            )
            return ExtensionInstallationPackage(
                ownership: .copiedDirectory,
                manifest: manifest,
                preferredDeclaredExtensionID: nil,
                runtimeOperation: .directory,
                backing: .copied(
                    transaction: transaction,
                    manifestFingerprint: ExtensionUtils.fingerprint(
                        fileAt: transaction.stagedPackageRoot
                            .appendingPathComponent("manifest.json")
                    ),
                    manifestPolicy: policy
                )
            )
        } catch let preparationError {
            do {
                try transaction.rollback()
            } catch let rollbackError {
                throw ExtensionError.installationFailed(
                    "Package preparation failed: "
                        + preparationError.localizedDescription
                        + ". Staging rollback also failed: "
                        + rollbackError.localizedDescription
                )
            }
            throw preparationError
        }
    }

    func materialize(extensionID _: String) throws -> Materialized {
        switch backing {
        case .external(
            let root,
            let appexBundleURL,
            let bundleIdentifier,
            let safariRuntimeIdentity,
            let manifestFingerprint,
            let manifestPolicy
        ):
            guard Bundle(url: appexBundleURL)?.bundleIdentifier
                    == bundleIdentifier,
                  SafariWebExtensionRuntimeIdentity.composedIdentifier(
                    sourceKind: .safariAppExtension,
                    sourceBundlePath: appexBundleURL.path
                  ) == safariRuntimeIdentity
            else {
                throw ExtensionError.installationFailed(
                    "The Safari extension bundle identity changed during installation"
                )
            }
            let manifestURL = root.appendingPathComponent("manifest.json")
            guard ExtensionUtils.fingerprint(fileAt: manifestURL)
                    == manifestFingerprint else {
                throw ExtensionError.installationFailed(
                    "The Safari extension manifest changed during installation"
                )
            }
            let currentManifest = try ExtensionUtils.validateManifest(
                at: manifestURL,
                policy: manifestPolicy
            )
            try ExtensionInstallSourceResolver.validateMV3Requirements(
                manifest: currentManifest,
                baseURL: root
            )
            return Materialized(root: root, manifest: currentManifest)
        case .copied(
            let transaction,
            let manifestFingerprint,
            let manifestPolicy
        ):
            let root = try transaction.installStagedPackage()
            let manifestURL = root.appendingPathComponent("manifest.json")
            guard ExtensionUtils.fingerprint(fileAt: manifestURL)
                    == manifestFingerprint else {
                throw ExtensionError.installationFailed(
                    "The staged extension manifest changed during installation"
                )
            }
            let currentManifest = try ExtensionUtils.validateManifest(
                at: manifestURL,
                policy: manifestPolicy
            )
            try ExtensionInstallSourceResolver.validateMV3Requirements(
                manifest: currentManifest,
                baseURL: root
            )
            return Materialized(
                root: root,
                manifest: currentManifest
            )
        }
    }

    func commit() {
        guard case .copied(let transaction, _, _) = backing else { return }
        transaction.commit()
    }

    func rollback() throws {
        guard case .copied(let transaction, _, _) = backing else { return }
        try transaction.rollback()
    }
}

@available(macOS 15.5, *)
extension ExtensionInstallationPackage:
    ExtensionInstallationPackageSettling {}

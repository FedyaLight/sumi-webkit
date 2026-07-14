import Foundation

/// Owns the package bytes for one installation attempt. Copied directory
/// packages are reversible; Safari app-extension resources remain externally
/// owned and therefore have no filesystem compensation.
@available(macOS 15.5, *)
@MainActor
final class ExtensionInstallationPackage {
    enum Ownership: CaseIterable, Sendable {
        case copiedDirectory
        case externalSafariBundle
    }

    struct Materialized {
        let root: URL
        let manifest: [String: Any]
        let manifestFingerprint: String
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
        activeGenerations: ExtensionPackageGenerationRegistry,
        fileExecutor: ExtensionPackageFileExecutor = .init()
    ) async throws -> ExtensionInstallationPackage {
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
            let manifestURL = source.resourcesURL.appendingPathComponent(
                "manifest.json"
            )
            let manifestData = try Data(contentsOf: manifestURL)
            let manifest = try validateManifest(
                data: manifestData,
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
                    manifestFingerprint: ExtensionPackageFingerprint.data(
                        manifestData
                    ),
                    manifestPolicy: policy
                )
            )
        }

        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: extensionsDirectory,
            activeGenerations: activeGenerations,
            fileExecutor: fileExecutor
        )
        do {
            let stagedManifest = try await transaction.stage(
                resourcesAt: source.resourcesURL
            )
            let manifest = try validateManifest(
                data: stagedManifest.data,
                policy: policy
            )
            return ExtensionInstallationPackage(
                ownership: .copiedDirectory,
                manifest: manifest,
                preferredDeclaredExtensionID: nil,
                runtimeOperation: .directory,
                backing: .copied(
                    transaction: transaction,
                    manifestFingerprint: stagedManifest.fingerprint,
                    manifestPolicy: policy
                )
            )
        } catch let preparationError {
            do {
                try await transaction.rollback()
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

    func materialize(extensionID _: String) async throws -> Materialized {
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
            let manifestData = try Data(contentsOf: manifestURL)
            guard ExtensionPackageFingerprint.data(manifestData)
                    == manifestFingerprint else {
                throw ExtensionError.installationFailed(
                    "The Safari extension manifest changed during installation"
                )
            }
            let currentManifest = try Self.validateManifest(
                data: manifestData,
                policy: manifestPolicy
            )
            try ExtensionInstallSourceResolver.validateMV3Requirements(
                manifest: currentManifest,
                baseURL: root
            )
            return Materialized(
                root: root,
                manifest: currentManifest,
                manifestFingerprint: manifestFingerprint
            )
        case .copied(
            let transaction,
            let manifestFingerprint,
            let manifestPolicy
        ):
            let materialized = try await transaction.materialize(
                expectedManifestFingerprint: manifestFingerprint
            )
            let currentManifest = try Self.validateManifest(
                data: materialized.manifestData,
                policy: manifestPolicy
            )
            return Materialized(
                root: materialized.root,
                manifest: currentManifest,
                manifestFingerprint: materialized.manifestFingerprint
            )
        }
    }

    func commit() async {
        guard case .copied(let transaction, _, _) = backing else { return }
        await transaction.commit()
    }

    func rollback() async throws {
        guard case .copied(let transaction, _, _) = backing else { return }
        try await transaction.rollback()
    }

    private static func validateManifest(
        data: Data,
        policy: WebExtensionManifestValidationPolicy
    ) throws -> [String: Any] {
        guard let manifest = try JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
            throw ExtensionError.invalidManifest("Invalid JSON structure")
        }
        try ExtensionManifestValidation.validateContents(
            manifest,
            policy: policy
        )
        return manifest
    }
}

@available(macOS 15.5, *)
extension ExtensionInstallationPackage:
    ExtensionInstallationPackageSettling {}

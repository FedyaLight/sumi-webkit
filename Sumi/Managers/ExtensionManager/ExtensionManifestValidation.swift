import Foundation

enum WebExtensionManifestValidationPolicy: Equatable, Sendable {
    case safariWebExtension
    case unpackedDirectory

    static func forSourceKind(_ sourceKind: WebExtensionSourceKind) -> Self {
        switch sourceKind {
        case .safariAppExtension:
            return .safariWebExtension
        case .directory:
            return .unpackedDirectory
        }
    }
}

enum ExtensionManifestValidation {
    static func validate(
        at url: URL,
        policy: WebExtensionManifestValidationPolicy = .unpackedDirectory
    ) throws -> [String: Any] {
        let manifest = try loadJSONObject(at: url)
        try validateContents(manifest, policy: policy)
        return manifest
    }

    static func validateContents(
        _ manifest: [String: Any],
        policy: WebExtensionManifestValidationPolicy
    ) throws {
        guard let name = manifest["name"] as? String, name.isEmpty == false else {
            throw ExtensionError.invalidManifest(
                "Manifest is missing a non-empty name."
            )
        }
        guard let version = manifest["version"] as? String,
              version.isEmpty == false
        else {
            throw ExtensionError.invalidManifest(
                "Manifest is missing a non-empty version."
            )
        }
        guard let manifestVersion = manifest["manifest_version"] as? Int else {
            throw ExtensionError.invalidManifest(
                "Manifest is missing manifest_version."
            )
        }

        switch policy {
        case .safariWebExtension:
            guard manifestVersion == 2 || manifestVersion == 3 else {
                throw ExtensionError.invalidManifest(
                    "Unsupported manifest_version \(manifestVersion); Safari Web Extensions support manifest_version 2 and 3."
                )
            }
        case .unpackedDirectory:
            guard manifestVersion == 3 else {
                throw ExtensionError.invalidManifest(
                    "Unsupported manifest_version \(manifestVersion); only manifest version 3 is accepted."
                )
            }
        }
    }

    static func loadJSONObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data)
            as? [String: Any]
        else {
            throw ExtensionError.invalidManifest("Invalid JSON structure")
        }
        return object
    }
}

import Foundation

struct ExtensionInstallationPersistedIdentity: Equatable {
    let extensionID: String
    let sourceBundlePath: String
    let sourceKind: WebExtensionSourceKind
    let safariRuntimeIdentity: String?
}

/// Resolves one installation identity before any runtime or package mutation.
/// Source continuity and manifest-declared identity must never silently split
/// into different mutation domains.
enum ExtensionInstallationIdentityResolver {
    struct Input {
        let sourceBundleURL: URL
        let declaredExtensionID: String?
        let sourceKind: WebExtensionSourceKind
        let safariRuntimeIdentity: String?
        let freshExtensionID: String
        let persistedIdentities: [ExtensionInstallationPersistedIdentity]
    }

    struct Resolution: Equatable {
        let extensionID: String
        let existingExtensionID: String?
    }

    static func resolve(_ input: Input) throws -> Resolution {
        let sourcePath = canonicalSourcePath(input.sourceBundleURL)
        let sourceMatches = input.persistedIdentities.filter {
            canonicalSourcePath(URL(fileURLWithPath: $0.sourceBundlePath))
                == sourcePath
        }
        guard sourceMatches.count <= 1 else {
            throw ExtensionError.installationFailed(
                "Multiple persisted extensions claim the same source package"
            )
        }

        let declaredID = input.declaredExtensionID?.nilIfEmpty
        if let sourceMatch = sourceMatches.first,
           let declaredID,
           declaredID != sourceMatch.extensionID {
            throw ExtensionError.installationFailed(
                "The source package changed its declared extension identity from "
                    + sourceMatch.extensionID + " to " + declaredID
                    + "; uninstall the existing extension before installing it as a different identity"
            )
        }

        let extensionID = sourceMatches.first?.extensionID
            ?? declaredID
            ?? input.freshExtensionID
        let validatedID = try ExtensionUtils.validateExtensionIDPathComponent(
            extensionID
        )
        let existingIdentity = input.persistedIdentities.first {
            $0.extensionID == validatedID
        }
        if let existingIdentity {
            guard existingIdentity.sourceKind == input.sourceKind else {
                throw ExtensionError.installationFailed(
                    "An installed extension with this identity uses a different package kind"
                )
            }
            if input.sourceKind == .safariAppExtension,
               existingIdentity.safariRuntimeIdentity
                != input.safariRuntimeIdentity {
                throw ExtensionError.installationFailed(
                    "The Safari extension signing identity does not match the installed extension"
                )
            }
        }
        return Resolution(
            extensionID: validatedID,
            existingExtensionID: existingIdentity?.extensionID
        )
    }

    static func canonicalSourcePath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

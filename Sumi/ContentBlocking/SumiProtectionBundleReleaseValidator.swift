import Foundation
import SumiDomain

struct SumiProtectionBundleReleaseSelection: Sendable {
    let manifest: SumiProtectionBundleReleaseManifest
    let bundle: SumiProtectionBundleReleaseManifest.Bundle
    let assets: [SumiProtectionBundleReleaseManifest.Asset]
}

struct SumiProtectionBundleReleaseValidator {
    func approvedAssetIndex(
        for release: SumiProtectionBundleGitHubRelease
    ) throws -> [String: SumiProtectionBundleGitHubRelease.Asset] {
        guard !release.draft, !release.prerelease else {
            throw SumiProtectionBundleRemoteUpdateError.releaseIsNotApproved
        }
        var result = [String: SumiProtectionBundleGitHubRelease.Asset]()
        for asset in release.assets {
            guard result.updateValue(asset, forKey: asset.name) == nil else {
                throw SumiProtectionBundleRemoteUpdateError.duplicateAssetName(asset.name)
            }
        }
        return result
    }

    func selectBundle(
        in manifest: SumiProtectionBundleReleaseManifest,
        profileId: String,
        releaseAssets: [String: SumiProtectionBundleGitHubRelease.Asset]
    ) throws -> SumiProtectionBundleReleaseSelection {
        try validateCompatibility(manifest)

        var bundlesByProfile = [String: SumiProtectionBundleReleaseManifest.Bundle]()
        for bundle in manifest.bundles {
            guard bundlesByProfile.updateValue(bundle, forKey: bundle.profileId) == nil else {
                throw SumiProtectionBundleRemoteUpdateError.duplicateBundleProfile(bundle.profileId)
            }
        }
        guard let bundle = bundlesByProfile[profileId] else {
            throw SumiProtectionBundleRemoteUpdateError.profileMissing(profileId)
        }
        try validateGroups(bundle)

        var descriptorsByName = [String: SumiProtectionBundleReleaseManifest.Asset]()
        for descriptor in manifest.assets {
            guard descriptorsByName.updateValue(descriptor, forKey: descriptor.name) == nil else {
                throw SumiProtectionBundleRemoteUpdateError.duplicateBundleAssetName(descriptor.name)
            }
        }
        guard Set(bundle.assetNames).count == bundle.assetNames.count else {
            throw SumiProtectionBundleRemoteUpdateError.releaseManifestIncompatible(
                "bundle \(profileId) repeats an asset name"
            )
        }

        var selectedAssets = [SumiProtectionBundleReleaseManifest.Asset]()
        var relativePaths = Set<String>()
        for name in bundle.assetNames {
            guard let descriptor = descriptorsByName[name], descriptor.bundleProfileId == profileId else {
                throw SumiProtectionBundleRemoteUpdateError.releaseManifestIncompatible(
                    "bundle \(profileId) asset list is incomplete"
                )
            }
            guard let releaseAsset = releaseAssets[name] else {
                throw SumiProtectionBundleRemoteUpdateError.assetMissing(name)
            }
            guard descriptor.byteSize > 0,
                  descriptor.byteSize <= SumiProtectionBundleRemoteUpdateConstants.maximumAssetByteCount
            else {
                throw SumiProtectionBundleRemoteUpdateError.assetTooLarge(
                    name: name,
                    byteCount: descriptor.byteSize
                )
            }
            guard releaseAsset.size == descriptor.byteSize else {
                throw SumiProtectionBundleRemoteUpdateError.assetSizeMismatch(
                    name: name,
                    expected: descriptor.byteSize,
                    actual: releaseAsset.size
                )
            }
            try validateRelativePath(descriptor.relativePath)
            guard relativePaths.insert(descriptor.relativePath).inserted else {
                throw SumiProtectionBundleRemoteUpdateError.duplicateBundleRelativePath(descriptor.relativePath)
            }
            let hashCharacters = descriptor.sha256.unicodeScalars
            let hexadecimalCharacters = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
            guard hashCharacters.count == 64,
                  hashCharacters.allSatisfy({ hexadecimalCharacters.contains($0) })
            else {
                throw SumiProtectionBundleRemoteUpdateError.releaseManifestIncompatible(
                    "asset \(name) has an invalid SHA-256 digest"
                )
            }
            selectedAssets.append(descriptor)
        }

        return SumiProtectionBundleReleaseSelection(
            manifest: manifest,
            bundle: bundle,
            assets: selectedAssets
        )
    }

    private func validateCompatibility(_ manifest: SumiProtectionBundleReleaseManifest) throws {
        guard manifest.schemaVersion == SumiProtectionBundleRemoteUpdateConstants.releaseManifestSchemaVersion else {
            throw SumiProtectionBundleRemoteUpdateError.releaseManifestSchemaUnsupported(manifest.schemaVersion)
        }
        let expectation = SumiProtectionBundleRemoteUpdateConstants.browserBundleExpectationVersion
        guard manifest.compatibility.minimumSumiBundleExpectationVersion <= expectation,
              manifest.compatibility.maximumSumiBundleExpectationVersion >= expectation
        else {
            throw SumiProtectionBundleRemoteUpdateError.releaseManifestIncompatible(
                "browser expectation \(expectation) is outside \(manifest.compatibility.minimumSumiBundleExpectationVersion)-\(manifest.compatibility.maximumSumiBundleExpectationVersion)"
            )
        }
        guard manifest.compatibility.bundleManifestSchemaVersion == 1 else {
            throw SumiProtectionBundleRemoteUpdateError.releaseManifestIncompatible(
                "bundle manifest schema \(manifest.compatibility.bundleManifestSchemaVersion) is unsupported"
            )
        }
        guard manifest.compatibility.requiredNativeCSSSafetyPolicyVersion == SumiAdblockNativeRuleBundle.requiredNativeCSSSafetyPolicyVersion else {
            throw SumiProtectionBundleRemoteUpdateError.releaseManifestIncompatible(
                "native CSS safety policy \(manifest.compatibility.requiredNativeCSSSafetyPolicyVersion) is unsupported"
            )
        }
    }

    private func validateGroups(_ bundle: SumiProtectionBundleReleaseManifest.Bundle) throws {
        guard let groups = bundle.groups, !groups.isEmpty else {
            throw incompatible("bundle \(bundle.profileId) has no logical group metadata")
        }
        var groupsById = [SumiProtectionGroupKind: SumiProtectionBundleReleaseManifest.Bundle.Group]()
        for group in groups {
            guard groupsById.updateValue(group, forKey: group.id) == nil else {
                throw incompatible("bundle \(bundle.profileId) has duplicate group \(group.id.rawValue)")
            }
        }
        guard let trackingGroup = groupsById[.trackingNetwork] else {
            throw incompatible("bundle \(bundle.profileId) is missing trackingNetwork metadata")
        }
        guard groupsById[.adblockAdsPrivacyNetwork] != nil else {
            throw incompatible("bundle \(bundle.profileId) is missing adblockAdsPrivacyNetwork metadata")
        }
        guard trackingGroup.ruleCount > 0,
              trackingGroup.shardCount > 0,
              !trackingGroup.assetNames.isEmpty
        else {
            throw incompatible("trackingNetwork metadata does not describe generated assets")
        }
        guard let source = trackingGroup.source else {
            throw incompatible("trackingNetwork metadata is missing source attribution")
        }
        guard source.sourceName == "DuckDuckGo Tracker Radar / TDS",
              source.sourceURL == "https://staticcdn.duckduckgo.com/trackerblocking/v6/current/macos-tds.json",
              source.sourceLicense == "CC BY-NC-SA 4.0",
              source.sourceLicenseURL == "https://creativecommons.org/licenses/by-nc-sa/4.0/",
              source.attribution?.isEmpty == false,
              source.generatedAt?.isEmpty == false,
              source.sourceSha256?.isEmpty == false,
              source.nonCommercialOnly == true,
              source.shareAlike == true
        else {
            throw incompatible("trackingNetwork source metadata is incomplete")
        }
        if let ruleCount = source.ruleCount, ruleCount != trackingGroup.ruleCount {
            throw incompatible("trackingNetwork source ruleCount does not match group ruleCount")
        }
        if let shardCount = source.shardCount, shardCount != trackingGroup.shardCount {
            throw incompatible("trackingNetwork source shardCount does not match group shardCount")
        }
    }

    private func validateRelativePath(_ relativePath: String) throws {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/", omittingEmptySubsequences: false).contains(where: {
                  $0.isEmpty || $0 == "." || $0 == ".."
              })
        else {
            throw SumiProtectionBundleRemoteUpdateError.invalidRelativePath(relativePath)
        }
    }

    private func incompatible(_ detail: String) -> SumiProtectionBundleRemoteUpdateError {
        .releaseManifestIncompatible(detail)
    }
}

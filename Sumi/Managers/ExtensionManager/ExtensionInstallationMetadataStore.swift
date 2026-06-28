//
//  ExtensionInstallationMetadataStore.swift
//  Sumi
//
//  Installed-extension metadata persistence and refresh owner.
//

import Foundation
import SwiftData

@available(macOS 15.5, *)
@MainActor
final class ExtensionInstallationMetadataStore {
    struct MetadataLoadResult {
        var didFetchPersistedMetadata: Bool
        var records: [InstalledExtension]
        var enabledEntities: [ExtensionEntity]
    }

    nonisolated private static let orphanedExtensionCleanupDefaultsKey =
        "\(SumiAppIdentity.bundleIdentifier).extensions.orphanedPackageCleanup.lastRunAt"
    nonisolated private static let orphanedExtensionCleanupInterval: TimeInterval =
        24 * 60 * 60

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func persist(record: InstalledExtension) throws {
        if let existing = try extensionEntity(for: record.id) {
            update(existing, from: record)
        } else {
            context.insert(ExtensionEntity(record: record))
        }
        try context.save()
    }

    func extensionEntity(for id: String) throws -> ExtensionEntity? {
        try context.fetch(FetchDescriptor<ExtensionEntity>()).first(where: { $0.id == id })
    }

    func extensionResourcesRoot(
        sourceKind: WebExtensionSourceKind,
        packagePath: String,
        sourceBundlePath: String
    ) throws -> URL {
        if sourceKind == .safariAppExtension {
            if let appexURL = SafariAppExtensionResources.installedAppexBundleURL(
                sourceKind: sourceKind,
                sourceBundlePath: sourceBundlePath
            ) {
                return try SafariAppExtensionResources.resourcesRoot(in: appexURL)
            }

            let packageURL = URL(fileURLWithPath: packagePath, isDirectory: true)
            if FileManager.default.fileExists(
                atPath: packageURL.appendingPathComponent("manifest.json").path
            ) {
                return packageURL
            }

            throw ExtensionError.installationFailed(
                "Installed Safari app extension bundle is unavailable"
            )
        }

        return URL(fileURLWithPath: packagePath, isDirectory: true)
    }

    func extensionResourcesRoot(for entity: ExtensionEntity) throws -> URL {
        let sourceKind = WebExtensionSourceKind(rawValue: entity.sourceKindRawValue) ?? .directory
        return try extensionResourcesRoot(
            sourceKind: sourceKind,
            packagePath: entity.packagePath,
            sourceBundlePath: entity.sourceBundlePath
        )
    }

    func loadInstalledExtensionMetadata(
        trace: (String) -> Void
    ) -> MetadataLoadResult {
        let entities: [ExtensionEntity]
        do {
            entities = try context.fetch(FetchDescriptor<ExtensionEntity>())
        } catch {
            ExtensionManager.logger.error("Failed to fetch extensions: \(error.localizedDescription, privacy: .public)")
            return MetadataLoadResult(
                didFetchPersistedMetadata: false,
                records: [],
                enabledEntities: []
            )
        }

        var loadedRecords: [InstalledExtension] = []
        var enabledEntitiesToLoad: [ExtensionEntity] = []
        var didMutatePersistence = false

        for entity in entities {
            let sourceKind = WebExtensionSourceKind(rawValue: entity.sourceKindRawValue) ?? .directory
            let packageURL: URL
            do {
                packageURL = try extensionResourcesRoot(
                    sourceKind: sourceKind,
                    packagePath: entity.packagePath,
                    sourceBundlePath: entity.sourceBundlePath
                )
            } catch {
                context.delete(entity)
                didMutatePersistence = true
                ExtensionManager.logger.error(
                    "Dropped invalid persisted extension record for \(entity.name, privacy: .public)"
                )
                continue
            }
            guard FileManager.default.fileExists(atPath: packageURL.path) else {
                context.delete(entity)
                didMutatePersistence = true
                ExtensionManager.logger.error(
                    "Dropped invalid persisted extension record for \(entity.name, privacy: .public)"
                )
                continue
            }

            var record = InstalledExtensionRecord(from: entity)
            if let manifest = try? ExtensionUtils.loadJSONObject(
                at: packageURL.appendingPathComponent("manifest.json")
            ),
               let refreshed = try? refreshedRecord(for: entity, manifest: manifest),
               extensionMetadataNeedsRefresh(entity, refreshedRecord: refreshed) {
                update(entity, from: refreshed)
                record = refreshed
                didMutatePersistence = true
                trace(
                    "Refreshed extension metadata id=\(entity.id) background=\(refreshed.backgroundModel.rawValue)"
                )
            }

            guard let record else {
                context.delete(entity)
                didMutatePersistence = true
                ExtensionManager.logger.error(
                    "Dropped invalid persisted extension record for \(entity.name, privacy: .public)"
                )
                continue
            }

            loadedRecords.append(record)
            if entity.isEnabled {
                enabledEntitiesToLoad.append(entity)
            }
        }

        cleanupOrphanedExtensionPackages(
            referencedPackagePaths: Set(loadedRecords.map(\.packagePath))
        )

        if didMutatePersistence {
            do {
                try context.save()
            } catch {
                ExtensionManager.logger.error("Failed to persist refreshed extension metadata: \(error.localizedDescription, privacy: .public)")
            }
        }

        return MetadataLoadResult(
            didFetchPersistedMetadata: true,
            records: loadedRecords.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            },
            enabledEntities: enabledEntitiesToLoad
        )
    }

    func update(
        _ entity: ExtensionEntity,
        from record: InstalledExtension
    ) {
        entity.name = record.name
        entity.version = record.version
        entity.manifestVersion = record.manifestVersion
        entity.extensionDescription = record.description
        entity.isEnabled = record.isEnabled
        entity.installDate = record.installDate
        entity.lastUpdateDate = record.lastUpdateDate
        entity.packagePath = record.packagePath
        entity.iconPath = record.iconPath
        entity.sourceKindRawValue = record.sourceKind.rawValue
        entity.backgroundModelRawValue = record.backgroundModel.rawValue
        entity.incognitoModeRawValue = record.incognitoMode.rawValue
        entity.sourcePathFingerprint = record.sourcePathFingerprint
        entity.manifestRootFingerprint = record.manifestRootFingerprint
        entity.sourceBundlePath = record.sourceBundlePath
        entity.optionsPagePath = record.optionsPagePath
        entity.defaultPopupPath = record.defaultPopupPath
        entity.hasBackground = record.hasBackground
        entity.hasAction = record.hasAction
        entity.hasOptionsPage = record.hasOptionsPage
        entity.hasContentScripts = record.hasContentScripts
        entity.hasExtensionPages = record.hasExtensionPages
        entity.broadScope = record.activationSummary.broadScope
        entity.activationSummaryJSON = record.encodedActivationSummary
        entity.manifestSnapshotJSON = record.encodedManifestSnapshot
    }

    func setEnabled(
        _ isEnabled: Bool,
        for entity: ExtensionEntity,
        lastUpdateDate: Date = Date()
    ) throws {
        entity.isEnabled = isEnabled
        entity.lastUpdateDate = lastUpdateDate
        try context.save()
    }

    func record(
        _ record: InstalledExtension,
        withEnabledState isEnabled: Bool,
        lastUpdateDate: Date = Date()
    ) -> InstalledExtension {
        InstalledExtensionRecord(
            id: record.id,
            name: record.name,
            version: record.version,
            manifestVersion: record.manifestVersion,
            description: record.description,
            isEnabled: isEnabled,
            installDate: record.installDate,
            lastUpdateDate: lastUpdateDate,
            packagePath: record.packagePath,
            iconPath: record.iconPath,
            sourceKind: record.sourceKind,
            backgroundModel: record.backgroundModel,
            incognitoMode: record.incognitoMode,
            sourcePathFingerprint: record.sourcePathFingerprint,
            manifestRootFingerprint: record.manifestRootFingerprint,
            sourceBundlePath: record.sourceBundlePath,
            optionsPagePath: record.optionsPagePath,
            defaultPopupPath: record.defaultPopupPath,
            hasBackground: record.hasBackground,
            hasAction: record.hasAction,
            hasOptionsPage: record.hasOptionsPage,
            hasContentScripts: record.hasContentScripts,
            hasExtensionPages: record.hasExtensionPages,
            activationSummary: record.activationSummary,
            manifest: record.manifest
        )
    }

    func refreshedRecord(
        for entity: ExtensionEntity,
        manifest: [String: Any]
    ) throws -> InstalledExtension {
        let sourceKind = WebExtensionSourceKind(rawValue: entity.sourceKindRawValue) ?? .directory
        let extensionRoot = try extensionResourcesRoot(
            sourceKind: sourceKind,
            packagePath: entity.packagePath,
            sourceBundlePath: entity.sourceBundlePath
        )
        return try makeInstalledRecord(
            extensionId: entity.id,
            manifest: manifest,
            extensionRoot: extensionRoot,
            isEnabled: entity.isEnabled,
            sourceKind: sourceKind,
            sourceBundlePath: entity.sourceBundlePath,
            sourceFingerprintURL: URL(fileURLWithPath: entity.sourceBundlePath),
            existingEntity: entity
        )
    }

    func makeInstalledRecord(
        extensionId: String,
        manifest: [String: Any],
        extensionRoot: URL,
        isEnabled: Bool,
        sourceKind: WebExtensionSourceKind,
        sourceBundlePath: String,
        sourceFingerprintURL: URL,
        existingEntity: ExtensionEntity?
    ) throws -> InstalledExtension {
        let installDate = existingEntity?.installDate ?? Date()
        let lastUpdateDate = Date()
        let backgroundModel = ExtensionUtils.backgroundModel(from: manifest)
        let optionsPagePath = ExtensionUtils.storedOptionsPagePath(
            from: manifest,
            in: extensionRoot
        )
        let defaultPopupPath = ExtensionUtils.defaultPopupPath(from: manifest)
        let manifestActivationSummary = ExtensionUtils.activationSummary(from: manifest)
        let activationSummary = ExtensionActivationSummary(
            matchPatternStrings: manifestActivationSummary.matchPatternStrings,
            broadScope: manifestActivationSummary.broadScope,
            hasContentScripts: manifestActivationSummary.hasContentScripts,
            hasAction: manifestActivationSummary.hasAction,
            hasOptionsPage: optionsPagePath != nil,
            hasExtensionPages: optionsPagePath != nil || defaultPopupPath != nil
        )
        let incognitoMode = try IncognitoExtensionMode.fromManifest(manifest)

        let localizedName = ExtensionUtils.localizedString(
            manifest["name"] as? String,
            in: extensionRoot
        ) ?? (manifest["name"] as? String) ?? "Unknown Extension"
        let localizedDescription = ExtensionUtils.localizedString(
            manifest["description"] as? String,
            in: extensionRoot
        ) ?? (manifest["description"] as? String)

        return InstalledExtensionRecord(
            id: extensionId,
            name: localizedName,
            version: manifest["version"] as? String ?? "1.0",
            manifestVersion: manifest["manifest_version"] as? Int ?? 3,
            description: localizedDescription,
            isEnabled: isEnabled,
            installDate: installDate,
            lastUpdateDate: lastUpdateDate,
            packagePath: extensionRoot.path,
            iconPath: ExtensionUtils.iconPath(in: extensionRoot, manifest: manifest),
            sourceKind: sourceKind,
            backgroundModel: backgroundModel,
            incognitoMode: incognitoMode,
            sourcePathFingerprint: ExtensionUtils.normalizePathFingerprint(sourceFingerprintURL),
            manifestRootFingerprint: ExtensionUtils.fingerprint(
                fileAt: extensionRoot.appendingPathComponent("manifest.json")
            ),
            sourceBundlePath: sourceBundlePath,
            optionsPagePath: optionsPagePath,
            defaultPopupPath: defaultPopupPath,
            hasBackground: backgroundModel != .none,
            hasAction: activationSummary.hasAction,
            hasOptionsPage: activationSummary.hasOptionsPage,
            hasContentScripts: activationSummary.hasContentScripts,
            hasExtensionPages: activationSummary.hasExtensionPages,
            activationSummary: activationSummary,
            manifest: manifest
        )
    }

    private func extensionMetadataNeedsRefresh(
        _ entity: ExtensionEntity,
        refreshedRecord: InstalledExtension
    ) -> Bool {
        entity.name != refreshedRecord.name
            || entity.version != refreshedRecord.version
            || entity.manifestVersion != refreshedRecord.manifestVersion
            || entity.extensionDescription != refreshedRecord.description
            || entity.packagePath != refreshedRecord.packagePath
            || entity.iconPath != refreshedRecord.iconPath
            || entity.sourceKindRawValue != refreshedRecord.sourceKind.rawValue
            || entity.backgroundModelRawValue != refreshedRecord.backgroundModel.rawValue
            || entity.incognitoModeRawValue != refreshedRecord.incognitoMode.rawValue
            || entity.sourcePathFingerprint != refreshedRecord.sourcePathFingerprint
            || entity.manifestRootFingerprint != refreshedRecord.manifestRootFingerprint
            || entity.sourceBundlePath != refreshedRecord.sourceBundlePath
            || entity.optionsPagePath != refreshedRecord.optionsPagePath
            || entity.defaultPopupPath != refreshedRecord.defaultPopupPath
            || entity.hasBackground != refreshedRecord.hasBackground
            || entity.hasAction != refreshedRecord.hasAction
            || entity.hasOptionsPage != refreshedRecord.hasOptionsPage
            || entity.hasContentScripts != refreshedRecord.hasContentScripts
            || entity.hasExtensionPages != refreshedRecord.hasExtensionPages
            || entity.broadScope != refreshedRecord.activationSummary.broadScope
            || entity.activationSummaryJSON != refreshedRecord.encodedActivationSummary
            || entity.manifestSnapshotJSON != refreshedRecord.encodedManifestSnapshot
    }

    private nonisolated func cleanupOrphanedExtensionPackages(
        referencedPackagePaths: Set<String>
    ) {
        guard !referencedPackagePaths.isEmpty else { return }
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        guard Self.shouldRunOrphanedExtensionPackageCleanup() else { return }
        UserDefaults.standard.set(
            Date(),
            forKey: Self.orphanedExtensionCleanupDefaultsKey
        )

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30) {
            let fileManager = FileManager.default
            let extensionsDirectory = ExtensionUtils.extensionsDirectory()
            let referencedPaths = Set(referencedPackagePaths.map {
                URL(fileURLWithPath: $0).standardizedFileURL.path
            })
            let packageDirectories = (try? fileManager.contentsOfDirectory(
                at: extensionsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for packageDirectory in packageDirectories {
                guard UUID(uuidString: packageDirectory.lastPathComponent) != nil else {
                    continue
                }
                guard (try? packageDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                    continue
                }
                guard referencedPaths.contains(packageDirectory.standardizedFileURL.path) == false else {
                    continue
                }
                try? fileManager.removeItem(at: packageDirectory)
            }
        }
    }

    private nonisolated static func shouldRunOrphanedExtensionPackageCleanup() -> Bool {
        guard let lastRun = UserDefaults.standard.object(
            forKey: orphanedExtensionCleanupDefaultsKey
        ) as? Date else {
            return true
        }

        return Date().timeIntervalSince(lastRun) >= orphanedExtensionCleanupInterval
    }
}

//
//  ExtensionInstallationMetadataStore.swift
//  Sumi
//
//  Installed-extension metadata persistence and refresh owner.
//

import Foundation
import OSLog
import SwiftData

@available(macOS 15.5, *)
@MainActor
final class ExtensionInstallationMetadataStore {
    nonisolated private static let logger = Logger.sumi(category: "Extensions")

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
    private let packageLayout: ExtensionPackageLayout
    private let packageMaintenance: ExtensionPackageMaintenance
    private let legacyBackupRecovery: LegacyExtensionBackupRecovery

    init(
        context: ModelContext,
        activePackageGenerations: ExtensionPackageGenerationRegistry = .init(),
        extensionsDirectory: URL = ExtensionUtils.extensionsDirectory()
    ) {
        let packageLayout = ExtensionPackageLayout(
            extensionsRoot: extensionsDirectory
        )
        self.context = context
        self.packageLayout = packageLayout
        self.packageMaintenance = ExtensionPackageMaintenance(
            layout: packageLayout,
            activeGenerations: activePackageGenerations
        )
        self.legacyBackupRecovery = LegacyExtensionBackupRecovery(
            layout: packageLayout
        )
    }

    func persist(record: InstalledExtension) throws {
        if let existing = try extensionEntity(for: record.id) {
            update(existing, from: record)
        } else {
            context.insert(ExtensionEntity(record: record))
        }
        try context.save()
    }

    func persistedInstallationIdentities() throws
        -> [ExtensionInstallationPersistedIdentity] {
        try context.fetch(FetchDescriptor<ExtensionEntity>()).map {
            ExtensionInstallationPersistedIdentity(
                extensionID: $0.id,
                sourceBundlePath: $0.sourceBundlePath,
                sourceKind: WebExtensionSourceKind(
                    rawValue: $0.sourceKindRawValue
                ) ?? .directory,
                safariRuntimeIdentity: $0.safariRuntimeIdentity ??
                    SafariWebExtensionRuntimeIdentity.composedIdentifier(
                        sourceKind: WebExtensionSourceKind(
                            rawValue: $0.sourceKindRawValue
                        ) ?? .directory,
                        sourceBundlePath: $0.sourceBundlePath
                    )
            )
        }
    }

    func restore(
        originalRecord: InstalledExtension?,
        extensionID: String
    ) throws {
        if let entity = try extensionEntity(for: extensionID) {
            if let originalRecord {
                update(entity, from: originalRecord)
            } else {
                context.delete(entity)
            }
        } else if let originalRecord {
            context.insert(ExtensionEntity(record: originalRecord))
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

        let packageURL = URL(
            fileURLWithPath: packagePath,
            isDirectory: true
        )
        switch packageLayout.packageRootKind(packageURL) {
        case .managedGeneration, .legacyDirect:
            return packageURL
        case .stagingTransaction, .outsideLayout:
            throw ExtensionError.installationFailed(
                "Installed extension package is outside browser-owned storage"
            )
        }
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
            Self.logger.error("Failed to fetch extensions: \(error.localizedDescription, privacy: .public)")
            return MetadataLoadResult(
                didFetchPersistedMetadata: false,
                records: [],
                enabledEntities: []
            )
        }

        var loadedRecords: [InstalledExtension] = []
        var enabledEntitiesToLoad: [ExtensionEntity] = []
        var didMutatePersistence = false
        var recoveredQuarantineURLs: [URL] = []
        var deferredPackagePaths: Set<String> = []

        for entity in entities {
            let sourceKind = WebExtensionSourceKind(rawValue: entity.sourceKindRawValue) ?? .directory
            let recovery = legacyBackupRecovery.recover(
                .init(
                    extensionID: entity.id,
                    packagePath: entity.packagePath,
                    manifestRootFingerprint: entity.manifestRootFingerprint,
                    sourceKind: sourceKind
                )
            )
            recoveredQuarantineURLs += recovery.quarantinedURLs
            guard recovery.validationDisposition == .proceed else {
                deferredPackagePaths.insert(entity.packagePath)
                Self.logger.error(
                    "Deferred ambiguous legacy package recovery for \(entity.id, privacy: .public)"
                )
                continue
            }
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
                Self.logger.error(
                    "Dropped invalid persisted extension record for \(entity.name, privacy: .public)"
                )
                continue
            }
            guard FileManager.default.fileExists(atPath: packageURL.path) else {
                context.delete(entity)
                didMutatePersistence = true
                Self.logger.error(
                    "Dropped invalid persisted extension record for \(entity.name, privacy: .public)"
                )
                continue
            }

            var record = InstalledExtensionRecord(from: entity)
            refreshPersistedMetadataIfNeeded(
                entity: entity,
                packageURL: packageURL,
                trace: trace,
                record: &record,
                didMutatePersistence: &didMutatePersistence
            )

            guard let record else {
                context.delete(entity)
                didMutatePersistence = true
                Self.logger.error(
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
                .union(deferredPackagePaths),
            recoveredQuarantineURLs: recoveredQuarantineURLs
        )

        if didMutatePersistence {
            do {
                try context.save()
            } catch {
                Self.logger.error("Failed to persist refreshed extension metadata: \(error.localizedDescription, privacy: .public)")
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
        if entity.safariRuntimeIdentity == nil {
            entity.safariRuntimeIdentity = record.safariRuntimeIdentity
        }
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
            safariRuntimeIdentity: record.safariRuntimeIdentity,
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
            safariRuntimeIdentity: existingEntity?.safariRuntimeIdentity
                ?? SafariWebExtensionRuntimeIdentity.composedIdentifier(
                    sourceKind: sourceKind,
                    sourceBundlePath: sourceBundlePath
                ),
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
            || entity.safariRuntimeIdentity != refreshedRecord.safariRuntimeIdentity
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

    private func refreshPersistedMetadataIfNeeded(
        entity: ExtensionEntity,
        packageURL: URL,
        trace: (String) -> Void,
        record: inout InstalledExtensionRecord?,
        didMutatePersistence: inout Bool
    ) {
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        let manifest: [String: Any]
        do {
            manifest = try ExtensionUtils.loadJSONObject(at: manifestURL)
        } catch {
            Self.logger.error(
                "Failed to read persisted extension manifest for \(entity.id, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return
        }

        let refreshed: InstalledExtension
        do {
            refreshed = try refreshedRecord(for: entity, manifest: manifest)
        } catch {
            Self.logger.error(
                "Failed to refresh persisted extension metadata for \(entity.id, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return
        }

        guard extensionMetadataNeedsRefresh(entity, refreshedRecord: refreshed) else {
            return
        }

        update(entity, from: refreshed)
        record = refreshed
        didMutatePersistence = true
        trace(
            "Refreshed extension metadata id=\(entity.id) background=\(refreshed.backgroundModel.rawValue)"
        )
    }

    private func cleanupOrphanedExtensionPackages(
        referencedPackagePaths: Set<String>,
        recoveredQuarantineURLs: [URL]
    ) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        guard Self.shouldRunOrphanedExtensionPackageCleanup() else {
            packageMaintenance.deleteQuarantinedPackages(
                recoveredQuarantineURLs
            )
            return
        }
        UserDefaults.standard.set(
            Date(),
            forKey: Self.orphanedExtensionCleanupDefaultsKey
        )
        let orphaned = packageMaintenance.quarantineOrphans(
            referencedPackagePaths: referencedPackagePaths
        )
        let quarantined = Array(Set(orphaned + recoveredQuarantineURLs))
        packageMaintenance.deleteQuarantinedPackages(quarantined)
    }

    nonisolated private static func shouldRunOrphanedExtensionPackageCleanup() -> Bool {
        guard let lastRun = UserDefaults.standard.object(
            forKey: orphanedExtensionCleanupDefaultsKey
        ) as? Date else {
            return true
        }

        return Date().timeIntervalSince(lastRun) >= orphanedExtensionCleanupInterval
    }
}

@available(macOS 15.5, *)
extension ExtensionInstallationMetadataStore:
    ExtensionInstallationRecordPersisting {}

// MARK: - ExtensionManager facade

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func persist(record: InstalledExtension) throws {
        try installationMetadataStore.persist(record: record)
    }

    func extensionEntity(for id: String) throws -> ExtensionEntity? {
        try installationMetadataStore.extensionEntity(for: id)
    }

    func extensionResourcesRoot(
        sourceKind: WebExtensionSourceKind,
        packagePath: String,
        sourceBundlePath: String
    ) throws -> URL {
        try installationMetadataStore.extensionResourcesRoot(
            sourceKind: sourceKind,
            packagePath: packagePath,
            sourceBundlePath: sourceBundlePath
        )
    }

    func extensionResourcesRoot(for entity: ExtensionEntity) throws -> URL {
        try installationMetadataStore.extensionResourcesRoot(for: entity)
    }

    func update(
        _ entity: ExtensionEntity,
        from record: InstalledExtension
    ) {
        installationMetadataStore.update(entity, from: record)
    }

    func refreshedRecord(
        for entity: ExtensionEntity,
        manifest: [String: Any]
    ) throws -> InstalledExtension {
        try installationMetadataStore.refreshedRecord(for: entity, manifest: manifest)
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
        try installationMetadataStore.makeInstalledRecord(
            extensionId: extensionId,
            manifest: manifest,
            extensionRoot: extensionRoot,
            isEnabled: isEnabled,
            sourceKind: sourceKind,
            sourceBundlePath: sourceBundlePath,
            sourceFingerprintURL: sourceFingerprintURL,
            existingEntity: existingEntity
        )
    }
}

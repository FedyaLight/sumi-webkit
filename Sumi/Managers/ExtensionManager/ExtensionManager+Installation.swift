//
//  ExtensionManager+Installation.swift
//  Sumi
//
//  Installation and runtime loading flows for Sumi's WebExtension runtime.
//

import AppKit
import Foundation
import SwiftData
import WebKit

@available(macOS 15.5, *)
extension ExtensionManager {
    enum WebExtensionStorageCleanupMode {
        case pruneDirectoryIfPossible
        case preserveDirectoryForImmediateRuntimeLoad
    }

    struct WebExtensionStorageSnapshot: Equatable {
        let directoryExists: Bool
        let entryNames: [String]
        let hasRegisteredContentScriptsStore: Bool
        let hasLocalStorageStore: Bool
        let hasSyncStorageStore: Bool

        static let trackedOptionalStoreNames = [
            "RegisteredContentScripts.db",
            "LocalStorage.db",
            "SyncStorage.db",
        ]

        var hasOnlyPrunableEntries: Bool {
            entryNames.allSatisfy { $0 == "State.plist" }
        }

        var missingTrackedOptionalStoreNames: [String] {
            Self.trackedOptionalStoreNames.filter { entryNames.contains($0) == false }
        }

        var isMissingTrackedOptionalStoresOnly: Bool {
            directoryExists && missingTrackedOptionalStoreNames.isEmpty == false
        }
    }

    struct WebExtensionStoreCapabilitySnapshot: Equatable {
        let usesWebKitCompatibilityPrelude: Bool
        let mayTouchDynamicContentScriptStore: Bool
        let mayTouchSyncStorageStore: Bool
        let declaredPermissions: [String]
        let unsupportedAPIs: [String]
    }

    struct WebExtensionCleanupErrorDiagnostic: Equatable {
        let domain: String
        let code: Int
        let localizedDescription: String
        let localizedFailureReason: String
        let debugDescription: String
        let userInfoDescription: String

        private var normalizedPayload: String {
            [
                localizedDescription,
                localizedFailureReason,
                debugDescription,
                userInfoDescription,
            ]
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
            .lowercased()
        }

        var referencesOptionalStore: Bool {
            WebExtensionStorageSnapshot.trackedOptionalStoreNames.contains { storeName in
                normalizedPayload.contains(storeName.lowercased())
            }
        }

        var mentionsMissingFile: Bool {
            normalizedPayload.contains("no such file or directory")
                || normalizedPayload.contains("cannot open file")
                || normalizedPayload.contains("open(")
        }

        var isGenericSQLiteStoreCreationFailure: Bool {
            normalizedPayload.contains("failed to create sqlite store")
        }

        var isWebKitExtensionStorageComputationFailure: Bool {
            domain == "WKWebExtensionDataRecordErrorDomain"
                && code == 3
                && (
                    normalizedPayload.contains("unable to calculate extension storage")
                        || normalizedPayload.contains("unable to delete extension storage")
                )
        }

        var logSummary: String {
            "domain=\(domain) code=\(code) desc=\(localizedDescription) reason=\(localizedFailureReason) debug=\(debugDescription) userInfo=\(userInfoDescription)"
        }
    }

    struct WebExtensionCleanupErrorClassification: Equatable {
        let benignOptionalStoreDiagnostics: [WebExtensionCleanupErrorDiagnostic]
        let actionableDiagnostics: [WebExtensionCleanupErrorDiagnostic]
    }

    /// Delivers install results on the next main runloop turn so SwiftUI does not emit
    /// "Publishing changes from within view updates" when UI callbacks mutate `@Published` state.
    private func deliverInstallCompletion(
        _ result: Result<InstalledExtension, ExtensionError>,
        to completionHandler: @escaping (Result<InstalledExtension, ExtensionError>) -> Void
    ) {
        Task { @MainActor in
            await Task.yield()
            completionHandler(result)
        }
    }

    func installExtension(
        from sourceURL: URL,
        completionHandler: @escaping (Result<InstalledExtension, ExtensionError>) -> Void
    ) {
        guard isExtensionSupportAvailable else {
            deliverInstallCompletion(.failure(.unsupportedOS), to: completionHandler)
            return
        }

        Task {
            do {
                let installed = try await performInstallation(from: sourceURL)
                deliverInstallCompletion(.success(installed), to: completionHandler)
            } catch let error as ExtensionError {
                deliverInstallCompletion(.failure(error), to: completionHandler)
            } catch {
                deliverInstallCompletion(
                    .failure(.installationFailed(error.localizedDescription)),
                    to: completionHandler
                )
            }
        }
    }

    func enableExtension(_ extensionId: String) async throws -> InstalledExtension {
        guard let entity = try extensionEntity(for: extensionId) else {
            throw ExtensionError.installationFailed("Extension was not found in persistence")
        }

        entity.isEnabled = true
        entity.lastUpdateDate = Date()
        try context.save()
        let sourceKind =
            WebExtensionSourceKind(rawValue: entity.sourceKindRawValue) ?? .directory
        let manifest = try ExtensionUtils.validateManifest(
            at: URL(fileURLWithPath: entity.packagePath).appendingPathComponent("manifest.json"),
            policy: WebExtensionManifestValidationPolicy.forSourceKind(sourceKind)
        )
        let refreshed = try refreshedRecord(for: entity, manifest: manifest)
        await applyInstalledExtensionsMutationOnNextRunLoop { manager in
            manager.upsertInstalledExtension(refreshed)
        }
        loadInstalledExtensionMetadata()

        let enableProfileId =
            currentProfileId
            ?? browserManager?.currentProfile?.id
        guard let enableProfileId else {
            throw ExtensionError.installationFailed(
                "Extension runtime profile is unavailable"
            )
        }

        _ = ensureExtensionController(for: enableProfileId)
        if getExtensionContext(for: extensionId, profileId: enableProfileId) == nil {
            return try await loadEnabledExtension(
                from: entity,
                profileId: enableProfileId,
                postLoadBackgroundWakeReason: .enable
            )
        }

        await finalizeEnabledExtensionRuntime(
            for: extensionId,
            profileId: enableProfileId,
            backgroundWakeReason: .enable
        )
        return refreshed
    }

    func disableExtension(
        _ extensionId: String,
        releaseRuntimeIfIdle: Bool = true
    ) async throws {
        tearDownExtensionRuntimeState(for: extensionId, removeUIState: true)

        if let entity = try extensionEntity(for: extensionId) {
            entity.isEnabled = false
            entity.lastUpdateDate = Date()
            try context.save()
        }

        await applyInstalledExtensionsMutationOnNextRunLoop { manager in
            guard let index = manager.installedExtensions.firstIndex(where: { $0.id == extensionId }) else {
                return
            }

            let current = manager.installedExtensions[index]
            let updated = InstalledExtensionRecord(
                id: current.id,
                name: current.name,
                version: current.version,
                manifestVersion: current.manifestVersion,
                description: current.description,
                isEnabled: false,
                installDate: current.installDate,
                lastUpdateDate: Date(),
                packagePath: current.packagePath,
                iconPath: current.iconPath,
                sourceKind: current.sourceKind,
                backgroundModel: current.backgroundModel,
                incognitoMode: current.incognitoMode,
                sourcePathFingerprint: current.sourcePathFingerprint,
                manifestRootFingerprint: current.manifestRootFingerprint,
                sourceBundlePath: current.sourceBundlePath,
                optionsPagePath: current.optionsPagePath,
                defaultPopupPath: current.defaultPopupPath,
                hasBackground: current.hasBackground,
                hasAction: current.hasAction,
                hasOptionsPage: current.hasOptionsPage,
                hasContentScripts: current.hasContentScripts,
                hasExtensionPages: current.hasExtensionPages,
                activationSummary: current.activationSummary,
                manifest: current.manifest
            )
            manager.installedExtensions[index] = updated
            manager.sortInstalledExtensions()
        }

        if releaseRuntimeIfIdle && hasEnabledInstalledExtensions == false {
            tearDownExtensionRuntime(
                reason: "disableExtension.noEnabledExtensions",
                removeUIState: true,
                releaseController: true
            )
        }
    }

    func uninstallExtension(_ extensionId: String) async throws {
        try await disableExtension(extensionId, releaseRuntimeIfIdle: false)
        await removeStoredWebExtensionData(for: extensionId)

        if let entity = try extensionEntity(for: extensionId) {
            let packageURL = URL(fileURLWithPath: entity.packagePath)
            if FileManager.default.fileExists(atPath: packageURL.path) {
                try FileManager.default.removeItem(at: packageURL)
            }
            context.delete(entity)
            try context.save()
        }

        await applyInstalledExtensionsMutationOnNextRunLoop { manager in
            manager.installedExtensions.removeAll { $0.id == extensionId }
        }

        if hasEnabledInstalledExtensions == false {
            tearDownExtensionRuntime(
                reason: "uninstallExtension.noEnabledExtensions",
                removeUIState: true,
                releaseController: true
            )
        }
    }

    @discardableResult
    func loadInstalledExtensionMetadata() -> [ExtensionEntity] {
        let signpostState = PerformanceTrace.beginInterval(
            "ExtensionManager.loadInstalledExtensionMetadata"
        )
        defer {
            PerformanceTrace.endInterval(
                "ExtensionManager.loadInstalledExtensionMetadata",
                signpostState
            )
        }

        extensionRuntimeTrace(
            "loadInstalledExtensionMetadata start installedContexts=\(extensionContexts.count)"
        )

        let entities: [ExtensionEntity]
        do {
            entities = try context.fetch(FetchDescriptor<ExtensionEntity>())
        } catch {
            Self.logger.error("Failed to fetch extensions: \(error.localizedDescription, privacy: .public)")
            installedExtensions = []
            extensionsLoaded = true
            return []
        }

        var loadedRecords: [InstalledExtension] = []
        var enabledEntitiesToLoad: [ExtensionEntity] = []
        var didMutatePersistence = false

        for entity in entities {
            let packageURL = URL(fileURLWithPath: entity.packagePath, isDirectory: true)
            guard FileManager.default.fileExists(atPath: packageURL.path) else {
                context.delete(entity)
                didMutatePersistence = true
                Self.logger.error(
                    "Dropped invalid persisted extension record for \(entity.name, privacy: .public)"
                )
                continue
            }

            var record = InstalledExtensionRecord(from: entity)
            if let manifest = try? ExtensionUtils.loadJSONObject(
                at: packageURL.appendingPathComponent("manifest.json")
            ),
               let refreshed = try? refreshedRecord(for: entity, manifest: manifest),
               extensionMetadataNeedsRefresh(entity, refreshedRecord: refreshed)
            {
                update(entity, from: refreshed)
                record = refreshed
                didMutatePersistence = true
                extensionRuntimeTrace(
                    "Refreshed extension metadata id=\(entity.id) background=\(refreshed.backgroundModel.rawValue)"
                )
            }

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

        installedExtensions = loadedRecords.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        reconcilePinnedToolbarExtensions()
        cleanupOrphanedExtensionPackages(
            referencedPackagePaths: Set(loadedRecords.map(\.packagePath))
        )

        if didMutatePersistence {
            do {
                try context.save()
            } catch {
                Self.logger.error("Failed to persist refreshed extension metadata: \(error.localizedDescription, privacy: .public)")
            }
        }

        extensionsLoaded = true
        extensionRuntimeTrace(
            "loadInstalledExtensionMetadata complete records=\(loadedRecords.count) enabled=\(enabledEntitiesToLoad.count)"
        )
        return enabledEntitiesToLoad
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

    func loadEnabledExtension(
        from entity: ExtensionEntity,
        profileId: UUID? = nil,
        expectedLoadGeneration: UInt64? = nil,
        postLoadBackgroundWakeReason: ExtensionBackgroundWakeReason? = nil
    ) async throws -> InstalledExtension {
        let signpostState = PerformanceTrace.beginInterval("ExtensionManager.loadEnabledExtension")
        defer {
            PerformanceTrace.endInterval("ExtensionManager.loadEnabledExtension", signpostState)
        }

        do {
            let resolvedProfileId =
                profileId
                ?? currentProfileId
                ?? browserManager?.currentProfile?.id
            guard let resolvedProfileId else {
                throw ExtensionError.installationFailed(
                    "Extension runtime profile is unavailable"
                )
            }
            let extensionController = ensureExtensionController(for: resolvedProfileId)

            let extensionRoot = URL(fileURLWithPath: entity.packagePath)
            let manifestURL = extensionRoot.appendingPathComponent("manifest.json")
            let sourceKind =
                WebExtensionSourceKind(rawValue: entity.sourceKindRawValue) ?? .directory
            extensionRuntimeTrace(
                "loadEnabledExtension start extensionId=\(entity.id) profileId=\(resolvedProfileId.uuidString) expectedGeneration=\(expectedLoadGeneration.map(String.init) ?? "nil") currentGeneration=\(extensionLoadGeneration) packagePath=\(entity.packagePath)"
            )
            let validationStart = CFAbsoluteTimeGetCurrent()
            let manifest = try ExtensionUtils.validateManifest(
                at: manifestURL,
                policy: WebExtensionManifestValidationPolicy.forSourceKind(sourceKind)
            )
            recordRuntimeMetric(for: entity.id) {
                $0.manifestValidationDuration = CFAbsoluteTimeGetCurrent() - validationStart
            }
            let webExtensionStart = CFAbsoluteTimeGetCurrent()
            let (webExtension, runtimeLoadSource) = try await cachedOrCreateWebExtension(
                extensionId: entity.id,
                sourceKind: sourceKind,
                sourceBundlePath: entity.sourceBundlePath,
                packageRoot: extensionRoot
            )
            extensionRuntimeTrace(
                "loadEnabledExtension webExtension source=\(runtimeLoadSource.rawValue) packagePath=\(entity.packagePath) sourceBundlePath=\(entity.sourceBundlePath)"
            )
            recordRuntimeMetric(for: entity.id) {
                $0.webExtensionCreationDuration =
                    CFAbsoluteTimeGetCurrent() - webExtensionStart
            }
            try validateExpectedExtensionLoadGeneration(expectedLoadGeneration)
            let extensionContext = WKWebExtensionContext(for: webExtension)
            configureContextIdentity(
                extensionContext,
                extensionId: entity.id,
                profileId: resolvedProfileId
            )
            grantRequestedPermissions(
                to: extensionContext,
                webExtension: webExtension,
                manifest: manifest
            )
            grantRequestedMatchPatterns(to: extensionContext, webExtension: webExtension)
            applyStoredExtensionPermissionDecisions(
                to: extensionContext,
                extensionId: entity.id,
                profileId: resolvedProfileId
            )
            extensionContext.isInspectable = RuntimeDiagnostics.isDeveloperInspectionEnabled
            observeExtensionErrors(for: extensionContext, extensionId: entity.id)
            prepareExtensionContextForRuntime(
                extensionContext,
                extensionId: entity.id,
                profileId: resolvedProfileId,
                manifest: manifest
            )
            ensureWebExtensionStorageDirectoryExists(
                for: entity.id,
                profileId: resolvedProfileId
            )
            traceWebExtensionStoreLifecycle(
                phase: "before-loadEnabledExtension-controller-load",
                extensionId: entity.id,
                manifest: manifest
            )

            setExtensionContext(
                extensionContext,
                extensionId: entity.id,
                profileId: resolvedProfileId
            )
            loadedExtensionManifests[entity.id] = manifest

            do {
                #if DEBUG
                    try testHooks.beforeControllerLoad?(
                        entity.id,
                        webExtensionStorageSnapshot(for: entity.id)
                    )
                #endif
                let contextLoadStart = CFAbsoluteTimeGetCurrent()
                try extensionController.load(extensionContext)
                recordRuntimeMetric(for: entity.id) {
                    $0.contextLoadDuration =
                        CFAbsoluteTimeGetCurrent() - contextLoadStart
                }
            } catch {
                tearDownExtensionRuntimeState(for: entity.id, removeUIState: false)
                throw error
            }

            extensionRuntimeTrace(
                "loadEnabledExtension loaded extensionId=\(entity.id) context=\(extensionRuntimeObjectDescription(extensionContext)) controller=\(extensionRuntimeControllerDescription(extensionController))"
            )

            clearExtensionLoadError(
                extensionId: entity.id,
                profileId: resolvedProfileId
            )
            touchLiveExtensionContext(
                extensionId: entity.id,
                profileId: resolvedProfileId
            )
            enforceBoundedLiveExtensionContexts(
                keepingProfileId: resolvedProfileId,
                keepingExtensionId: entity.id
            )

            await finalizeEnabledExtensionRuntime(
                for: entity.id,
                profileId: resolvedProfileId,
                backgroundWakeReason: postLoadBackgroundWakeReason
            )
            markExtensionRuntimeReadyIfProfileContextsLoaded(for: resolvedProfileId)

            let refreshed = try refreshedRecord(for: entity, manifest: manifest)
            await applyInstalledExtensionsMutationOnNextRunLoop { manager in
                manager.upsertInstalledExtension(refreshed)
            }
            update(entity, from: refreshed)
            try context.save()
            return refreshed
        } catch {
            let errorProfileId =
                profileId
                ?? currentProfileId
                ?? browserManager?.currentProfile?.id
            if let errorProfileId {
                recordExtensionLoadError(
                    error,
                    extensionId: entity.id,
                    profileId: errorProfileId
                )
            }
            tearDownExtensionRuntimeState(for: entity.id, removeUIState: false)
            throw error
        }
    }

    func cachedOrCreateWebExtension(
        extensionId: String,
        sourceKind: WebExtensionSourceKind,
        sourceBundlePath: String,
        packageRoot: URL
    ) async throws -> (extension: WKWebExtension, loadSource: SafariAppExtensionRuntimeLoadSource) {
        if let cached = cachedWebExtensionsByID[extensionId] {
            return (cached, .copiedPackage)
        }

        let created = try await SafariAppExtensionResources.makeWebExtension(
            sourceKind: sourceKind,
            sourceBundlePath: sourceBundlePath,
            packageRoot: packageRoot
        )
        cachedWebExtensionsByID[extensionId] = created.extension
        return created
    }

    @discardableResult
    func ensureBackgroundAvailableIfRequired(
        for webExtension: WKWebExtension,
        context extensionContext: WKWebExtensionContext,
        reason: ExtensionBackgroundWakeReason
    ) async throws -> Bool {
        guard webExtension.hasBackgroundContent else { return false }
        let wakeKey = backgroundWakeKey(for: extensionContext)

        switch backgroundRuntimeState(for: wakeKey) {
        case .loaded:
            extensionRuntimeTrace(
                "Skipping required background wake for \(wakeKey): already loaded"
            )
            return false
        case .wakeInFlight:
            if let existingTask = backgroundWakeTasks[wakeKey] {
                extensionRuntimeTrace(
                    "Awaiting required background wake already in flight for \(wakeKey)"
                )
                try await existingTask.value
                return false
            }
            setBackgroundRuntimeState(.neverLoaded, for: wakeKey)
        case .neverLoaded, .loadFailed:
            break
        }

        let task = startBackgroundWakeTask(
            wakeKey: wakeKey,
            extensionContext: extensionContext,
            reason: reason,
            mode: "required"
        )
        try await task.value
        return true
    }

    private func makeBackgroundWakeTask(
        wakeKey: String,
        extensionContext: WKWebExtensionContext,
        reason: ExtensionBackgroundWakeReason
    ) -> Task<Void, Error> {
        Task { @MainActor in
            defer {
                self.backgroundWakeTasks.removeValue(forKey: wakeKey)
            }

            let wakeStart = CFAbsoluteTimeGetCurrent()
            do {
                #if DEBUG
                    if let backgroundContentWake = self.testHooks.backgroundContentWake {
                        try await backgroundContentWake(wakeKey, extensionContext)
                    } else {
                        try await extensionContext.loadBackgroundContent()
                    }
                #else
                    try await extensionContext.loadBackgroundContent()
                #endif

                self.setBackgroundRuntimeState(.loaded, for: wakeKey)
                self.recordRuntimeMetric(for: wakeKey) {
                    $0.backgroundWakeDuration =
                        CFAbsoluteTimeGetCurrent() - wakeStart
                    $0.backgroundWakeCount += 1
                    $0.lastBackgroundWakeReason = reason
                    $0.lastBackgroundWakeFailed = false
                }
            } catch {
                self.setBackgroundRuntimeState(.loadFailed, for: wakeKey)
                self.recordRuntimeMetric(for: wakeKey) {
                    $0.backgroundWakeDuration =
                        CFAbsoluteTimeGetCurrent() - wakeStart
                    $0.backgroundWakeCount += 1
                    $0.lastBackgroundWakeReason = reason
                    $0.lastBackgroundWakeFailed = true
                }
                throw error
            }
        }
    }

    @discardableResult
    private func startBackgroundWakeTask(
        wakeKey: String,
        extensionContext: WKWebExtensionContext,
        reason: ExtensionBackgroundWakeReason,
        mode: String
    ) -> Task<Void, Error> {
        setBackgroundRuntimeState(.wakeInFlight, for: wakeKey)
        extensionRuntimeTrace(
            "Starting \(mode) background wake for \(wakeKey) reason=\(reason.rawValue)"
        )
        let task = makeBackgroundWakeTask(
            wakeKey: wakeKey,
            extensionContext: extensionContext,
            reason: reason
        )
        backgroundWakeTasks[wakeKey] = task
        return task
    }

    private func backgroundWakeKey(
        for extensionContext: WKWebExtensionContext
    ) -> String {
        if let extensionId = extensionID(for: extensionContext),
           let profileId = profileId(for: extensionContext)
        {
            return backgroundScopedKey(extensionId: extensionId, profileId: profileId)
        }
        return "context:\(ObjectIdentifier(extensionContext))"
    }

    func backgroundRuntimeState(
        for extensionId: String,
        profileId: UUID? = nil
    ) -> BackgroundRuntimeState {
        let resolvedProfileId =
            profileId ?? currentProfileId ?? browserManager?.currentProfile?.id
        guard let resolvedProfileId else { return .neverLoaded }
        return backgroundRuntimeStateByExtensionID[
            backgroundScopedKey(extensionId: extensionId, profileId: resolvedProfileId)
        ] ?? .neverLoaded
    }

    private func setBackgroundRuntimeState(
        _ state: BackgroundRuntimeState,
        for wakeKey: String
    ) {
        if state == .neverLoaded {
            backgroundRuntimeStateByExtensionID.removeValue(forKey: wakeKey)
        } else {
            backgroundRuntimeStateByExtensionID[wakeKey] = state
        }
    }

    func performInstallation(
        from sourceURL: URL,
        enableOnInstall: Bool = true
    ) async throws -> InstalledExtension {
        if enableOnInstall {
            _ = await requestExtensionRuntimeAndWait(
                reason: .install,
                allowWithoutEnabledExtensions: true
            )
        }

        let extensionsDirectory = ExtensionUtils.extensionsDirectory()
        let resolvedSource = try Self.resolveInstallSource(at: sourceURL)
        let temporaryDirectory = extensionsDirectory.appendingPathComponent(
            "temp_\(UUID().uuidString)",
            isDirectory: true
        )

        if FileManager.default.fileExists(atPath: temporaryDirectory.path) {
            try FileManager.default.removeItem(at: temporaryDirectory)
        }

        var finalDirectory: URL?
        var backupDirectory: URL?
        var installedExtensionID: String?
        var existingEntitySnapshot: ExtensionEntity?
        var shouldRestoreExistingRuntime = false

        do {
            if resolvedSource.sourceKind == .safariAppExtension,
               let appexBundleURL = resolvedSource.appexBundleURL
            {
                guard let bundle = Bundle(url: appexBundleURL) else {
                    throw ExtensionError.installationFailed(
                        "Safari app extension bundle could not be opened"
                    )
                }
                _ = try await WKWebExtension(appExtensionBundle: bundle)
                try SafariAppExtensionResources.copyResources(
                    from: resolvedSource.resourcesURL,
                    to: temporaryDirectory
                )
            } else {
                try FileManager.default.copyItem(
                    at: resolvedSource.resourcesURL,
                    to: temporaryDirectory
                )
            }

            let manifestPolicy = WebExtensionManifestValidationPolicy.forSourceKind(
                resolvedSource.sourceKind
            )
            let manifestURL = temporaryDirectory.appendingPathComponent("manifest.json")
            let manifest = try ExtensionUtils.validateManifest(
                at: manifestURL,
                policy: manifestPolicy
            )
            try validateMV3Requirements(manifest: manifest, baseURL: temporaryDirectory)

            let extensionId: String
            let allEntities = try context.fetch(FetchDescriptor<ExtensionEntity>())
            if let existingEntity = allEntities.first(where: { $0.sourceBundlePath == resolvedSource.sourceBundlePath.path }) {
                extensionId = existingEntity.id
            } else if let browserSpecificSettings = manifest["browser_specific_settings"] as? [String: Any],
                      let gecko = browserSpecificSettings["gecko"] as? [String: Any],
                      let geckoId = gecko["id"] as? String {
                extensionId = geckoId
            } else {
                extensionId = UUID().uuidString
            }
            
            installedExtensionID = extensionId

            let destinationDirectory = extensionsDirectory.appendingPathComponent(
                extensionId,
                isDirectory: true
            )
            finalDirectory = destinationDirectory
            existingEntitySnapshot = try extensionEntity(for: extensionId)
            shouldRestoreExistingRuntime = existingEntitySnapshot?.isEnabled == true

            if FileManager.default.fileExists(atPath: destinationDirectory.path) {
                let existingBackup = extensionsDirectory.appendingPathComponent(
                    "backup_\(extensionId)_\(UUID().uuidString)",
                    isDirectory: true
                )
                try FileManager.default.moveItem(at: destinationDirectory, to: existingBackup)
                backupDirectory = existingBackup
            }

            if let existingEntitySnapshot {
                tearDownExtensionRuntimeState(
                    for: existingEntitySnapshot.id,
                    removeUIState: false
                )
            } else if hasStoredWebExtensionDataCandidate(for: extensionId) {
                traceWebExtensionStoreLifecycle(
                    phase: "before-install-cleanup",
                    extensionId: extensionId,
                    manifest: manifest
                )
                await removeStoredWebExtensionData(
                    for: extensionId,
                    mode: .preserveDirectoryForImmediateRuntimeLoad
                )
                traceWebExtensionStoreLifecycle(
                    phase: "after-install-cleanup",
                    extensionId: extensionId,
                    manifest: manifest
                )
            } else {
                if RuntimeDiagnostics.isVerboseEnabled {
                    extensionRuntimeTrace(
                        "Skipped WebExtension data cleanup for \(extensionId): no stored data candidate (fresh install path)"
                    )
                }
            }

            try FileManager.default.moveItem(at: temporaryDirectory, to: destinationDirectory)

            let finalManifestURL = destinationDirectory.appendingPathComponent("manifest.json")
            let finalManifest = try ExtensionUtils.validateManifest(
                at: finalManifestURL,
                policy: manifestPolicy
            )

            let record = try makeInstalledRecord(
                extensionId: extensionId,
                manifest: finalManifest,
                extensionRoot: destinationDirectory,
                isEnabled: enableOnInstall,
                sourceKind: resolvedSource.sourceKind,
                sourceBundlePath: resolvedSource.sourceBundlePath.path,
                sourceFingerprintURL: resolvedSource.sourceFingerprintURL,
                existingEntity: existingEntitySnapshot
            )

            if enableOnInstall {
                let installProfileId =
                    currentProfileId
                    ?? browserManager?.currentProfile?.id
                guard let installProfileId else {
                    throw ExtensionError.installationFailed(
                        "Extension runtime profile is unavailable"
                    )
                }
                let installController = ensureExtensionController(for: installProfileId)

                let (webExtension, runtimeLoadSource) = try await cachedOrCreateWebExtension(
                    extensionId: extensionId,
                    sourceKind: resolvedSource.sourceKind,
                    sourceBundlePath: resolvedSource.sourceBundlePath.path,
                    packageRoot: destinationDirectory
                )
                extensionRuntimeTrace(
                    "performInstallation webExtension source=\(runtimeLoadSource.rawValue) packagePath=\(destinationDirectory.path) sourceBundlePath=\(resolvedSource.sourceBundlePath.path)"
                )
                let extensionContext = WKWebExtensionContext(for: webExtension)
                configureContextIdentity(
                    extensionContext,
                    extensionId: extensionId,
                    profileId: installProfileId
                )
                grantRequestedPermissions(
                    to: extensionContext,
                    webExtension: webExtension,
                    manifest: finalManifest
                )
                grantRequestedMatchPatterns(to: extensionContext, webExtension: webExtension)
                applyStoredExtensionPermissionDecisions(
                    to: extensionContext,
                    extensionId: extensionId,
                    profileId: installProfileId
                )
                extensionContext.isInspectable = RuntimeDiagnostics.isDeveloperInspectionEnabled
                observeExtensionErrors(for: extensionContext, extensionId: extensionId)
                prepareExtensionContextForRuntime(
                    extensionContext,
                    extensionId: extensionId,
                    profileId: installProfileId,
                    manifest: finalManifest
                )
                ensureWebExtensionStorageDirectoryExists(
                    for: extensionId,
                    profileId: installProfileId
                )
                traceWebExtensionStoreLifecycle(
                    phase: "before-install-controller-load",
                    extensionId: extensionId,
                    manifest: finalManifest
                )

                setExtensionContext(
                    extensionContext,
                    extensionId: extensionId,
                    profileId: installProfileId
                )
                loadedExtensionManifests[extensionId] = finalManifest

                do {
                    #if DEBUG
                        try testHooks.beforeControllerLoad?(
                            extensionId,
                            webExtensionStorageSnapshot(for: extensionId)
                        )
                    #endif
                    try installController.load(extensionContext)
                } catch {
                    tearDownExtensionRuntimeState(for: extensionId, removeUIState: false)
                    throw error
                }

                // New contexts must see existing windows even before `loadInstalledExtensions` sets
                // `extensionsLoaded`, or MV3 onboarding (`tabs.create`) may not run reliably.
                tabOpenNotificationGeneration &+= 1
                updateWebViewsForProfile(
                    installProfileId,
                    allowWhenExtensionsNotLoaded: true
                )
                resyncOpenTabsWithExtensionRuntimeAfterGenerationBump(
                    reason: "ExtensionManager.performInstallation.afterLoad",
                    allowWhenExtensionsNotLoaded: true
                )
                registerExistingWindowStateIfAttached()

                // Await background load so `runtime.onInstalled` / `tabs.create` can run in this install cycle
                // (fire-and-forget was returning before the service worker finished starting).
                let installedWebExtension = extensionContext.webExtension
                let installedDisplayName = installedWebExtension.displayName ?? record.id
                do {
                    _ = try await ensureBackgroundAvailableIfRequired(
                        for: installedWebExtension,
                        context: extensionContext,
                        reason: .install
                    )
                } catch {
                    Self.logger.error(
                        "Failed to wake background worker after install for \(installedDisplayName, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
                markExtensionRuntimeReadyIfProfileContextsLoaded(for: installProfileId)
            } else {
                ensureWebExtensionStorageDirectoryExists(for: extensionId)
            }

            #if DEBUG
                try testHooks.beforePersistInstalledRecord?(record)
            #endif
            try persist(record: record)
            await applyInstalledExtensionsMutationOnNextRunLoop { manager in
                manager.upsertInstalledExtension(record)
            }

            if let backupDirectory {
                try? FileManager.default.removeItem(at: backupDirectory)
            }

            return record
        } catch {
            if let installedExtensionID {
                tearDownExtensionRuntimeState(
                    for: installedExtensionID,
                    removeUIState: false
                )
            }

            if let finalDirectory, FileManager.default.fileExists(atPath: finalDirectory.path) {
                try? FileManager.default.removeItem(at: finalDirectory)
            }

            if FileManager.default.fileExists(atPath: temporaryDirectory.path) {
                try? FileManager.default.removeItem(at: temporaryDirectory)
            }

            if let backupDirectory, let finalDirectory {
                if FileManager.default.fileExists(atPath: finalDirectory.path) {
                    try? FileManager.default.removeItem(at: finalDirectory)
                }
                try? FileManager.default.moveItem(at: backupDirectory, to: finalDirectory)
            }

            if shouldRestoreExistingRuntime, let existingEntitySnapshot {
                _ = try? await loadEnabledExtension(from: existingEntitySnapshot)
            }

            throw error
        }
    }

    private func applyInstalledExtensionsMutationOnNextRunLoop(
        _ mutation: @escaping @MainActor (ExtensionManager) -> Void
    ) async {
        await withCheckedContinuation { continuation in
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self else {
                    continuation.resume(returning: ())
                    return
                }

                mutation(self)
                continuation.resume(returning: ())
            }
        }
    }

    func removeStoredWebExtensionData(
        for extensionId: String,
        mode: WebExtensionStorageCleanupMode = .pruneDirectoryIfPossible
    ) async {
        traceWebExtensionStoreLifecycle(
            phase: "cleanup-start",
            extensionId: extensionId
        )
        let hasDataCandidate = hasStoredWebExtensionDataCandidate(for: extensionId)
        if hasDataCandidate == false {
            finalizeWebExtensionStorageCleanup(for: extensionId, mode: mode)
            traceWebExtensionStoreLifecycle(
                phase: "cleanup-finished-no-local-candidate",
                extensionId: extensionId
            )
            if RuntimeDiagnostics.isVerboseEnabled {
                extensionRuntimeTrace(
                    "Skipped WebExtension data cleanup for \(extensionId): no stored data candidate"
                )
            }
            return
        }

        #if DEBUG
            if let webExtensionDataCleanup = testHooks.webExtensionDataCleanup,
               await webExtensionDataCleanup(extensionId)
            {
                finalizeWebExtensionStorageCleanup(for: extensionId, mode: mode)
                traceWebExtensionStoreLifecycle(
                    phase: "cleanup-finished-test-hook",
                    extensionId: extensionId
                )
                return
            }
        #endif

        let dataTypes = WKWebExtensionController.allExtensionDataTypes
        var matchingRecords: [WKWebExtension.DataRecord] = []
        for (profileId, controller) in extensionControllersByProfile {
            let records = await withCheckedContinuation { continuation in
                controller.fetchDataRecords(ofTypes: dataTypes) { records in
                    continuation.resume(returning: records)
                }
            }
            let scopedIdentifier = "\(profileId.uuidString):\(extensionId)"
            matchingRecords.append(
                contentsOf: records.filter {
                    $0.uniqueIdentifier == extensionId
                        || $0.uniqueIdentifier == scopedIdentifier
                }
            )
        }

        let preCleanupSnapshot = webExtensionStorageSnapshot(for: extensionId)

        guard matchingRecords.isEmpty == false else {
            finalizeWebExtensionStorageCleanup(for: extensionId, mode: mode)
            traceWebExtensionStoreLifecycle(
                phase: "cleanup-finished-no-controller-records",
                extensionId: extensionId
            )
            if RuntimeDiagnostics.isVerboseEnabled {
                extensionRuntimeTrace(
                    "No stored WebExtension data found for \(extensionId)"
                )
            }
            return
        }

        for (profileId, controller) in extensionControllersByProfile {
            let scopedIdentifier = "\(profileId.uuidString):\(extensionId)"
            let profileRecords = matchingRecords.filter {
                $0.uniqueIdentifier == extensionId
                    || $0.uniqueIdentifier == scopedIdentifier
            }
            guard profileRecords.isEmpty == false else { continue }
            await withCheckedContinuation { continuation in
                controller.removeData(
                    ofTypes: dataTypes,
                    from: profileRecords
                ) {
                    continuation.resume(returning: ())
                }
            }
        }

        let errors = matchingRecords.flatMap(\.errors)
        finalizeWebExtensionStorageCleanup(for: extensionId, mode: mode)
        let postCleanupSnapshot = webExtensionStorageSnapshot(for: extensionId)
        let classifiedErrors = classifyWebExtensionDataCleanupErrors(
            errors,
            for: extensionId,
            preCleanupSnapshot: preCleanupSnapshot,
            postCleanupSnapshot: postCleanupSnapshot
        )
        if RuntimeDiagnostics.isVerboseEnabled {
            if errors.isEmpty {
                extensionRuntimeTrace(
                    "Removed stored WebExtension data for \(extensionId)"
                )
            } else if classifiedErrors.actionableDiagnostics.isEmpty {
                extensionRuntimeTrace(
                    "Removed stored WebExtension data for \(extensionId); ignored \(classifiedErrors.benignOptionalStoreDiagnostics.count) missing optional store errors"
                )
            } else {
                extensionRuntimeTrace(
                    "Removed stored WebExtension data for \(extensionId) with \(classifiedErrors.actionableDiagnostics.count) actionable record errors"
                )
                let diagnosticsSummary = classifiedErrors.actionableDiagnostics.map(\.logSummary)
                    .joined(separator: " | ")
                extensionRuntimeTrace(
                    "Actionable WebExtension cleanup diagnostics for \(extensionId): \(diagnosticsSummary)"
                )
            }
        }
        traceWebExtensionStoreLifecycle(
            phase: "cleanup-finished",
            extensionId: extensionId
        )
    }

    private func finalizeWebExtensionStorageCleanup(
        for extensionId: String,
        mode: WebExtensionStorageCleanupMode
    ) {
        switch mode {
        case .pruneDirectoryIfPossible:
            _ = pruneEmptyOrStateOnlyWebExtensionStorageDirectory(for: extensionId)
        case .preserveDirectoryForImmediateRuntimeLoad:
            ensureWebExtensionStorageDirectoryExists(for: extensionId)
        }
    }

    func hasStoredWebExtensionDataCandidate(for extensionId: String) -> Bool {
        webExtensionStorageSnapshot(for: extensionId).entryNames.contains {
            $0 != "State.plist"
        }
    }

    @discardableResult
    func pruneEmptyOrStateOnlyWebExtensionStorageDirectory(for extensionId: String) -> Bool {
        guard let storageDirectory = webExtensionStorageDirectory(for: extensionId) else {
            return false
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        guard contents.allSatisfy(isPrunableWebExtensionStorageEntry) else {
            return false
        }

        do {
            try FileManager.default.removeItem(at: storageDirectory)
            return true
        } catch {
            Self.logger.debug(
                "Failed to prune empty WebExtension storage directory for \(extensionId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    func webExtensionStorageDirectory(
        for extensionId: String,
        profileId: UUID? = nil
    ) -> URL? {
        let resolvedProfileId =
            profileId ?? currentProfileId ?? browserManager?.currentProfile?.id
        guard let resolvedProfileId else { return nil }
        guard let libraryDirectory = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let controllerStorageId = extensionControllerIdentifier(for: resolvedProfileId)
        return libraryDirectory
            .appendingPathComponent("WebKit", isDirectory: true)
            .appendingPathComponent(SumiAppIdentity.runtimeBundleIdentifier, isDirectory: true)
            .appendingPathComponent("WebExtensions", isDirectory: true)
            .appendingPathComponent(controllerStorageId.uuidString.uppercased(), isDirectory: true)
            .appendingPathComponent(extensionId, isDirectory: true)
    }

    @discardableResult
    func ensureWebExtensionStorageDirectoryExists(
        for extensionId: String,
        profileId: UUID? = nil
    ) -> Bool {
        guard let storageDirectory = webExtensionStorageDirectory(
            for: extensionId,
            profileId: profileId
        ) else {
            return false
        }

        do {
            try FileManager.default.createDirectory(
                at: storageDirectory,
                withIntermediateDirectories: true
            )
            return true
        } catch {
            Self.logger.debug(
                "Failed to create WebExtension storage directory for \(extensionId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    func webExtensionStorageSnapshot(
        for extensionId: String
    ) -> WebExtensionStorageSnapshot {
        guard let storageDirectory = webExtensionStorageDirectory(for: extensionId) else {
            return WebExtensionStorageSnapshot(
                directoryExists: false,
                entryNames: [],
                hasRegisteredContentScriptsStore: false,
                hasLocalStorageStore: false,
                hasSyncStorageStore: false
            )
        }

        let directoryExists = FileManager.default.fileExists(atPath: storageDirectory.path)
        guard directoryExists else {
            return WebExtensionStorageSnapshot(
                directoryExists: false,
                entryNames: [],
                hasRegisteredContentScriptsStore: false,
                hasLocalStorageStore: false,
                hasSyncStorageStore: false
            )
        }

        let entryNames = ((try? FileManager.default.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []).map(\.lastPathComponent).sorted()

        return WebExtensionStorageSnapshot(
            directoryExists: true,
            entryNames: entryNames,
            hasRegisteredContentScriptsStore: entryNames.contains("RegisteredContentScripts.db"),
            hasLocalStorageStore: entryNames.contains("LocalStorage.db"),
            hasSyncStorageStore: entryNames.contains("SyncStorage.db")
        )
    }

    func webExtensionStoreCapabilitySnapshot(
        for manifest: [String: Any]
    ) -> WebExtensionStoreCapabilitySnapshot {
        let permissions = Set((manifest["permissions"] as? [String] ?? []).map {
            $0.lowercased()
        })
        let unsupportedAPIs = Self.webKitRuntimeUnsupportedAPIs(for: manifest).sorted()

        return WebExtensionStoreCapabilitySnapshot(
            usesWebKitCompatibilityPrelude: false,
            mayTouchDynamicContentScriptStore: permissions.contains("scripting"),
            mayTouchSyncStorageStore: permissions.contains("storage"),
            declaredPermissions: permissions.sorted(),
            unsupportedAPIs: unsupportedAPIs
        )
    }

    func classifyWebExtensionDataCleanupErrors(
        _ errors: [Error],
        for extensionId: String,
        preCleanupSnapshot: WebExtensionStorageSnapshot,
        postCleanupSnapshot: WebExtensionStorageSnapshot
    ) -> WebExtensionCleanupErrorClassification {
        let diagnostics = errors.map(makeWebExtensionCleanupErrorDiagnostic)
        let hasNonOptionalFailureSignals = diagnostics.contains { diagnostic in
            diagnostic.referencesOptionalStore == false
                && diagnostic.isGenericSQLiteStoreCreationFailure == false
                && diagnostic.isWebKitExtensionStorageComputationFailure == false
        }

        let benignOptionalStoreDiagnostics = diagnostics.filter { diagnostic in
            isBenignMissingOptionalWebExtensionStoreError(
                diagnostic,
                extensionId: extensionId,
                preCleanupSnapshot: preCleanupSnapshot,
                postCleanupSnapshot: postCleanupSnapshot,
                hasNonOptionalFailureSignals: hasNonOptionalFailureSignals
            )
        }
        let actionableDiagnostics = diagnostics.filter { diagnostic in
            benignOptionalStoreDiagnostics.contains(diagnostic) == false
        }

        return WebExtensionCleanupErrorClassification(
            benignOptionalStoreDiagnostics: benignOptionalStoreDiagnostics,
            actionableDiagnostics: actionableDiagnostics
        )
    }

    func traceWebExtensionStoreLifecycle(
        phase: String,
        extensionId: String,
        manifest: [String: Any]? = nil
    ) {
        guard Self.isWebKitRuntimeTraceEnabled else { return }
        let snapshot = webExtensionStorageSnapshot(for: extensionId)
        var message =
            "storeLifecycle phase=\(phase) extensionId=\(extensionId) directoryExists=\(snapshot.directoryExists) entries=\(snapshot.entryNames.joined(separator: ",")) registeredContentScripts=\(snapshot.hasRegisteredContentScriptsStore) localStorage=\(snapshot.hasLocalStorageStore) syncStorage=\(snapshot.hasSyncStorageStore) onlyPrunable=\(snapshot.hasOnlyPrunableEntries)"

        if let manifest {
            let capabilities = webExtensionStoreCapabilitySnapshot(for: manifest)
            message +=
                " webKitCompat=\(capabilities.usesWebKitCompatibilityPrelude) mayTouchDynamicContentScripts=\(capabilities.mayTouchDynamicContentScriptStore) mayTouchSyncStorage=\(capabilities.mayTouchSyncStorageStore) permissions=\(capabilities.declaredPermissions.joined(separator: ",")) unsupportedAPIs=\(capabilities.unsupportedAPIs.joined(separator: ","))"
        }

        extensionRuntimeTrace(message)
    }

    func makeWebExtensionCleanupErrorDiagnostic(
        _ error: Error,
    ) -> WebExtensionCleanupErrorDiagnostic {
        let nsError = error as NSError
        return WebExtensionCleanupErrorDiagnostic(
            domain: nsError.domain,
            code: nsError.code,
            localizedDescription: nsError.localizedDescription,
            localizedFailureReason: nsError.localizedFailureReason ?? "",
            debugDescription: String(describing: error),
            userInfoDescription: nsError.userInfo.description
        )
    }

    func isBenignMissingOptionalWebExtensionStoreError(
        _ diagnostic: WebExtensionCleanupErrorDiagnostic,
        extensionId: String,
        preCleanupSnapshot: WebExtensionStorageSnapshot,
        postCleanupSnapshot: WebExtensionStorageSnapshot,
        hasNonOptionalFailureSignals: Bool
    ) -> Bool {
        let extensionMatches = diagnostic.logSummary.lowercased().contains(extensionId.lowercased())
        let snapshotShowsOnlyOptionalStoreGap =
            preCleanupSnapshot.isMissingTrackedOptionalStoresOnly
            || postCleanupSnapshot.isMissingTrackedOptionalStoresOnly
        if diagnostic.referencesOptionalStore && diagnostic.mentionsMissingFile {
            return true
        }

        if diagnostic.isGenericSQLiteStoreCreationFailure,
           snapshotShowsOnlyOptionalStoreGap,
           hasNonOptionalFailureSignals == false,
           extensionMatches || diagnostic.referencesOptionalStore
        {
            return true
        }

        if diagnostic.isWebKitExtensionStorageComputationFailure,
           snapshotShowsOnlyOptionalStoreGap,
           hasNonOptionalFailureSignals == false
        {
            return true
        }

        return false
    }

    private func isPrunableWebExtensionStorageEntry(_ url: URL) -> Bool {
        url.lastPathComponent == "State.plist"
    }

    func configureContextIdentity(
        _ extensionContext: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID
    ) {
        let scopedIdentifier = "\(profileId.uuidString):\(extensionId)"
        extensionContext.uniqueIdentifier = scopedIdentifier
        let host =
            "ext-"
            + scopedIdentifier.utf8.map { String(format: "%02x", $0) }.joined()
        if let baseURL = URL(string: "webkit-extension://\(host)") {
            extensionContext.baseURL = baseURL
        }
    }

    func grantRequestedPermissions(
        to extensionContext: WKWebExtensionContext,
        webExtension: WKWebExtension,
        manifest: [String: Any]
    ) {
        let permissions = RuntimeDiagnostics.isRunningTests
            ? webExtension.requestedPermissions.union(webExtension.optionalPermissions)
            : webExtension.requestedPermissions

        for permission in permissions {
            if shouldDenyAutoGrantForWebKitRuntime(permission, manifest: manifest) {
                extensionContext.setPermissionStatus(.deniedExplicitly, for: permission)
                continue
            }
            extensionContext.setPermissionStatus(.grantedExplicitly, for: permission)
        }
    }

    func shouldDenyAutoGrantForWebKitRuntime(
        _ permission: WKWebExtension.Permission,
        manifest: [String: Any]
    ) -> Bool {
        guard Self.manifestDeclaresWebKitBrowserTarget(for: manifest) else {
            return false
        }

        return permission.rawValue == "scripting"
    }

    static func webKitRuntimeUnsupportedAPIs(
        for manifest: [String: Any]
    ) -> Set<String> {
        guard Self.manifestDeclaresWebKitBrowserTarget(for: manifest) else {
            return []
        }

        return [
            "browser.contentScripts.register",
            "browser.scripting.executeScript",
            "browser.scripting.insertCSS",
            "browser.scripting.registerContentScripts",
            "browser.tabs.executeScript",
            "browser.tabs.insertCSS",
        ]
    }

    func grantRequestedMatchPatterns(
        to extensionContext: WKWebExtensionContext,
        webExtension: WKWebExtension
    ) {
        let requiredMatchPatterns = webExtension.requestedPermissionMatchPatterns
            .union(webExtension.allRequestedMatchPatterns)
        let matchPatterns = RuntimeDiagnostics.isRunningTests
            ? requiredMatchPatterns.union(webExtension.optionalPermissionMatchPatterns)
            : requiredMatchPatterns

        for matchPattern in matchPatterns {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: matchPattern)
        }
    }

    /// Grants temporary host access for the active tab when the manifest declares `activeTab`.
    func grantActiveTabURLAccess(
        for extensionContext: WKWebExtensionContext,
        tab: Tab,
        manifest: [String: Any]
    ) {
        let url = tab.url
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            SafariExtensionAutofillFillDiagnostics.recordActiveTabPermission(
                granted: false,
                extensionId: extensionID(for: extensionContext),
                reason: "nonHTTPActiveTab"
            )
            return
        }

        let permissions = (manifest["permissions"] as? [String] ?? [])
            + (manifest["optional_permissions"] as? [String] ?? [])
        guard permissions.contains("activeTab") else {
            SafariExtensionAutofillFillDiagnostics.recordActiveTabPermission(
                granted: false,
                extensionId: extensionID(for: extensionContext),
                reason: "activeTabNotDeclared"
            )
            return
        }

        extensionContext.setPermissionStatus(.grantedExplicitly, for: url)
        SafariExtensionAutofillFillDiagnostics.recordActiveTabPermission(
            granted: true,
            extensionId: extensionID(for: extensionContext),
            reason: "activeTabGranted"
        )
    }

    func isGrantedPermissionStatus(
        _ status: WKWebExtensionContext.PermissionStatus
    ) -> Bool {
        status == .grantedExplicitly || status == .grantedImplicitly
    }

    func explicitlyGrantURLIfCoveredByGrantedMatchPattern(
        _ url: URL,
        in extensionContext: WKWebExtensionContext
    ) -> Bool {
        var grantedPatterns = Set(extensionContext.grantedPermissionMatchPatterns.keys)
        let declaredPatterns = extensionContext.webExtension
            .allRequestedMatchPatterns
            .union(extensionContext.webExtension.optionalPermissionMatchPatterns)

        for pattern in declaredPatterns where isGrantedPermissionStatus(
            extensionContext.permissionStatus(for: pattern)
        ) {
            grantedPatterns.insert(pattern)
        }

        guard let matchingPattern = grantedPatterns.first(where: { $0.matches(url) }) else {
            return false
        }

        extensionContext.setPermissionStatus(.grantedExplicitly, for: url)
        RuntimeDiagnostics.debug(category: "Extensions") {
            let host = url.host ?? url.scheme ?? "unknown"
            return "Auto-granted URL access for \(extensionContext.webExtension.displayName ?? extensionContext.uniqueIdentifier): host=\(host) via \(matchingPattern.string)"
        }
        return true
    }
}

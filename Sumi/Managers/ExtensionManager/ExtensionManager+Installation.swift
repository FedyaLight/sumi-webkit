//
//  ExtensionManager+Installation.swift
//  Sumi
//
//  Installation and runtime loading flows for Sumi's WebExtension runtime.
//

import Foundation
import SwiftData
import WebKit

@available(macOS 15.5, *)
extension ExtensionManager {
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
        let extensionRoot = try extensionResourcesRoot(
            sourceKind: sourceKind,
            packagePath: entity.packagePath,
            sourceBundlePath: entity.sourceBundlePath
        )
        let manifest = try ExtensionUtils.validateManifest(
            at: extensionRoot.appendingPathComponent("manifest.json"),
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
            let sourceKind = WebExtensionSourceKind(rawValue: entity.sourceKindRawValue) ?? .directory
            let packageURL = URL(fileURLWithPath: entity.packagePath, isDirectory: true)
            if sourceKind == .directory,
               FileManager.default.fileExists(atPath: packageURL.path)
            {
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

        let result = installationMetadataStore.loadInstalledExtensionMetadata {
            extensionRuntimeTrace($0)
        }
        return applyInstalledExtensionMetadataLoadResult(result)
    }

    @discardableResult
    func applyInstalledExtensionMetadataLoadResult(
        _ result: ExtensionInstallationMetadataStore.MetadataLoadResult
    ) -> [ExtensionEntity] {
        installedExtensions = result.records
        if result.didFetchPersistedMetadata {
            reconcilePinnedToolbarExtensions()
        }
        extensionsLoaded = true
        extensionRuntimeTrace(
            "loadInstalledExtensionMetadata complete records=\(result.records.count) enabled=\(result.enabledEntities.count)"
        )
        return result.enabledEntities
    }

    func loadEnabledExtension(
        from entity: ExtensionEntity,
        profileId: UUID? = nil,
        expectedLoadGeneration: UInt64? = nil,
        postLoadBackgroundWakeReason: ExtensionBackgroundWakeReason? = nil
    ) async throws -> InstalledExtension {
        let loadGeneration = expectedLoadGeneration ?? extensionLoadGeneration
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
            let sourceKind =
                WebExtensionSourceKind(rawValue: entity.sourceKindRawValue) ?? .directory
            let extensionRoot = try extensionResourcesRoot(
                sourceKind: sourceKind,
                packagePath: entity.packagePath,
                sourceBundlePath: entity.sourceBundlePath
            )
            let manifestURL = extensionRoot.appendingPathComponent("manifest.json")
            extensionRuntimeTrace(
                "loadEnabledExtension start extensionId=\(entity.id) profileId=\(resolvedProfileId.uuidString) expectedGeneration=\(loadGeneration) currentGeneration=\(extensionLoadGeneration) packagePath=\(extensionRoot.path)"
            )
            let validationStart = CFAbsoluteTimeGetCurrent()
            let manifest = try ExtensionUtils.validateManifest(
                at: manifestURL,
                policy: WebExtensionManifestValidationPolicy.forSourceKind(sourceKind)
            )
            recordRuntimeMetric(for: entity.id) {
                $0.manifestValidationDuration = CFAbsoluteTimeGetCurrent() - validationStart
            }
            _ = try await ExtensionRuntimeContextLoadOwner(manager: self).load(
                ExtensionRuntimeContextLoadOwner.Request(
                    extensionId: entity.id,
                    profileId: resolvedProfileId,
                    sourceKind: sourceKind,
                    sourceBundlePath: entity.sourceBundlePath,
                    packageRoot: extensionRoot,
                    manifest: manifest,
                    operation: .loadEnabled(expectedGeneration: loadGeneration)
                )
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

    @discardableResult
    func ensureBackgroundAvailableIfRequired(
        for webExtension: WKWebExtension,
        context extensionContext: WKWebExtensionContext,
        reason: ExtensionBackgroundWakeReason
    ) async throws -> Bool {
        let wakeKey = backgroundWakeKey(for: extensionContext)
        return try await backgroundRuntimeStateOwner.ensureBackgroundAvailableIfRequired(
            wakeKey: wakeKey,
            hasBackgroundContent: webExtension.hasBackgroundContent,
            reason: reason,
            trace: { extensionRuntimeTrace($0) },
            loadBackgroundContent: {
                #if DEBUG
                    if let backgroundContentWake = self.testHooks.backgroundContentWake {
                        try await backgroundContentWake(wakeKey, extensionContext)
                    } else {
                        try await extensionContext.loadBackgroundContent()
                    }
                #else
                    try await extensionContext.loadBackgroundContent()
                #endif
            },
            recordWakeMetric: { duration, reason, didFail in
                self.recordRuntimeMetric(for: wakeKey) {
                    $0.backgroundWakeDuration = duration
                    $0.backgroundWakeCount += 1
                    $0.lastBackgroundWakeReason = reason
                    $0.lastBackgroundWakeFailed = didFail
                }
            }
        )
    }

    func scheduleNativeMessagingBackgroundWake(
        for extensionContext: WKWebExtensionContext,
        operation: String
    ) {
        let wakeKey = backgroundWakeKey(for: extensionContext)
        guard nativeMessagingBackgroundWakeTasksByKey[wakeKey] == nil else { return }

        let token = UUID()
        let task = Self.detachedMainActorRuntimeTask { [weak self] in
            guard let self else { return }
            defer {
                if self.nativeMessagingBackgroundWakeTasksByKey[wakeKey]?.token == token {
                    self.nativeMessagingBackgroundWakeTasksByKey.removeValue(
                        forKey: wakeKey
                    )
                }
            }
            guard Task.isCancelled == false else { return }

            do {
                _ = try await self.ensureBackgroundAvailableIfRequired(
                    for: extensionContext.webExtension,
                    context: extensionContext,
                    reason: .nativeMessaging
                )
            } catch {
                self.logBackgroundWakeFailure(
                    error,
                    extensionContext: extensionContext,
                    reason: .nativeMessaging,
                    operation: operation
                )
            }
        }
        nativeMessagingBackgroundWakeTasksByKey[wakeKey] = (token, task)
    }

    func cancelNativeMessagingBackgroundWakeTasks(forExtensionId extensionId: String) {
        for (wakeKey, scheduledTask) in nativeMessagingBackgroundWakeTasksByKey {
            guard ExtensionRuntimeResidencyState.parseScopedKey(wakeKey)?.extensionId
                == extensionId
            else { continue }

            scheduledTask.task.cancel()
            nativeMessagingBackgroundWakeTasksByKey.removeValue(forKey: wakeKey)
        }
    }

    func cancelNativeMessagingBackgroundWakeTasks() {
        nativeMessagingBackgroundWakeTasksByKey.values.forEach { $0.task.cancel() }
        nativeMessagingBackgroundWakeTasksByKey.removeAll()
    }

    private func backgroundWakeKey(
        for extensionContext: WKWebExtensionContext
    ) -> String {
        if let identity = contextIdentity(for: extensionContext)
        {
            return backgroundScopedKey(
                extensionId: identity.extensionId,
                profileId: identity.profileId
            )
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
        let wakeKey = backgroundScopedKey(
            extensionId: extensionId,
            profileId: resolvedProfileId
        )
        return backgroundRuntimeStateOwner.state(for: wakeKey)
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

        let resolvedSource = try Self.resolveInstallSource(at: sourceURL)
        if resolvedSource.sourceKind == .safariAppExtension {
            return try await enableDiscoveredSafariAppExtension(
                resolvedSource,
                enableOnInstall: enableOnInstall
            )
        }

        let extensionsDirectory = ExtensionUtils.extensionsDirectory()
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
            try FileManager.default.copyItem(
                at: resolvedSource.resourcesURL,
                to: temporaryDirectory
            )

            let manifestPolicy = WebExtensionManifestValidationPolicy.forSourceKind(
                resolvedSource.sourceKind
            )
            let manifestURL = temporaryDirectory.appendingPathComponent("manifest.json")
            let manifest = try ExtensionUtils.validateManifest(
                at: manifestURL,
                policy: manifestPolicy
            )
            try validateMV3Requirements(manifest: manifest, baseURL: temporaryDirectory)

            let rawExtensionId: String
            let allEntities = try context.fetch(FetchDescriptor<ExtensionEntity>())
            if let existingEntity = allEntities.first(where: { $0.sourceBundlePath == resolvedSource.sourceBundlePath.path }) {
                rawExtensionId = existingEntity.id
            } else if let browserSpecificSettings = manifest["browser_specific_settings"] as? [String: Any],
                      let gecko = browserSpecificSettings["gecko"] as? [String: Any],
                      let geckoId = gecko["id"] as? String {
                rawExtensionId = geckoId
            } else {
                rawExtensionId = UUID().uuidString
            }
            let extensionId = try ExtensionUtils.validateExtensionIDPathComponent(
                rawExtensionId
            )

            installedExtensionID = extensionId

            let destinationDirectory = try ExtensionUtils.extensionDirectory(
                forExtensionID: extensionId,
                under: extensionsDirectory
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
                let extensionContext = try await ExtensionRuntimeContextLoadOwner(
                    manager: self
                ).load(
                    ExtensionRuntimeContextLoadOwner.Request(
                        extensionId: extensionId,
                        profileId: installProfileId,
                        sourceKind: resolvedSource.sourceKind,
                        sourceBundlePath: resolvedSource.sourceBundlePath.path,
                        packageRoot: destinationDirectory,
                        manifest: finalManifest,
                        operation: .install
                    )
                )

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
                do {
                    _ = try await loadEnabledExtension(from: existingEntitySnapshot)
                } catch let restoreError {
                    if let restoreProfileId = currentProfileId ?? browserManager?.currentProfile?.id {
                        logExtensionLoadFailure(
                            restoreError,
                            extensionId: existingEntitySnapshot.id,
                            profileId: restoreProfileId,
                            operation: "restore existing runtime after failed installation"
                        )
                    } else {
                        Self.logger.error(
                            "Failed to restore existing runtime after failed installation for extension \(existingEntitySnapshot.id, privacy: .public): \(restoreError.localizedDescription, privacy: .public)"
                        )
                    }
                }
            }

            throw error
        }
    }

    private func enableDiscoveredSafariAppExtension(
        _ resolvedSource: ResolvedInstallSource,
        enableOnInstall: Bool
    ) async throws -> InstalledExtension {
        guard resolvedSource.sourceKind == .safariAppExtension,
              let appexBundleURL = resolvedSource.appexBundleURL,
              let bundle = Bundle(url: appexBundleURL)
        else {
            throw ExtensionError.installationFailed(
                "Installed Safari app extension bundle is unavailable"
            )
        }

        let extensionRoot = resolvedSource.resourcesURL
        let manifestPolicy = WebExtensionManifestValidationPolicy.forSourceKind(
            resolvedSource.sourceKind
        )
        let manifestURL = extensionRoot.appendingPathComponent("manifest.json")
        let manifest = try ExtensionUtils.validateManifest(
            at: manifestURL,
            policy: manifestPolicy
        )
        try validateMV3Requirements(manifest: manifest, baseURL: extensionRoot)

        let allEntities = try context.fetch(FetchDescriptor<ExtensionEntity>())
        let existingEntityBySource = allEntities.first {
            URL(fileURLWithPath: $0.sourceBundlePath, isDirectory: true)
                .standardizedFileURL.path == resolvedSource.sourceBundlePath.standardizedFileURL.path
        }
        let rawExtensionId: String
        if let existingEntityBySource {
            rawExtensionId = existingEntityBySource.id
        } else if let bundleIdentifier = bundle.bundleIdentifier,
                  bundleIdentifier.isEmpty == false
        {
            rawExtensionId = bundleIdentifier
        } else if let browserSpecificSettings = manifest["browser_specific_settings"] as? [String: Any],
                  let gecko = browserSpecificSettings["gecko"] as? [String: Any],
                  let geckoId = gecko["id"] as? String
        {
            rawExtensionId = geckoId
        } else {
            rawExtensionId = UUID().uuidString
        }
        let extensionId = try ExtensionUtils.validateExtensionIDPathComponent(
            rawExtensionId
        )

        let existingEntitySnapshot: ExtensionEntity?
        if let existingEntityBySource {
            existingEntitySnapshot = existingEntityBySource
        } else {
            existingEntitySnapshot = try extensionEntity(for: extensionId)
        }
        let shouldRestoreExistingRuntime = existingEntitySnapshot?.isEnabled == true

        do {
            if let existingEntitySnapshot {
                tearDownExtensionRuntimeState(
                    for: existingEntitySnapshot.id,
                    removeUIState: false
                )
            } else if hasStoredWebExtensionDataCandidate(for: extensionId) {
                traceWebExtensionStoreLifecycle(
                    phase: "before-safari-enable-cleanup",
                    extensionId: extensionId,
                    manifest: manifest
                )
                await removeStoredWebExtensionData(
                    for: extensionId,
                    mode: .preserveDirectoryForImmediateRuntimeLoad
                )
                traceWebExtensionStoreLifecycle(
                    phase: "after-safari-enable-cleanup",
                    extensionId: extensionId,
                    manifest: manifest
                )
            }

            let record = try makeInstalledRecord(
                extensionId: extensionId,
                manifest: manifest,
                extensionRoot: extensionRoot,
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
                let extensionContext = try await ExtensionRuntimeContextLoadOwner(
                    manager: self
                ).load(
                    ExtensionRuntimeContextLoadOwner.Request(
                        extensionId: extensionId,
                        profileId: installProfileId,
                        sourceKind: resolvedSource.sourceKind,
                        sourceBundlePath: resolvedSource.sourceBundlePath.path,
                        packageRoot: extensionRoot,
                        manifest: manifest,
                        operation: .safariEnable
                    )
                )

                tabOpenNotificationGeneration &+= 1
                updateWebViewsForProfile(
                    installProfileId,
                    allowWhenExtensionsNotLoaded: true
                )
                resyncOpenTabsWithExtensionRuntimeAfterGenerationBump(
                    reason: "ExtensionManager.enableSafariAppExtension.afterLoad",
                    allowWhenExtensionsNotLoaded: true
                )
                registerExistingWindowStateIfAttached()

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
                        "Failed to wake background worker after Safari extension enable for \(installedDisplayName, privacy: .public): \(error.localizedDescription, privacy: .public)"
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

            return record
        } catch {
            tearDownExtensionRuntimeState(
                for: existingEntitySnapshot?.id ?? extensionId,
                removeUIState: false
            )
            if shouldRestoreExistingRuntime, let existingEntitySnapshot {
                do {
                    _ = try await loadEnabledExtension(from: existingEntitySnapshot)
                } catch let restoreError {
                    if let restoreProfileId = currentProfileId ?? browserManager?.currentProfile?.id {
                        logExtensionLoadFailure(
                            restoreError,
                            extensionId: existingEntitySnapshot.id,
                            profileId: restoreProfileId,
                            operation: "restore existing runtime after failed Safari extension enable"
                        )
                    } else {
                        Self.logger.error(
                            "Failed to restore existing runtime after failed Safari extension enable for extension \(existingEntitySnapshot.id, privacy: .public): \(restoreError.localizedDescription, privacy: .public)"
                        )
                    }
                }
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

        let dataCleanupOwner = WebExtensionControllerDataCleanupOwner()
        let matchingRecords = await dataCleanupOwner.matchingRecords(
            for: extensionId,
            controllersByProfile: extensionControllersByProfile
        )

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

        await dataCleanupOwner.remove(
            matchingRecords,
            extensionId: extensionId,
            using: extensionControllersByProfile
        )

        let errors = matchingRecords.errors
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

    private func webExtensionStorageCleanupStore(
        profileId: UUID? = nil
    ) -> WebExtensionStorageCleanupStore {
        let resolvedProfileId =
            profileId ?? currentProfileId ?? browserManager?.currentProfile?.id
        let controllerStorageId = resolvedProfileId.map {
            extensionControllerIdentifier(for: $0)
        }
        return WebExtensionStorageCleanupStore(controllerStorageId: controllerStorageId)
    }

    func hasStoredWebExtensionDataCandidate(for extensionId: String) -> Bool {
        webExtensionStorageCleanupStore().hasStoredDataCandidate(for: extensionId)
    }

    @discardableResult
    func pruneEmptyOrStateOnlyWebExtensionStorageDirectory(for extensionId: String) -> Bool {
        webExtensionStorageCleanupStore()
            .pruneEmptyOrStateOnlyDirectory(for: extensionId)
    }

    func webExtensionStorageDirectory(
        for extensionId: String,
        profileId: UUID? = nil
    ) -> URL? {
        webExtensionStorageCleanupStore(profileId: profileId)
            .directory(for: extensionId)
    }

    @discardableResult
    func ensureWebExtensionStorageDirectoryExists(
        for extensionId: String,
        profileId: UUID? = nil
    ) -> Bool {
        webExtensionStorageCleanupStore(profileId: profileId)
            .ensureDirectoryExists(for: extensionId)
    }

    func webExtensionStorageSnapshot(
        for extensionId: String
    ) -> WebExtensionStorageSnapshot {
        webExtensionStorageCleanupStore().snapshot(for: extensionId)
    }

    func webExtensionStoreCapabilitySnapshot(
        for manifest: [String: Any]
    ) -> WebExtensionStoreCapabilitySnapshot {
        installCapabilityOwner.webExtensionStoreCapabilitySnapshot(for: manifest)
    }

    func classifyWebExtensionDataCleanupErrors(
        _ errors: [Error],
        for extensionId: String,
        preCleanupSnapshot: WebExtensionStorageSnapshot,
        postCleanupSnapshot: WebExtensionStorageSnapshot
    ) -> WebExtensionCleanupErrorClassification {
        WebExtensionStorageCleanupPlanner.shared.classifyCleanupErrors(
            errors,
            extensionId: extensionId,
            preCleanupSnapshot: preCleanupSnapshot,
            postCleanupSnapshot: postCleanupSnapshot
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
        WebExtensionStorageCleanupPlanner.shared.makeErrorDiagnostic(error)
    }

    func isBenignMissingOptionalWebExtensionStoreError(
        _ diagnostic: WebExtensionCleanupErrorDiagnostic,
        extensionId: String,
        preCleanupSnapshot: WebExtensionStorageSnapshot,
        postCleanupSnapshot: WebExtensionStorageSnapshot,
        hasNonOptionalFailureSignals: Bool
    ) -> Bool {
        WebExtensionStorageCleanupPlanner.shared.isBenignMissingOptionalStoreError(
            diagnostic,
            extensionId: extensionId,
            preCleanupSnapshot: preCleanupSnapshot,
            postCleanupSnapshot: postCleanupSnapshot,
            hasNonOptionalFailureSignals: hasNonOptionalFailureSignals
        )
    }

    func configureContextIdentity(
        _ extensionContext: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID
    ) {
        ExtensionRuntimeContextLoadOwner.configureContextIdentity(
            extensionContext,
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func grantRequestedPermissions(
        to extensionContext: WKWebExtensionContext,
        webExtension: WKWebExtension,
        extensionId: String? = nil,
        profileId: UUID? = nil,
        manifest: [String: Any]
    ) {
        installCapabilityOwner.grantRequestedPermissions(
            to: extensionContext,
            webExtension: webExtension,
            extensionId: extensionId,
            profileId: profileId,
            manifest: manifest
        )
    }

    static func manifestDeclaresNativeMessaging(_ manifest: [String: Any]) -> Bool {
        SafariExtensionInstallCapabilityOwner.manifestDeclaresNativeMessaging(manifest)
    }

    func shouldDenyAutoGrantForWebKitRuntime(
        _ permission: WKWebExtension.Permission,
        manifest: [String: Any]
    ) -> Bool {
        installCapabilityOwner.shouldDenyAutoGrantForWebKitRuntime(
            permission,
            manifest: manifest
        )
    }

    static func webKitRuntimeUnsupportedAPIs(
        for manifest: [String: Any]
    ) -> Set<String> {
        SafariExtensionInstallCapabilityOwner.webKitRuntimeUnsupportedAPIs(
            for: manifest
        )
    }

    func grantRequestedMatchPatterns(
        to extensionContext: WKWebExtensionContext,
        webExtension: WKWebExtension
    ) {
        guard let extensionId = extensionID(for: extensionContext),
              let profileId = profileId(for: extensionContext)
        else { return }
        let manifest = loadedExtensionManifests[extensionId]
            ?? installedExtensions.first { $0.id == extensionId }?.manifest
        applyConfiguredSiteAccessPolicy(
            to: extensionContext,
            extensionId: extensionId,
            profileId: profileId,
            webExtension: webExtension,
            manifest: manifest
        )
    }

    /// Grants temporary host access for the active tab when the manifest declares `activeTab`.
    func grantActiveTabURLAccess(
        for extensionContext: WKWebExtensionContext,
        tab: Tab,
        manifest: [String: Any]
    ) {
        installCapabilityOwner.grantActiveTabURLAccess(
            for: extensionContext,
            tab: tab,
            manifest: manifest,
            extensionId: extensionID(for: extensionContext),
            profileId: profileId(for: extensionContext)
        )
    }

    func isGrantedPermissionStatus(
        _ status: WKWebExtensionContext.PermissionStatus
    ) -> Bool {
        installCapabilityOwner.isGrantedPermissionStatus(status)
    }

    func effectivePermissionStatus(
        for permission: WKWebExtension.Permission,
        in extensionContext: WKWebExtensionContext,
        tab: (any WKWebExtensionTab)?
    ) -> WKWebExtensionContext.PermissionStatus {
        installCapabilityOwner.effectivePermissionStatus(
            for: permission,
            in: extensionContext,
            tab: tab
        )
    }

    func effectivePermissionStatus(
        for matchPattern: WKWebExtension.MatchPattern,
        in extensionContext: WKWebExtensionContext,
        tab: (any WKWebExtensionTab)?
    ) -> WKWebExtensionContext.PermissionStatus {
        installCapabilityOwner.effectivePermissionStatus(
            for: matchPattern,
            in: extensionContext,
            tab: tab
        )
    }

    func effectivePermissionStatus(
        for url: URL,
        in extensionContext: WKWebExtensionContext,
        tab: (any WKWebExtensionTab)?
    ) -> WKWebExtensionContext.PermissionStatus {
        installCapabilityOwner.effectivePermissionStatus(
            for: url,
            in: extensionContext,
            tab: tab
        )
    }

    func explicitlyGrantURLIfCoveredByGrantedMatchPattern(
        _ url: URL,
        in extensionContext: WKWebExtensionContext,
        tab: (any WKWebExtensionTab)? = nil
    ) -> Bool {
        installCapabilityOwner.explicitlyGrantURLIfCoveredByGrantedMatchPattern(
            url,
            in: extensionContext,
            tab: tab
        )
    }
}

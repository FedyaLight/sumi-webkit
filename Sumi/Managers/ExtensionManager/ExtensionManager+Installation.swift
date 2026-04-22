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
        let usesSafariCompatibilityPrelude: Bool
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
        let preCleanupSnapshot: WebExtensionStorageSnapshot
        let postCleanupSnapshot: WebExtensionStorageSnapshot
        let benignOptionalStoreDiagnostics: [WebExtensionCleanupErrorDiagnostic]
        let actionableDiagnostics: [WebExtensionCleanupErrorDiagnostic]
    }

    func discoverSafariExtensions() async -> [SafariExtensionInfo] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fileManager = FileManager.default
                let searchDirectories: [URL] = [
                    URL(fileURLWithPath: "/Applications", isDirectory: true),
                    fileManager.homeDirectoryForCurrentUser
                        .appendingPathComponent("Applications", isDirectory: true),
                ]

                var results: [SafariExtensionInfo] = []

                for directory in searchDirectories {
                    guard let appURLs = try? fileManager.contentsOfDirectory(
                        at: directory,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    ) else {
                        continue
                    }

                    for appURL in appURLs where appURL.pathExtension.lowercased() == "app" {
                        let pluginsDirectory = appURL.appendingPathComponent("Contents/PlugIns", isDirectory: true)
                        guard let appexURLs = try? fileManager.contentsOfDirectory(
                            at: pluginsDirectory,
                            includingPropertiesForKeys: nil,
                            options: [.skipsHiddenFiles]
                        ) else {
                            continue
                        }

                        for appexURL in appexURLs where appexURL.pathExtension.lowercased() == "appex" {
                            guard
                                Self.isSafariWebExtensionBundle(appexURL),
                                let resourcesURL = try? Self.resolveSafariResources(in: appexURL)
                            else {
                                continue
                            }

                            let manifestURL = resourcesURL.appendingPathComponent("manifest.json")
                            guard
                                let manifest = try? ExtensionUtils.validateManifest(at: manifestURL)
                            else {
                                continue
                            }

                            let bundleID = Bundle(url: appexURL)?.bundleIdentifier
                                ?? appexURL.deletingPathExtension().lastPathComponent
                            let displayName = ExtensionUtils.localizedString(
                                manifest["name"] as? String,
                                in: resourcesURL
                            ) ?? (manifest["name"] as? String) ?? appURL.deletingPathExtension().lastPathComponent

                            results.append(
                                SafariExtensionInfo(
                                    id: bundleID,
                                    name: displayName,
                                    appPath: appURL,
                                    appexPath: appexURL,
                                    resourcesPath: resourcesURL
                                )
                            )
                        }
                    }
                }

                let deduplicated = Dictionary(
                    results.map { ($0.appexPath.path, $0) },
                    uniquingKeysWith: { lhs, _ in lhs }
                ).values.sorted { lhs, rhs in
                    lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }

                continuation.resume(returning: Array(deduplicated))
            }
        }
    }

    func installSafariExtension(
        _ info: SafariExtensionInfo,
        completionHandler: @escaping (Result<InstalledExtension, ExtensionError>) -> Void
    ) {
        installExtension(from: info.appexPath, completionHandler: completionHandler)
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
        let manifest = try ExtensionUtils.validateManifest(
            at: URL(fileURLWithPath: entity.packagePath).appendingPathComponent("manifest.json")
        )
        let refreshed = try refreshedRecord(for: entity, manifest: manifest)
        await applyInstalledExtensionsMutationOnNextRunLoop { manager in
            manager.upsertInstalledExtension(refreshed)
        }
        loadInstalledExtensionMetadata()
        _ = await requestExtensionRuntimeAndWait(
            reason: .enable,
            allowWithoutEnabledExtensions: true
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
                teamID: current.teamID,
                appBundleID: current.appBundleID,
                appexBundleID: current.appexBundleID,
                optionsPagePath: current.optionsPagePath,
                defaultPopupPath: current.defaultPopupPath,
                hasBackground: current.hasBackground,
                hasAction: current.hasAction,
                hasOptionsPage: current.hasOptionsPage,
                hasContentScripts: current.hasContentScripts,
                hasExtensionPages: current.hasExtensionPages,
                trustSummary: current.trustSummary,
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

    func loadInstalledExtensions() {
        let signpostState = PerformanceTrace.beginInterval("ExtensionManager.loadInstalledExtensions")
        defer {
            PerformanceTrace.endInterval(
                "ExtensionManager.loadInstalledExtensions",
                signpostState
            )
        }

        loadInstalledExtensionMetadata()

        if hasEnabledInstalledExtensions {
            requestExtensionRuntime(reason: .refresh, forceReload: true)
        } else {
            tearDownExtensionRuntime(
                reason: "loadInstalledExtensions.noEnabledExtensions",
                removeUIState: false,
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
            guard FileManager.default.fileExists(atPath: packageURL.path),
                  let record = InstalledExtensionRecord(from: entity)
            else {
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
        expectedLoadGeneration: UInt64? = nil
    ) async throws -> InstalledExtension {
        let signpostState = PerformanceTrace.beginInterval("ExtensionManager.loadEnabledExtension")
        defer {
            PerformanceTrace.endInterval("ExtensionManager.loadEnabledExtension", signpostState)
        }

        do {
            guard let extensionController else {
                throw ExtensionError.installationFailed(
                    "Extension runtime controller is unavailable"
                )
            }

            let extensionRoot = URL(fileURLWithPath: entity.packagePath)
            let manifestURL = extensionRoot.appendingPathComponent("manifest.json")
            extensionRuntimeTrace(
                "loadEnabledExtension start extensionId=\(entity.id) expectedGeneration=\(expectedLoadGeneration.map(String.init) ?? "nil") currentGeneration=\(extensionLoadGeneration) packagePath=\(entity.packagePath)"
            )
            let patchStart = CFAbsoluteTimeGetCurrent()
            patchManifestForWebKit(at: manifestURL)
            recordRuntimeMetric(for: entity.id) {
                $0.manifestPatchDuration = CFAbsoluteTimeGetCurrent() - patchStart
            }

            let validationStart = CFAbsoluteTimeGetCurrent()
            let manifest = try ExtensionUtils.validateManifest(at: manifestURL)
            recordRuntimeMetric(for: entity.id) {
                $0.manifestValidationDuration = CFAbsoluteTimeGetCurrent() - validationStart
            }

            let webExtensionStart = CFAbsoluteTimeGetCurrent()
            let webExtension = try await WKWebExtension(resourceBaseURL: extensionRoot)
            recordRuntimeMetric(for: entity.id) {
                $0.webExtensionCreationDuration =
                    CFAbsoluteTimeGetCurrent() - webExtensionStart
            }
            try validateExpectedExtensionLoadGeneration(expectedLoadGeneration)
            let extensionContext = WKWebExtensionContext(for: webExtension)
            configureContextIdentity(extensionContext, extensionId: entity.id)
            grantRequestedPermissions(
                to: extensionContext,
                webExtension: webExtension,
                manifest: manifest
            )
            grantRequestedMatchPatterns(to: extensionContext, webExtension: webExtension)
            extensionContext.isInspectable = RuntimeDiagnostics.isDeveloperInspectionEnabled
            observeExtensionErrors(for: extensionContext, extensionId: entity.id)
            prepareExtensionContextForRuntime(
                extensionContext,
                extensionId: entity.id,
                manifest: manifest
            )
            ensureWebExtensionStorageDirectoryExists(for: entity.id)
            traceWebExtensionStoreLifecycle(
                phase: "before-loadEnabledExtension-controller-load",
                extensionId: entity.id,
                manifest: manifest
            )

            extensionContexts[entity.id] = extensionContext
            loadedExtensionManifests[entity.id] = manifest
            setupExternallyConnectableBridge(
                extensionId: entity.id,
                packagePath: entity.packagePath
            )

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

            let refreshed = try refreshedRecord(for: entity, manifest: manifest)
            await applyInstalledExtensionsMutationOnNextRunLoop { manager in
                manager.upsertInstalledExtension(refreshed)
            }
            update(entity, from: refreshed)
            try context.save()
            return refreshed
        } catch {
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
        guard webExtension.hasBackgroundContent else { return false }
        let wakeKey = backgroundWakeKey(for: extensionContext)

        switch backgroundRuntimeState(for: wakeKey) {
        case .loaded:
            Self.logger.debug(
                "Skipping required background wake for \(wakeKey, privacy: .public): already loaded"
            )
            return false
        case .wakeInFlight:
            if let existingTask = backgroundWakeTasks[wakeKey] {
                Self.logger.debug(
                    "Awaiting required background wake already in flight for \(wakeKey, privacy: .public)"
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

    func startBackgroundContentDefensively(
        for webExtension: WKWebExtension,
        context extensionContext: WKWebExtensionContext,
        reason: ExtensionBackgroundWakeReason,
        successMessage: String,
        failureMessage: String
    ) {
        guard webExtension.hasBackgroundContent else { return }
        let wakeKey = backgroundWakeKey(for: extensionContext)

        switch backgroundRuntimeState(for: wakeKey) {
        case .loaded:
            Self.logger.debug(
                "Skipping defensive background wake for \(wakeKey, privacy: .public): already loaded"
            )
            return
        case .wakeInFlight:
            Self.logger.debug(
                "Skipping defensive background wake for \(wakeKey, privacy: .public): wake already in flight"
            )
            return
        case .neverLoaded, .loadFailed:
            break
        }

        let wakeTask = startBackgroundWakeTask(
            wakeKey: wakeKey,
            extensionContext: extensionContext,
            reason: reason,
            mode: "defensive"
        )

        Task { @MainActor in
            do {
                try await wakeTask.value
                Self.logger.debug("\(successMessage, privacy: .public)")
            } catch {
                Self.logger.error(
                    "\(failureMessage, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
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
        Self.logger.debug(
            "Starting \(mode, privacy: .public) background wake for \(wakeKey, privacy: .public) reason=\(reason.rawValue, privacy: .public)"
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
        extensionID(for: extensionContext)
            ?? "context:\(ObjectIdentifier(extensionContext))"
    }

    func backgroundRuntimeState(
        for extensionId: String
    ) -> BackgroundRuntimeState {
        backgroundRuntimeStateByExtensionID[extensionId] ?? .neverLoaded
    }

    private func setBackgroundRuntimeState(
        _ state: BackgroundRuntimeState,
        for extensionId: String
    ) {
        if state == .neverLoaded {
            backgroundRuntimeStateByExtensionID.removeValue(forKey: extensionId)
        } else {
            backgroundRuntimeStateByExtensionID[extensionId] = state
        }
    }

    func performInstallation(
        from sourceURL: URL
    ) async throws -> InstalledExtension {
        _ = await requestExtensionRuntimeAndWait(
            reason: .install,
            allowWithoutEnabledExtensions: true
        )

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
            try FileManager.default.copyItem(
                at: resolvedSource.resourcesURL,
                to: temporaryDirectory
            )

            let manifestURL = temporaryDirectory.appendingPathComponent("manifest.json")
            let manifest = try ExtensionUtils.validateManifest(at: manifestURL)
            try validateMV3Requirements(manifest: manifest, baseURL: temporaryDirectory)
            patchManifestForWebKit(at: manifestURL)

            let extensionId: String
            let allEntities = try context.fetch(FetchDescriptor<ExtensionEntity>())
            if let existingEntity = allEntities.first(where: { $0.sourceBundlePath == resolvedSource.sourceBundlePath.path }) {
                extensionId = existingEntity.id
            } else if let appexId = resolvedSource.appexBundleID {
                extensionId = appexId
            } else if let appBundleID = resolvedSource.appBundleID {
                extensionId = appBundleID
            } else if let browserSpecificSettings = manifest["browser_specific_settings"] as? [String: Any],
                      let safari = browserSpecificSettings["safari"] as? [String: Any],
                      let safariId = safari["id"] as? String {
                extensionId = safariId
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
                    Self.logger.debug(
                        "Skipped WebExtension data cleanup for \(extensionId, privacy: .public): no stored data candidate (fresh install path)"
                    )
                }
            }

            try FileManager.default.moveItem(at: temporaryDirectory, to: destinationDirectory)

            let finalManifestURL = destinationDirectory.appendingPathComponent("manifest.json")
            let finalManifest = try ExtensionUtils.validateManifest(at: finalManifestURL)

            let webExtension = try await WKWebExtension(resourceBaseURL: destinationDirectory)
            let extensionContext = WKWebExtensionContext(for: webExtension)
            configureContextIdentity(extensionContext, extensionId: extensionId)
            grantRequestedPermissions(
                to: extensionContext,
                webExtension: webExtension,
                manifest: finalManifest
            )
            grantRequestedMatchPatterns(to: extensionContext, webExtension: webExtension)
            extensionContext.isInspectable = RuntimeDiagnostics.isDeveloperInspectionEnabled
            observeExtensionErrors(for: extensionContext, extensionId: extensionId)
            prepareExtensionContextForRuntime(
                extensionContext,
                extensionId: extensionId,
                manifest: finalManifest
            )
            ensureWebExtensionStorageDirectoryExists(for: extensionId)
            traceWebExtensionStoreLifecycle(
                phase: "before-install-controller-load",
                extensionId: extensionId,
                manifest: finalManifest
            )

            let record = try makeInstalledRecord(
                extensionId: extensionId,
                manifest: finalManifest,
                extensionRoot: destinationDirectory,
                isEnabled: true,
                sourceKind: resolvedSource.sourceKind,
                sourceBundlePath: resolvedSource.sourceBundlePath.path,
                sourceFingerprintURL: resolvedSource.sourceFingerprintURL,
                appBundleID: resolvedSource.appBundleID,
                appexBundleID: resolvedSource.appexBundleID,
                existingEntity: existingEntitySnapshot
            )

            extensionContexts[extensionId] = extensionContext
            loadedExtensionManifests[extensionId] = finalManifest
            setupExternallyConnectableBridge(
                extensionId: extensionId,
                packagePath: destinationDirectory.path
            )

            do {
                #if DEBUG
                    try testHooks.beforeControllerLoad?(
                        extensionId,
                        webExtensionStorageSnapshot(for: extensionId)
                    )
                #endif
                guard let extensionController else {
                    throw ExtensionError.installationFailed(
                        "Extension runtime controller is unavailable"
                    )
                }
                try extensionController.load(extensionContext)
            } catch {
                tearDownExtensionRuntimeState(for: extensionId, removeUIState: false)
                throw error
            }

            // New contexts must see existing windows even before `loadInstalledExtensions` sets
            // `extensionsLoaded`, or MV3 onboarding (`tabs.create`) may not run reliably.
            tabOpenNotificationGeneration &+= 1
            resyncOpenTabsWithExtensionRuntimeAfterGenerationBump(
                reason: "ExtensionManager.performInstallation.afterLoad",
                allowWhenExtensionsNotLoaded: true
            )
            registerExistingWindowStateIfAttached()

            #if DEBUG
                try testHooks.beforePersistInstalledRecord?(record)
            #endif
            try persist(record: record)
            await applyInstalledExtensionsMutationOnNextRunLoop { manager in
                manager.upsertInstalledExtension(record)
            }

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
                Self.logger.debug(
                    "Skipped WebExtension data cleanup for \(extensionId, privacy: .public): no stored data candidate"
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

        guard let extensionController else {
            Self.logger.debug(
                "Skipped WebExtension data cleanup for \(extensionId, privacy: .public): no controller"
            )
            return
        }

        let dataTypes = WKWebExtensionController.allExtensionDataTypes
        let dataRecords = await withCheckedContinuation { continuation in
            extensionController.fetchDataRecords(ofTypes: dataTypes) { records in
                continuation.resume(returning: records)
            }
        }
        let matchingRecords = dataRecords.filter {
            $0.uniqueIdentifier == extensionId
        }
        let preCleanupSnapshot = webExtensionStorageSnapshot(for: extensionId)

        guard matchingRecords.isEmpty == false else {
            finalizeWebExtensionStorageCleanup(for: extensionId, mode: mode)
            traceWebExtensionStoreLifecycle(
                phase: "cleanup-finished-no-controller-records",
                extensionId: extensionId
            )
            if RuntimeDiagnostics.isVerboseEnabled {
                Self.logger.debug(
                    "No stored WebExtension data found for \(extensionId, privacy: .public)"
                )
            }
            return
        }

        await withCheckedContinuation { continuation in
            extensionController.removeData(
                ofTypes: dataTypes,
                from: matchingRecords
            ) {
                continuation.resume(returning: ())
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
        if errors.isEmpty {
            Self.logger.debug(
                "Removed stored WebExtension data for \(extensionId, privacy: .public)"
            )
        } else if classifiedErrors.actionableDiagnostics.isEmpty {
            Self.logger.debug(
                "Removed stored WebExtension data for \(extensionId, privacy: .public); ignored \(classifiedErrors.benignOptionalStoreDiagnostics.count, privacy: .public) missing optional store errors"
            )
        } else {
            Self.logger.debug(
                "Removed stored WebExtension data for \(extensionId, privacy: .public) with \(classifiedErrors.actionableDiagnostics.count, privacy: .public) actionable record errors"
            )
            let diagnosticsSummary = classifiedErrors.actionableDiagnostics.map(\.logSummary)
                .joined(separator: " | ")
            Self.logger.debug(
                "Actionable WebExtension cleanup diagnostics for \(extensionId, privacy: .public): \(diagnosticsSummary, privacy: .public)"
            )
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

    func webExtensionStorageDirectory(for extensionId: String) -> URL? {
        guard let libraryDirectory = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        return libraryDirectory
            .appendingPathComponent("WebKit", isDirectory: true)
            .appendingPathComponent(SumiAppIdentity.runtimeBundleIdentifier, isDirectory: true)
            .appendingPathComponent("WebExtensions", isDirectory: true)
            .appendingPathComponent(controllerIdentifier.uuidString.uppercased(), isDirectory: true)
            .appendingPathComponent(extensionId, isDirectory: true)
    }

    @discardableResult
    func ensureWebExtensionStorageDirectoryExists(for extensionId: String) -> Bool {
        guard let storageDirectory = webExtensionStorageDirectory(for: extensionId) else {
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
        let unsupportedAPIs = Self.safariOnlyRuntimeUnsupportedAPIs(for: manifest).sorted()

        return WebExtensionStoreCapabilitySnapshot(
            usesSafariCompatibilityPrelude: Self.shouldInstallWebKitRuntimeCompatibilityPrelude(
                for: manifest
            ),
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
            preCleanupSnapshot: preCleanupSnapshot,
            postCleanupSnapshot: postCleanupSnapshot,
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
                " safariCompat=\(capabilities.usesSafariCompatibilityPrelude) mayTouchDynamicContentScripts=\(capabilities.mayTouchDynamicContentScriptStore) mayTouchSyncStorage=\(capabilities.mayTouchSyncStorageStore) permissions=\(capabilities.declaredPermissions.joined(separator: ",")) unsupportedAPIs=\(capabilities.unsupportedAPIs.joined(separator: ","))"
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
        extensionId: String
    ) {
        extensionContext.uniqueIdentifier = extensionId
        let host = "ext-" + extensionId.utf8.map { String(format: "%02x", $0) }.joined()
        if let baseURL = URL(string: "webkit-extension://\(host)") {
            extensionContext.baseURL = baseURL
        }
    }

    func grantRequestedPermissions(
        to extensionContext: WKWebExtensionContext,
        webExtension: WKWebExtension,
        manifest: [String: Any]
    ) {
        for permission in webExtension.requestedPermissions.union(
            webExtension.optionalPermissions
        ) {
            if shouldDenyAutoGrantForSafariOnlyRuntime(permission, manifest: manifest) {
                extensionContext.setPermissionStatus(.deniedExplicitly, for: permission)
                continue
            }
            extensionContext.setPermissionStatus(.grantedExplicitly, for: permission)
        }
    }

    func shouldDenyAutoGrantForSafariOnlyRuntime(
        _ permission: WKWebExtension.Permission,
        manifest: [String: Any]
    ) -> Bool {
        guard Self.shouldInstallWebKitRuntimeCompatibilityPrelude(for: manifest) else {
            return false
        }

        return permission.rawValue == "scripting"
    }

    static func safariOnlyRuntimeUnsupportedAPIs(
        for manifest: [String: Any]
    ) -> Set<String> {
        guard shouldInstallWebKitRuntimeCompatibilityPrelude(for: manifest) else {
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
        for matchPattern in webExtension.allRequestedMatchPatterns.union(
            webExtension.optionalPermissionMatchPatterns
        ) {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: matchPattern)
        }
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
        Self.logger.debug(
            "Auto-granted URL access for \(extensionContext.webExtension.displayName ?? extensionContext.uniqueIdentifier, privacy: .public): \(url.absoluteString, privacy: .private(mask: .hash)) via \(matchingPattern.string, privacy: .public)"
        )
        return true
    }
}

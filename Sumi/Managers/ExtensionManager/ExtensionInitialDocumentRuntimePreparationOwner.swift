import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionInitialDocumentRuntimePreparationOwner {
    private weak var manager: ExtensionManager?

    private var contentScriptContextLoadTasksByProfile: [UUID: Task<Void, Never>] = [:]
    private var nativeMessagingWarmupTasksByProfile:
        [UUID: (token: UUID, task: Task<Void, Never>)] = [:]
    private var retiredNativeMessagingWarmupTaskTokens = Set<UUID>()
    private var finishedUnregisteredNativeMessagingWarmupTaskTokens = Set<UUID>()
    private var deferredTabNotificationTasksByTabID:
        [UUID: (token: UUID, task: Task<Void, Never>)] = [:]

    init(manager: ExtensionManager) {
        self.manager = manager
    }

    func profileHasLoadedContentScriptContexts(profileId: UUID) -> Bool {
        guard let manager else { return true }
        guard manager.extensionsModuleEnabledForRuntimeBoundary() else { return true }

        let contentScriptEntities = manager.enabledPersistedExtensionEntities().filter {
            $0.isEnabled && $0.hasContentScripts
        }
        guard contentScriptEntities.isEmpty == false else { return true }

        return contentScriptEntities.allSatisfy { entity in
            guard
                let context = manager.getExtensionContext(
                    for: entity.id,
                    profileId: profileId
                )
            else {
                return false
            }
            return context.isLoaded
        }
    }

    func profileNeedsContentScriptContextLoad(profileId: UUID) -> Bool {
        profileHasLoadedContentScriptContexts(profileId: profileId) == false
    }

    func profileNeedsInitialDocumentExtensionContextLoad(profileId: UUID) -> Bool {
        profileNeedsContentScriptContextLoad(profileId: profileId)
            || profileNeedsInitialDocumentNativeMessagingWarmup(profileId: profileId)
    }

    func ensureContentScriptContextsLoaded(for profileId: UUID) async {
        guard let manager else { return }
        guard manager.extensionsModuleEnabledForRuntimeBoundary() else { return }
        guard profileNeedsContentScriptContextLoad(profileId: profileId) else { return }

        if let existingTask = contentScriptContextLoadTasksByProfile[profileId] {
            await existingTask.value
            return
        }

        let task = Self.detachedMainActorRuntimeTask { [weak self] in
            guard let self, let manager = self.manager else { return }
            defer {
                self.contentScriptContextLoadTasksByProfile.removeValue(forKey: profileId)
            }
            guard Task.isCancelled == false else { return }

            for entity in manager.enabledPersistedExtensionEntities()
                where entity.isEnabled && entity.hasContentScripts
            {
                guard Task.isCancelled == false else { return }
                do {
                    _ = try await manager.ensureExtensionLoaded(
                        extensionId: entity.id,
                        profileId: profileId
                    )
                } catch {
                    manager.logExtensionLoadFailure(
                        error,
                        extensionId: entity.id,
                        profileId: profileId,
                        operation: "preload content-script context"
                    )
                }
            }
        }
        contentScriptContextLoadTasksByProfile[profileId] = task
        await task.value
    }

    /// Prepares extension contexts needed by the first normal-tab document.
    ///
    /// Manifest content scripts are still loaded lazily, but extensions that combine
    /// `content_scripts`, background content, and the required `nativeMessaging`
    /// permission need their background page/service worker ready before the first
    /// content-script message. Chrome/Firefox route native messaging through that
    /// background context, and WebKit exposes `loadBackgroundContent` for the same
    /// app-owned preflight without opening the action popup.
    func ensureInitialDocumentExtensionContextsLoaded(for profileId: UUID) async {
        guard let manager else { return }
        guard manager.extensionsModuleEnabledForRuntimeBoundary() else { return }
        await ensureContentScriptContextsLoaded(for: profileId)
        await ensureInitialDocumentNativeMessagingBackgroundsLoaded(for: profileId)
    }

    func profileNeedsInitialDocumentNativeMessagingWarmup(profileId: UUID) -> Bool {
        guard let manager else { return false }
        return initialDocumentNativeMessagingWarmupEntities(profileId: profileId).contains {
            manager.backgroundRuntimeState(for: $0.id, profileId: profileId) != .loaded
        }
    }

    @discardableResult
    func scheduleDeferredTabNotificationAfterContextLoad(
        _ tab: Tab,
        profileId: UUID,
        extensionLoadGeneration: UInt64,
        reason: String
    ) -> Task<Void, Never> {
        let tabId = tab.id
        let token = UUID()
        let task = Self.detachedMainActorRuntimeTask { [weak self] in
            guard let self, let manager = self.manager else { return }
            defer {
                if self.deferredTabNotificationTasksByTabID[tabId]?.token == token {
                    self.deferredTabNotificationTasksByTabID.removeValue(forKey: tabId)
                }
            }

            guard Task.isCancelled == false,
                  manager.extensionLoadGeneration == extensionLoadGeneration
            else { return }

            await self.ensureInitialDocumentExtensionContextsLoaded(for: profileId)

            guard Task.isCancelled == false,
                  manager.extensionLoadGeneration == extensionLoadGeneration
            else { return }

            guard
                let resolvedTab = manager.browserBridgeContext?.extensionTab(
                    for: tabId
                )
            else {
                return
            }
            manager.reconcileTabAfterContentScriptContextsLoaded(
                resolvedTab,
                reason: "\(reason).afterContextLoad"
            )
        }
        deferredTabNotificationTasksByTabID[tabId]?.task.cancel()
        deferredTabNotificationTasksByTabID[tabId] = (token, task)
        return task
    }

    func deferredTabNotificationTask(for tabId: UUID) -> Task<Void, Never>? {
        deferredTabNotificationTasksByTabID[tabId]?.task
    }

    func cancelContentScriptContextLoadTasks() {
        contentScriptContextLoadTasksByProfile.values.forEach { $0.cancel() }
        contentScriptContextLoadTasksByProfile.removeAll()
    }

    func cancelInitialDocumentNativeMessagingWarmupTasks() {
        for scheduledTask in nativeMessagingWarmupTasksByProfile.values {
            scheduledTask.task.cancel()
            retiredNativeMessagingWarmupTaskTokens.insert(scheduledTask.token)
        }
        nativeMessagingWarmupTasksByProfile.removeAll()
        finishedUnregisteredNativeMessagingWarmupTaskTokens.removeAll()
    }

    func cancelDeferredTabNotificationTasks() {
        deferredTabNotificationTasksByTabID.values.forEach { $0.task.cancel() }
        deferredTabNotificationTasksByTabID.removeAll()
    }

    #if DEBUG
        func runtimeTasksForDrain() -> [Task<Void, Never>] {
            deferredTabNotificationTasksByTabID.values.map(\.task)
                + Array(contentScriptContextLoadTasksByProfile.values)
                + nativeMessagingWarmupTasksByProfile.values.map(\.task)
        }
    #endif

    private func ensureInitialDocumentNativeMessagingBackgroundsLoaded(
        for profileId: UUID
    ) async {
        guard let manager else { return }
        guard manager.extensionsModuleEnabledForRuntimeBoundary() else { return }
        guard profileNeedsInitialDocumentNativeMessagingWarmup(profileId: profileId)
        else { return }

        if let existingTask = nativeMessagingWarmupTasksByProfile[profileId] {
            await existingTask.task.value
            return
        }

        let token = UUID()
        let task = Self.detachedMainActorRuntimeTask { [weak self] in
            guard let self, let manager = self.manager else { return }
            defer {
                self.finishInitialDocumentNativeMessagingWarmupTask(
                    profileId: profileId,
                    token: token
                )
            }
            guard Task.isCancelled == false else { return }

            for entity in self.initialDocumentNativeMessagingWarmupEntities(
                profileId: profileId
            ) {
                guard Task.isCancelled == false else { return }
                do {
                    guard
                        let extensionContext = try await manager.ensureExtensionLoaded(
                            extensionId: entity.id,
                            profileId: profileId
                        )
                    else {
                        continue
                    }
                    _ = try await manager.ensureBackgroundAvailableIfRequired(
                        for: extensionContext.webExtension,
                        context: extensionContext,
                        reason: .nativeMessaging
                    )
                } catch {
                    manager.logExtensionLoadFailure(
                        error,
                        extensionId: entity.id,
                        profileId: profileId,
                        operation: "warm initial-document native messaging runtime"
                    )
                }
            }
        }
        nativeMessagingWarmupTasksByProfile[profileId] = (token, task)
        clearInitialDocumentNativeMessagingWarmupTaskIfFinishedBeforeRegistration(
            profileId: profileId,
            token: token
        )
        await task.value
    }

    private func finishInitialDocumentNativeMessagingWarmupTask(
        profileId: UUID,
        token: UUID
    ) {
        var didResolveTask = false
        if nativeMessagingWarmupTasksByProfile[profileId]?.token == token {
            nativeMessagingWarmupTasksByProfile.removeValue(forKey: profileId)
            didResolveTask = true
        }
        if retiredNativeMessagingWarmupTaskTokens.remove(token) != nil {
            didResolveTask = true
        }
        guard !didResolveTask else { return }
        finishedUnregisteredNativeMessagingWarmupTaskTokens.insert(token)
    }

    private func clearInitialDocumentNativeMessagingWarmupTaskIfFinishedBeforeRegistration(
        profileId: UUID,
        token: UUID
    ) {
        guard finishedUnregisteredNativeMessagingWarmupTaskTokens.remove(token) != nil
        else { return }

        if nativeMessagingWarmupTasksByProfile[profileId]?.token == token {
            nativeMessagingWarmupTasksByProfile.removeValue(forKey: profileId)
        }
    }

    private func initialDocumentNativeMessagingWarmupEntities(
        profileId: UUID
    ) -> [ExtensionEntity] {
        guard let manager else { return [] }
        guard manager.extensionsModuleEnabledForRuntimeBoundary() else { return [] }

        return manager.enabledPersistedExtensionEntities().filter { entity in
            entity.isEnabled
                && entity.hasContentScripts
                && entity.hasBackground
                && extensionDeclaresNativeMessaging(entity)
                && manager.backgroundRuntimeState(for: entity.id, profileId: profileId)
                    != .loaded
        }
    }

    private func extensionDeclaresNativeMessaging(_ entity: ExtensionEntity) -> Bool {
        guard let manager else { return false }
        let manifest =
            manager.loadedExtensionManifests[entity.id]
            ?? manager.installedExtensions.first(where: { $0.id == entity.id })?.manifest
            ?? InstalledExtensionRecord(from: entity)?.manifest
            ?? [:]
        let permissions = Self.manifestStringArray(from: manifest["permissions"])
        return permissions.contains("nativeMessaging")
    }

    private nonisolated static func manifestStringArray(from value: Any?) -> [String] {
        value as? [String] ?? []
    }

    private nonisolated static func detachedMainActorRuntimeTask(
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) -> Task<Void, Never> {
        Task.detached {
            await operation()
        }
    }
}

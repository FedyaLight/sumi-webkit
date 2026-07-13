import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionInitialDocumentRuntimePreparationOwner:
    ExtensionContentScriptContextLoading {
    private weak var manager: ExtensionManager?

    private var contentScriptContextLoadTasksByProfile: [UUID: Task<Void, Never>] = [:]
    private var nativeMessagingWarmupTasksByProfile:
        [UUID: (token: UUID, task: Task<Void, Never>)] = [:]
    private var retiredNativeMessagingWarmupTaskTokens = Set<UUID>()
    private var finishedUnregisteredNativeMessagingWarmupTaskTokens = Set<UUID>()

    init(manager: ExtensionManager) {
        self.manager = manager
    }

    func profileHasLoadedContentScriptContexts(profileId: UUID) -> Bool {
        guard let manager else { return true }
        guard manager.extensionsModuleEnabledForRuntimeBoundary() else { return true }

        let contentScriptExtensions = manager.installedExtensionCollection.records.filter {
            $0.isEnabled && $0.hasContentScripts
        }
        guard contentScriptExtensions.isEmpty == false else { return true }

        return contentScriptExtensions.allSatisfy { installedExtension in
            guard
                let context = manager.getExtensionContext(
                    for: installedExtension.id,
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

            for installedExtension in manager.installedExtensionCollection.records
                where installedExtension.isEnabled
                    && installedExtension.hasContentScripts {
                guard Task.isCancelled == false else { return }
                do {
                    _ = try await manager.ensureExtensionLoaded(
                        extensionId: installedExtension.id,
                        profileId: profileId
                    )
                } catch {
                    manager.logExtensionLoadFailure(
                        error,
                        extensionId: installedExtension.id,
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
    func ensureInitialExtensionContextsLoaded(for profileId: UUID) async {
        guard let manager else { return }
        guard manager.extensionsModuleEnabledForRuntimeBoundary() else { return }
        await ensureContentScriptContextsLoaded(for: profileId)
        await ensureInitialDocumentNativeMessagingBackgroundsLoaded(for: profileId)
    }

    func profileNeedsInitialDocumentNativeMessagingWarmup(profileId: UUID) -> Bool {
        guard let manager else { return false }
        return initialDocumentNativeMessagingWarmupExtensions(profileId: profileId).contains {
            manager.backgroundRuntimeState(for: $0.id, profileId: profileId) != .loaded
        }
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

    #if DEBUG
        func runtimeTasksForDrain() -> [Task<Void, Never>] {
            Array(contentScriptContextLoadTasksByProfile.values)
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

            for installedExtension in self.initialDocumentNativeMessagingWarmupExtensions(
                profileId: profileId
            ) {
                guard Task.isCancelled == false else { return }
                do {
                    guard
                        let extensionContext = try await manager.ensureExtensionLoaded(
                            extensionId: installedExtension.id,
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
                        extensionId: installedExtension.id,
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

    private func initialDocumentNativeMessagingWarmupExtensions(
        profileId: UUID
    ) -> [InstalledExtension] {
        guard let manager else { return [] }
        guard manager.extensionsModuleEnabledForRuntimeBoundary() else { return [] }

        return manager.installedExtensionCollection.records.filter { installedExtension in
            installedExtension.isEnabled
                && installedExtension.hasContentScripts
                && installedExtension.hasBackground
                && extensionDeclaresNativeMessaging(installedExtension)
                && manager.backgroundRuntimeState(
                    for: installedExtension.id,
                    profileId: profileId
                )
                    != .loaded
        }
    }

    private func extensionDeclaresNativeMessaging(
        _ installedExtension: InstalledExtension
    ) -> Bool {
        guard let manager else { return false }
        let manifest =
            manager.runtimeCatalog.manifest(for: installedExtension.id)
            ?? installedExtension.manifest
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

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func profileHasLoadedContentScriptContexts(profileId: UUID) -> Bool {
        initialDocumentRuntimePreparationOwner
            .profileHasLoadedContentScriptContexts(profileId: profileId)
    }

    func profileNeedsContentScriptContextLoad(profileId: UUID) -> Bool {
        initialDocumentRuntimePreparationOwner
            .profileNeedsContentScriptContextLoad(profileId: profileId)
    }

    func profileNeedsInitialDocumentExtensionContextLoad(profileId: UUID) -> Bool {
        initialDocumentRuntimePreparationOwner
            .profileNeedsInitialDocumentExtensionContextLoad(profileId: profileId)
    }

    func ensureContentScriptContextsLoaded(for profileId: UUID) async {
        await initialDocumentRuntimePreparationOwner
            .ensureContentScriptContextsLoaded(for: profileId)
    }

    func ensureInitialExtensionContextsLoaded(for profileId: UUID) async {
        await initialDocumentRuntimePreparationOwner
            .ensureInitialExtensionContextsLoaded(for: profileId)
    }

    func cancelInitialDocumentNativeMessagingWarmupTasks() {
        loadedInitialDocumentRuntimePreparationOwner?
            .cancelInitialDocumentNativeMessagingWarmupTasks()
    }

    func profileNeedsInitialDocumentNativeMessagingWarmup(profileId: UUID) -> Bool {
        initialDocumentRuntimePreparationOwner
            .profileNeedsInitialDocumentNativeMessagingWarmup(profileId: profileId)
    }

    @discardableResult
    func scheduleDeferredTabNotificationAfterContextLoad(
        _ tab: Tab,
        profileId: UUID,
        reason: String = #function
    ) -> Task<Void, Never> {
        deferredTabRegistration
            .scheduleDeferredTabNotificationAfterContextLoad(
                tab,
                profileId: profileId,
                extensionLoadRevision: extensionLoadRevisions.issue(),
                reason: reason
            )
    }

    func deferredTabNotificationTask(for tabId: UUID) -> Task<Void, Never>? {
        deferredTabRegistration.task(for: tabId)
    }
}

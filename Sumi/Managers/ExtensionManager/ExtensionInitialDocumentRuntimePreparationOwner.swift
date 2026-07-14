import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionInitialDocumentRuntimePreparationOwner:
    ExtensionContentScriptContextLoading {
    private let contentScripts: ExtensionContentScriptContextPreparationOwner
    private let nativeMessaging: ExtensionInitialDocumentNativeMessagingWarmupOwner

    init(
        contentScripts: ExtensionContentScriptContextPreparationOwner,
        nativeMessaging: ExtensionInitialDocumentNativeMessagingWarmupOwner
    ) {
        self.contentScripts = contentScripts
        self.nativeMessaging = nativeMessaging
    }

    func profileHasLoadedContentScriptContexts(profileId: UUID) -> Bool {
        contentScripts.profileHasLoadedContexts(profileID: profileId)
    }

    func profileNeedsContentScriptContextLoad(profileId: UUID) -> Bool {
        contentScripts.profileNeedsLoad(profileID: profileId)
    }

    func profileNeedsInitialDocumentExtensionContextLoad(profileId: UUID) -> Bool {
        contentScripts.profileNeedsLoad(profileID: profileId)
            || nativeMessaging.profileNeedsWarmup(profileID: profileId)
    }

    func ensureContentScriptContextsLoaded(for profileId: UUID) async {
        await contentScripts.ensureLoaded(profileID: profileId)
    }

    func ensureInitialExtensionContextsLoaded(for profileId: UUID) async {
        await contentScripts.ensureLoaded(profileID: profileId)
        await nativeMessaging.ensureLoaded(profileID: profileId)
    }

    func profileNeedsInitialDocumentNativeMessagingWarmup(profileId: UUID) -> Bool {
        nativeMessaging.profileNeedsWarmup(profileID: profileId)
    }

    func cancelContentScriptContextLoadTasks() {
        contentScripts.cancelAll()
    }

    func cancelInitialDocumentNativeMessagingWarmupTasks() {
        nativeMessaging.cancelAll()
    }

    #if DEBUG
        func runtimeTasksForDrain() -> [Task<Void, Never>] {
            contentScripts.runtimeTasksForDrain()
                + nativeMessaging.runtimeTasksForDrain()
        }
    #endif
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
        deferredTabRegistration.scheduleDeferredTabNotificationAfterContextLoad(
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

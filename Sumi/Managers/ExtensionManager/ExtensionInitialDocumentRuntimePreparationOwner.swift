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

    func participatesInInitialDocumentRuntime() -> Bool {
        contentScripts.participatesInInitialDocumentRuntime()
    }

    func profileHasLoadedExtensionContext(profileId: UUID) -> Bool {
        contentScripts.profileHasLoadedExtensionContext(profileID: profileId)
    }

    func profileNeedsContentScriptContextLoad(profileId: UUID) -> Bool {
        contentScripts.profileNeedsLoad(profileID: profileId)
    }

    func profileNeedsInitialDocumentExtensionContextLoad(profileId: UUID) -> Bool {
        contentScripts.profileNeedsLoad(profileID: profileId)
    }

    func ensureContentScriptContextsLoaded(for profileId: UUID) async {
        _ = await contentScripts.ensureLoaded(profileID: profileId)
    }

    func ensureInitialExtensionContextsLoaded(for profileId: UUID) async
        -> PageNavigationPrerequisiteResult {
        await contentScripts.ensureLoaded(profileID: profileId)
    }

    func warmInitialDocumentNativeMessaging(for profileId: UUID) async {
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

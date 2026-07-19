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
        await contentScripts.ensureLoaded(profileID: profileId)
    }

    func ensureInitialExtensionContextsLoaded(for profileId: UUID) async {
        await contentScripts.ensureLoaded(profileID: profileId)
        // Initial-document materialization is the browser's bootstrap
        // boundary. Complete the background/native-messaging wake before a
        // WebView is created so document-start scripts observe the same ready
        // runtime as Safari.
        await nativeMessaging.ensureLoaded(profileID: profileId)
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

import Foundation
import OSLog

@available(macOS 15.5, *)
@MainActor
final class ExtensionDeferredRuntimeQuery {
    private let modules: SumiModuleRegistry

    init(modules: SumiModuleRegistry) {
        self.modules = modules
    }

    var extensionsAreEnabled: Bool {
        modules.isAvailable == false || modules.isEnabled(.extensions)
    }
}

@available(macOS 15.5, *)
struct ExtensionDeferredRuntimeFailureLogger {
    private let logger = Logger.sumi(category: "Extensions")

    func log(
        _ error: Error,
        extensionID: String,
        profileID: UUID,
        operation: String
    ) {
        logger.error(
            "Failed to \(operation, privacy: .public) for extension \(extensionID, privacy: .public) profile \(profileID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionDeferredRuntimeOwnerStore {
    private let installedExtensions: InstalledExtensionCollection
    private let runtimeCatalog: ExtensionRuntimeCatalog
    private let runtimeQuery: ExtensionDeferredRuntimeQuery
    private let profileQuery: ExtensionProfileRuntime
    private let contextLoading: ExtensionContextResidencyOwner
    private let backgroundWake: ExtensionBackgroundWakeCoordinator
    private let failureLogger: ExtensionDeferredRuntimeFailureLogger
    private var initialDocumentRuntimePreparationOwnerStorage:
        ExtensionInitialDocumentRuntimePreparationOwner?

    init(
        installedExtensions: InstalledExtensionCollection,
        runtimeCatalog: ExtensionRuntimeCatalog,
        runtimeQuery: ExtensionDeferredRuntimeQuery,
        profileQuery: ExtensionProfileRuntime,
        contextLoading: ExtensionContextResidencyOwner,
        backgroundWake: ExtensionBackgroundWakeCoordinator,
        failureLogger: ExtensionDeferredRuntimeFailureLogger
    ) {
        self.installedExtensions = installedExtensions
        self.runtimeCatalog = runtimeCatalog
        self.runtimeQuery = runtimeQuery
        self.profileQuery = profileQuery
        self.contextLoading = contextLoading
        self.backgroundWake = backgroundWake
        self.failureLogger = failureLogger
    }

    var initialDocumentRuntimePreparationOwner: ExtensionInitialDocumentRuntimePreparationOwner {
        if let initialDocumentRuntimePreparationOwnerStorage {
            return initialDocumentRuntimePreparationOwnerStorage
        }
        let runtimeIsEnabled: @MainActor () -> Bool = { [runtimeQuery] in
            runtimeQuery.extensionsAreEnabled
        }
        let logFailure: ExtensionContentScriptContextPreparationOwner.FailureLog = {
            [failureLogger] error, extensionID, profileID, operation in
            failureLogger.log(
                error,
                extensionID: extensionID,
                profileID: profileID,
                operation: operation
            )
        }
        let contentScripts = ExtensionContentScriptContextPreparationOwner(
            installedExtensions: installedExtensions,
            runtimeIsEnabled: runtimeIsEnabled,
            context: { [profileQuery] extensionID, profileID in
                profileQuery.contexts(for: profileID)[extensionID]
            },
            load: { [contextLoading] extensionID, profileID in
                _ = try await contextLoading.ensureExtensionLoaded(
                    extensionId: extensionID,
                    profileId: profileID
                )
            },
            logFailure: logFailure
        )
        let nativeMessaging = ExtensionInitialDocumentNativeMessagingWarmupOwner(
            installedExtensions: installedExtensions,
            runtimeCatalog: runtimeCatalog,
            runtimeIsEnabled: runtimeIsEnabled,
            contextLoad: { [contextLoading] extensionID, profileID in
                try await contextLoading.ensureExtensionLoaded(
                    extensionId: extensionID,
                    profileId: profileID
                )
            },
            backgroundState: { [backgroundWake] extensionID, profileID in
                backgroundWake.backgroundRuntimeState(
                    for: extensionID,
                    profileId: profileID
                )
            },
            wakeBackground: { [backgroundWake] webExtension, context in
                _ = try await backgroundWake
                    .ensureBackgroundAvailableIfRequired(
                        for: webExtension,
                        context: context,
                        reason: .nativeMessaging
                    )
            },
            logFailure: logFailure
        )
        let owner = ExtensionInitialDocumentRuntimePreparationOwner(
            contentScripts: contentScripts,
            nativeMessaging: nativeMessaging
        )
        initialDocumentRuntimePreparationOwnerStorage = owner
        return owner
    }

    var loadedInitialDocumentRuntimePreparationOwner:
        ExtensionInitialDocumentRuntimePreparationOwner? {
        initialDocumentRuntimePreparationOwnerStorage
    }
}

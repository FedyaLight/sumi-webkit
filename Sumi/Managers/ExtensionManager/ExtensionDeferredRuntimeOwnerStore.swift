import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionDeferredRuntimeOwnerStore {
    private unowned let manager: ExtensionManager
    private var nativeMessagingBackgroundWakeOwnerStorage:
        ExtensionNativeMessagingBackgroundWakeOwner?
    private var initialDocumentRuntimePreparationOwnerStorage:
        ExtensionInitialDocumentRuntimePreparationOwner?

    init(manager: ExtensionManager) {
        self.manager = manager
    }

    var nativeMessagingBackgroundWakeOwner: ExtensionNativeMessagingBackgroundWakeOwner {
        if let nativeMessagingBackgroundWakeOwnerStorage {
            return nativeMessagingBackgroundWakeOwnerStorage
        }
        let owner = ExtensionNativeMessagingBackgroundWakeOwner()
        nativeMessagingBackgroundWakeOwnerStorage = owner
        return owner
    }

    var loadedNativeMessagingBackgroundWakeOwner: ExtensionNativeMessagingBackgroundWakeOwner? {
        nativeMessagingBackgroundWakeOwnerStorage
    }

    var initialDocumentRuntimePreparationOwner: ExtensionInitialDocumentRuntimePreparationOwner {
        if let initialDocumentRuntimePreparationOwnerStorage {
            return initialDocumentRuntimePreparationOwnerStorage
        }
        let owner = ExtensionInitialDocumentRuntimePreparationOwner(manager: manager)
        initialDocumentRuntimePreparationOwnerStorage = owner
        return owner
    }

    var loadedInitialDocumentRuntimePreparationOwner:
        ExtensionInitialDocumentRuntimePreparationOwner? {
        initialDocumentRuntimePreparationOwnerStorage
    }

}

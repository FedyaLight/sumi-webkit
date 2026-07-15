import Foundation

#if DEBUG
    /// Test-only terminal operation for awaiting extension-owned tasks. It
    /// exposes no individual task owner or runtime authority.
    @available(macOS 15.5, *)
    @MainActor
    struct ExtensionRuntimeTaskDrain {
        private let deferredRuntimeOwners: ExtensionDeferredRuntimeOwnerStore
        private let normalTabLifecycle:
            ExtensionBrowserAttachmentAuthority.NormalTabLifecycle
        private let nativeMessaging: ExtensionNativeMessagingSessionControl
        private let backgroundRuntimeState: ExtensionBackgroundRuntimeStateOwner

        init(
            deferredRuntimeOwners: ExtensionDeferredRuntimeOwnerStore,
            normalTabLifecycle:
                ExtensionBrowserAttachmentAuthority.NormalTabLifecycle,
            nativeMessaging: ExtensionNativeMessagingSessionControl,
            backgroundRuntimeState: ExtensionBackgroundRuntimeStateOwner
        ) {
            self.deferredRuntimeOwners = deferredRuntimeOwners
            self.normalTabLifecycle = normalTabLifecycle
            self.nativeMessaging = nativeMessaging
            self.backgroundRuntimeState = backgroundRuntimeState
        }

        func drain() async {
            while true {
                let tasks =
                    (deferredRuntimeOwners
                        .loadedInitialDocumentRuntimePreparationOwner?
                        .runtimeTasksForDrain() ?? [])
                    + normalTabLifecycle.runtimeTasksForDrain()
                    + nativeMessaging.runtimeTasksForDrain()
                let didDrainWakeTask = await backgroundRuntimeState
                    .drainWakeTasksForTests()
                guard tasks.isEmpty == false || didDrainWakeTask else { return }
                for task in tasks { await task.value }
            }
        }
    }
#endif

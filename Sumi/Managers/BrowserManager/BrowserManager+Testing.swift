import Foundation

#if DEBUG
extension BrowserManager {
    func drainProtectionRuntimeTasksForTests(cancel: Bool = false) async {
        await startupProtectionRuntime.drainProtectionRestoreTaskForTests(cancel: cancel)
        await adBlockingModule.drainRuleListTasksForTests(cancel: cancel)
        await optionalModules.extensions.drainSafariContentBlockerRuntimeForTests(
            cancel: cancel
        )
    }

    func drainBrowserRuntimeTasksForTests(cancel: Bool = false) async {
        await drainProtectionRuntimeTasksForTests(cancel: cancel)
        await dataServices.faviconService.drainRuntimeTasksForTests(cancel: cancel)
    }
}
#endif

#if DEBUG
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionManagerDebugSignals {
    var hooks = ExtensionManager.TestHooks()

    var beforeControllerLoad:
        ExtensionContextControllerTransaction.BeforeControllerLoad? {
        hooks.beforeControllerLoad
    }

    var backgroundContentWake:
        (@MainActor (String, WKWebExtensionContext) async throws -> Void)? {
        hooks.backgroundContentWake
    }

    var permissionPromptDecision:
        ((WKWebExtensionContext, [String], String) ->
            ExtensionManager.ExtensionPermissionPromptDecision)? {
        hooks.permissionPromptDecision
    }

    var webExtensionDataCleanup: (@MainActor (String) async -> Bool)? {
        hooks.webExtensionDataCleanup
    }

    var beforePersistInstalledRecord:
        ((InstalledExtension) throws -> Void)? {
        hooks.beforePersistInstalledRecord
    }

    func dispatchExtensionAction(_ extensionID: String) {
        hooks.didDispatchExtensionAction?(extensionID)
    }

    func dispatchAuxiliaryPublication(
        _ event: ExtensionAuxiliaryPublicationDebugEvent
    ) {
        switch event {
        case .didOpenWindow(let sessionID):
            hooks.didOpenAuxiliaryWindow?(sessionID)
        case .didOpenTab(_, let tabID):
            hooks.didOpenTab?(tabID)
        case .didFocusWindow(let sessionID):
            hooks.didFocusAuxiliaryWindow?(sessionID)
        case .didCloseTab(_, let tabID):
            hooks.didCloseTab?(tabID)
        case .didCloseWindow(let sessionID):
            hooks.didCloseAuxiliaryWindow?(sessionID)
        }
    }

    func dispatchNormalTabLifecycle(
        _ event: ExtensionNormalTabLifecycleDebugEvent
    ) {
        switch event {
        case .didActivateTab(let tabID):
            hooks.didActivateTab?(tabID)
        case .didSelectTab(let tabID):
            hooks.didSelectTab?(tabID)
        case .didDeselectTab(let tabID):
            hooks.didDeselectTab?(tabID)
        }
    }
}
#endif

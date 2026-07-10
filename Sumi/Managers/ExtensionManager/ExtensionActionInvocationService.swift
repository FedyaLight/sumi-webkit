import Foundation
import WebKit

/// Performs the final action invocation after runtime admission and page authorization.
@available(macOS 15.5, *)
@MainActor
final class ExtensionActionInvocationService {
    struct Environment {
        let runtimeResolver: ExtensionActionRuntimeResolver
        let pageAccess: ExtensionActionPageAccessAuthorizer
        let capabilities: SafariExtensionInstallCapabilityOwner
        let actionPublication: ExtensionActionSurfacePublisher
        let runtimeSession: ExtensionRuntimeSession
        let stableAdapter: @MainActor (Tab) -> ExtensionTabAdapter?
        let registerTab: @MainActor (Tab, String) -> Void
        let grantRequestedMatchPatterns: @MainActor (
            WKWebExtensionContext, WKWebExtension
        ) -> Void
        let trace: @MainActor (String) -> Void
    }

    private let environment: Environment

    init(environment: Environment) {
        self.environment = environment
    }

    func openPopup(
        extensionID: String,
        currentTab: Tab?
    ) async -> BrowserExtensionActionPopupRequestResult {
        let ready: ExtensionActionRuntimeResolution.Ready
        switch await environment.runtimeResolver.resolve(
            extensionID: extensionID,
            currentTab: currentTab
        ) {
        case .blocked(let result):
            return result
        case .ready(let resolution):
            ready = resolution
        }

        let adapter: ExtensionTabAdapter?
        if let currentTab {
            environment.registerTab(
                currentTab,
                "ExtensionActionInvocationService.openPopup"
            )
            adapter = environment.stableAdapter(currentTab)
        } else {
            adapter = nil
        }
        environment.capabilities.grantRequestedPermissions(
            to: ready.context,
            webExtension: ready.context.webExtension,
            manifest: ready.extensionRecord.manifest
        )
        environment.grantRequestedMatchPatterns(
            ready.context,
            ready.context.webExtension
        )
        if let currentTab {
            guard await environment.pageAccess.authorize(
                context: ready.context,
                installedExtension: ready.extensionRecord,
                tab: currentTab
            ) else {
                return .blocked(
                    .currentPagePermissionMissing,
                    message: "\(ready.extensionRecord.name) was not granted access to the current page."
                )
            }
        }

        guard let action = ready.context.action(for: adapter) else {
            return .blocked(
                .actionMissing,
                message: "WebKit did not expose an action for \(ready.extensionRecord.name)."
            )
        }
        environment.actionPublication.updateActionSurfaceState(
            for: action,
            extensionContext: ready.context
        )
        guard action.isEnabled else {
            return .blocked(
                .actionDisabled,
                message: "\(action.label) is disabled for the current page."
            )
        }

        trace(
            "urlHubAction performAction extensionId=\(extensionID) actionLabel=\(action.label) actionEnabled=\(action.isEnabled) presentsPopup=\(action.presentsPopup)"
        )
        ready.context.performAction(for: adapter)
        environment.runtimeSession.recordRuntimeMetric(for: extensionID) { metrics in
            metrics.lastBackgroundWakeReason = .actionPopup
            metrics.backgroundWakeCount += 1
        }
        return action.presentsPopup ? .openedPopup : .performedAction
    }

    private func trace(_ message: @autoclosure () -> String) {
        guard ExtensionManager.isWebKitRuntimeTraceEnabled else { return }
        environment.trace(message())
    }
}

@available(macOS 15.5, *)
extension ExtensionActionInvocationService.Environment {
    @MainActor
    static func makeLive(manager: ExtensionManager) -> Self {
        Self(
            runtimeResolver: ExtensionActionRuntimeResolver(
                environment: .makeLive(manager: manager)
            ),
            pageAccess: ExtensionActionPageAccessAuthorizer(
                environment: .makeLive(manager: manager)
            ),
            capabilities: manager.installCapabilityOwner,
            actionPublication: manager.actionSurfacePublisher,
            runtimeSession: manager.runtimeSession,
            stableAdapter: { [weak manager] in
                manager?.adapterResolutionOwner.stableAdapter(for: $0)
            },
            registerTab: { [weak manager] tab, reason in
                manager?.registerTabWithExtensionRuntime(tab, reason: reason)
            },
            grantRequestedMatchPatterns: { [weak manager] context, webExtension in
                manager?.grantRequestedMatchPatterns(
                    to: context,
                    webExtension: webExtension
                )
            },
            trace: { [weak manager] message in manager?.runtimeDiagnostics.trace(message) }
        )
    }
}

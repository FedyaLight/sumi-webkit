import Foundation
import WebKit

/// Performs the final action invocation after runtime admission and page
/// authorization. The whole invocation is one exact fail-closed transaction:
/// click authority is captured before runtime resolution, completed with the
/// exact WebKit binding after its await, and revalidated before every
/// independent effect. A stale invocation stops immediately with a
/// deterministic blocked result and never continues with later grants,
/// persistence, publication, dispatch or metrics.
@available(macOS 15.5, *)
@MainActor
final class ExtensionActionInvocationService {
    struct Environment {
        let runtimeResolver: ExtensionActionRuntimeResolver
        let requestAdmission: ExtensionActionRequestAdmission
        let pageAccess: ExtensionActionPageAccessAuthorizer
        let admission: ExtensionActionInvocationAdmission
        let capabilities: SafariExtensionInstallCapabilityOwner
        let actionPublication: ExtensionActionSurfacePublisher
        let runtimeSession: ExtensionRuntimeSession
        let stableAdapter: @MainActor (Tab) -> ExtensionTabAdapter?
        let registerTab: @MainActor (Tab, String) -> Void
        let actionDispatchProbe: @MainActor (String) -> Void
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
        guard let request = environment.requestAdmission.capture(
                  extensionID: extensionID,
                  currentTab: currentTab
              )
        else {
            return Self.staleResult()
        }
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

        // Barrier: runtime resolution awaited context loading. Admit the
        // click only against the exact current binding and catalog record.
        guard var evidence = environment.admission.capture(
                  request: request,
                  profileID: ready.profileID,
                  context: ready.context,
                  controller: ready.context.webExtensionController
              )
        else {
            return Self.staleResult()
        }

        if let currentTab {
            environment.registerTab(
                currentTab,
                "ExtensionActionInvocationService.openPopup"
            )
            let adapter = environment.stableAdapter(currentTab)
            // Barrier: registration and adapter resolution publish runtime
            // events that can reentrantly replace the captured authority.
            guard let adapterBound = environment.admission.admitAdapter(
                adapter,
                for: evidence
            ) else {
                return Self.staleResult()
            }
            evidence = adapterBound
        }

        guard environment.admission.isCurrent(evidence) else {
            return Self.staleResult()
        }
        environment.capabilities.grantRequestedPermissions(
            to: evidence.context,
            webExtension: evidence.context.webExtension,
            manifest: evidence.installedRecord.manifest
        )
        // Barrier: requested-permission grants are observable context state.
        guard environment.admission.isCurrent(evidence) else {
            return Self.staleResult()
        }
        guard environment.pageAccess.applyConfiguredPolicy(evidence: evidence) else {
            return Self.staleResult()
        }
        if evidence.page != nil {
            switch await environment.pageAccess.authorize(evidence: evidence) {
            case .authorized:
                break
            case .denied:
                return .blocked(
                    .currentPagePermissionMissing,
                    message: "\(evidence.installedRecord.name) was not granted access to the current page."
                )
            case .stale:
                return Self.staleResult()
            }
        }

        // Barrier: page authorization awaited the permission prompt.
        guard environment.admission.isCurrent(evidence) else {
            return Self.staleResult()
        }
        guard let action = evidence.context.action(for: evidence.adapter) else {
            return .blocked(
                .actionMissing,
                message: "WebKit did not expose an action for \(evidence.installedRecord.name)."
            )
        }
        environment.actionPublication.updateActionSurfaceState(
            for: action,
            extensionContext: evidence.context
        )
        // Barrier: action-surface publication is observable and can
        // reentrantly replace the captured authority before dispatch.
        guard environment.admission.isCurrent(evidence) else {
            return Self.staleResult()
        }
        guard action.isEnabled else {
            return .blocked(
                .actionDisabled,
                message: "\(action.label) is disabled for the current page."
            )
        }

        trace(
            "urlHubAction performAction extensionId=\(extensionID) actionLabel=\(action.label) actionEnabled=\(action.isEnabled) presentsPopup=\(action.presentsPopup)"
        )
        guard environment.admission.isCurrent(evidence) else {
            return Self.staleResult()
        }
        let presentsPopup = action.presentsPopup
        evidence.context.performAction(for: evidence.adapter)
        environment.actionDispatchProbe(extensionID)
        // Barrier: dispatch itself is observable; a reentrant replacement
        // must not record success metrics for superseded authority.
        if environment.admission.isCurrent(evidence) {
            environment.runtimeSession.recordRuntimeMetric(
                for: extensionID
            ) { metrics in
                metrics.lastBackgroundWakeReason = .actionPopup
                metrics.backgroundWakeCount += 1
            }
        }
        return presentsPopup ? .openedPopup : .performedAction
    }

    private static func staleResult() -> BrowserExtensionActionPopupRequestResult {
        .blocked(
            .staleInvocation,
            message: "The extension action click was superseded by a runtime, catalog, profile or page change and was stopped before its next effect."
        )
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
        let requestAdmission = ExtensionActionRequestAdmission(
            runtimeBindingAdmission: manager.controllerCallbackAdmission,
            profileRuntime: manager.profileRuntime,
            runtime: { [weak manager] in manager?.runtime ?? .inactive },
            installedExtensions: manager.installedExtensionCollection
        )
        let admission = ExtensionActionInvocationAdmission(
            runtimeBindingAdmission: manager.controllerCallbackAdmission,
            requestAdmission: requestAdmission,
            installedExtensions: manager.installedExtensionCollection,
            adapterStore: manager.adapterStore
        )
        return Self(
            runtimeResolver: ExtensionActionRuntimeResolver(
                environment: .makeLive(manager: manager)
            ),
            requestAdmission: requestAdmission,
            pageAccess: ExtensionActionPageAccessAuthorizer(
                environment: .makeLive(manager: manager),
                admission: admission
            ),
            admission: admission,
            capabilities: manager.installCapabilityOwner,
            actionPublication: manager.actionSurfacePublisher,
            runtimeSession: manager.runtimeSession,
            stableAdapter: { [weak manager] in
                manager?.adapterResolutionOwner.stableAdapter(for: $0)
            },
            registerTab: { [weak manager] tab, reason in
                manager?.registerTabWithExtensionRuntime(tab, reason: reason)
            },
            actionDispatchProbe: { [weak manager] extensionID in
                #if DEBUG
                    manager?.testHooks.didDispatchExtensionAction?(extensionID)
                #else
                    _ = manager
                    _ = extensionID
                #endif
            },
            trace: { [weak manager] message in manager?.runtimeDiagnostics.trace(message) }
        )
    }
}

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
        let actionPublication: ExtensionActionSurfacePublisher
        let runtimeMetrics: ExtensionRuntimeMetricsAuthority
        let stableAdapter: @MainActor (Tab) -> ExtensionTabAdapter?
        let registerTab: @MainActor (Tab, String) -> Void
        let actionDispatchProbe: @MainActor (String) -> Void
        let trace: @MainActor (String) -> Void
    }

    private let environment: Environment
    private let actionDispatch: any ExtensionActionDispatching
    private let popupBindingRecovery: any ExtensionActionPopupBindingRecovering

    init(
        environment: Environment,
        actionDispatch: any ExtensionActionDispatching,
        popupBindingRecovery: any ExtensionActionPopupBindingRecovering
    ) {
        self.environment = environment
        self.actionDispatch = actionDispatch
        self.popupBindingRecovery = popupBindingRecovery
    }

    func openPopup(
        extensionID: String,
        currentTab: Tab?,
        popupTargetRequest: ExtensionActionPopupTargetRequest = .implicit
    ) async -> BrowserExtensionActionPopupRequestResult {
        await openPopupAttempt(
            extensionID: extensionID,
            currentTab: currentTab,
            popupTargetRequest: popupTargetRequest,
            allowsBindingRecovery: true
        )
    }

    private func openPopupAttempt(
        extensionID: String,
        currentTab: Tab?,
        popupTargetRequest: ExtensionActionPopupTargetRequest,
        allowsBindingRecovery: Bool
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
            currentTab: currentTab,
            popupTargetRequest: popupTargetRequest
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
        let presentsPopup = action.presentsPopup
        let popupRegistration: ExtensionActionPopupInvocationRegistration?
        switch actionDispatch.perform(
            action: action,
            evidence: evidence,
            popupTarget: ready.popupTarget
        ) {
        case .performed(let registration):
            popupRegistration = registration
        case .stale:
            return Self.staleResult()
        case .popupTargetUnavailable:
            return .blocked(
                .staleInvocation,
                message: "The action popup lost its exact presentation target before dispatch."
            )
        case .awaitingPopupSettlement:
            return .blocked(
                .staleInvocation,
                message: "This popup is still loading and awaiting WebKit settlement from the previous click."
            )
        case .popupBindingRecoveryRequired(let stalledBinding):
            guard allowsBindingRecovery,
                  await popupBindingRecovery.recover(stalledBinding)
            else {
                return .blocked(
                    .runtimeLoadFailed,
                    message: "The stalled WebKit popup runtime could not be replaced safely."
                )
            }
            return await openPopupAttempt(
                extensionID: extensionID,
                currentTab: currentTab,
                popupTargetRequest: popupTargetRequest,
                allowsBindingRecovery: false
            )
        }
        environment.actionDispatchProbe(extensionID)
        // Barrier: dispatch itself is observable; a reentrant replacement
        // cannot undo WebKit's call, but must cancel local popup admission and
        // return a stale result rather than report a popup that cannot present.
        guard environment.admission.isCurrent(evidence) else {
            actionDispatch.cancel(popupRegistration)
            return Self.staleResult()
        }
        environment.runtimeMetrics.recordBackgroundWakeInvocation(
            reason: .actionPopup,
            for: extensionID
        )
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

import Foundation

@available(macOS 15.5, *)
@MainActor
extension ExtensionActionInvocationService {
    static func live(manager: ExtensionManager) -> Self {
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
        let environment = Environment(
            runtimeResolver: ExtensionActionRuntimeResolver(
                environment: .makeLive(manager: manager)
            ),
            requestAdmission: requestAdmission,
            pageAccess: ExtensionActionPageAccessAuthorizer(
                environment: .makeLive(manager: manager),
                admission: admission
            ),
            admission: admission,
            actionPublication: manager.actionSurfacePublisher,
            runtimeMetrics: manager.runtimeMetrics,
            stableAdapter: { [weak manager] in
                manager?.adapterCatalog.stableAdapter(for: $0)
            },
            registerTab: { [weak manager] tab, reason in
                manager?.normalTabRegistration.register(tab, reason: reason)
            },
            actionDispatchProbe: { [weak manager] extensionID in
                #if DEBUG
                    manager?.testHooks.didDispatchExtensionAction?(extensionID)
                #else
                    _ = manager
                    _ = extensionID
                #endif
            },
            trace: { [weak manager] message in
                manager?.runtimeDiagnostics.trace(message)
            }
        )
        return Self(
            environment: environment,
            actionDispatch: ExtensionActionDispatch(
                admission: admission,
                popupInvocations: manager.actionPopupInvocationLedger
            ),
            popupBindingRecovery: manager.actionPopupBindingRecovery
        )
    }
}

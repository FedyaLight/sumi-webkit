import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
enum ExtensionControllerOpeningCallbackComposition {
    struct Invocation {
        let evidence: ExtensionControllerCallbackEvidence
        let runtime: ExtensionControllerOpeningCallbackRuntime
    }

    static func invocation(
        from manager: ExtensionManager,
        context: WKWebExtensionContext,
        controller: WKWebExtensionController
    ) -> Invocation? {
        guard let evidence = manager.controllerCallbackAdmission.capture(
                  context: context,
                  controller: controller
              ),
              let runtime = runtime(from: manager)
        else {
            return nil
        }
        return Invocation(evidence: evidence, runtime: runtime)
    }

    static func runtime(
        from manager: ExtensionManager
    ) -> ExtensionControllerOpeningCallbackRuntime? {
        guard let windowQuery = manager.extensionWindowQuery,
              let windowPresentation = manager.extensionWindowPresentation
        else {
            return nil
        }
        return ExtensionControllerOpeningCallbackRuntime(
            admission: manager.controllerCallbackAdmission,
            contextPreloader: manager.requestedTabContextPreloader,
            tabOpening: manager.requestedTabOpening,
            adapterResolver: manager.adapterCatalog,
            windowRouter: manager.extensionWindowRequestRouter,
            windowQuery: windowQuery,
            windowPresentation: windowPresentation,
            auxiliaryRuntime: ExtensionAuxiliaryWindowCallbackRuntime(
                contextLoading: manager.initialDocumentRuntimePreparationOwner,
                loadResolver: manager.requestedTabLoadResolver,
                contextPreloader: manager.requestedTabContextPreloader,
                recentRequests: manager.recentExtensionTabRequests,
                configurationPreparation:
                    manager.webViewConfigurationPreparation,
                integration: manager.auxiliaryWindowIntegration()
            )
        )
    }
}

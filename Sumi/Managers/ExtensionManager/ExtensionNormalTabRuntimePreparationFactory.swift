import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionNormalTabRuntimePreparationAssembly {
    let contextLoading: ExtensionInitialDocumentRuntimePreparationOwner
    let configuration: ExtensionWebViewConfigurationPreparation
    let diagnostics: ExtensionRuntimeDiagnostics
    #if DEBUG
        let debugSignals: ExtensionManagerDebugSignals
    #endif
}

/// Creates only demand-scoped preparation and debug publication roles.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalTabRuntimePreparationFactory {
    private let deferredRuntimeOwners: ExtensionDeferredRuntimeOwnerStore
    private let configuration: ExtensionWebViewConfigurationPreparation
    private let diagnostics: ExtensionRuntimeDiagnostics
    #if DEBUG
        private var debugSignals: ExtensionManagerDebugSignals?
    #endif

    init(
        deferredRuntimeOwners: ExtensionDeferredRuntimeOwnerStore,
        configurationPreparation: ExtensionWebViewConfigurationPreparation,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.deferredRuntimeOwners = deferredRuntimeOwners
        configuration = configurationPreparation
        self.diagnostics = diagnostics
    }

    #if DEBUG
        func installDebugSignals(_ signals: ExtensionManagerDebugSignals) {
            debugSignals = signals
        }
    #endif

    func makeAssembly() -> ExtensionNormalTabRuntimePreparationAssembly {
        #if DEBUG
            guard let debugSignals else {
                preconditionFailure("Debug signals must be installed before assembly")
            }
            return ExtensionNormalTabRuntimePreparationAssembly(
                contextLoading:
                    deferredRuntimeOwners.initialDocumentRuntimePreparationOwner,
                configuration: configuration,
                diagnostics: diagnostics,
                debugSignals: debugSignals
            )
        #else
            return ExtensionNormalTabRuntimePreparationAssembly(
                contextLoading:
                    deferredRuntimeOwners
                    .initialDocumentRuntimePreparationOwner,
                configuration: configuration,
                diagnostics: diagnostics
            )
        #endif
    }
}

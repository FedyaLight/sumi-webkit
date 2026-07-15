import Foundation
import WebKit

/// Retires one exact bound context. The binding remains authoritative while
/// WebKit unload runs; compare-and-remove prevents a reentrant replacement
/// from being erased by the older retirement.
@available(macOS 15.5, *)
@MainActor
final class ExtensionContextRetirement {
    typealias UnloadContext = @MainActor (
        WKWebExtensionController,
        WKWebExtensionContext
    ) throws -> Void
    typealias IsLoadedContext = @MainActor (
        WKWebExtensionController,
        WKWebExtensionContext
    ) -> Bool

    enum Outcome: Equatable {
        case retired
        case notBound
        case controllerUnavailable
        case unloadFailed
        case superseded
        case retirementInProgress
    }

    private let profileRuntime: ExtensionProfileRuntime
    private let backgroundRuntimeState: ExtensionBackgroundRuntimeStateOwner
    private let runtimeResidency: ExtensionRuntimeResidencyAuthority
    private let errorObservation: ExtensionContextErrorObservation
    private let diagnostics: ExtensionRuntimeDiagnostics
    private let actionPopups: ExtensionActionPopupRuntimeRetirement?
    private var inFlightReceipts = Set<ExtensionContextBindingReceipt>()
    #if DEBUG
        private var debugUnloadContext: UnloadContext?
        private var debugIsLoadedContext: IsLoadedContext?
    #endif

    init(
        profileRuntime: ExtensionProfileRuntime,
        backgroundRuntimeState: ExtensionBackgroundRuntimeStateOwner,
        runtimeResidency: ExtensionRuntimeResidencyAuthority,
        errorObservation: ExtensionContextErrorObservation,
        diagnostics: ExtensionRuntimeDiagnostics,
        actionPopups: ExtensionActionPopupRuntimeRetirement? = nil
    ) {
        self.profileRuntime = profileRuntime
        self.backgroundRuntimeState = backgroundRuntimeState
        self.runtimeResidency = runtimeResidency
        self.errorObservation = errorObservation
        self.diagnostics = diagnostics
        self.actionPopups = actionPopups
    }

    #if DEBUG
        convenience init(
            profileRuntime: ExtensionProfileRuntime,
            backgroundRuntimeState: ExtensionBackgroundRuntimeStateOwner,
            runtimeResidency: ExtensionRuntimeResidencyAuthority,
            errorObservation: ExtensionContextErrorObservation,
            diagnostics: ExtensionRuntimeDiagnostics,
            actionPopups: ExtensionActionPopupRuntimeRetirement? = nil,
            unloadContext: @escaping UnloadContext,
            isLoadedContext: @escaping IsLoadedContext = { controller, context in
                controller.extensionContexts.contains { $0 === context }
            }
        ) {
            self.init(
                profileRuntime: profileRuntime,
                backgroundRuntimeState: backgroundRuntimeState,
                runtimeResidency: runtimeResidency,
                errorObservation: errorObservation,
                diagnostics: diagnostics,
                actionPopups: actionPopups
            )
            installDebugOperations(
                unloadContext: unloadContext,
                isLoadedContext: isLoadedContext
            )
        }

        func installDebugOperations(
            unloadContext: UnloadContext?,
            isLoadedContext: IsLoadedContext?
        ) {
            debugUnloadContext = unloadContext
            debugIsLoadedContext = isLoadedContext
        }
    #endif

    func retireCurrent(
        extensionId: String,
        profileId: UUID
    ) -> Outcome {
        guard let receipt = profileRuntime.contextBindingReceipt(
            extensionId: extensionId,
            profileId: profileId
        ) else {
            return .notBound
        }
        return retire(receipt)
    }

    func retire(_ receipt: ExtensionContextBindingReceipt) -> Outcome {
        guard inFlightReceipts.insert(receipt).inserted else {
            return .retirementInProgress
        }
        defer { inFlightReceipts.remove(receipt) }

        actionPopups?.begin(receipt)
        guard let context = profileRuntime.context(ifCurrent: receipt) else {
            actionPopups?.complete(receipt)
            return .superseded
        }
        guard let controller = profileRuntime.controller(ifCurrent: receipt)
        else {
            return .controllerUnavailable
        }

        return retireExact(
            context: context,
            controller: controller,
            receipt: receipt
        )
    }

    /// Rolls back a context captured by a load transaction even if its binding
    /// was superseded. The exact old WebKit context is unloaded, while removal
    /// remains conditional so a newer binding survives.
    func rollbackLoad(
        context: WKWebExtensionContext,
        controller: WKWebExtensionController,
        receipt: ExtensionContextBindingReceipt
    ) -> Outcome {
        guard ObjectIdentifier(context) == receipt.contextIdentifier,
              ObjectIdentifier(controller) == receipt.controllerIdentifier
        else {
            return .superseded
        }
        guard inFlightReceipts.insert(receipt).inserted else {
            return .retirementInProgress
        }
        defer { inFlightReceipts.remove(receipt) }

        actionPopups?.begin(receipt)
        return retireExact(
            context: context,
            controller: controller,
            receipt: receipt
        )
    }

    private func retireExact(
        context: WKWebExtensionContext,
        controller: WKWebExtensionController,
        receipt: ExtensionContextBindingReceipt
    ) -> Outcome {
        let key = receipt.key
        if profileRuntime.isCurrent(receipt) {
            let wakeKey = ExtensionRuntimeResidencyState.scopedKey(
                extensionId: key.extensionId,
                profileId: key.profileId
            )
            backgroundRuntimeState.cancelWakePreservingRuntimeState(
                for: wakeKey
            )
        }

        // A load transaction publishes its exact binding before calling
        // WebKit so delegate callbacks can resolve identity during load. A
        // terminal shutdown can therefore retire that staged binding before
        // `WKWebExtensionController.load` runs. Asking WebKit to unload a
        // context it never loaded throws; the local binding is nevertheless
        // safe to retire because the controller is the authoritative loaded
        // context inventory.
        guard contextIsLoaded(context, in: controller) else {
            return completeRetirement(
                context: context,
                receipt: receipt,
                phase: "beforeWebKitLoad"
            )
        }

        do {
            try unload(context, from: controller)
        } catch {
            if profileRuntime.isCurrent(receipt) == false {
                errorObservation.removeObservation(
                    ifObserving: context,
                    extensionId: key.extensionId,
                    profileId: key.profileId
                )
            }
            diagnostics.trace(
                "contextRetirement unloadFailed extensionId=\(key.extensionId) "
                    + "profileId=\(key.profileId.uuidString) "
                    + "error=\(error.localizedDescription)"
            )
            return .unloadFailed
        }

        return completeRetirement(
            context: context,
            receipt: receipt,
            phase: "afterWebKitUnload"
        )
    }

    private func contextIsLoaded(
        _ context: WKWebExtensionContext,
        in controller: WKWebExtensionController
    ) -> Bool {
        #if DEBUG
            if let debugIsLoadedContext {
                return debugIsLoadedContext(controller, context)
            }
        #endif
        return controller.extensionContexts.contains { $0 === context }
    }

    private func unload(
        _ context: WKWebExtensionContext,
        from controller: WKWebExtensionController
    ) throws {
        #if DEBUG
            if let debugUnloadContext {
                try debugUnloadContext(controller, context)
                return
            }
        #endif
        try controller.unload(context)
    }

    private func completeRetirement(
        context: WKWebExtensionContext,
        receipt: ExtensionContextBindingReceipt,
        phase: String
    ) -> Outcome {
        let key = receipt.key
        let removal = profileRuntime.removeContext(ifCurrent: receipt)
        errorObservation.removeObservation(
            ifObserving: context,
            extensionId: key.extensionId,
            profileId: key.profileId
        )
        actionPopups?.complete(receipt)
        guard removal != nil else {
            diagnostics.trace(
                "contextRetirement superseded extensionId=\(key.extensionId) "
                    + "profileId=\(key.profileId.uuidString)"
            )
            return .superseded
        }

        runtimeResidency.remove(
            extensionID: key.extensionId,
            profileID: key.profileId
        )
        backgroundRuntimeState.removeRuntimeState(
            for: ExtensionRuntimeResidencyState.scopedKey(
                extensionId: key.extensionId,
                profileId: key.profileId
            )
        )
        diagnostics.trace(
            "contextRetirement retired extensionId=\(key.extensionId) "
                + "profileId=\(key.profileId.uuidString) phase=\(phase)"
        )
        return .retired
    }
}

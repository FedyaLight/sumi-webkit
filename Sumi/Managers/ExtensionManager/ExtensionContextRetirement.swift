import Foundation
import WebKit

/// Retires one exact bound context. The binding remains authoritative while
/// WebKit unload runs; compare-and-remove prevents a reentrant replacement
/// from being erased by the older retirement.
@available(macOS 15.5, *)
@MainActor
final class ExtensionContextRetirement {
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
    private let runtimeSession: ExtensionRuntimeSession
    private let errorObservation: ExtensionContextErrorObservation
    private let diagnostics: ExtensionRuntimeDiagnostics
    private let actionPopups: ExtensionActionPopupRuntimeRetirement?
    private let unloadContext: @MainActor (
        WKWebExtensionController,
        WKWebExtensionContext
    ) throws -> Void
    private let isLoadedContext: @MainActor (
        WKWebExtensionController,
        WKWebExtensionContext
    ) -> Bool
    private var inFlightReceipts = Set<ExtensionContextBindingReceipt>()

    init(
        profileRuntime: ExtensionProfileRuntime,
        backgroundRuntimeState: ExtensionBackgroundRuntimeStateOwner,
        runtimeSession: ExtensionRuntimeSession,
        errorObservation: ExtensionContextErrorObservation,
        diagnostics: ExtensionRuntimeDiagnostics,
        actionPopups: ExtensionActionPopupRuntimeRetirement? = nil,
        unloadContext: @escaping @MainActor (
            WKWebExtensionController,
            WKWebExtensionContext
        ) throws -> Void = { controller, context in
            try controller.unload(context)
        },
        isLoadedContext: @escaping @MainActor (
            WKWebExtensionController,
            WKWebExtensionContext
        ) -> Bool = { controller, context in
            controller.extensionContexts.contains(where: { $0 === context })
        }
    ) {
        self.profileRuntime = profileRuntime
        self.backgroundRuntimeState = backgroundRuntimeState
        self.runtimeSession = runtimeSession
        self.errorObservation = errorObservation
        self.diagnostics = diagnostics
        self.actionPopups = actionPopups
        self.unloadContext = unloadContext
        self.isLoadedContext = isLoadedContext
    }

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
        guard isLoadedContext(controller, context) else {
            return completeRetirement(
                context: context,
                receipt: receipt,
                phase: "beforeWebKitLoad"
            )
        }

        do {
            try unloadContext(controller, context)
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

        runtimeSession.extensionRuntimeResidencyState.remove(
            extensionId: key.extensionId,
            profileId: key.profileId
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

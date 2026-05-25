//
//  ChromeMV3ControllerLoadOwner.swift
//  Sumi
//
//  The only DEBUG/internal owner that may call WKWebExtensionController.load(_:)
//  for a minimal inert fixture. This does not expose Chrome MV3 runtime.
//

#if DEBUG
import Foundation
import WebKit

@available(macOS 15.5, *)
final class ChromeMV3ControllerLoadOwner {
    private let gateDecision: ChromeMV3ControllerLoadGateDecision
    private var loadedController: WKWebExtensionController?
    private var loadedContext: WKWebExtensionContext?
    private var lastError: ChromeMV3ExtensionObjectProbeErrorDiagnostic?
    private var lastUnloadError: ChromeMV3ExtensionObjectProbeErrorDiagnostic?
    private var controllerLoadCount = 0
    private var controllerUnloadAttempted = false
    private var contextUnloadedFromController = false
    private(set) var state: ChromeMV3ControllerLoadOwnerState = .notAttempted

    @MainActor
    init(gateDecision: ChromeMV3ControllerLoadGateDecision) {
        self.gateDecision = gateDecision
    }

    @MainActor
    @discardableResult
    func loadContextIntoControllerIfAllowed(
        emptyControllerOwner: ChromeMV3EmptyControllerOwner?,
        detachedContextOwner: ChromeMV3DetachedContextOwner?,
        acceptedWebExtension: WKWebExtension?
    ) -> ChromeMV3ControllerLoadOwnerDiagnostics {
        guard gateDecision.loadAttemptAllowed else {
            state = .blocked
            return diagnostics()
        }

        guard let controller = emptyControllerOwner?.controller else {
            state = .failed
            lastError = errorDiagnostic(
                code: 1,
                description:
                    "Controller load was allowed by the gate, but no empty WKWebExtensionController owner was supplied."
            )
            return diagnostics()
        }
        guard let context = detachedContextOwner?.detachedContext else {
            state = .failed
            lastError = errorDiagnostic(
                code: 2,
                description:
                    "Controller load was allowed by the gate, but no detached WKWebExtensionContext was supplied."
            )
            return diagnostics()
        }
        guard let acceptedWebExtension else {
            state = .failed
            lastError = errorDiagnostic(
                code: 3,
                description:
                    "Controller load was allowed by the gate, but no accepted WKWebExtension object was supplied."
            )
            return diagnostics()
        }
        guard context.webExtension === acceptedWebExtension else {
            state = .failed
            lastError = errorDiagnostic(
                code: 4,
                description:
                    "Detached WKWebExtensionContext is not associated with the accepted WKWebExtension object."
            )
            return diagnostics()
        }
        guard context.isLoaded == false,
              context.webExtensionController == nil
        else {
            state = .failed
            lastError = errorDiagnostic(
                code: 5,
                description:
                    "Detached WKWebExtensionContext was already loaded before the controller-load probe."
            )
            return diagnostics()
        }
        guard controller.extensionContexts.isEmpty,
              controller.extensions.isEmpty
        else {
            state = .failed
            lastError = errorDiagnostic(
                code: 6,
                description:
                    "WKWebExtensionController was not empty before the controller-load probe."
            )
            return diagnostics()
        }

        state = .loadingAttempted
        controllerLoadCount += 1
        loadedController = controller
        loadedContext = context

        do {
            try controller.load(context)
        } catch {
            state = .failed
            lastError = ChromeMV3ExtensionObjectProbeErrorDiagnostic(
                error: error
            )
            return diagnostics()
        }

        let loaded = context.isLoaded
            && context.webExtensionController === controller
            && controller.extensionContexts.contains(context)
            && controller.extensions.contains(acceptedWebExtension)
        guard loaded else {
            state = .failed
            lastError = errorDiagnostic(
                code: 7,
                description:
                    "WKWebExtensionController.load(_:) returned without a matching loaded context identity."
            )
            return diagnostics()
        }

        state = .loadedIntoController
        lastError = nil
        return diagnostics()
    }

    @MainActor
    @discardableResult
    func unloadIfNeeded() -> ChromeMV3ControllerLoadOwnerDiagnostics {
        guard let controller = loadedController,
              let context = loadedContext,
              context.isLoaded
        else {
            if state == .loadedIntoController {
                state = .unloaded
            }
            return diagnostics()
        }

        controllerUnloadAttempted = true
        do {
            try controller.unload(context)
            contextUnloadedFromController =
                context.isLoaded == false
                    && context.webExtensionController == nil
            state = .unloaded
            lastUnloadError = nil
        } catch {
            state = .failed
            lastUnloadError =
                ChromeMV3ExtensionObjectProbeErrorDiagnostic(error: error)
        }
        return diagnostics()
    }

    @MainActor
    @discardableResult
    func tearDown() -> ChromeMV3ControllerLoadOwnerDiagnostics {
        _ = unloadIfNeeded()
        loadedController = nil
        loadedContext = nil
        state = .teardownComplete
        return diagnostics()
    }

    @MainActor
    func diagnostics() -> ChromeMV3ControllerLoadOwnerDiagnostics {
        let loaded = loadedController != nil
            && loadedContext?.isLoaded == true
            && loadedContext?.webExtensionController === loadedController
        return ChromeMV3ControllerLoadOwnerDiagnostics.make(
            state: state,
            gateDecision: gateDecision,
            controllerLoadAttempted:
                state == .loadingAttempted
                    || state == .loadedIntoController
                    || state == .failed
                    || controllerLoadCount > 0,
            contextLoadedIntoController:
                state == .loadedIntoController && loaded,
            controllerLoadCount: controllerLoadCount,
            controllerUnloadAttempted: controllerUnloadAttempted,
            contextUnloadedFromController: contextUnloadedFromController,
            teardownComplete: state == .teardownComplete,
            webKitError: lastError,
            unloadError: lastUnloadError
        )
    }

    private func errorDiagnostic(
        code: Int,
        description: String
    ) -> ChromeMV3ExtensionObjectProbeErrorDiagnostic {
        ChromeMV3ExtensionObjectProbeErrorDiagnostic(
            nsError: NSError(
                domain: "Sumi.ChromeMV3ControllerLoadOwner",
                code: code,
                userInfo: [
                    NSLocalizedDescriptionKey: description,
                ]
            )
        )
    }
}

#endif

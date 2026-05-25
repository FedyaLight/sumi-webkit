//
//  ChromeMV3DetachedContextOwner.swift
//  Sumi
//
//  DEBUG/internal owner for a detached WKWebExtensionContext object. It never
//  loads the context into WKWebExtensionController and never executes extension
//  code.
//

#if DEBUG
import Foundation
import WebKit

@available(macOS 15.5, *)
final class ChromeMV3DetachedContextOwner {
    private let gateDecision: ChromeMV3ContextCreationGateDecision
    private var contextStorage: WKWebExtensionContext?
    private var lastError: ChromeMV3ExtensionObjectProbeErrorDiagnostic?
    private(set) var state: ChromeMV3ContextCreationOwnerState = .notCreated

    @MainActor
    init(gateDecision: ChromeMV3ContextCreationGateDecision) {
        self.gateDecision = gateDecision
    }

    @MainActor
    var contextObjectCreated: Bool {
        contextStorage != nil
    }

    @MainActor
    var detachedContext: WKWebExtensionContext? {
        contextStorage
    }

    @MainActor
    @discardableResult
    func createDetachedContextIfAllowed(
        acceptedWebExtension: WKWebExtension?
    ) -> ChromeMV3DetachedContextOwnerDiagnostics {
        guard gateDecision.canCreateContextObjectNow else {
            state = .blocked
            return diagnostics()
        }

        guard let acceptedWebExtension else {
            state = .failed
            lastError = ChromeMV3ExtensionObjectProbeErrorDiagnostic(
                nsError: NSError(
                    domain: "Sumi.ChromeMV3DetachedContextOwner",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Detached WKWebExtensionContext creation was allowed by the gate, but no accepted WKWebExtension object was supplied.",
                    ]
                )
            )
            return diagnostics()
        }

        if state == .createdDetached, contextStorage != nil {
            return diagnostics()
        }

        guard gateDecision.input.sdkCompatibility
            .canConstructDetachedContext
        else {
            state = .failed
            lastError = ChromeMV3ExtensionObjectProbeErrorDiagnostic(
                nsError: NSError(
                    domain: "Sumi.ChromeMV3DetachedContextOwner",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "The active SDK does not expose a safe detached WKWebExtensionContext construction path.",
                        NSLocalizedFailureReasonErrorKey:
                            gateDecision.input.sdkCompatibility
                            .localSDKHeaderFinding,
                    ]
                )
            )
            return diagnostics()
        }

        let context = WKWebExtensionContext.init(for: acceptedWebExtension)
        guard context.isLoaded == false,
              nil == context.webExtensionController
        else {
            state = .failed
            contextStorage = nil
            lastError = ChromeMV3ExtensionObjectProbeErrorDiagnostic(
                nsError: NSError(
                    domain: "Sumi.ChromeMV3DetachedContextOwner",
                    code: 3,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "WKWebExtensionContext construction did not remain detached.",
                    ]
                )
            )
            return diagnostics()
        }

        contextStorage = context
        lastError = nil
        state = .createdDetached
        return diagnostics()
    }

    @MainActor
    @discardableResult
    func tearDown() -> ChromeMV3DetachedContextOwnerDiagnostics {
        contextStorage = nil
        state = .released
        return diagnostics()
    }

    @MainActor
    func diagnostics() -> ChromeMV3DetachedContextOwnerDiagnostics {
        switch state {
        case .notCreated:
            return .make(
                state: .notCreated,
                gateDecision: gateDecision,
                contextObjectCreated: false
            )
        case .blocked:
            return .make(
                state: .blocked,
                gateDecision: gateDecision,
                contextObjectCreated: false
            )
        case .createdDetached:
            guard let contextStorage else {
                return .make(
                    state: .released,
                    gateDecision: gateDecision,
                    contextObjectCreated: false,
                    error: lastError
                )
            }
            return .make(
                state:
                    contextStorage.isLoaded
                        ? .failed
                        : .createdDetached,
                gateDecision: gateDecision,
                contextObjectCreated:
                        contextStorage.isLoaded == false
                        && nil == contextStorage.webExtensionController,
                error: lastError
            )
        case .failed:
            return .make(
                state: .failed,
                gateDecision: gateDecision,
                contextObjectCreated: false,
                error: lastError
            )
        case .released:
            return .make(
                state: .released,
                gateDecision: gateDecision,
                contextObjectCreated: false,
                error: lastError
            )
        }
    }
}

@available(macOS 15.5, *)
enum ChromeMV3DetachedContextFactory {
    @MainActor
    static func makeOwner(
        gateDecision: ChromeMV3ContextCreationGateDecision,
        acceptedWebExtension: WKWebExtension?
    ) -> ChromeMV3DetachedContextOwner? {
        let owner = ChromeMV3DetachedContextOwner(
            gateDecision: gateDecision
        )
        guard gateDecision.canCreateContextObjectNow else {
            _ = owner.createDetachedContextIfAllowed(
                acceptedWebExtension: acceptedWebExtension
            )
            return nil
        }
        _ = owner.createDetachedContextIfAllowed(
            acceptedWebExtension: acceptedWebExtension
        )
        return owner
    }
}

#endif

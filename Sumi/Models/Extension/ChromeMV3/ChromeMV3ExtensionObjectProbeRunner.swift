//
//  ChromeMV3ExtensionObjectProbeRunner.swift
//  Sumi
//
//  DEBUG/internal WKWebExtension object creation probe. This file is the only
//  Chrome MV3 generated-rewritten boundary that may allocate WKWebExtension.
//  It does not create a context, load a controller, attach configurations,
//  register scripts, launch native messaging, or execute extension code.
//

#if DEBUG
import Foundation
import WebKit

@available(macOS 15.5, *)
struct ChromeMV3ExtensionObjectProbeRunnerResult {
    var webExtension: WKWebExtension?
    var diagnostics: ChromeMV3ExtensionObjectProbeDiagnostics
}

@available(macOS 15.5, *)
struct ChromeMV3ExtensionObjectProbeRunner {
    @MainActor
    func createExtensionObject(
        gateDecision: ChromeMV3ExtensionObjectProbeGateDecision
    ) async -> ChromeMV3ExtensionObjectProbeRunnerResult {
        guard gateDecision.canCreateExtensionObjectNow,
              let resourceBaseURLPath =
                gateDecision.input.resourceBaseURLPath
        else {
            return ChromeMV3ExtensionObjectProbeRunnerResult(
                webExtension: nil,
                diagnostics: .blocked(gateDecision: gateDecision)
            )
        }

        let resourceBaseURL = URL(
            fileURLWithPath: resourceBaseURLPath,
            isDirectory: true
        ).standardizedFileURL

        do {
            let webExtension = try await WKWebExtension(
                resourceBaseURL: resourceBaseURL
            )
            let parseErrors = webExtension.errors.map {
                ChromeMV3ExtensionObjectProbeErrorDiagnostic(error: $0)
            }
            return ChromeMV3ExtensionObjectProbeRunnerResult(
                webExtension: webExtension,
                diagnostics: .created(
                    gateDecision: gateDecision,
                    parseErrors: parseErrors
                )
            )
        } catch {
            return ChromeMV3ExtensionObjectProbeRunnerResult(
                webExtension: nil,
                diagnostics: .failed(
                    gateDecision: gateDecision,
                    error: ChromeMV3ExtensionObjectProbeErrorDiagnostic(
                        error: error
                    )
                )
            )
        }
    }
}

@available(macOS 15.5, *)
final class ChromeMV3ExtensionObjectProbeOwner {
    private let gateDecision: ChromeMV3ExtensionObjectProbeGateDecision
    private let runner: ChromeMV3ExtensionObjectProbeRunner
    private var webExtensionStorage: WKWebExtension?
    private var lastError: ChromeMV3ExtensionObjectProbeErrorDiagnostic?
    private var lastParseErrors: [ChromeMV3ExtensionObjectProbeErrorDiagnostic] = []
    private(set) var state: ChromeMV3ExtensionObjectProbeState = .notAttempted

    @MainActor
    init(
        gateDecision: ChromeMV3ExtensionObjectProbeGateDecision,
        runner: ChromeMV3ExtensionObjectProbeRunner =
            ChromeMV3ExtensionObjectProbeRunner()
    ) {
        self.gateDecision = gateDecision
        self.runner = runner
    }

    @MainActor
    var webExtensionObjectCreated: Bool {
        webExtensionStorage != nil
    }

    @MainActor
    func acceptedWebExtensionObjectForDetachedContext(
        objectAcceptanceReport: ChromeMV3WebKitObjectAcceptanceReport?
    ) -> WKWebExtension? {
        guard objectAcceptanceReport?.objectAcceptedByWebKit == true,
              state == .created,
              webExtensionStorage != nil,
              diagnostics().extensionObjectCreated
        else {
            return nil
        }
        return webExtensionStorage
    }

    @MainActor
    func hasAcceptedWebExtensionObjectForDetachedContext(
        objectAcceptanceReport: ChromeMV3WebKitObjectAcceptanceReport?
    ) -> Bool {
        acceptedWebExtensionObjectForDetachedContext(
            objectAcceptanceReport: objectAcceptanceReport
        ) != nil
    }

    @MainActor
    @discardableResult
    func runProbeIfAllowed() async -> ChromeMV3ExtensionObjectProbeDiagnostics {
        guard gateDecision.canCreateExtensionObjectNow else {
            state = .blocked
            return diagnostics()
        }

        if state == .created, webExtensionStorage != nil {
            return diagnostics()
        }

        let result = await runner.createExtensionObject(
            gateDecision: gateDecision
        )
        webExtensionStorage = result.webExtension
        lastError = result.diagnostics.error
        lastParseErrors = result.diagnostics.webExtensionParseErrors
        state = result.diagnostics.state
        return result.diagnostics
    }

    @MainActor
    @discardableResult
    func tearDown() -> ChromeMV3ExtensionObjectProbeDiagnostics {
        webExtensionStorage = nil
        state = .released
        return diagnostics()
    }

    @MainActor
    func diagnostics() -> ChromeMV3ExtensionObjectProbeDiagnostics {
        switch state {
        case .notAttempted:
            return .notAttempted(gateDecision: gateDecision)
        case .blocked:
            return .blocked(gateDecision: gateDecision)
        case .created:
            if webExtensionStorage != nil {
                return .created(
                    gateDecision: gateDecision,
                    parseErrors: lastParseErrors
                )
            }
            return .released(
                gateDecision: gateDecision,
                lastError: lastError,
                lastParseErrors: lastParseErrors
            )
        case .failed:
            if let lastError {
                return .failed(
                    gateDecision: gateDecision,
                    error: lastError
                )
            }
            return .failed(
                gateDecision: gateDecision,
                error: ChromeMV3ExtensionObjectProbeErrorDiagnostic(
                    nsError: NSError(
                        domain: "Sumi.ChromeMV3ExtensionObjectProbe",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "WKWebExtension object probe failed without a captured NSError.",
                        ]
                    )
                )
            )
        case .released:
            return .released(
                gateDecision: gateDecision,
                lastError: lastError,
                lastParseErrors: lastParseErrors
            )
        }
    }
}
#endif

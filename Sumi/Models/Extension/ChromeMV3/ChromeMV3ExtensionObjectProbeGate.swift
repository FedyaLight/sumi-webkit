//
//  ChromeMV3ExtensionObjectProbeGate.swift
//  Sumi
//
//  DEBUG/internal policy and diagnostics for probing WKWebExtension object
//  creation from a generated-rewritten MV3 bundle. This file is policy-only
//  and does not import WebKit.
//

import Foundation

enum ChromeMV3ExtensionObjectProbeState: String, Codable, Sendable {
    case notAttempted
    case blocked
    case created
    case failed
    case released
}

enum ChromeMV3ExtensionObjectProbeBlocker: String, Codable, CaseIterable, Sendable {
    case extensionsModuleDisabled
    case profileHostDisabled
    case explicitObjectProbeNotAllowed
    case resourceBaseURLMissing
    case generatedRewrittenBundleMissing
    case runtimeLoadabilityReportMissing
    case runtimeLoadableMissingOrTrue
    case manifestVersionNotMV3
    case contextCreationRequested
    case contextLoadingRequested
    case controllerLoadRequested
    case extensionCodeExecutionRequested
    case userScriptRegistrationRequested
    case nativeMessagingLaunchRequested

    var reason: String {
        switch self {
        case .extensionsModuleDisabled:
            return "The extensions module is disabled."
        case .profileHostDisabled:
            return "The Chrome MV3 profile host is disabled."
        case .explicitObjectProbeNotAllowed:
            return "Explicit DEBUG/internal WKWebExtension object probing is not allowed."
        case .resourceBaseURLMissing:
            return "A generated-rewritten resource base URL is required before probing WKWebExtension object creation."
        case .generatedRewrittenBundleMissing:
            return "The generated-rewritten bundle does not exist."
        case .runtimeLoadabilityReportMissing:
            return "Runtime-loadability report is missing."
        case .runtimeLoadableMissingOrTrue:
            return "runtimeLoadable must remain false for this object creation probe."
        case .manifestVersionNotMV3:
            return "Only Chrome Manifest V3 generated-rewritten bundles may be probed."
        case .contextCreationRequested:
            return "WKWebExtensionContext creation was requested, but this probe only creates a WKWebExtension object."
        case .contextLoadingRequested:
            return "Extension context loading was requested, but context loading remains blocked."
        case .controllerLoadRequested:
            return "Controller loading was requested, but the probe must not load an extension context."
        case .extensionCodeExecutionRequested:
            return "Extension code execution was requested, but the probe is diagnostic-only."
        case .userScriptRegistrationRequested:
            return "User script registration was requested, but the probe must not register scripts."
        case .nativeMessagingLaunchRequested:
            return "Native messaging launch was requested, but native messaging remains blocked."
        }
    }
}

struct ChromeMV3ExtensionObjectProbeGateInput: Codable, Equatable, Sendable {
    var extensionsModuleEnabled: Bool
    var profileHostModuleState: ChromeMV3ProfileHostModuleState
    var explicitInternalExtensionObjectProbeAllowed: Bool
    var resourceBaseURLPath: String?
    var generatedBundleID: String?
    var generatedBundleHash: String?
    var generatedRewrittenBundleExists: Bool
    var runtimeLoadabilityReportExists: Bool
    var runtimeLoadabilityReportID: String?
    var runtimeLoadabilityReportPath: String?
    var runtimeLoadabilityReportSHA256: String?
    var manifestVersion: Int?
    var runtimeLoadable: Bool?
    var staticRuntimeBlockers: [String]
    var requestedContextCreation: Bool
    var requestedContextLoading: Bool
    var requestedControllerLoad: Bool
    var requestedExtensionCodeExecution: Bool
    var requestedUserScriptRegistration: Bool
    var requestedNativeMessagingLaunch: Bool
    var staleAttachedWebViewCount: Int
}

struct ChromeMV3ExtensionObjectProbeGateDecision: Codable, Equatable, Sendable {
    var input: ChromeMV3ExtensionObjectProbeGateInput
    var canCreateExtensionObjectNow: Bool
    var canCreateContextNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var blockers: [ChromeMV3ExtensionObjectProbeBlocker]
    var blockingReasons: [String]
    var warnings: [String]

    var passed: Bool {
        canCreateExtensionObjectNow
    }
}

struct ChromeMV3ExtensionObjectProbeErrorDiagnostic:
    Codable,
    Equatable,
    Sendable
{
    var domain: String
    var code: Int
    var message: String
    var failureReason: String?
    var recoverySuggestion: String?
    var debugDescription: String
}

struct ChromeMV3ExtensionObjectProbeDiagnostics:
    Codable,
    Equatable,
    Sendable
{
    var state: ChromeMV3ExtensionObjectProbeState
    var gateDecision: ChromeMV3ExtensionObjectProbeGateDecision
    var attempted: Bool
    var blocked: Bool
    var resourceBaseURLPath: String?
    var generatedBundleID: String?
    var generatedBundleHash: String?
    var runtimeLoadabilityReportID: String?
    var runtimeLoadabilityReportPath: String?
    var runtimeLoadabilityReportSHA256: String?
    var extensionObjectCreated: Bool
    var contextCount: Int
    var controllerLoadCount: Int
    var generatedBundleLoadedIntoController: Bool
    var canCreateContextNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var extensionCodeExecuted: Bool
    var userScriptRegistrationCount: Int
    var nativeMessagingPortCount: Int
    var error: ChromeMV3ExtensionObjectProbeErrorDiagnostic?
    var webExtensionParseErrorCount: Int
    var webExtensionParseErrors: [ChromeMV3ExtensionObjectProbeErrorDiagnostic]
    var blockingReasons: [String]
    var warnings: [String]

    static func notAttempted(
        gateDecision: ChromeMV3ExtensionObjectProbeGateDecision
    ) -> ChromeMV3ExtensionObjectProbeDiagnostics {
        diagnostics(
            state: .notAttempted,
            gateDecision: gateDecision,
            attempted: false,
            extensionObjectCreated: false,
            error: nil,
            parseErrors: []
        )
    }

    static func blocked(
        gateDecision: ChromeMV3ExtensionObjectProbeGateDecision
    ) -> ChromeMV3ExtensionObjectProbeDiagnostics {
        diagnostics(
            state: .blocked,
            gateDecision: gateDecision,
            attempted: false,
            extensionObjectCreated: false,
            error: nil,
            parseErrors: []
        )
    }

    static func created(
        gateDecision: ChromeMV3ExtensionObjectProbeGateDecision,
        parseErrors: [ChromeMV3ExtensionObjectProbeErrorDiagnostic]
    ) -> ChromeMV3ExtensionObjectProbeDiagnostics {
        diagnostics(
            state: .created,
            gateDecision: gateDecision,
            attempted: true,
            extensionObjectCreated: true,
            error: nil,
            parseErrors: parseErrors
        )
    }

    static func failed(
        gateDecision: ChromeMV3ExtensionObjectProbeGateDecision,
        error: ChromeMV3ExtensionObjectProbeErrorDiagnostic
    ) -> ChromeMV3ExtensionObjectProbeDiagnostics {
        diagnostics(
            state: .failed,
            gateDecision: gateDecision,
            attempted: true,
            extensionObjectCreated: false,
            error: error,
            parseErrors: []
        )
    }

    static func released(
        gateDecision: ChromeMV3ExtensionObjectProbeGateDecision,
        lastError: ChromeMV3ExtensionObjectProbeErrorDiagnostic?,
        lastParseErrors: [ChromeMV3ExtensionObjectProbeErrorDiagnostic]
    ) -> ChromeMV3ExtensionObjectProbeDiagnostics {
        diagnostics(
            state: .released,
            gateDecision: gateDecision,
            attempted: true,
            extensionObjectCreated: false,
            error: lastError,
            parseErrors: lastParseErrors
        )
    }

    private static func diagnostics(
        state: ChromeMV3ExtensionObjectProbeState,
        gateDecision: ChromeMV3ExtensionObjectProbeGateDecision,
        attempted: Bool,
        extensionObjectCreated: Bool,
        error: ChromeMV3ExtensionObjectProbeErrorDiagnostic?,
        parseErrors: [ChromeMV3ExtensionObjectProbeErrorDiagnostic]
    ) -> ChromeMV3ExtensionObjectProbeDiagnostics {
        ChromeMV3ExtensionObjectProbeDiagnostics(
            state: state,
            gateDecision: gateDecision,
            attempted: attempted,
            blocked: state == .blocked,
            resourceBaseURLPath: gateDecision.input.resourceBaseURLPath,
            generatedBundleID: gateDecision.input.generatedBundleID,
            generatedBundleHash: gateDecision.input.generatedBundleHash,
            runtimeLoadabilityReportID:
                gateDecision.input.runtimeLoadabilityReportID,
            runtimeLoadabilityReportPath:
                gateDecision.input.runtimeLoadabilityReportPath,
            runtimeLoadabilityReportSHA256:
                gateDecision.input.runtimeLoadabilityReportSHA256,
            extensionObjectCreated: extensionObjectCreated,
            contextCount: 0,
            controllerLoadCount: 0,
            generatedBundleLoadedIntoController: false,
            canCreateContextNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            extensionCodeExecuted: false,
            userScriptRegistrationCount: 0,
            nativeMessagingPortCount: 0,
            error: error,
            webExtensionParseErrorCount: parseErrors.count,
            webExtensionParseErrors: parseErrors,
            blockingReasons: gateDecision.blockingReasons,
            warnings: gateDecision.warnings
        )
    }
}

enum ChromeMV3ExtensionObjectProbeGate {
    static func evaluate(
        input: ChromeMV3ExtensionObjectProbeGateInput
    ) -> ChromeMV3ExtensionObjectProbeGateDecision {
        var blockers: [ChromeMV3ExtensionObjectProbeBlocker] = []
        var warnings: [String] = []

        if input.extensionsModuleEnabled == false {
            blockers.append(.extensionsModuleDisabled)
        }

        if input.profileHostModuleState != .enabled {
            blockers.append(.profileHostDisabled)
        }

        if input.explicitInternalExtensionObjectProbeAllowed == false {
            blockers.append(.explicitObjectProbeNotAllowed)
        }

        if input.resourceBaseURLPath?.isEmpty != false {
            blockers.append(.resourceBaseURLMissing)
        }

        if input.generatedRewrittenBundleExists == false {
            blockers.append(.generatedRewrittenBundleMissing)
        }

        if input.runtimeLoadabilityReportExists == false {
            blockers.append(.runtimeLoadabilityReportMissing)
        }

        if input.runtimeLoadable != false {
            blockers.append(.runtimeLoadableMissingOrTrue)
        }

        if input.manifestVersion != 3 {
            blockers.append(.manifestVersionNotMV3)
        }

        if input.requestedContextCreation {
            blockers.append(.contextCreationRequested)
        }

        if input.requestedContextLoading {
            blockers.append(.contextLoadingRequested)
        }

        if input.requestedControllerLoad {
            blockers.append(.controllerLoadRequested)
        }

        if input.requestedExtensionCodeExecution {
            blockers.append(.extensionCodeExecutionRequested)
        }

        if input.requestedUserScriptRegistration {
            blockers.append(.userScriptRegistrationRequested)
        }

        if input.requestedNativeMessagingLaunch {
            blockers.append(.nativeMessagingLaunchRequested)
        }

        if input.staleAttachedWebViewCount > 0 {
            warnings.append(
                "There are \(input.staleAttachedWebViewCount) DEBUG-attached WebViews marked stale and needing recreation; the object probe does not mutate or detach them."
            )
        }

        if input.staticRuntimeBlockers.isEmpty == false {
            warnings.append(
                "Runtime-loadability blockers remain recorded; this probe may create only a WKWebExtension object and must not create or load a context."
            )
        }

        return ChromeMV3ExtensionObjectProbeGateDecision(
            input: input,
            canCreateExtensionObjectNow: blockers.isEmpty,
            canCreateContextNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            blockers: uniqueSorted(blockers),
            blockingReasons: uniqueSorted(blockers.map(\.reason)),
            warnings: uniqueSorted(warnings)
        )
    }

    private static func uniqueSorted(
        _ blockers: [ChromeMV3ExtensionObjectProbeBlocker]
    ) -> [ChromeMV3ExtensionObjectProbeBlocker] {
        Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }
}

extension ChromeMV3ExtensionObjectProbeErrorDiagnostic {
    init(error: Error) {
        self.init(nsError: error as NSError)
    }

    init(nsError: NSError) {
        self.domain = nsError.domain
        self.code = nsError.code
        self.message = nsError.localizedDescription
        self.failureReason = nsError.localizedFailureReason
        self.recoverySuggestion = nsError.localizedRecoverySuggestion
        self.debugDescription = String(reflecting: nsError)
    }
}

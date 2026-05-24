//
//  ChromeMV3ProfileHost.swift
//  Sumi
//
//  Profile-scoped Chrome MV3 host skeleton. It evaluates policy and preflight
//  only; it does not create, load, attach, register, poll, or execute runtime
//  resources.
//

import Foundation

enum ChromeMV3ProfileHostModuleState: String, Codable, Sendable {
    case enabled
    case disabled
}

enum ChromeMV3ProfileHostControllerState: String, Codable, Sendable {
    case absentNotCreated
}

enum ChromeMV3ProfileDataStoreIdentity: Codable, Equatable, Sendable {
    case profileIdentifier(String)
    case ephemeralProfileIdentifier(String)
    case placeholder(String)
    case unresolved
}

struct ChromeMV3RewrittenVariantCandidate: Codable, Equatable, Sendable {
    var id: String
    var rewrittenVariantRootPath: String
    var runtimeLoadabilityReportPath: String?
    var manifestVersion: Int?
    var rewrittenVariantExists: Bool
}

struct ChromeMV3ProfileRuntimeAllowance: Codable, Equatable, Sendable {
    var allowedForProfilePreflight: Bool
    var reason: String
    var requiredFuturePreconditions: [String]
    var canCreateControllerNow: Bool
    var canLoadContextNow: Bool
    var canAttachToNormalTabsNow: Bool
}

struct ChromeMV3ProfileHostDiagnosticsSummary: Codable, Equatable, Sendable {
    var profileIdentifier: String
    var moduleState: ChromeMV3ProfileHostModuleState
    var profileDataStoreIdentity: ChromeMV3ProfileDataStoreIdentity
    var controllerState: ChromeMV3ProfileHostControllerState
    var candidateVariantCount: Int
    var allowedForProfilePreflight: Bool
    var canCreateControllerNow: Bool
    var canLoadContextNow: Bool
    var canAttachToNormalTabsNow: Bool
    var registersUserScriptsNow: Bool
    var launchesNativeMessagingNow: Bool
    var startsBackgroundWorkNow: Bool
    var blockingReasons: [String]
    var futureRequirements: [String]
}

struct ChromeMV3ProfileHost: Codable, Equatable, Sendable {
    static let unresolvedProfileIdentifier = "unresolved-profile"

    var profileIdentifier: String
    var moduleState: ChromeMV3ProfileHostModuleState
    var profileDataStoreIdentity: ChromeMV3ProfileDataStoreIdentity
    var controllerState: ChromeMV3ProfileHostControllerState
    var candidateRewrittenVariants: [ChromeMV3RewrittenVariantCandidate]

    init(
        profileIdentifier: String,
        extensionsEnabled: Bool,
        profileDataStoreIdentity: ChromeMV3ProfileDataStoreIdentity = .unresolved,
        candidateRewrittenVariants: [ChromeMV3RewrittenVariantCandidate] = []
    ) {
        self.profileIdentifier = profileIdentifier.isEmpty
            ? Self.unresolvedProfileIdentifier
            : profileIdentifier
        self.moduleState = extensionsEnabled ? .enabled : .disabled
        self.profileDataStoreIdentity = profileDataStoreIdentity
        self.controllerState = .absentNotCreated
        self.candidateRewrittenVariants = candidateRewrittenVariants.sorted {
            $0.id < $1.id
        }
    }

    var isActive: Bool {
        moduleState == .enabled
    }

    var canCreateControllerNow: Bool {
        false
    }

    var canLoadContextNow: Bool {
        false
    }

    var canAttachToNormalTabsNow: Bool {
        false
    }

    func profileRuntimeAllowance() -> ChromeMV3ProfileRuntimeAllowance {
        if isActive == false {
            return ChromeMV3ProfileRuntimeAllowance(
                allowedForProfilePreflight: false,
                reason: "The extensions module is disabled for this profile.",
                requiredFuturePreconditions: [
                    "Enable the extensions module before Chrome MV3 runtime preflight.",
                ],
                canCreateControllerNow: false,
                canLoadContextNow: false,
                canAttachToNormalTabsNow: false
            )
        }

        return ChromeMV3ProfileRuntimeAllowance(
            allowedForProfilePreflight: true,
            reason: "The profile may evaluate Chrome MV3 preflight, but WebKit runtime loading remains blocked.",
            requiredFuturePreconditions: [
                "Clear generated-rewritten runtime blockers.",
                "Add explicit future WebKit controller creation.",
                "Add explicit future context loading.",
                "Re-evaluate normal-tab WebView eligibility before any future attachment.",
            ],
            canCreateControllerNow: false,
            canLoadContextNow: false,
            canAttachToNormalTabsNow: false
        )
    }

    func candidate(
        withID candidateID: String
    ) -> ChromeMV3RewrittenVariantCandidate? {
        candidateRewrittenVariants.first { $0.id == candidateID }
    }

    func evaluatePreflight(
        candidateID: String,
        report: ChromeMV3RuntimeLoadabilityReport?,
        surface: ChromeMV3WebViewSurface = .normalTab
    ) -> ChromeMV3RuntimePreflightResult {
        let eligibility = ChromeMV3WebViewEligibilityPolicy.evaluate(
            surface: surface,
            extensionModuleEnabled: isActive,
            profileHostActive: isActive
        )
        return ChromeMV3RuntimePreflight.evaluate(
            profileHost: self,
            candidate: candidate(withID: candidateID),
            report: report,
            webViewEligibility: eligibility
        )
    }

    func diagnosticsSummary(
        preflightResults: [ChromeMV3RuntimePreflightResult] = []
    ) -> ChromeMV3ProfileHostDiagnosticsSummary {
        let allowance = profileRuntimeAllowance()
        let preflightBlockingReasons = preflightResults
            .flatMap(\.blockingReasons)
        let preflightFutureRequirements = preflightResults
            .flatMap(\.futureRequirements)

        return ChromeMV3ProfileHostDiagnosticsSummary(
            profileIdentifier: profileIdentifier,
            moduleState: moduleState,
            profileDataStoreIdentity: profileDataStoreIdentity,
            controllerState: controllerState,
            candidateVariantCount: candidateRewrittenVariants.count,
            allowedForProfilePreflight: allowance.allowedForProfilePreflight,
            canCreateControllerNow: false,
            canLoadContextNow: false,
            canAttachToNormalTabsNow: false,
            registersUserScriptsNow: false,
            launchesNativeMessagingNow: false,
            startsBackgroundWorkNow: false,
            blockingReasons: uniqueSorted(
                [allowance.reason] + preflightBlockingReasons
            ),
            futureRequirements: uniqueSorted(
                allowance.requiredFuturePreconditions
                    + preflightFutureRequirements
            )
        )
    }

    private func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }
}

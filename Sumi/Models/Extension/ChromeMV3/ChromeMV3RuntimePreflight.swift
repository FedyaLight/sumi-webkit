//
//  ChromeMV3RuntimePreflight.swift
//  Sumi
//
//  Non-loading preflight for generated-rewritten Chrome MV3 variants.
//  This layer reports future requirements only; it does not create or load
//  WebKit extension runtime objects.
//

import Foundation

enum ChromeMV3RuntimePreflightCheck: String, Codable, CaseIterable, Sendable {
    case reportExists
    case runtimeLoadableRemainsFalse
    case manifestVersionIsMV3
    case rewrittenVariantExists
    case runtimeTemplatesExist
    case blockersRecorded
    case unsupportedAndDeferredAPIsRepresented
    case futureWebKitPreconditionsRemainUnsatisfied
    case profileHostEnabled
    case normalTabFutureEligibility
}

struct ChromeMV3RuntimePreflightCheckResult: Codable, Equatable, Sendable {
    var check: ChromeMV3RuntimePreflightCheck
    var passed: Bool
    var message: String
}

struct ChromeMV3RuntimePreflightResult: Codable, Equatable, Sendable {
    var candidateID: String?
    var consumedRuntimeLoadabilityReport: Bool
    var runtimeLoadable: Bool?
    var checks: [ChromeMV3RuntimePreflightCheckResult]
    var canCreateControllerNow: Bool
    var canLoadContextNow: Bool
    var canAttachToNormalTabsNow: Bool
    var normalTabFutureEligible: Bool
    var blockingReasons: [String]
    var futureRequirements: [String]
}

enum ChromeMV3RuntimePreflight {
    static func evaluate(
        profileHost: ChromeMV3ProfileHost,
        candidate: ChromeMV3RewrittenVariantCandidate?,
        report: ChromeMV3RuntimeLoadabilityReport?,
        webViewEligibility: ChromeMV3WebViewEligibility
    ) -> ChromeMV3RuntimePreflightResult {
        let reportChecks = Set(report?.verificationChecks.map(\.category) ?? [])
        var checks: [ChromeMV3RuntimePreflightCheckResult] = []
        var blockingReasons: [String] = []
        var futureRequirements: [String] = []

        append(
            &checks,
            check: .reportExists,
            passed: report != nil,
            message: report == nil
                ? "Runtime-loadability report is missing."
                : "Runtime-loadability report is present."
        )
        if report == nil {
            blockingReasons.append("Runtime-loadability report is missing.")
            futureRequirements.append("Write and review the static runtime-loadability report for the generated-rewritten variant.")
        }

        let runtimeLoadableRemainsFalse = report?.runtimeLoadable == false
        append(
            &checks,
            check: .runtimeLoadableRemainsFalse,
            passed: runtimeLoadableRemainsFalse,
            message: runtimeLoadableRemainsFalse
                ? "runtimeLoadable remains false."
                : "runtimeLoadable is missing or no longer false."
        )
        if runtimeLoadableRemainsFalse == false {
            blockingReasons.append("runtimeLoadable must remain false in this non-loading host skeleton.")
        }

        let manifestIsMV3 = candidate?.manifestVersion == 3
            || report?.passedChecks.contains(.manifestShape) == true
        append(
            &checks,
            check: .manifestVersionIsMV3,
            passed: manifestIsMV3,
            message: manifestIsMV3
                ? "The generated-rewritten variant is represented as Chrome Manifest V3."
                : "The generated-rewritten variant is not represented as Chrome Manifest V3."
        )
        if manifestIsMV3 == false {
            blockingReasons.append("Only Chrome Manifest V3 candidates can enter runtime preflight.")
        }

        let variantExists = candidate?.rewrittenVariantExists == true
            || report?.generatedVariantRootPath.isEmpty == false
        append(
            &checks,
            check: .rewrittenVariantExists,
            passed: variantExists,
            message: variantExists
                ? "Generated-rewritten variant metadata is present."
                : "Generated-rewritten variant metadata is missing."
        )
        if variantExists == false {
            blockingReasons.append("Generated-rewritten variant must exist before future WebKit loading can be considered.")
        }

        let runtimeTemplatesExist = report?.runtimeTemplateFileHashes.isEmpty == false
        append(
            &checks,
            check: .runtimeTemplatesExist,
            passed: runtimeTemplatesExist,
            message: runtimeTemplatesExist
                ? "Runtime template file hashes are represented."
                : "Runtime template file hashes are missing."
        )
        if runtimeTemplatesExist == false {
            blockingReasons.append("Inert runtime template files must be represented before future loading can be considered.")
        }

        let blockersRecorded = report?.blockers.isEmpty == false
        append(
            &checks,
            check: .blockersRecorded,
            passed: blockersRecorded,
            message: blockersRecorded
                ? "Runtime blockers are recorded."
                : "Runtime blockers are missing."
        )
        if blockersRecorded == false {
            blockingReasons.append("Blocking reasons must be explicit while loading remains disabled.")
        }
        blockingReasons.append(contentsOf: report?.blockers ?? [])

        let unsupportedAndDeferredRepresented =
            reportChecks.contains(.unsupportedAPIs)
            && reportChecks.contains(.deferredAPIs)
        append(
            &checks,
            check: .unsupportedAndDeferredAPIsRepresented,
            passed: unsupportedAndDeferredRepresented,
            message: unsupportedAndDeferredRepresented
                ? "Unsupported and deferred API classifications are represented."
                : "Unsupported or deferred API classifications are missing."
        )
        if unsupportedAndDeferredRepresented == false {
            blockingReasons.append("Unsupported and deferred API classifications must be represented before preflight can proceed.")
        }

        let webKitPreconditionsBlocked =
            report?.deferredChecks.contains(.WebKitRuntimeNotWired) == true
            || report?.requiredFutureRuntimeComponents.contains {
                $0.localizedCaseInsensitiveContains("WebKit")
            } == true
        append(
            &checks,
            check: .futureWebKitPreconditionsRemainUnsatisfied,
            passed: webKitPreconditionsBlocked,
            message: webKitPreconditionsBlocked
                ? "Future WebKit loading preconditions remain unsatisfied."
                : "Future WebKit loading preconditions are not represented as blocked."
        )
        if webKitPreconditionsBlocked == false {
            blockingReasons.append("Future WebKit loading preconditions must remain blocked in this prompt.")
        }
        futureRequirements.append(contentsOf: report?.requiredFutureRuntimeComponents ?? [])

        append(
            &checks,
            check: .profileHostEnabled,
            passed: profileHost.isActive,
            message: profileHost.isActive
                ? "Profile host is enabled for preflight evaluation."
                : "Profile host is disabled."
        )
        if profileHost.isActive == false {
            blockingReasons.append("Chrome MV3 profile host is disabled for this profile.")
            futureRequirements.append("Enable the extensions module and create an active profile host before future loading.")
        }

        let normalTabFutureEligible = webViewEligibility.isFutureEligibleForNormalBrowsing
        append(
            &checks,
            check: .normalTabFutureEligibility,
            passed: normalTabFutureEligible,
            message: normalTabFutureEligible
                ? "The WebView surface is future-eligible for normal browsing."
                : "The WebView surface is not future-eligible for normal browsing."
        )
        if normalTabFutureEligible == false {
            blockingReasons.append(webViewEligibility.reason)
        }
        futureRequirements.append(contentsOf: webViewEligibility.requiredFuturePreconditions)

        blockingReasons.append("Controller creation is intentionally blocked by the non-loading host skeleton.")
        blockingReasons.append("Context loading is intentionally blocked by the non-loading host skeleton.")
        blockingReasons.append("Normal-tab attachment is intentionally blocked by the non-loading host skeleton.")

        return ChromeMV3RuntimePreflightResult(
            candidateID: candidate?.id,
            consumedRuntimeLoadabilityReport: report != nil,
            runtimeLoadable: report?.runtimeLoadable,
            checks: checks.sorted { $0.check.rawValue < $1.check.rawValue },
            canCreateControllerNow: false,
            canLoadContextNow: false,
            canAttachToNormalTabsNow: false,
            normalTabFutureEligible: normalTabFutureEligible,
            blockingReasons: uniqueSorted(blockingReasons),
            futureRequirements: uniqueSorted(futureRequirements)
        )
    }

    private static func append(
        _ checks: inout [ChromeMV3RuntimePreflightCheckResult],
        check: ChromeMV3RuntimePreflightCheck,
        passed: Bool,
        message: String
    ) {
        checks.append(
            ChromeMV3RuntimePreflightCheckResult(
                check: check,
                passed: passed,
                message: message
            )
        )
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }
}

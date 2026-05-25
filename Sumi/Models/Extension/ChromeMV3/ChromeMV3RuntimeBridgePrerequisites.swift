//
//  ChromeMV3RuntimeBridgePrerequisites.swift
//  Sumi
//
//  Deterministic prerequisite model for the addRuntimeBridgePrerequisites
//  branch. This layer records non-executing future-runtime requirements only;
//  it does not import WebKit, create contexts, load controllers, inject
//  scripts, launch native messaging, or execute extension code.
//

import Foundation

enum ChromeMV3RuntimeBridgePrerequisiteCategory:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case runtimeMessaging
    case nativeMessaging
    case storage
    case permissionsAndActiveTab
    case serviceWorkerLifecycle
    case contextCreationDeferred
    case controllerLoadingDeferred

    static func < (
        lhs: ChromeMV3RuntimeBridgePrerequisiteCategory,
        rhs: ChromeMV3RuntimeBridgePrerequisiteCategory
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3RuntimeBridgePrerequisite:
    Codable,
    Equatable,
    Sendable
{
    var category: ChromeMV3RuntimeBridgePrerequisiteCategory
    var required: Bool
    var blockers: [String]
    var requiredFutureAction: String
    var nonExecuting: Bool
}

struct ChromeMV3RuntimeBridgePrerequisitePlan:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var sourceContextReadinessReportID: String
    var sourceContextReadinessReportPath: String
    var nextRequiredPromptCategory:
        ChromeMV3ContextReadinessNextPromptCategory?
    var canRecordPrerequisitesNow: Bool
    var branchImplemented:
        ChromeMV3ContextReadinessNextPromptCategory?
    var prerequisites: [ChromeMV3RuntimeBridgePrerequisite]
    var runtimeLoadable: Bool
    var canLoadContextNow: Bool
    var contextCreationAllowed: Bool
    var controllerLoadAllowed: Bool
    var extensionCodeExecutionAllowed: Bool
    var userScriptRegistrationAllowed: Bool
    var nativeMessagingLaunchAllowed: Bool
    var blockingReasons: [String]
    var warnings: [String]
}

enum ChromeMV3RuntimeBridgePrerequisitePlanner {
    static func plan(
        report: ChromeMV3ContextReadinessReport,
        consumptionDiagnostic:
            ChromeMV3ContextReadinessReportConsumptionDiagnostic
    ) -> ChromeMV3RuntimeBridgePrerequisitePlan {
        let branch =
            consumptionDiagnostic.nextRequiredPromptCategory
        var blockers: [String] = []
        var warnings: [String] = [
            "Runtime bridge prerequisites are diagnostic models only; Sumi still does not claim Chrome MV3 runtime support.",
        ]

        if consumptionDiagnostic.state != .ready
            || consumptionDiagnostic.canImplementRecommendedBranch == false
        {
            blockers.append(
                "Generated context-readiness report was not consumed successfully."
            )
        }

        if branch != .addRuntimeBridgePrerequisites {
            blockers.append(
                "Generated context-readiness report did not select addRuntimeBridgePrerequisites."
            )
        }

        if report.runtimeLoadable {
            blockers.append("runtimeLoadable must remain false.")
        }

        if report.canLoadContextNow {
            blockers.append("canLoadContextNow must remain false.")
        }

        let prerequisites = [
            prerequisite(
                category: .runtimeMessaging,
                blockers: report.runtimeBlockers.runtimeMessagingBlockers,
                action: "Model the future runtime messaging bridge contract without wiring message dispatch."
            ),
            prerequisite(
                category: .nativeMessaging,
                blockers: report.runtimeBlockers.nativeMessagingBlockers,
                action: "Model native messaging validation, consent, and lifecycle prerequisites without launching a host."
            ),
            prerequisite(
                category: .storage,
                blockers: report.runtimeBlockers.storageBlockers,
                action: "Model storage behavior prerequisites without enabling extension storage APIs."
            ),
            prerequisite(
                category: .permissionsAndActiveTab,
                blockers: report.runtimeBlockers
                    .permissionActiveTabBlockers,
                action: "Model permission broker and activeTab prerequisites without granting runtime permissions."
            ),
            prerequisite(
                category: .serviceWorkerLifecycle,
                blockers: report.runtimeBlockers
                    .serviceWorkerLifecycleBlockers,
                action: "Model service-worker lifecycle checks without waking or loading a worker."
            ),
            prerequisite(
                category: .contextCreationDeferred,
                blockers: [
                    "WKWebExtensionContext creation remains deferred until a generated report selects addContextCreationGate.",
                ],
                action: "Keep context construction behind a future generated addContextCreationGate report."
            ),
            prerequisite(
                category: .controllerLoadingDeferred,
                blockers: [
                    "WKWebExtensionController loading remains deferred until a later verified loading prompt.",
                ],
                action: "Keep controller loading absent until context and runtime behavior are separately verified."
            ),
        ].sorted { lhs, rhs in
            lhs.category < rhs.category
        }

        if prerequisites.filter(\.required).isEmpty {
            warnings.append(
                "No concrete runtime bridge blocker arrays were present; only deferred context/loading prerequisites were recorded."
            )
        }

        return ChromeMV3RuntimeBridgePrerequisitePlan(
            schemaVersion: 1,
            sourceContextReadinessReportID: report.id,
            sourceContextReadinessReportPath:
                consumptionDiagnostic.reportPath,
            nextRequiredPromptCategory: branch,
            canRecordPrerequisitesNow: blockers.isEmpty,
            branchImplemented:
                blockers.isEmpty ? .addRuntimeBridgePrerequisites : nil,
            prerequisites: prerequisites,
            runtimeLoadable: false,
            canLoadContextNow: false,
            contextCreationAllowed: false,
            controllerLoadAllowed: false,
            extensionCodeExecutionAllowed: false,
            userScriptRegistrationAllowed: false,
            nativeMessagingLaunchAllowed: false,
            blockingReasons: uniqueSorted(blockers),
            warnings: uniqueSorted(warnings)
        )
    }

    private static func prerequisite(
        category: ChromeMV3RuntimeBridgePrerequisiteCategory,
        blockers: [String],
        action: String
    ) -> ChromeMV3RuntimeBridgePrerequisite {
        ChromeMV3RuntimeBridgePrerequisite(
            category: category,
            required: blockers.isEmpty == false,
            blockers: uniqueSorted(blockers),
            requiredFutureAction: action,
            nonExecuting: true
        )
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }
}

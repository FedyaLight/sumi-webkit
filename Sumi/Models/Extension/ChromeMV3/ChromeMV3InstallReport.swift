//
//  ChromeMV3InstallReport.swift
//  Sumi
//
//  Structured install-time report models for Chrome MV3 manifests.
//

import Foundation

enum ChromeMV3InstallIssueSeverity: String, Codable, CaseIterable {
    case warning
    case fatal
}

struct ChromeMV3InstallIssue: Codable, Equatable {
    var severity: ChromeMV3InstallIssueSeverity
    var code: String
    var message: String
    var field: String?
}

struct ChromeMV3PasswordManagerFeatureReport: Codable, Equatable {
    var contentScripts: Bool
    var allFrames: Bool
    var matchAboutBlank: Bool
    var runtimeMessaging: Bool
    var nativeMessaging: Bool
    var actionPopup: Bool
    var storage: Bool
    var hostPermissions: Bool
}

struct ChromeMV3InstallNetworkCompatibilitySummary: Codable, Equatable {
    var declaresDeclarativeNetRequest: Bool
    var staticRulesetResourceCount: Int
    var declaresWebRequest: Bool
    var declaresWebRequestBlocking: Bool
    var declaresWebRequestAuthProvider: Bool
    var hostPermissionCount: Int
    var dnrAvailableInInternalEvaluator: Bool
    var dnrAvailableInProduct: Bool
    var dnrProductEnforcementAvailable: Bool
    var webRequestAvailableInInternalFixture: Bool
    var webRequestBlockingAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
}

struct ChromeMV3ManifestSummary: Codable, Equatable {
    var manifestVersion: Int
    var name: String
    var version: String
    var description: String?
    var backgroundServiceWorker: String?
    var backgroundType: String?
    var permissions: [String]
    var optionalPermissions: [String]
    var hostPermissions: [String]
    var contentScriptCount: Int
    var hasAction: Bool
    var hasOptionsPage: Bool
    var webAccessibleResourceCount: Int
    var hasExternallyConnectable: Bool
    var hasDeclarativeNetRequest: Bool
    var hasSidePanel: Bool
    var commandCount: Int
    var minimumChromeVersion: String?
    var hasBrowserSpecificSettings: Bool
}

struct ChromeMV3InstallReport: Codable, Equatable {
    var manifestSummary: ChromeMV3ManifestSummary?
    var packageMetadata: ChromeMV3PackageMetadata?
    var detectedAPIs: [ChromeMV3API]
    var supportedAPIs: [ChromeMV3API]
    var shimmedAPIs: [ChromeMV3API]
    var nativeHostAPIs: [ChromeMV3API]
    var deferredAPIs: [ChromeMV3API]
    var unsupportedAPIs: [ChromeMV3API]
    var needsVerificationAPIs: [ChromeMV3API]
    var capabilityClassifications: [ChromeMV3CapabilityClassification]
    var warnings: [ChromeMV3InstallIssue]
    var fatalValidationErrors: [ChromeMV3InstallIssue]
    var passwordManagerFeatures: ChromeMV3PasswordManagerFeatureReport
    var networkCompatibilitySummary:
        ChromeMV3InstallNetworkCompatibilitySummary

    var isValid: Bool {
        fatalValidationErrors.isEmpty
    }
}

enum ChromeMV3InstallReporter {
    static func report(
        for manifest: ChromeMV3Manifest,
        packageMetadata: ChromeMV3PackageMetadata? = nil,
        validationWarnings: [ChromeMV3InstallIssue] = []
    ) -> ChromeMV3InstallReport {
        let classifications = ChromeMV3CapabilityClassifier.classify(
            manifest: manifest
        )
        let warnings = (
            validationWarnings + capabilityWarnings(
                classifications: classifications,
                manifest: manifest
            )
        ).sorted { lhs, rhs in
            if lhs.code == rhs.code {
                return (lhs.field ?? "") < (rhs.field ?? "")
            }
            return lhs.code < rhs.code
        }

        return ChromeMV3InstallReport(
            manifestSummary: summary(for: manifest),
            packageMetadata: packageMetadata,
            detectedAPIs: classifications.map(\.api).sorted(),
            supportedAPIs: apis(
                in: classifications,
                matching: .nativeWebKit
            ),
            shimmedAPIs: apis(in: classifications, matching: .shim),
            nativeHostAPIs: apis(in: classifications, matching: .nativeHost),
            deferredAPIs: apis(in: classifications, matching: .deferred),
            unsupportedAPIs: apis(in: classifications, matching: .unsupported),
            needsVerificationAPIs: apis(
                in: classifications,
                matching: .needsVerification
            ),
            capabilityClassifications: classifications,
            warnings: warnings,
            fatalValidationErrors: [],
            passwordManagerFeatures: passwordManagerFeatures(for: manifest),
            networkCompatibilitySummary:
                networkCompatibilitySummary(for: manifest)
        )
    }

    static func fatalReport(
        error: Error,
        packageMetadata: ChromeMV3PackageMetadata? = nil
    ) -> ChromeMV3InstallReport {
        ChromeMV3InstallReport(
            manifestSummary: nil,
            packageMetadata: packageMetadata,
            detectedAPIs: [],
            supportedAPIs: [],
            shimmedAPIs: [],
            nativeHostAPIs: [],
            deferredAPIs: [],
            unsupportedAPIs: [],
            needsVerificationAPIs: [],
            capabilityClassifications: [],
            warnings: [],
            fatalValidationErrors: [issue(for: error)],
            passwordManagerFeatures: ChromeMV3PasswordManagerFeatureReport(
                contentScripts: false,
                allFrames: false,
                matchAboutBlank: false,
                runtimeMessaging: false,
                nativeMessaging: false,
                actionPopup: false,
                storage: false,
                hostPermissions: false
            ),
            networkCompatibilitySummary:
                ChromeMV3InstallNetworkCompatibilitySummary(
                    declaresDeclarativeNetRequest: false,
                    staticRulesetResourceCount: 0,
                    declaresWebRequest: false,
                    declaresWebRequestBlocking: false,
                    declaresWebRequestAuthProvider: false,
                    hostPermissionCount: 0,
                    dnrAvailableInInternalEvaluator: false,
                    dnrAvailableInProduct: false,
                    dnrProductEnforcementAvailable: false,
                    webRequestAvailableInInternalFixture: false,
                    webRequestBlockingAvailableInProduct: false,
                    normalTabRuntimeBridgeAvailable: false,
                    runtimeLoadable: false
                )
        )
    }

    private static func summary(
        for manifest: ChromeMV3Manifest
    ) -> ChromeMV3ManifestSummary {
        ChromeMV3ManifestSummary(
            manifestVersion: manifest.manifestVersion,
            name: manifest.name,
            version: manifest.version,
            description: manifest.description,
            backgroundServiceWorker: manifest.background?.serviceWorker,
            backgroundType: manifest.background?.type,
            permissions: manifest.permissions,
            optionalPermissions: manifest.optionalPermissions,
            hostPermissions: manifest.hostPermissions,
            contentScriptCount: manifest.contentScripts.count,
            hasAction: manifest.action != nil,
            hasOptionsPage: manifest.optionsPage != nil
                || manifest.optionsUI?.page != nil,
            webAccessibleResourceCount: manifest.webAccessibleResources.count,
            hasExternallyConnectable: manifest.externallyConnectable != nil,
            hasDeclarativeNetRequest: manifest.declarativeNetRequest != nil,
            hasSidePanel: manifest.sidePanel != nil,
            commandCount: manifest.commands.count,
            minimumChromeVersion: manifest.minimumChromeVersion,
            hasBrowserSpecificSettings: manifest.browserSpecificSettings.isEmpty == false
        )
    }

    private static func apis(
        in classifications: [ChromeMV3CapabilityClassification],
        matching status: ChromeMV3CapabilityStatus
    ) -> [ChromeMV3API] {
        classifications
            .filter { $0.statuses.contains(status) }
            .map(\.api)
            .sorted()
    }

    private static func capabilityWarnings(
        classifications: [ChromeMV3CapabilityClassification],
        manifest: ChromeMV3Manifest
    ) -> [ChromeMV3InstallIssue] {
        var warnings: [ChromeMV3InstallIssue] = []

        for classification in classifications {
            if classification.statuses.contains(.unsupported) {
                warnings.append(
                    ChromeMV3InstallIssue(
                        severity: .warning,
                        code: "unsupportedAPI",
                        message: "\(classification.api.rawValue) is not supported by the Chrome MV3 foundation.",
                        field: classification.api.rawValue
                    )
                )
            }

            if classification.statuses.contains(.deferred) {
                warnings.append(
                    ChromeMV3InstallIssue(
                        severity: .warning,
                        code: "deferredAPI",
                        message: "\(classification.api.rawValue) is deferred until a future runtime task.",
                        field: classification.api.rawValue
                    )
                )
            }

            if classification.statuses.contains(.needsVerification) {
                warnings.append(
                    ChromeMV3InstallIssue(
                        severity: .warning,
                        code: "needsFixtureVerification",
                        message: "\(classification.api.rawValue) requires fixture verification before Sumi can claim Chrome parity.",
                        field: classification.api.rawValue
                    )
                )
            }
        }

        if manifest.browserSpecificSettings.isEmpty == false {
            warnings.append(
                ChromeMV3InstallIssue(
                    severity: .warning,
                    code: "browserSpecificSettingsMetadataOnly",
                    message: "browser_specific_settings is retained as compatibility metadata only and does not imply Safari product support.",
                    field: "browser_specific_settings"
                )
            )
        }

        if manifest.declaresPermission("webRequestBlocking") {
            warnings.append(
                ChromeMV3InstallIssue(
                    severity: .warning,
                    code: "webRequestBlockingProductBlocked",
                    message: "Blocking webRequest assumptions are product-blocked; only synthetic compatibility diagnostics are available.",
                    field: "permissions.webRequestBlocking"
                )
            )
        }

        if manifest.declaresPermission("webRequest") {
            warnings.append(
                ChromeMV3InstallIssue(
                    severity: .warning,
                    code: "webRequestObservableSyntheticOnly",
                    message: "webRequest is classified for internal synthetic observation only; Sumi does not subscribe to product network events.",
                    field: "permissions.webRequest"
                )
            )
        }

        if let dnr = manifest.declarativeNetRequest {
            warnings.append(
                ChromeMV3InstallIssue(
                    severity: .warning,
                    code: "dnrSyntheticEvaluatorOnly",
                    message: "declarativeNetRequest rules can be parsed/evaluated internally, but product DNR enforcement is unavailable.",
                    field: "declarative_net_request"
                )
            )
            for (index, resource) in dnr.ruleResources.enumerated() {
                if resource.id?.isEmpty ?? true {
                    warnings.append(
                        ChromeMV3InstallIssue(
                            severity: .warning,
                            code: "dnrRulesetMissingID",
                            message: "DNR static ruleset resource is missing a deterministic id.",
                            field:
                                "declarative_net_request.rule_resources[\(index)].id"
                        )
                    )
                }
                if resource.path?.isEmpty ?? true {
                    warnings.append(
                        ChromeMV3InstallIssue(
                            severity: .warning,
                            code: "dnrRulesetMissingPath",
                            message: "DNR static ruleset resource is missing a path.",
                            field:
                                "declarative_net_request.rule_resources[\(index)].path"
                        )
                    )
                }
            }
        }

        return warnings
    }

    private static func passwordManagerFeatures(
        for manifest: ChromeMV3Manifest
    ) -> ChromeMV3PasswordManagerFeatureReport {
        let hasContentScripts = manifest.contentScripts.isEmpty == false
        let hasServiceWorker = manifest.background?.serviceWorker != nil
        let hasExternallyConnectable = manifest.externallyConnectable != nil

        return ChromeMV3PasswordManagerFeatureReport(
            contentScripts: hasContentScripts,
            allFrames: manifest.contentScripts.contains { $0.allFrames },
            matchAboutBlank: manifest.contentScripts.contains { $0.matchAboutBlank },
            runtimeMessaging: (hasContentScripts && hasServiceWorker)
                || hasExternallyConnectable,
            nativeMessaging: manifest.declaresPermission("nativeMessaging"),
            actionPopup: manifest.action?.defaultPopup != nil,
            storage: manifest.declaresPermission("storage"),
            hostPermissions: manifest.hostPermissions.isEmpty == false
        )
    }

    private static func networkCompatibilitySummary(
        for manifest: ChromeMV3Manifest
    ) -> ChromeMV3InstallNetworkCompatibilitySummary {
        let declaresDNR = manifest.declarativeNetRequest != nil
            || manifest.declaresPermission("declarativeNetRequest")
            || manifest.declaresPermission("declarativeNetRequestWithHostAccess")
            || manifest.declaresPermission("declarativeNetRequestFeedback")
        let declaresWebRequest = manifest.declaresPermission("webRequest")
        let declaresWebRequestBlocking =
            manifest.declaresPermission("webRequestBlocking")
        let declaresWebRequestAuth =
            manifest.declaresPermission("webRequestAuthProvider")
        return ChromeMV3InstallNetworkCompatibilitySummary(
            declaresDeclarativeNetRequest: declaresDNR,
            staticRulesetResourceCount:
                manifest.declarativeNetRequest?.ruleResources.count ?? 0,
            declaresWebRequest: declaresWebRequest,
            declaresWebRequestBlocking: declaresWebRequestBlocking,
            declaresWebRequestAuthProvider: declaresWebRequestAuth,
            hostPermissionCount: manifest.hostPermissions.count,
            dnrAvailableInInternalEvaluator: declaresDNR,
            dnrAvailableInProduct: false,
            dnrProductEnforcementAvailable: false,
            webRequestAvailableInInternalFixture:
                declaresWebRequest || declaresWebRequestBlocking
                    || declaresWebRequestAuth,
            webRequestBlockingAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false
        )
    }

    private static func issue(for error: Error) -> ChromeMV3InstallIssue {
        let message = (error as? LocalizedError)?.errorDescription
            ?? String(describing: error)
        return ChromeMV3InstallIssue(
            severity: .fatal,
            code: code(for: error),
            message: message,
            field: nil
        )
    }

    private static func code(for error: Error) -> String {
        guard let validationError = error as? ChromeMV3ManifestValidationError else {
            return "validationError"
        }

        switch validationError {
        case .missingManifest:
            return "missingManifest"
        case .invalidJSON:
            return "invalidJSON"
        case .invalidJSONStructure:
            return "invalidJSONStructure"
        case .missingManifestVersion:
            return "missingManifestVersion"
        case .invalidManifestVersion:
            return "invalidManifestVersion"
        case .unsupportedManifestVersion:
            return "unsupportedManifestVersion"
        case .missingName:
            return "missingName"
        case .missingVersion:
            return "missingVersion"
        case .backgroundPageUnsupported:
            return "backgroundPageUnsupported"
        case .backgroundScriptsUnsupported:
            return "backgroundScriptsUnsupported"
        case .backgroundPersistenceUnsupported:
            return "backgroundPersistenceUnsupported"
        case .unsafeResourcePath:
            return "unsafeResourcePath"
        case .unsupportedSafariPackageInput:
            return "unsupportedSafariPackageInput"
        case .unsupportedArchiveInspection:
            return "unsupportedArchiveInspection"
        }
    }
}

enum ChromeMV3InstallInspector {
    static func inspectUnpackedDirectory(at directoryURL: URL) -> ChromeMV3InstallReport {
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        do {
            let manifest = try ChromeMV3ManifestValidator.validatePackage(
                at: directoryURL,
                sourceKind: .unpackedDirectory
            )
            let metadata = ChromeMV3ManifestValidator.packageMetadata(
                for: directoryURL,
                sourceKind: .unpackedDirectory,
                manifestURL: manifestURL,
                manifest: manifest
            )
            return ChromeMV3InstallReporter.report(
                for: manifest,
                packageMetadata: metadata
            )
        } catch {
            let metadata = ChromeMV3ManifestValidator.packageMetadata(
                for: directoryURL,
                sourceKind: .unpackedDirectory,
                manifestURL: FileManager.default.fileExists(atPath: manifestURL.path)
                    ? manifestURL
                    : nil,
                manifest: nil
            )
            return ChromeMV3InstallReporter.fatalReport(
                error: error,
                packageMetadata: metadata
            )
        }
    }

    static func inspectManifestFile(at manifestURL: URL) -> ChromeMV3InstallReport {
        do {
            let manifest = try ChromeMV3ManifestValidator.validateManifestFile(
                at: manifestURL
            )
            let packageURL = manifestURL.deletingLastPathComponent()
            let metadata = ChromeMV3ManifestValidator.packageMetadata(
                for: packageURL,
                sourceKind: .unpackedDirectory,
                manifestURL: manifestURL,
                manifest: manifest
            )
            return ChromeMV3InstallReporter.report(
                for: manifest,
                packageMetadata: metadata
            )
        } catch {
            return ChromeMV3InstallReporter.fatalReport(error: error)
        }
    }
}

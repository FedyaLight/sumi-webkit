//
//  ChromeMV3NativeMessagingSecurity.swift
//  Sumi
//
//  Deterministic Chrome MV3 native messaging security and host-validation
//  models. This file records future host manifest, lookup, authorization,
//  framing, preflight, Port lifecycle, and readiness behavior only. It does
//  not import WebKit, create contexts, load controllers, register scripts,
//  wake service workers, open ports, launch native hosts, or schedule work.
//

import CryptoKit
import Foundation

enum ChromeMV3NativeHostManifestSourceKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case appManagedFutureLocation
    case explicitTestRoot
    case systemLevel
    case unknown
    case userLevel

    static func < (
        lhs: ChromeMV3NativeHostManifestSourceKind,
        rhs: ChromeMV3NativeHostManifestSourceKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3NativeHostManifestSourceLocation:
    Codable,
    Equatable,
    Sendable
{
    var kind: ChromeMV3NativeHostManifestSourceKind
    var browserFamily: String
    var rootPath: String
    var manifestPath: String?
    var lookupAllowedInThisModel: Bool
    var arbitraryDirectoryScanAllowed: Bool
    var diagnostics: [String]

    static func explicitTestRoot(
        rootPath: String,
        hostName: String? = nil
    ) -> ChromeMV3NativeHostManifestSourceLocation {
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            .standardizedFileURL
            .path
        return ChromeMV3NativeHostManifestSourceLocation(
            kind: .explicitTestRoot,
            browserFamily: "test-fixture",
            rootPath: root,
            manifestPath: hostName.map {
                URL(fileURLWithPath: root, isDirectory: true)
                    .appendingPathComponent("\($0).json")
                    .standardizedFileURL
                    .path
            },
            lookupAllowedInThisModel: true,
            arbitraryDirectoryScanAllowed: false,
            diagnostics: [
                "Only exact host-name manifest lookup is allowed under the explicit test root.",
            ]
        )
    }
}

enum ChromeMV3NativeMessagingDiagnosticSeverity:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case error
    case info
    case warning

    static func < (
        lhs: ChromeMV3NativeMessagingDiagnosticSeverity,
        rhs: ChromeMV3NativeMessagingDiagnosticSeverity
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3NativeHostManifestDiagnosticCode:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case hostNameMatchesRequestedName
    case invalidHostName
    case invalidJSON
    case malformedAllowedOrigin
    case missingAllowedOrigins
    case missingDescription
    case missingName
    case missingPath
    case missingType
    case pathNotExecuted
    case rootNotObject
    case unknownFieldIgnored
    case unsafePath
    case unsupportedPlatformField
    case unsupportedType

    static func < (
        lhs: ChromeMV3NativeHostManifestDiagnosticCode,
        rhs: ChromeMV3NativeHostManifestDiagnosticCode
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3NativeHostManifestDiagnostic:
    Codable,
    Equatable,
    Sendable
{
    var severity: ChromeMV3NativeMessagingDiagnosticSeverity
    var code: ChromeMV3NativeHostManifestDiagnosticCode
    var field: String?
    var message: String
}

struct ChromeMV3NativeMessagingAllowedOrigin:
    Codable,
    Equatable,
    Sendable
{
    var rawValue: String
    var extensionID: String?
    var isValid: Bool
    var diagnostics: [String]

    static func parse(_ rawValue: String) -> ChromeMV3NativeMessagingAllowedOrigin {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var diagnostics: [String] = []

        guard value.isEmpty == false else {
            return ChromeMV3NativeMessagingAllowedOrigin(
                rawValue: rawValue,
                extensionID: nil,
                isValid: false,
                diagnostics: ["Allowed origin is empty."]
            )
        }

        if value.contains("*") {
            diagnostics.append(
                "Allowed origin contains a wildcard, which Chrome native host manifests do not allow."
            )
        }

        let prefix = "chrome-extension://"
        guard value.hasPrefix(prefix), value.hasSuffix("/") else {
            return ChromeMV3NativeMessagingAllowedOrigin(
                rawValue: rawValue,
                extensionID: nil,
                isValid: false,
                diagnostics: uniqueSorted(
                    diagnostics + [
                        "Allowed origin must use chrome-extension scheme and a trailing slash.",
                    ]
                )
            )
        }

        let idStart = value.index(value.startIndex, offsetBy: prefix.count)
        let idEnd = value.index(before: value.endIndex)
        let extensionID = String(value[idStart..<idEnd])
        if extensionID.contains("/") || extensionID.contains("?")
            || extensionID.contains("#")
        {
            diagnostics.append(
                "Allowed origin must not include a path, query, or fragment after the extension id."
            )
        }
        if isChromeExtensionID(extensionID) == false {
            diagnostics.append(
                "Allowed origin extension id must be a 32-character Chrome extension id."
            )
        }

        return ChromeMV3NativeMessagingAllowedOrigin(
            rawValue: rawValue,
            extensionID: extensionID,
            isValid: diagnostics.isEmpty,
            diagnostics: uniqueSorted(
                diagnostics.isEmpty
                    ? ["Allowed origin is valid for the native messaging model."]
                    : diagnostics
            )
        )
    }

    static func originString(extensionID: String) -> String {
        "chrome-extension://\(extensionID)/"
    }
}

struct ChromeMV3NativeHostManifest:
    Codable,
    Equatable,
    Sendable
{
    var name: String?
    var description: String?
    var path: String?
    var type: String?
    var allowedOrigins: [ChromeMV3NativeMessagingAllowedOrigin]
    var sourceLocation: ChromeMV3NativeHostManifestSourceLocation
    var rawJSONSHA256: String?
    var canonicalJSONSHA256: String?
    var unknownFields: [String]
    var diagnostics: [ChromeMV3NativeHostManifestDiagnostic]

    var isValid: Bool {
        diagnostics.contains { $0.severity == .error } == false
    }

    var validationSummary: ChromeMV3NativeHostManifestValidationSummary {
        ChromeMV3NativeHostManifestValidationSummary(
            hostName: name,
            sourcePath: sourceLocation.manifestPath,
            valid: isValid,
            errorCodes:
                diagnostics
                .filter { $0.severity == .error }
                .map(\.code)
                .sorted(),
            warningCodes:
                diagnostics
                .filter { $0.severity == .warning }
                .map(\.code)
                .sorted(),
            allowedExtensionIDs:
                allowedOrigins.compactMap(\.extensionID).sorted()
        )
    }
}

struct ChromeMV3NativeHostManifestValidationSummary:
    Codable,
    Equatable,
    Sendable
{
    var hostName: String?
    var sourcePath: String?
    var valid: Bool
    var errorCodes: [ChromeMV3NativeHostManifestDiagnosticCode]
    var warningCodes: [ChromeMV3NativeHostManifestDiagnosticCode]
    var allowedExtensionIDs: [String]
}

enum ChromeMV3NativeHostManifestDecoder {
    static func decode(
        data: Data,
        sourceLocation: ChromeMV3NativeHostManifestSourceLocation,
        requestedHostName: String? = nil
    ) -> ChromeMV3NativeHostManifest {
        let rawHash = sha256Hex(data)
        let object: [String: Any]
        do {
            guard let decoded = try JSONSerialization
                .jsonObject(with: data) as? [String: Any]
            else {
                return invalidShell(
                    sourceLocation: sourceLocation,
                    rawHash: rawHash,
                    diagnostic: diagnostic(
                        .error,
                        .rootNotObject,
                        field: nil,
                        "Native host manifest JSON root must be an object."
                    )
                )
            }
            object = decoded
        } catch {
            return invalidShell(
                sourceLocation: sourceLocation,
                rawHash: rawHash,
                diagnostic: diagnostic(
                    .error,
                    .invalidJSON,
                    field: nil,
                    "Native host manifest is not valid JSON: \(error.localizedDescription)"
                )
            )
        }

        return decode(
            object: object,
            sourceLocation: sourceLocation,
            rawHash: rawHash,
            requestedHostName: requestedHostName
        )
    }

    static func decode(
        object: [String: Any],
        sourceLocation: ChromeMV3NativeHostManifestSourceLocation,
        rawHash: String? = nil,
        requestedHostName: String? = nil
    ) -> ChromeMV3NativeHostManifest {
        let knownFields = Set([
            "allowed_origins",
            "description",
            "name",
            "path",
            "type",
        ])
        var diagnostics: [ChromeMV3NativeHostManifestDiagnostic] = []
        let name = object["name"] as? String
        let description = object["description"] as? String
        let path = object["path"] as? String
        let type = object["type"] as? String
        let allowedOriginValues = object["allowed_origins"] as? [Any]
        let unknownFields = object.keys.filter {
            knownFields.contains($0) == false
                && $0 != "platform"
                && $0 != "platforms"
        }.sorted()

        if let name, name.isEmpty == false {
            if isValidNativeHostName(name) == false {
                diagnostics.append(
                    diagnostic(
                        .error,
                        .invalidHostName,
                        field: "name",
                        "Native host name contains invalid characters or dot placement."
                    )
                )
            } else if let requestedHostName,
                      requestedHostName == name
            {
                diagnostics.append(
                    diagnostic(
                        .info,
                        .hostNameMatchesRequestedName,
                        field: "name",
                        "Native host manifest name matches the requested host name."
                    )
                )
            }
        } else {
            diagnostics.append(
                diagnostic(
                    .error,
                    .missingName,
                    field: "name",
                    "Native host manifest is missing name."
                )
            )
        }

        if description?.isEmpty != false {
            diagnostics.append(
                diagnostic(
                    .error,
                    .missingDescription,
                    field: "description",
                    "Native host manifest is missing description."
                )
            )
        }

        if let path, path.isEmpty == false {
            diagnostics.append(contentsOf: pathDiagnostics(path))
        } else {
            diagnostics.append(
                diagnostic(
                    .error,
                    .missingPath,
                    field: "path",
                    "Native host manifest is missing path."
                )
            )
        }

        if let type, type.isEmpty == false {
            if type != "stdio" {
                diagnostics.append(
                    diagnostic(
                        .error,
                        .unsupportedType,
                        field: "type",
                        "Native host manifest type must be stdio."
                    )
                )
            }
        } else {
            diagnostics.append(
                diagnostic(
                    .error,
                    .missingType,
                    field: "type",
                    "Native host manifest is missing type."
                )
            )
        }

        let allowedOrigins: [ChromeMV3NativeMessagingAllowedOrigin]
        if let allowedOriginValues, allowedOriginValues.isEmpty == false {
            allowedOrigins = allowedOriginValues.map { value in
                guard let raw = value as? String else {
                    return ChromeMV3NativeMessagingAllowedOrigin(
                        rawValue: String(describing: value),
                        extensionID: nil,
                        isValid: false,
                        diagnostics: [
                            "Allowed origin entry must be a string.",
                        ]
                    )
                }
                return ChromeMV3NativeMessagingAllowedOrigin.parse(raw)
            }
            for origin in allowedOrigins where origin.isValid == false {
                diagnostics.append(
                    diagnostic(
                        .error,
                        .malformedAllowedOrigin,
                        field: "allowed_origins",
                        origin.diagnostics.joined(separator: " ")
                    )
                )
            }
        } else {
            allowedOrigins = []
            diagnostics.append(
                diagnostic(
                    .error,
                    .missingAllowedOrigins,
                    field: "allowed_origins",
                    "Native host manifest must list allowed extension origins."
                )
            )
        }

        if object.keys.contains("platform") || object.keys.contains("platforms") {
            diagnostics.append(
                diagnostic(
                    .warning,
                    .unsupportedPlatformField,
                    field: "platform",
                    "Platform-specific native host manifest fields are not supported by this model."
                )
            )
        }

        for field in unknownFields {
            diagnostics.append(
                diagnostic(
                    .warning,
                    .unknownFieldIgnored,
                    field: field,
                    "Unknown native host manifest field is ignored by this model."
                )
            )
        }

        diagnostics.append(
            diagnostic(
                .info,
                .pathNotExecuted,
                field: "path",
                "Host path is recorded for future policy only; no executable check or launch is performed."
            )
        )

        return ChromeMV3NativeHostManifest(
            name: name,
            description: description,
            path: path,
            type: type,
            allowedOrigins: allowedOrigins.sorted {
                $0.rawValue < $1.rawValue
            },
            sourceLocation: sourceLocation,
            rawJSONSHA256: rawHash,
            canonicalJSONSHA256: canonicalHash(object),
            unknownFields: unknownFields,
            diagnostics: diagnostics.sorted {
                if $0.severity != $1.severity {
                    return $0.severity < $1.severity
                }
                if $0.code != $1.code {
                    return $0.code < $1.code
                }
                return ($0.field ?? "") < ($1.field ?? "")
            }
        )
    }

    private static func invalidShell(
        sourceLocation: ChromeMV3NativeHostManifestSourceLocation,
        rawHash: String,
        diagnostic: ChromeMV3NativeHostManifestDiagnostic
    ) -> ChromeMV3NativeHostManifest {
        ChromeMV3NativeHostManifest(
            name: nil,
            description: nil,
            path: nil,
            type: nil,
            allowedOrigins: [],
            sourceLocation: sourceLocation,
            rawJSONSHA256: rawHash,
            canonicalJSONSHA256: nil,
            unknownFields: [],
            diagnostics: [diagnostic]
        )
    }

    private static func pathDiagnostics(
        _ path: String
    ) -> [ChromeMV3NativeHostManifestDiagnostic] {
        var diagnostics: [ChromeMV3NativeHostManifestDiagnostic] = []
        if path.contains("\u{0}") {
            diagnostics.append(
                diagnostic(
                    .error,
                    .unsafePath,
                    field: "path",
                    "Native host path contains a NUL byte."
                )
            )
        }
        if path.hasPrefix("/") == false {
            diagnostics.append(
                diagnostic(
                    .error,
                    .unsafePath,
                    field: "path",
                    "Native host path must be absolute on macOS and Linux."
                )
            )
        }
        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        if components.contains(where: { $0 == ".." }) {
            diagnostics.append(
                diagnostic(
                    .error,
                    .unsafePath,
                    field: "path",
                    "Native host path must not contain traversal components."
                )
            )
        }
        return diagnostics
    }

    private static func canonicalHash(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys]
              )
        else { return nil }
        return sha256Hex(data)
    }

    private static func diagnostic(
        _ severity: ChromeMV3NativeMessagingDiagnosticSeverity,
        _ code: ChromeMV3NativeHostManifestDiagnosticCode,
        field: String?,
        _ message: String
    ) -> ChromeMV3NativeHostManifestDiagnostic {
        ChromeMV3NativeHostManifestDiagnostic(
            severity: severity,
            code: code,
            field: field,
            message: message
        )
    }
}

enum ChromeMV3NativeHostLookupStatus:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case disabledModule
    case found
    case invalidHostName
    case malformedManifest
    case missing
    case unsupported

    static func < (
        lhs: ChromeMV3NativeHostLookupStatus,
        rhs: ChromeMV3NativeHostLookupStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3NativeHostLookupResult:
    Codable,
    Equatable,
    Sendable
{
    var hostName: String
    var status: ChromeMV3NativeHostLookupStatus
    var checkedLocations: [ChromeMV3NativeHostManifestSourceLocation]
    var futureLocationsRecorded:
        [ChromeMV3NativeHostManifestSourceLocation]
    var arbitrarySystemScanPerformed: Bool
    var manifest: ChromeMV3NativeHostManifest?
    var diagnostics: [String]
}

struct ChromeMV3NativeHostLookupPolicy:
    Codable,
    Equatable,
    Sendable
{
    var platform: String
    var extensionModuleEnabled: Bool
    var locations: [ChromeMV3NativeHostManifestSourceLocation]
    var profilePolicyRestrictions: [String]
    var disabledModuleBehavior: String
    var diagnostics: [String]

    static func macOS(
        explicitTestRootPath: String? = nil,
        appManagedRootPath: String? = nil,
        extensionModuleEnabled: Bool = true
    ) -> ChromeMV3NativeHostLookupPolicy {
        var locations: [ChromeMV3NativeHostManifestSourceLocation] = [
            futureLocation(
                kind: .userLevel,
                browserFamily: "Google Chrome",
                rootPath:
                    "~/Library/Application Support/Google/Chrome/NativeMessagingHosts"
            ),
            futureLocation(
                kind: .userLevel,
                browserFamily: "Google Chrome for Testing",
                rootPath:
                    "~/Library/Application Support/Google/ChromeForTesting/NativeMessagingHosts"
            ),
            futureLocation(
                kind: .userLevel,
                browserFamily: "Chromium",
                rootPath:
                    "~/Library/Application Support/Chromium/NativeMessagingHosts"
            ),
            futureLocation(
                kind: .systemLevel,
                browserFamily: "Google Chrome",
                rootPath: "/Library/Google/Chrome/NativeMessagingHosts"
            ),
            futureLocation(
                kind: .systemLevel,
                browserFamily: "Google Chrome for Testing",
                rootPath: "/Library/Google/ChromeForTesting/NativeMessagingHosts"
            ),
            futureLocation(
                kind: .systemLevel,
                browserFamily: "Chromium",
                rootPath:
                    "/Library/Application Support/Chromium/NativeMessagingHosts"
            ),
        ]
        if let appManagedRootPath {
            locations.append(
                futureLocation(
                    kind: .appManagedFutureLocation,
                    browserFamily: "Sumi",
                    rootPath: appManagedRootPath
                )
            )
        }
        if let explicitTestRootPath {
            locations.append(
                .explicitTestRoot(rootPath: explicitTestRootPath)
            )
        }

        return ChromeMV3NativeHostLookupPolicy(
            platform: "macOS",
            extensionModuleEnabled: extensionModuleEnabled,
            locations: locations.sorted {
                if $0.lookupAllowedInThisModel != $1.lookupAllowedInThisModel {
                    return $0.lookupAllowedInThisModel
                        && $1.lookupAllowedInThisModel == false
                }
                if $0.kind != $1.kind {
                    return $0.kind < $1.kind
                }
                return $0.rootPath < $1.rootPath
            },
            profilePolicyRestrictions: [
                "Only explicit test roots are read in this model.",
                "User-level and system-level native host locations are records for future implementation.",
                "No background discovery state is persisted.",
            ],
            disabledModuleBehavior:
                "When extensions are disabled, native host lookup returns disabledModule and reads no manifests.",
            diagnostics: [
                "Lookup policy records Chrome macOS locations without scanning them.",
                "Sumi-managed native host roots remain future policy inputs only.",
            ]
        )
    }

    func lookupHost(
        named hostName: String,
        fileManager: FileManager = .default
    ) -> ChromeMV3NativeHostLookupResult {
        let normalizedHostName = hostName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard extensionModuleEnabled else {
            return ChromeMV3NativeHostLookupResult(
                hostName: normalizedHostName,
                status: .disabledModule,
                checkedLocations: [],
                futureLocationsRecorded: locations,
                arbitrarySystemScanPerformed: false,
                manifest: nil,
                diagnostics: [
                    disabledModuleBehavior,
                    "No native host manifest read was attempted.",
                ]
            )
        }
        guard isValidNativeHostName(normalizedHostName) else {
            return ChromeMV3NativeHostLookupResult(
                hostName: normalizedHostName,
                status: .invalidHostName,
                checkedLocations: [],
                futureLocationsRecorded: locations,
                arbitrarySystemScanPerformed: false,
                manifest: nil,
                diagnostics: [
                    "Native host name is syntactically invalid.",
                    "No manifest path was read for an invalid host name.",
                ]
            )
        }

        var checked: [ChromeMV3NativeHostManifestSourceLocation] = []
        for location in locations where location.lookupAllowedInThisModel {
            var concrete = location
            concrete.manifestPath = URL(
                fileURLWithPath: location.rootPath,
                isDirectory: true
            )
            .appendingPathComponent("\(normalizedHostName).json")
            .standardizedFileURL
            .path
            checked.append(concrete)

            guard let path = concrete.manifestPath,
                  fileManager.fileExists(atPath: path)
            else { continue }

            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let manifest = ChromeMV3NativeHostManifestDecoder.decode(
                    data: data,
                    sourceLocation: concrete,
                    requestedHostName: normalizedHostName
                )
                return ChromeMV3NativeHostLookupResult(
                    hostName: normalizedHostName,
                    status: manifest.isValid ? .found : .malformedManifest,
                    checkedLocations: checked,
                    futureLocationsRecorded:
                        locations.filter {
                            $0.lookupAllowedInThisModel == false
                        },
                    arbitrarySystemScanPerformed: false,
                    manifest: manifest,
                    diagnostics: uniqueSorted(
                        manifest.diagnostics.map(\.message)
                            + [
                                "Manifest was read from an explicit test root exact path.",
                                "No user-level or system-level directory was scanned.",
                            ]
                    )
                )
            } catch {
                return ChromeMV3NativeHostLookupResult(
                    hostName: normalizedHostName,
                    status: .malformedManifest,
                    checkedLocations: checked,
                    futureLocationsRecorded:
                        locations.filter {
                            $0.lookupAllowedInThisModel == false
                        },
                    arbitrarySystemScanPerformed: false,
                    manifest: nil,
                    diagnostics: [
                        "Native host manifest could not be read: \(error.localizedDescription)",
                    ]
                )
            }
        }

        return ChromeMV3NativeHostLookupResult(
            hostName: normalizedHostName,
            status: .missing,
            checkedLocations: checked,
            futureLocationsRecorded:
                locations.filter { $0.lookupAllowedInThisModel == false },
            arbitrarySystemScanPerformed: false,
            manifest: nil,
            diagnostics: [
                "No native host manifest was found under explicit lookup roots.",
                "Future user-level and system-level locations were recorded but not scanned.",
            ]
        )
    }

    private static func futureLocation(
        kind: ChromeMV3NativeHostManifestSourceKind,
        browserFamily: String,
        rootPath: String
    ) -> ChromeMV3NativeHostManifestSourceLocation {
        ChromeMV3NativeHostManifestSourceLocation(
            kind: kind,
            browserFamily: browserFamily,
            rootPath: rootPath,
            manifestPath: nil,
            lookupAllowedInThisModel: false,
            arbitraryDirectoryScanAllowed: false,
            diagnostics: [
                "Location is recorded for future native host discovery policy only.",
            ]
        )
    }
}

enum ChromeMV3NativeMessagingPermissionState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case deferred
    case denied
    case grantedByManifest
    case missing
    case unsupported

    static func < (
        lhs: ChromeMV3NativeMessagingPermissionState,
        rhs: ChromeMV3NativeMessagingPermissionState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var hasPermission: Bool {
        self == .grantedByManifest
    }
}

struct ChromeMV3NativeMessagingProductPolicy:
    Codable,
    Equatable,
    Sendable
{
    var extensionModuleEnabled: Bool
    var nativeMessagingAllowedByProductPolicy: Bool
    var userConsentRequired: Bool
    var userConsentGranted: Bool

    static let blockedRuntimeDefault = ChromeMV3NativeMessagingProductPolicy(
        extensionModuleEnabled: true,
        nativeMessagingAllowedByProductPolicy: true,
        userConsentRequired: true,
        userConsentGranted: false
    )
}

struct ChromeMV3NativeMessagingAuthorizationResult:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var extensionOrigin: String
    var hostName: String?
    var authorizedByManifest: Bool
    var hasNativeMessagingPermission: Bool
    var permissionState: ChromeMV3NativeMessagingPermissionState
    var requiresUserConsent: Bool
    var blockedByPolicy: Bool
    var blockedByMissingPermission: Bool
    var blockedByHostManifest: Bool
    var blockedByDisabledModule: Bool
    var canConnectNativeNow: Bool
    var diagnostics: [String]
}

enum ChromeMV3NativeMessagingAuthorizationEvaluator {
    static func evaluate(
        extensionID: String,
        permissionState: ChromeMV3NativeMessagingPermissionState,
        hostManifest: ChromeMV3NativeHostManifest?,
        productPolicy: ChromeMV3NativeMessagingProductPolicy =
            .blockedRuntimeDefault
    ) -> ChromeMV3NativeMessagingAuthorizationResult {
        let extensionOrigin =
            ChromeMV3NativeMessagingAllowedOrigin
            .originString(extensionID: extensionID)
        let extensionOriginValid = isChromeExtensionID(extensionID)
        let manifestValid = hostManifest?.isValid == true
        let allowed = hostManifest?.allowedOrigins.contains {
            $0.isValid && $0.extensionID == extensionID
        } ?? false
        let permissionPresent = permissionState.hasPermission
        let disabled = productPolicy.extensionModuleEnabled == false
        let policyBlocked =
            disabled || productPolicy.nativeMessagingAllowedByProductPolicy == false
        let requiresConsent =
            productPolicy.userConsentRequired
                && productPolicy.userConsentGranted == false
        let blockedByManifest = manifestValid == false || allowed == false

        return ChromeMV3NativeMessagingAuthorizationResult(
            extensionID: extensionID,
            extensionOrigin: extensionOrigin,
            hostName: hostManifest?.name,
            authorizedByManifest: allowed && manifestValid && extensionOriginValid,
            hasNativeMessagingPermission: permissionPresent,
            permissionState: permissionState,
            requiresUserConsent: requiresConsent,
            blockedByPolicy: policyBlocked,
            blockedByMissingPermission: permissionPresent == false,
            blockedByHostManifest: blockedByManifest,
            blockedByDisabledModule: disabled,
            canConnectNativeNow: false,
            diagnostics: uniqueSorted(
                [
                    extensionOriginValid
                        ? "Extension origin has Chrome native messaging format."
                        : "Extension id does not form a valid Chrome native messaging origin.",
                    permissionPresent
                        ? "nativeMessaging permission is present in the modeled permission state."
                        : "nativeMessaging permission is missing, denied, deferred, or unsupported.",
                    manifestValid
                        ? "Native host manifest is valid."
                        : "Native host manifest is missing or malformed.",
                    allowed
                        ? "Extension origin is listed in allowed origins."
                        : "Extension origin is not authorized by the host manifest.",
                    disabled
                        ? "Extensions module is disabled."
                        : nil,
                    productPolicy.nativeMessagingAllowedByProductPolicy
                        ? nil
                        : "Product policy blocks native messaging.",
                    requiresConsent
                        ? "User consent or product policy approval is required before future native host access."
                        : nil,
                    "Native messaging authorization is a preflight model only.",
                    "No native connection can be opened now.",
                ].compactMap { $0 }
            )
        )
    }
}

enum ChromeMV3NativeMessagingFrameDirection:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case inboundFromHost
    case outboundToHost

    static func < (
        lhs: ChromeMV3NativeMessagingFrameDirection,
        rhs: ChromeMV3NativeMessagingFrameDirection
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3NativeMessagingFrameDiagnosticCode:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case invalidDeclaredLength
    case lengthMismatch
    case missingLengthPrefix
    case oversizedMessage
    case validFrame

    static func < (
        lhs: ChromeMV3NativeMessagingFrameDiagnosticCode,
        rhs: ChromeMV3NativeMessagingFrameDiagnosticCode
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3NativeMessagingFrameDiagnostic:
    Codable,
    Equatable,
    Sendable
{
    var code: ChromeMV3NativeMessagingFrameDiagnosticCode
    var direction: ChromeMV3NativeMessagingFrameDirection
    var message: String
}

struct ChromeMV3NativeMessagingFrameValidation:
    Codable,
    Equatable,
    Sendable
{
    var direction: ChromeMV3NativeMessagingFrameDirection
    var declaredPayloadLength: Int?
    var actualPayloadByteCount: Int?
    var maximumPayloadBytes: Int
    var valid: Bool
    var diagnostics: [ChromeMV3NativeMessagingFrameDiagnostic]
}

struct ChromeMV3NativeMessagingFramingPolicy:
    Codable,
    Equatable,
    Sendable
{
    var lengthPrefixBytes: Int
    var lengthPrefixByteOrder: String
    var payloadEncoding: String
    var inboundHostMessageLimitBytes: Int
    var outboundHostMessageLimitBytes: Int
    var serializesNow: Bool
    var readsPipesNow: Bool
    var diagnostics: [String]

    static let chromeStdioJSON = ChromeMV3NativeMessagingFramingPolicy(
        lengthPrefixBytes: 4,
        lengthPrefixByteOrder: "native-endian",
        payloadEncoding: "JSON UTF-8",
        inboundHostMessageLimitBytes: 1_048_576,
        outboundHostMessageLimitBytes: 67_108_864,
        serializesNow: false,
        readsPipesNow: false,
        diagnostics: [
            "Native messages are modeled as JSON UTF-8 payloads with a 32-bit native-endian byte length prefix.",
            "Inbound host messages are limited to 1 MB.",
            "Outbound messages to the host are limited to 64 MiB.",
            "No pipe I/O or serialization to a native host is performed.",
        ]
    )

    func validateFrame(
        declaredPayloadLength: Int?,
        actualPayloadByteCount: Int?,
        direction: ChromeMV3NativeMessagingFrameDirection
    ) -> ChromeMV3NativeMessagingFrameValidation {
        let maximum = direction == .inboundFromHost
            ? inboundHostMessageLimitBytes
            : outboundHostMessageLimitBytes
        var diagnostics: [ChromeMV3NativeMessagingFrameDiagnostic] = []
        if declaredPayloadLength == nil {
            diagnostics.append(
                frameDiagnostic(
                    .missingLengthPrefix,
                    direction,
                    "Native message frame is missing its length prefix."
                )
            )
        }
        if let declaredPayloadLength, declaredPayloadLength < 0 {
            diagnostics.append(
                frameDiagnostic(
                    .invalidDeclaredLength,
                    direction,
                    "Native message frame length is negative."
                )
            )
        }
        if let declaredPayloadLength, declaredPayloadLength > maximum {
            diagnostics.append(
                frameDiagnostic(
                    .oversizedMessage,
                    direction,
                    "Native message frame exceeds the modeled size limit."
                )
            )
        }
        if let declaredPayloadLength,
           let actualPayloadByteCount,
           declaredPayloadLength != actualPayloadByteCount
        {
            diagnostics.append(
                frameDiagnostic(
                    .lengthMismatch,
                    direction,
                    "Native message frame length does not match payload byte count."
                )
            )
        }
        if diagnostics.isEmpty {
            diagnostics.append(
                frameDiagnostic(
                    .validFrame,
                    direction,
                    "Native message frame is valid for the deterministic policy."
                )
            )
        }

        return ChromeMV3NativeMessagingFrameValidation(
            direction: direction,
            declaredPayloadLength: declaredPayloadLength,
            actualPayloadByteCount: actualPayloadByteCount,
            maximumPayloadBytes: maximum,
            valid:
                diagnostics.allSatisfy { $0.code == .validFrame },
            diagnostics: diagnostics.sorted { $0.code < $1.code }
        )
    }

    private func frameDiagnostic(
        _ code: ChromeMV3NativeMessagingFrameDiagnosticCode,
        _ direction: ChromeMV3NativeMessagingFrameDirection,
        _ message: String
    ) -> ChromeMV3NativeMessagingFrameDiagnostic {
        ChromeMV3NativeMessagingFrameDiagnostic(
            code: code,
            direction: direction,
            message: message
        )
    }
}

enum ChromeMV3NativeMessagingOperationKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case longLivedNativePort
    case oneShotNativeMessage

    static func < (
        lhs: ChromeMV3NativeMessagingOperationKind,
        rhs: ChromeMV3NativeMessagingOperationKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var apiDisplayName: String {
        switch self {
        case .longLivedNativePort:
            return ["runtime.connect", "Native"].joined()
        case .oneShotNativeMessage:
            return ["runtime.send", "NativeMessage"].joined()
        }
    }
}

enum ChromeMV3NativeMessagingDisconnectReason:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case authorizationFailed
    case extensionDisabled
    case hostManifestMissing
    case malformedFrame
    case nativeHostExited
    case oversizedMessage
    case permissionRevoked
    case profileClosed
    case runtimeNotImplemented

    static func < (
        lhs: ChromeMV3NativeMessagingDisconnectReason,
        rhs: ChromeMV3NativeMessagingDisconnectReason
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3NativeMessagingPortLifecycleContract:
    Codable,
    Equatable,
    Sendable
{
    var operationID: String
    var portKind: ChromeMV3RuntimePortKind
    var hostName: String
    var extensionID: String
    var profileID: String
    var futurePortWouldBeLongLived: Bool
    var canOpenPortNow: Bool
    var keepaliveStartsNow: Bool
    var processLaunchAllowedNow: Bool
    var portLifecycleImplemented: Bool
    var serviceWorkerKeepaliveSource:
        ChromeMV3ServiceWorkerKeepaliveSource
    var cleanupTriggers: [String]
    var disconnectReasons:
        [ChromeMV3NativeMessagingDisconnectReason]
    var diagnostics: [String]

    static func model(
        operationID: String,
        operationKind: ChromeMV3NativeMessagingOperationKind,
        hostName: String,
        extensionID: String,
        profileID: String
    ) -> ChromeMV3NativeMessagingPortLifecycleContract {
        let keepalive = ChromeMV3ServiceWorkerKeepaliveSource.make(
            kind: .nativeMessagingPort,
            extensionID: extensionID,
            profileID: profileID,
            sourceSeed: operationID
        )
        return ChromeMV3NativeMessagingPortLifecycleContract(
            operationID: operationID,
            portKind: .nativeMessaging,
            hostName: hostName,
            extensionID: extensionID,
            profileID: profileID,
            futurePortWouldBeLongLived:
                operationKind == .longLivedNativePort,
            canOpenPortNow: false,
            keepaliveStartsNow: false,
            processLaunchAllowedNow: false,
            portLifecycleImplemented: false,
            serviceWorkerKeepaliveSource: keepalive,
            cleanupTriggers: [
                "disabled extension cleanup",
                "permission revoke cleanup",
                "profile close cleanup",
                "host exit cleanup",
            ],
            disconnectReasons:
                ChromeMV3NativeMessagingDisconnectReason.allCases.sorted(),
            diagnostics: uniqueSorted(
                keepalive.blockers
                    + [
                        "Native Port lifecycle is modeled only.",
                        "No native messaging Port is opened.",
                        "No service-worker keepalive starts now.",
                        "No host process launch is allowed now.",
                    ]
            )
        )
    }
}

struct ChromeMV3NativeMessagingPreflightInput:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var hostName: String
    var operationKind: ChromeMV3NativeMessagingOperationKind
    var sourceContext: ChromeMV3RuntimeMessagingContextKind
    var permissionState: ChromeMV3NativeMessagingPermissionState
    var productPolicy: ChromeMV3NativeMessagingProductPolicy
}

struct ChromeMV3NativeMessagingOperationPreflight:
    Codable,
    Equatable,
    Sendable
{
    var operationID: String
    var operationKind: ChromeMV3NativeMessagingOperationKind
    var apiDisplayName: String
    var extensionID: String
    var profileID: String
    var hostName: String
    var sourceContext: ChromeMV3RuntimeMessagingContextKind
    var permissionState: ChromeMV3NativeMessagingPermissionState
    var hostLookupResult: ChromeMV3NativeHostLookupResult
    var hostManifestValidationSummary:
        ChromeMV3NativeHostManifestValidationSummary?
    var authorizationResult:
        ChromeMV3NativeMessagingAuthorizationResult
    var serviceWorkerKeepaliveImplication:
        ChromeMV3ServiceWorkerKeepaliveSource
    var messageFramingPolicy:
        ChromeMV3NativeMessagingFramingPolicy
    var portLifecycleContract:
        ChromeMV3NativeMessagingPortLifecycleContract
    var canConnectNativeNow: Bool
    var canSendNativeMessageNow: Bool
    var processLaunchAllowedNow: Bool
    var nativeMessagingRuntimeImplemented: Bool
    var canOpenPortNow: Bool
    var canWakeServiceWorkerNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var blockers: [String]
    var diagnostics: [String]
}

enum ChromeMV3NativeMessagingPreflightEvaluator {
    static func evaluate(
        input: ChromeMV3NativeMessagingPreflightInput,
        lookupPolicy: ChromeMV3NativeHostLookupPolicy,
        lookupResult: ChromeMV3NativeHostLookupResult? = nil,
        fileManager: FileManager = .default
    ) -> ChromeMV3NativeMessagingOperationPreflight {
        let operationID = stableID(
            prefix: "native-messaging-preflight",
            parts: [
                input.operationKind.rawValue,
                input.extensionID,
                input.profileID,
                input.hostName,
                input.sourceContext.rawValue,
                input.permissionState.rawValue,
            ]
        )
        let hostLookup = lookupResult
            ?? lookupPolicy.lookupHost(
                named: input.hostName,
                fileManager: fileManager
            )
        let authorization =
            ChromeMV3NativeMessagingAuthorizationEvaluator.evaluate(
                extensionID: input.extensionID,
                permissionState: input.permissionState,
                hostManifest: hostLookup.manifest,
                productPolicy: input.productPolicy
            )
        let keepalive = ChromeMV3ServiceWorkerKeepaliveSource.make(
            kind: .nativeMessagingPort,
            extensionID: input.extensionID,
            profileID: input.profileID,
            sourceSeed: operationID
        )
        let lifecycle = ChromeMV3NativeMessagingPortLifecycleContract.model(
            operationID: operationID,
            operationKind: input.operationKind,
            hostName: input.hostName,
            extensionID: input.extensionID,
            profileID: input.profileID
        )
        let blockers = uniqueSorted(
            [
                hostLookup.status == .found
                    ? nil
                    : "Native host manifest is not available and valid.",
                authorization.hasNativeMessagingPermission
                    ? nil
                    : "nativeMessaging permission state blocks native host access.",
                authorization.authorizedByManifest
                    ? nil
                    : "Extension is not authorized by host allowed origins.",
                authorization.blockedByPolicy
                    ? "Product policy or disabled module blocks native messaging."
                    : nil,
                authorization.requiresUserConsent
                    ? "User consent or product policy approval is required."
                    : nil,
                "Native messaging runtime is not implemented.",
                "Native host process launch is not implemented.",
                "No native messaging Port is opened.",
                "No service-worker wake or keepalive starts now.",
                "Context loading remains blocked.",
                "runtimeLoadable remains false.",
            ].compactMap { $0 }
        )

        return ChromeMV3NativeMessagingOperationPreflight(
            operationID: operationID,
            operationKind: input.operationKind,
            apiDisplayName: input.operationKind.apiDisplayName,
            extensionID: input.extensionID,
            profileID: input.profileID,
            hostName: input.hostName,
            sourceContext: input.sourceContext,
            permissionState: input.permissionState,
            hostLookupResult: hostLookup,
            hostManifestValidationSummary:
                hostLookup.manifest?.validationSummary,
            authorizationResult: authorization,
            serviceWorkerKeepaliveImplication: keepalive,
            messageFramingPolicy: .chromeStdioJSON,
            portLifecycleContract: lifecycle,
            canConnectNativeNow: false,
            canSendNativeMessageNow: false,
            processLaunchAllowedNow: false,
            nativeMessagingRuntimeImplemented: false,
            canOpenPortNow: false,
            canWakeServiceWorkerNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            blockers: blockers,
            diagnostics: uniqueSorted(
                hostLookup.diagnostics
                    + authorization.diagnostics
                    + keepalive.blockers
                    + lifecycle.diagnostics
                    + [
                        "Operation \(input.operationKind.rawValue) is preflight-only.",
                        "canConnectNativeNow remains false.",
                        "canSendNativeMessageNow remains false.",
                        "processLaunchAllowedNow remains false.",
                    ]
            )
        )
    }
}

struct ChromeMV3PasswordManagerNativeMessagingSummary:
    Codable,
    Equatable,
    Sendable
{
    var nativeMessagingPermissionDetected: Bool
    var expectedHostNameKnown: Bool
    var expectedHostName: String?
    var hostManifestRequired: Bool
    var hostAuthorizationRequired: Bool
    var userConsentOrPolicyRequired: Bool
    var nativePortRequiredForUnlockFillFlow: Bool
    var serviceWorkerKeepaliveNeededButBlocked: Bool
    var processLaunchImplemented: Bool
    var passwordManagerNativeMessagingReady: Bool
    var blockers: [String]
}

struct ChromeMV3NativeMessagingPreflightSummary:
    Codable,
    Equatable,
    Sendable
{
    var operationID: String
    var operationKind: ChromeMV3NativeMessagingOperationKind
    var hostLookupStatus: ChromeMV3NativeHostLookupStatus
    var authorizedByManifest: Bool
    var hasNativeMessagingPermission: Bool
    var canConnectNativeNow: Bool
    var canSendNativeMessageNow: Bool
    var processLaunchAllowedNow: Bool
    var canOpenPortNow: Bool
    var canWakeServiceWorkerNow: Bool
    var blockerCount: Int
}

struct ChromeMV3NativeMessagingReadinessReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var nativeMessagingPermissionDetected: Bool
    var hostLookupStatus: ChromeMV3NativeHostLookupStatus
    var hostManifestValid: Bool
    var extensionAuthorizedByHost: Bool
    var canConnectNativeNow: Bool
    var canSendNativeMessageNow: Bool
    var processLaunchAllowedNow: Bool
    var canOpenPortNow: Bool
    var canWakeServiceWorkerNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var passwordManagerNativeMessagingReady: Bool
}

struct ChromeMV3NativeMessagingReadinessReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var extensionID: String
    var profileID: String
    var requestedHostName: String
    var expectedHostNameKnown: Bool
    var nativeMessagingPermissionDetected: Bool
    var permissionState: ChromeMV3NativeMessagingPermissionState
    var hostLookupPolicy: ChromeMV3NativeHostLookupPolicy
    var hostLookupResult: ChromeMV3NativeHostLookupResult
    var hostManifestValidationSummary:
        ChromeMV3NativeHostManifestValidationSummary?
    var extensionToHostAuthorization:
        ChromeMV3NativeMessagingAuthorizationResult
    var longLivedPortPreflight:
        ChromeMV3NativeMessagingPreflightSummary
    var oneShotMessagePreflight:
        ChromeMV3NativeMessagingPreflightSummary
    var messageFramingPolicy:
        ChromeMV3NativeMessagingFramingPolicy
    var nativePortLifecycle:
        ChromeMV3NativeMessagingPortLifecycleContract
    var serviceWorkerKeepaliveBlockers:
        [String]
    var passwordManagerNativeMessagingSummary:
        ChromeMV3PasswordManagerNativeMessagingSummary
    var canConnectNativeNow: Bool
    var canSendNativeMessageNow: Bool
    var processLaunchAllowedNow: Bool
    var canOpenPortNow: Bool
    var canWakeServiceWorkerNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
    var blockers: [String]
    var documentationSources: [ChromeMV3ManifestRewritePreviewSource]

    var summary: ChromeMV3NativeMessagingReadinessReportSummary {
        ChromeMV3NativeMessagingReadinessReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            nativeMessagingPermissionDetected:
                nativeMessagingPermissionDetected,
            hostLookupStatus: hostLookupResult.status,
            hostManifestValid:
                hostManifestValidationSummary?.valid ?? false,
            extensionAuthorizedByHost:
                extensionToHostAuthorization.authorizedByManifest,
            canConnectNativeNow: false,
            canSendNativeMessageNow: false,
            processLaunchAllowedNow: false,
            canOpenPortNow: false,
            canWakeServiceWorkerNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            passwordManagerNativeMessagingReady: false
        )
    }
}

enum ChromeMV3NativeMessagingReadinessReportWriter {
    static let reportFileName = "runtime-native-messaging-readiness-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3NativeMessagingReadinessReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3NativeMessagingReadinessReport {
        guard directoryExists(rootURL.standardizedFileURL) else {
            return report
        }
        try ChromeMV3DeterministicJSON.write(
            report,
            to: rootURL.standardizedFileURL
                .appendingPathComponent(Self.reportFileName)
        )
        return report
    }

    private static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }
}

enum ChromeMV3NativeMessagingReadinessReportGenerator {
    static func makeReport(
        prerequisitesReport prerequisites:
            ChromeMV3RuntimeBridgePrerequisitesReport,
        profileID: String = "diagnostic-profile",
        requestedHostName: String? = nil,
        lookupPolicy: ChromeMV3NativeHostLookupPolicy = .macOS(),
        productPolicy: ChromeMV3NativeMessagingProductPolicy =
            .blockedRuntimeDefault,
        fileManager: FileManager = .default
    ) -> ChromeMV3NativeMessagingReadinessReport {
        let detected = prerequisites.manifestFacts
            .nativeMessagingPermissionPresent
            || prerequisites.nativeMessagingPrerequisites
            .nativeMessagingDetected
            || prerequisites.passwordManagerPrerequisiteSummary
            .nativeMessagingPermissionPresent
        let permissionState = permissionStateForPrerequisites(
            prerequisites,
            detected: detected
        )
        return makeReport(
            extensionID: prerequisites.candidateID,
            profileID: profileID,
            nativeMessagingPermissionDetected: detected,
            permissionState: permissionState,
            requestedHostName: requestedHostName,
            lookupPolicy: lookupPolicy,
            productPolicy: productPolicy,
            passwordManagerLikeFixtureDetected:
                prerequisites.passwordManagerPrerequisiteSummary
                .nativeMessagingPermissionPresent
                    || prerequisites.passwordManagerPrerequisiteSummary
                    .contentScriptsPresent
                    || prerequisites.passwordManagerPrerequisiteSummary
                    .actionPopupPresent,
            fileManager: fileManager
        )
    }

    static func makeReport(
        loadingPrerequisitesReportFrom rootURL: URL,
        profileID: String = "diagnostic-profile",
        requestedHostName: String? = nil,
        lookupPolicy: ChromeMV3NativeHostLookupPolicy = .macOS(),
        productPolicy: ChromeMV3NativeMessagingProductPolicy =
            .blockedRuntimeDefault,
        fileManager: FileManager = .default
    ) throws -> ChromeMV3NativeMessagingReadinessReport {
        let reportURL = rootURL.standardizedFileURL
            .appendingPathComponent(
                ChromeMV3RuntimeBridgePrerequisitesReportWriter
                    .reportFileName
            )
        let data = try Data(contentsOf: reportURL)
        let prerequisites = try JSONDecoder().decode(
            ChromeMV3RuntimeBridgePrerequisitesReport.self,
            from: data
        )
        return makeReport(
            prerequisitesReport: prerequisites,
            profileID: profileID,
            requestedHostName: requestedHostName,
            lookupPolicy: lookupPolicy,
            productPolicy: productPolicy,
            fileManager: fileManager
        )
    }

    static func makeReport(
        extensionID: String,
        profileID: String,
        nativeMessagingPermissionDetected: Bool,
        permissionState: ChromeMV3NativeMessagingPermissionState,
        requestedHostName: String?,
        lookupPolicy: ChromeMV3NativeHostLookupPolicy = .macOS(),
        productPolicy: ChromeMV3NativeMessagingProductPolicy =
            .blockedRuntimeDefault,
        passwordManagerLikeFixtureDetected: Bool = false,
        fileManager: FileManager = .default
    ) -> ChromeMV3NativeMessagingReadinessReport {
        let hostName = requestedHostName ?? "unknown.native.host"
        let expectedKnown = requestedHostName != nil
        let lookup = lookupPolicy.lookupHost(
            named: hostName,
            fileManager: fileManager
        )
        let longInput = ChromeMV3NativeMessagingPreflightInput(
            extensionID: extensionID,
            profileID: profileID,
            hostName: hostName,
            operationKind: .longLivedNativePort,
            sourceContext: .serviceWorker,
            permissionState: permissionState,
            productPolicy: productPolicy
        )
        let oneShotInput = ChromeMV3NativeMessagingPreflightInput(
            extensionID: extensionID,
            profileID: profileID,
            hostName: hostName,
            operationKind: .oneShotNativeMessage,
            sourceContext: .serviceWorker,
            permissionState: permissionState,
            productPolicy: productPolicy
        )
        let longPreflight = ChromeMV3NativeMessagingPreflightEvaluator
            .evaluate(
                input: longInput,
                lookupPolicy: lookupPolicy,
                lookupResult: lookup,
                fileManager: fileManager
            )
        let oneShotPreflight = ChromeMV3NativeMessagingPreflightEvaluator
            .evaluate(
                input: oneShotInput,
                lookupPolicy: lookupPolicy,
                lookupResult: lookup,
                fileManager: fileManager
            )
        let password = passwordSummary(
            nativeMessagingPermissionDetected:
                nativeMessagingPermissionDetected,
            expectedHostNameKnown: expectedKnown,
            expectedHostName: requestedHostName,
            authorization: longPreflight.authorizationResult,
            portLifecycle: longPreflight.portLifecycleContract,
            fixtureDetected: passwordManagerLikeFixtureDetected
        )
        let blockers = uniqueSorted(
            longPreflight.blockers
                + oneShotPreflight.blockers
                + password.blockers
                + [
                    "Native messaging readiness is false.",
                    "No native runtime execution is implemented.",
                ]
        )
        let reportID = stableID(
            prefix: "runtime-native-messaging-readiness",
            parts: [
                extensionID,
                profileID,
                hostName,
                permissionState.rawValue,
                lookup.status.rawValue,
                nativeMessagingPermissionDetected.description,
            ]
        )

        return ChromeMV3NativeMessagingReadinessReport(
            schemaVersion: 1,
            id: reportID,
            reportFileName:
                ChromeMV3NativeMessagingReadinessReportWriter.reportFileName,
            extensionID: extensionID,
            profileID: profileID,
            requestedHostName: hostName,
            expectedHostNameKnown: expectedKnown,
            nativeMessagingPermissionDetected:
                nativeMessagingPermissionDetected,
            permissionState: permissionState,
            hostLookupPolicy: lookupPolicy,
            hostLookupResult: lookup,
            hostManifestValidationSummary:
                lookup.manifest?.validationSummary,
            extensionToHostAuthorization:
                longPreflight.authorizationResult,
            longLivedPortPreflight: summary(longPreflight),
            oneShotMessagePreflight: summary(oneShotPreflight),
            messageFramingPolicy: .chromeStdioJSON,
            nativePortLifecycle: longPreflight.portLifecycleContract,
            serviceWorkerKeepaliveBlockers:
                longPreflight.serviceWorkerKeepaliveImplication.blockers,
            passwordManagerNativeMessagingSummary: password,
            canConnectNativeNow: false,
            canSendNativeMessageNow: false,
            processLaunchAllowedNow: false,
            canOpenPortNow: false,
            canWakeServiceWorkerNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            diagnostics: uniqueSorted(
                lookup.diagnostics
                    + longPreflight.diagnostics
                    + oneShotPreflight.diagnostics
                    + [
                        "Native messaging security model is deterministic.",
                        "Host validation exists but host execution remains blocked.",
                        "runtimeLoadable remains false.",
                    ]
            ),
            blockers: blockers,
            documentationSources: documentationSources()
        )
    }

    private static func permissionStateForPrerequisites(
        _ prerequisites: ChromeMV3RuntimeBridgePrerequisitesReport,
        detected: Bool
    ) -> ChromeMV3NativeMessagingPermissionState {
        if prerequisites.unsupportedDeferredAPIs.unsupportedAPIs
            .contains(.nativeMessaging)
        {
            return .unsupported
        }
        if prerequisites.unsupportedDeferredAPIs.deferredAPIs
            .contains(.nativeMessaging)
        {
            return .deferred
        }
        return detected ? .grantedByManifest : .missing
    }

    private static func summary(
        _ preflight: ChromeMV3NativeMessagingOperationPreflight
    ) -> ChromeMV3NativeMessagingPreflightSummary {
        ChromeMV3NativeMessagingPreflightSummary(
            operationID: preflight.operationID,
            operationKind: preflight.operationKind,
            hostLookupStatus: preflight.hostLookupResult.status,
            authorizedByManifest:
                preflight.authorizationResult.authorizedByManifest,
            hasNativeMessagingPermission:
                preflight.authorizationResult.hasNativeMessagingPermission,
            canConnectNativeNow: false,
            canSendNativeMessageNow: false,
            processLaunchAllowedNow: false,
            canOpenPortNow: false,
            canWakeServiceWorkerNow: false,
            blockerCount: preflight.blockers.count
        )
    }

    private static func passwordSummary(
        nativeMessagingPermissionDetected: Bool,
        expectedHostNameKnown: Bool,
        expectedHostName: String?,
        authorization: ChromeMV3NativeMessagingAuthorizationResult,
        portLifecycle: ChromeMV3NativeMessagingPortLifecycleContract,
        fixtureDetected: Bool
    ) -> ChromeMV3PasswordManagerNativeMessagingSummary {
        let relevant = fixtureDetected || nativeMessagingPermissionDetected
        return ChromeMV3PasswordManagerNativeMessagingSummary(
            nativeMessagingPermissionDetected:
                nativeMessagingPermissionDetected,
            expectedHostNameKnown: expectedHostNameKnown,
            expectedHostName: expectedHostName,
            hostManifestRequired: relevant,
            hostAuthorizationRequired: relevant,
            userConsentOrPolicyRequired:
                relevant && authorization.requiresUserConsent,
            nativePortRequiredForUnlockFillFlow: relevant,
            serviceWorkerKeepaliveNeededButBlocked:
                relevant && portLifecycle.keepaliveStartsNow == false,
            processLaunchImplemented: false,
            passwordManagerNativeMessagingReady: false,
            blockers: relevant
                ? uniqueSorted(
                    [
                        nativeMessagingPermissionDetected
                            ? "nativeMessaging permission is detected."
                            : "nativeMessaging permission is not detected.",
                        expectedHostNameKnown
                            ? nil
                            : "Expected password-manager native host name is unknown.",
                        "Native host manifest is required.",
                        "Extension-to-host authorization is required.",
                        authorization.requiresUserConsent
                            ? "User consent or product policy approval is required."
                            : "User consent and product policy remain future checks.",
                        "A native messaging Port is required for unlock/fill flow.",
                        "Service-worker keepalive would be needed but is blocked.",
                        "Native host process launch is not implemented.",
                        "Password-manager native messaging readiness remains false.",
                    ].compactMap { $0 }
                )
                : [
                    "No password-manager native messaging requirement was detected.",
                ]
        )
    }

    private static func documentationSources()
        -> [ChromeMV3ManifestRewritePreviewSource]
    {
        [
            source(
                title: "Chrome native messaging",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging",
                note: "Defines native host manifests, host name rules, allowed origins, lookup locations, stdio framing, size limits, host lifetime, and errors."
            ),
            source(
                title: "Chrome runtime API native messaging",
                url: "https://developer.chrome.com/docs/extensions/reference/api/runtime",
                note: "Defines native messaging permission requirements, native Port return shape, one-shot native message method, and Port disconnect behavior."
            ),
            source(
                title: "Chrome extension service-worker lifecycle",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle",
                note: "Defines native messaging Port impact on extension service-worker lifetime."
            ),
            ChromeMV3ManifestRewritePreviewSource(
                kind: .currentSumiCode,
                title: "Sumi Chrome MV3 runtime contracts",
                url: nil,
                note: "Existing Sumi contracts keep native messaging runtime execution blocked."
            ),
        ]
    }

    private static func source(
        title: String,
        url: String,
        note: String
    ) -> ChromeMV3ManifestRewritePreviewSource {
        ChromeMV3ManifestRewritePreviewSource(
            kind: .chromeDocumentation,
            title: title,
            url: url,
            note: note
        )
    }
}

private func isValidNativeHostName(_ value: String) -> Bool {
    guard value.isEmpty == false,
          value.first != ".",
          value.last != ".",
          value.contains("..") == false
    else { return false }
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_.")
    return value.unicodeScalars.allSatisfy { allowed.contains($0) }
}

private func isChromeExtensionID(_ value: String) -> Bool {
    guard value.count == 32 else { return false }
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnop")
    return value.unicodeScalars.allSatisfy { allowed.contains($0) }
}

private func stableID(prefix: String, parts: [String]) -> String {
    let seed = parts.joined(separator: "|")
    return "\(prefix)-\(sha256Hex(Data(seed.utf8)).prefix(32))"
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}

private func uniqueSorted(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}

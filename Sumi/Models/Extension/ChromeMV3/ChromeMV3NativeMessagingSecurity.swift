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

    static func nativeMessagingOriginExtensionID(
        for extensionID: String
    ) -> String {
        let normalized = extensionID.lowercased()
        guard isChromeExtensionID(normalized) == false else {
            return normalized
        }

        let alphabet = Array("abcdefghijklmnop")
        let digest = SHA256.hash(data: Data(extensionID.utf8))
        var mapped = ""
        for byte in digest {
            mapped.append(alphabet[Int(byte >> 4)])
            mapped.append(alphabet[Int(byte & 0x0f)])
            if mapped.count >= 32 {
                break
            }
        }
        return String(mapped.prefix(32))
    }

    static func originString(extensionID: String) -> String {
        "chrome-extension://\(nativeMessagingOriginExtensionID(for: extensionID))/"
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

struct ChromeMV3NativeHostDiscoveryRoot:
    Codable,
    Equatable,
    Sendable
{
    var discoveryRoot: String
    var reason: String
    var scanAllowed: Bool
    var hostsFound: [String]
    var hostsBlocked: [String]
    var diagnostics: [String]
}

struct ChromeMV3NativeHostDiscoveryPolicyReport:
    Codable,
    Equatable,
    Sendable
{
    var extensionModuleEnabled: Bool
    var nativeHostScanningAllowed: Bool
    var roots: [ChromeMV3NativeHostDiscoveryRoot]
    var arbitrarySystemScanPerformed: Bool
    var diagnostics: [String]

    static func make(
        lookupPolicy: ChromeMV3NativeHostLookupPolicy,
        requestedHostNames: [String]
    ) -> ChromeMV3NativeHostDiscoveryPolicyReport {
        guard lookupPolicy.extensionModuleEnabled else {
            return ChromeMV3NativeHostDiscoveryPolicyReport(
                extensionModuleEnabled: false,
                nativeHostScanningAllowed: false,
                roots: [],
                arbitrarySystemScanPerformed: false,
                diagnostics: [
                    "Extensions module is disabled; no native host discovery or manifest read occurs.",
                ]
            )
        }

        let requested = Set(
            requestedHostNames
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
        )
        let roots = lookupPolicy.locations.map { location in
            ChromeMV3NativeHostDiscoveryRoot(
                discoveryRoot: location.rootPath,
                reason:
                    location.lookupAllowedInThisModel
                        ? "Exact requested host manifest lookup root."
                        : "Future Chrome native host location recorded but not scanned.",
                scanAllowed:
                    location.lookupAllowedInThisModel
                        && location.arbitraryDirectoryScanAllowed,
                hostsFound: [],
                hostsBlocked:
                    location.lookupAllowedInThisModel
                        ? requested.sorted()
                        : [],
                diagnostics:
                    uniqueSorted(
                        location.diagnostics + [
                            "Directory enumeration is not performed.",
                            "Only exact host-name manifest lookup is allowed when a host name is supplied.",
                        ]
                    )
            )
        }
        return ChromeMV3NativeHostDiscoveryPolicyReport(
            extensionModuleEnabled: true,
            nativeHostScanningAllowed:
                roots.contains { $0.scanAllowed },
            roots: roots,
            arbitrarySystemScanPerformed: false,
            diagnostics: [
                "Native host discovery policy is conservative.",
                "No arbitrary system or user native host directory scan occurred.",
                "Real password-manager native hosts are not discovered unless explicitly configured as test fixtures.",
            ]
        )
    }
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
    var productGate: ChromeMV3NativeMessagingProductGateRecord

    static let blockedRuntimeDefault = ChromeMV3NativeMessagingProductPolicy(
        extensionModuleEnabled: true,
        nativeMessagingAllowedByProductPolicy: true,
        userConsentRequired: true,
        userConsentGranted: false
    )

    init(
        extensionModuleEnabled: Bool,
        nativeMessagingAllowedByProductPolicy: Bool,
        userConsentRequired: Bool,
        userConsentGranted: Bool,
        productGate: ChromeMV3NativeMessagingProductGateRecord? = nil
    ) {
        self.extensionModuleEnabled = extensionModuleEnabled
        self.nativeMessagingAllowedByProductPolicy =
            nativeMessagingAllowedByProductPolicy
        self.userConsentRequired = userConsentRequired
        self.userConsentGranted = userConsentGranted
        self.productGate =
            productGate ?? ChromeMV3NativeMessagingProductGateRecord
            .developerPreviewDefault(
                extensionModuleEnabled: extensionModuleEnabled,
                trustedHostPolicyAvailable:
                    nativeMessagingAllowedByProductPolicy
            )
    }
}

struct ChromeMV3NativeMessagingProductGateRecord:
    Codable,
    Equatable,
    Sendable
{
    var nativeMessagingAvailableInDeveloperPreview: Bool
    var nativeMessagingAvailableInPublicProduct: Bool
    var trustedHostPolicyAvailable: Bool
    var trustedHostApprovalRequired: Bool
    var arbitraryHostLaunchAllowed: Bool
    var nativeHostScanningAllowed: Bool
    var nativeHostProductBlockedReason: String
    var diagnostics: [String]

    static func developerPreviewDefault(
        extensionModuleEnabled: Bool = true,
        trustedHostPolicyAvailable: Bool = true,
        trustedHostApprovalRequired: Bool = true,
        nativeHostScanningAllowed: Bool = false
    ) -> ChromeMV3NativeMessagingProductGateRecord {
        let developerPreview =
            extensionModuleEnabled && trustedHostPolicyAvailable
        return ChromeMV3NativeMessagingProductGateRecord(
            nativeMessagingAvailableInDeveloperPreview: developerPreview,
            nativeMessagingAvailableInPublicProduct: false,
            trustedHostPolicyAvailable: trustedHostPolicyAvailable,
            trustedHostApprovalRequired: trustedHostApprovalRequired,
            arbitraryHostLaunchAllowed: false,
            nativeHostScanningAllowed: nativeHostScanningAllowed,
            nativeHostProductBlockedReason:
                developerPreview
                    ? "Native messaging is developer-preview only and still requires trusted-host approval."
                    : "Native messaging is blocked because the module or trusted-host policy gate is unavailable.",
            diagnostics: uniqueSorted([
                developerPreview
                    ? "Developer-preview native messaging gate can pass after permission, manifest, trusted-host, and executable checks."
                    : "Developer-preview native messaging gate is blocked.",
                "nativeMessagingAvailableInPublicProduct remains false.",
                "arbitraryHostLaunchAllowed remains false.",
                nativeHostScanningAllowed
                    ? "Native host scanning was explicitly enabled for a reviewed root policy."
                    : "nativeHostScanningAllowed is false by default.",
                "Trusted-host approval is separate from nativeMessaging API permission.",
            ])
        )
    }
}

enum ChromeMV3NativeTrustedHostTrustState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case unknown
    case manifestFound
    case manifestValid
    case extensionAuthorized
    case userApproved
    case userDenied
    case revoked
    case blocked
    case trustedForDeveloperPreview

    static func < (
        lhs: ChromeMV3NativeTrustedHostTrustState,
        rhs: ChromeMV3NativeTrustedHostTrustState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3NativeTrustedHostApprovalSource:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case developerPreviewManager
    case explicitTestFixture
    case importedPolicyRecord
    case none

    static func < (
        lhs: ChromeMV3NativeTrustedHostApprovalSource,
        rhs: ChromeMV3NativeTrustedHostApprovalSource
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3NativeTrustedHostControlKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case approveForDeveloperPreview
    case deny
    case revoke
    case reset

    static func < (
        lhs: ChromeMV3NativeTrustedHostControlKind,
        rhs: ChromeMV3NativeTrustedHostControlKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3NativeTrustedHostApprovalRecord:
    Codable,
    Equatable,
    Sendable
{
    var hostName: String
    var extensionID: String
    var profileID: String
    var manifestPath: String?
    var executablePath: String?
    var resolvedExecutablePath: String?
    var allowedOrigins: [String]
    var trustState: ChromeMV3NativeTrustedHostTrustState
    var observedTrustStates: [ChromeMV3NativeTrustedHostTrustState]
    var approvalSource: ChromeMV3NativeTrustedHostApprovalSource
    var approvalSequence: Int
    var approvalTimestamp: Date?
    var userConsentGranted: Bool
    var manifestSHA256: String?
    var executableInsideApprovedRoot: Bool
    var executableIsExecutable: Bool
    var arbitraryHostLaunchAllowed: Bool
    var nativeHostScanningAllowed: Bool
    var diagnostics: [String]

    var trustedForDeveloperPreview: Bool {
        trustState == .trustedForDeveloperPreview
            && userConsentGranted
            && executableInsideApprovedRoot
            && executableIsExecutable
            && arbitraryHostLaunchAllowed == false
            && nativeHostScanningAllowed == false
    }

    var canLaunchTrustedFixtureHost: Bool {
        trustedForDeveloperPreview
    }

    static func unknown(
        hostName: String,
        extensionID: String,
        profileID: String,
        diagnostics: [String] = []
    ) -> ChromeMV3NativeTrustedHostApprovalRecord {
        ChromeMV3NativeTrustedHostApprovalRecord(
            hostName: hostName,
            extensionID: extensionID,
            profileID: profileID,
            manifestPath: nil,
            executablePath: nil,
            resolvedExecutablePath: nil,
            allowedOrigins: [],
            trustState: .unknown,
            observedTrustStates: [.unknown],
            approvalSource: .none,
            approvalSequence: 0,
            approvalTimestamp: nil,
            userConsentGranted: false,
            manifestSHA256: nil,
            executableInsideApprovedRoot: false,
            executableIsExecutable: false,
            arbitraryHostLaunchAllowed: false,
            nativeHostScanningAllowed: false,
            diagnostics:
                uniqueSorted(
                    diagnostics + [
                        "No trusted-host approval record exists for this extension/profile/host.",
                    ]
                )
        )
    }
}

struct ChromeMV3NativeTrustedHostPolicyEvaluation:
    Codable,
    Equatable,
    Sendable
{
    var record: ChromeMV3NativeTrustedHostApprovalRecord
    var diagnostics: [String]
}

enum ChromeMV3NativeTrustedHostPolicyEvaluator {
    static func evaluate(
        hostName: String,
        extensionID: String,
        profileID: String,
        lookupResult: ChromeMV3NativeHostLookupResult,
        authorizationResult: ChromeMV3NativeMessagingAuthorizationResult,
        approvedRootPaths: [String],
        control: ChromeMV3NativeTrustedHostControlKind,
        sequence: Int,
        now: Date? = Date(),
        existingRecord: ChromeMV3NativeTrustedHostApprovalRecord? = nil,
        fileManager: FileManager = .default
    ) -> ChromeMV3NativeTrustedHostPolicyEvaluation {
        let normalizedHostName = hostName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let manifest = lookupResult.manifest
        let executable = manifest?.path
        let resolvedExecutable =
            executable.map {
                URL(fileURLWithPath: $0)
                    .resolvingSymlinksInPath()
                    .standardizedFileURL
            }
        let resolvedRoots = approvedRootPaths.map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .resolvingSymlinksInPath()
                .standardizedFileURL
        }
        let insideRoot = resolvedExecutable.map { executable in
            resolvedRoots.contains { root in
                executable.path == root.path
                    || executable.path.hasPrefix(root.path + "/")
            }
        } ?? false
        let executableOK = resolvedExecutable.map {
            fileManager.isExecutableFile(atPath: $0.path)
        } ?? false
        let sourceAllowed =
            manifest?.sourceLocation.kind == .explicitTestRoot
                && manifest?.sourceLocation.lookupAllowedInThisModel == true
        var states: [ChromeMV3NativeTrustedHostTrustState] = [.unknown]
        if lookupResult.status == .found || lookupResult.manifest != nil {
            states.append(.manifestFound)
        }
        if manifest?.isValid == true {
            states.append(.manifestValid)
        }
        if authorizationResult.authorizedByManifest {
            states.append(.extensionAuthorized)
        }

        let trustState: ChromeMV3NativeTrustedHostTrustState
        let userConsent: Bool
        switch control {
        case .approveForDeveloperPreview:
            if lookupResult.status == .found
                && manifest?.isValid == true
                && authorizationResult.authorizedByManifest
                && sourceAllowed
                && insideRoot
                && executableOK
            {
                trustState = .trustedForDeveloperPreview
                states.append(contentsOf: [
                    .userApproved,
                    .trustedForDeveloperPreview,
                ])
                userConsent = true
            } else {
                trustState = .blocked
                states.append(.blocked)
                userConsent = false
            }
        case .deny:
            trustState = .userDenied
            states.append(.userDenied)
            userConsent = false
        case .revoke:
            trustState = .revoked
            states.append(.revoked)
            userConsent = false
        case .reset:
            return ChromeMV3NativeTrustedHostPolicyEvaluation(
                record: .unknown(
                    hostName: normalizedHostName,
                    extensionID: extensionID,
                    profileID: profileID,
                    diagnostics: [
                        "Trusted-host policy state was reset by explicit developer-preview control.",
                    ]
                ),
                diagnostics: [
                    "Trusted-host approval record reset; no host launch was attempted.",
                ]
            )
        }

        let diagnostics = uniqueSorted(
            lookupResult.diagnostics
                + authorizationResult.diagnostics
                + (existingRecord?.diagnostics ?? [])
                + [
                    sourceAllowed
                        ? "Host manifest was found under an explicit approved root."
                        : "Host manifest source is not approved for launch.",
                    insideRoot
                        ? "Resolved executable remains under an approved root."
                        : "Resolved executable escapes approved roots or is unavailable.",
                    executableOK
                        ? "Resolved executable is executable."
                        : "Resolved executable is missing or not executable.",
                    "Trusted-host control \(control.rawValue) required explicit user action.",
                    "Approval did not launch the native host.",
                    "arbitraryHostLaunchAllowed remains false.",
                    "nativeHostScanningAllowed remains false.",
                ]
        )
        return ChromeMV3NativeTrustedHostPolicyEvaluation(
            record: ChromeMV3NativeTrustedHostApprovalRecord(
                hostName: normalizedHostName,
                extensionID: extensionID,
                profileID: profileID,
                manifestPath: manifest?.sourceLocation.manifestPath,
                executablePath: executable,
                resolvedExecutablePath: resolvedExecutable?.path,
                allowedOrigins:
                    manifest?.allowedOrigins.map(\.rawValue).sorted() ?? [],
                trustState: trustState,
                observedTrustStates: Array(Set(states)).sorted(),
                approvalSource:
                    control == .approveForDeveloperPreview
                        ? .developerPreviewManager
                        : .none,
                approvalSequence: sequence,
                approvalTimestamp:
                    control == .approveForDeveloperPreview ? now : nil,
                userConsentGranted: userConsent,
                manifestSHA256: manifest?.canonicalJSONSHA256,
                executableInsideApprovedRoot: insideRoot,
                executableIsExecutable: executableOK,
                arbitraryHostLaunchAllowed: false,
                nativeHostScanningAllowed: false,
                diagnostics: diagnostics
            ),
            diagnostics: diagnostics
        )
    }
}

struct ChromeMV3NativeTrustedHostPolicySnapshot:
    Codable,
    Equatable,
    Sendable
{
    static let schemaVersion = 1

    var schemaVersion: Int
    var profileID: String
    var extensionID: String
    var records: [ChromeMV3NativeTrustedHostApprovalRecord]
    var diagnostics: [String]

    init(
        schemaVersion: Int = Self.schemaVersion,
        profileID: String,
        extensionID: String,
        records: [ChromeMV3NativeTrustedHostApprovalRecord] = [],
        diagnostics: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.profileID = profileID
        self.extensionID = extensionID
        self.records = records.sorted {
            if $0.hostName != $1.hostName {
                return $0.hostName < $1.hostName
            }
            return $0.approvalSequence < $1.approvalSequence
        }
        self.diagnostics = uniqueSorted(diagnostics)
    }

    func record(
        hostName: String
    ) -> ChromeMV3NativeTrustedHostApprovalRecord? {
        records.last { $0.hostName == hostName }
    }

    func replacing(
        _ record: ChromeMV3NativeTrustedHostApprovalRecord
    ) -> ChromeMV3NativeTrustedHostPolicySnapshot {
        ChromeMV3NativeTrustedHostPolicySnapshot(
            profileID: profileID,
            extensionID: extensionID,
            records:
                records.filter { $0.hostName != record.hostName } + [record],
            diagnostics:
                diagnostics + [
                    "Trusted-host policy record \(record.trustState.rawValue) stored for \(record.hostName).",
                ]
        )
    }

    func removing(
        hostName: String
    ) -> ChromeMV3NativeTrustedHostPolicySnapshot {
        ChromeMV3NativeTrustedHostPolicySnapshot(
            profileID: profileID,
            extensionID: extensionID,
            records: records.filter { $0.hostName != hostName },
            diagnostics:
                diagnostics + [
                    "Trusted-host policy record reset for \(hostName).",
                ]
        )
    }
}

struct ChromeMV3NativeTrustedHostPolicyStore {
    var rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    func loadSnapshot(
        profileID: String,
        extensionID: String
    ) -> ChromeMV3NativeTrustedHostPolicySnapshot {
        let url = snapshotURL(profileID: profileID, extensionID: extensionID)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(
                ChromeMV3NativeTrustedHostPolicySnapshot.self,
                from: data
              )
        else {
            return ChromeMV3NativeTrustedHostPolicySnapshot(
                profileID: profileID,
                extensionID: extensionID,
                diagnostics: [
                    "No persisted trusted native host policy snapshot exists.",
                ]
            )
        }
        return snapshot
    }

    func saveSnapshot(
        _ snapshot: ChromeMV3NativeTrustedHostPolicySnapshot
    ) throws -> ChromeMV3NativeTrustedHostPolicySnapshot {
        let url = snapshotURL(
            profileID: snapshot.profileID,
            extensionID: snapshot.extensionID
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try ChromeMV3DeterministicJSON.write(snapshot, to: url)
        return snapshot
    }

    func record(
        profileID: String,
        extensionID: String,
        hostName: String
    ) -> ChromeMV3NativeTrustedHostApprovalRecord? {
        loadSnapshot(profileID: profileID, extensionID: extensionID)
            .record(hostName: hostName)
    }

    func saveRecord(
        _ record: ChromeMV3NativeTrustedHostApprovalRecord
    ) throws -> ChromeMV3NativeTrustedHostPolicySnapshot {
        let snapshot = loadSnapshot(
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        return try saveSnapshot(snapshot.replacing(record))
    }

    func resetRecord(
        profileID: String,
        extensionID: String,
        hostName: String
    ) throws -> ChromeMV3NativeTrustedHostPolicySnapshot {
        let snapshot = loadSnapshot(
            profileID: profileID,
            extensionID: extensionID
        )
        return try saveSnapshot(snapshot.removing(hostName: hostName))
    }

    func snapshotURL(profileID: String, extensionID: String) -> URL {
        rootURL
            .appendingPathComponent(
                "native-host-policy",
                isDirectory: true
            )
            .appendingPathComponent(profileID, isDirectory: true)
            .appendingPathComponent("\(extensionID).json")
    }
}

enum ChromeMV3NativeTrustedHostPolicyFactory {
    static func recordForExplicitDeveloperPreviewApproval(
        hostName: String,
        extensionID: String,
        profileID: String,
        lookupPolicy: ChromeMV3NativeHostLookupPolicy,
        permissionState: ChromeMV3NativeMessagingPermissionState,
        productPolicy: ChromeMV3NativeMessagingProductPolicy =
            .blockedRuntimeDefault,
        approvedRootPaths: [String],
        sequence: Int,
        now: Date? = Date(),
        fileManager: FileManager = .default
    ) -> ChromeMV3NativeTrustedHostPolicyEvaluation {
        let lookup = lookupPolicy.lookupHost(
            named: hostName,
            fileManager: fileManager
        )
        let authorization = ChromeMV3NativeMessagingAuthorizationEvaluator
            .evaluate(
                extensionID: extensionID,
                permissionState: permissionState,
                hostManifest: lookup.manifest,
                productPolicy: productPolicy
            )
        return ChromeMV3NativeTrustedHostPolicyEvaluator.evaluate(
            hostName: hostName,
            extensionID: extensionID,
            profileID: profileID,
            lookupResult: lookup,
            authorizationResult: authorization,
            approvedRootPaths: approvedRootPaths,
            control: .approveForDeveloperPreview,
            sequence: sequence,
            now: now,
            fileManager: fileManager
        )
    }
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
        let nativeOriginExtensionID =
            ChromeMV3NativeMessagingAllowedOrigin
            .nativeMessagingOriginExtensionID(for: extensionID)
        let extensionOrigin =
            ChromeMV3NativeMessagingAllowedOrigin
            .originString(extensionID: extensionID)
        let rawExtensionOriginValid = isChromeExtensionID(
            extensionID.lowercased()
        )
        let manifestValid = hostManifest?.isValid == true
        let allowed = hostManifest?.allowedOrigins.contains {
            $0.isValid && $0.extensionID == nativeOriginExtensionID
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
            authorizedByManifest: allowed && manifestValid,
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
                    rawExtensionOriginValid
                        ? "Extension origin has Chrome native messaging format."
                        : "Sumi developer-preview native messaging origin alias is used for this internal extension id.",
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
        profileID: String,
        canOpenPortNow: Bool = false,
        processLaunchAllowedNow: Bool = false,
        portLifecycleImplemented: Bool = false
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
            canOpenPortNow: canOpenPortNow,
            keepaliveStartsNow: false,
            processLaunchAllowedNow: processLaunchAllowedNow,
            portLifecycleImplemented: portLifecycleImplemented,
            serviceWorkerKeepaliveSource: keepalive,
            cleanupTriggers: [
                "disabled extension cleanup",
                "permission revoke cleanup",
                "trusted host revoke cleanup",
                "profile close cleanup",
                "host exit cleanup",
            ],
            disconnectReasons:
                ChromeMV3NativeMessagingDisconnectReason.allCases.sorted(),
            diagnostics: uniqueSorted(
                keepalive.blockers
                    + [
                        portLifecycleImplemented
                            ? "Native Port lifecycle is developer-preview trusted-host scoped."
                            : "Native Port lifecycle is modeled only.",
                        canOpenPortNow
                            ? "Native messaging Port can open only after trusted-host developer-preview gates pass."
                            : "No native messaging Port is opened.",
                        "No service-worker keepalive starts now.",
                        processLaunchAllowedNow
                            ? "Host process launch is limited to the approved fixture/trusted root."
                            : "No host process launch is allowed now.",
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
    var trustedHostPolicyRecord:
        ChromeMV3NativeTrustedHostApprovalRecord? = nil
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
    var productGate:
        ChromeMV3NativeMessagingProductGateRecord
    var trustedHostPolicyRecord:
        ChromeMV3NativeTrustedHostApprovalRecord?
    var serviceWorkerKeepaliveImplication:
        ChromeMV3ServiceWorkerKeepaliveSource
    var messageFramingPolicy:
        ChromeMV3NativeMessagingFramingPolicy
    var portLifecycleContract:
        ChromeMV3NativeMessagingPortLifecycleContract
    var trustedHostPolicyApproved: Bool
    var userConsentSatisfied: Bool
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
        let productGate = input.productPolicy.productGate
        let trustedRecord = input.trustedHostPolicyRecord
        let trustedRecordMatches =
            trustedRecord?.hostName == input.hostName
                && trustedRecord?.extensionID == input.extensionID
                && trustedRecord?.profileID == input.profileID
                && trustedRecord?.manifestSHA256
                    == hostLookup.manifest?.canonicalJSONSHA256
        let trustedPolicyApproved =
            trustedRecordMatches
                && trustedRecord?.trustedForDeveloperPreview == true
        let userConsentSatisfied =
            authorization.requiresUserConsent == false
                || input.productPolicy.userConsentGranted
                || trustedRecord?.userConsentGranted == true
        let productDeveloperPreviewAllowed =
            productGate.nativeMessagingAvailableInDeveloperPreview
                && input.productPolicy.nativeMessagingAllowedByProductPolicy
                && productGate.nativeMessagingAvailableInPublicProduct == false
                && productGate.arbitraryHostLaunchAllowed == false
                && productGate.nativeHostScanningAllowed == false
        let launchAllowedNow =
            hostLookup.status == .found
                && authorization.hasNativeMessagingPermission
                && authorization.authorizedByManifest
                && authorization.blockedByPolicy == false
                && productDeveloperPreviewAllowed
                && trustedPolicyApproved
                && userConsentSatisfied
        let lifecycle = ChromeMV3NativeMessagingPortLifecycleContract.model(
            operationID: operationID,
            operationKind: input.operationKind,
            hostName: input.hostName,
            extensionID: input.extensionID,
            profileID: input.profileID,
            canOpenPortNow:
                launchAllowedNow
                    && input.operationKind == .longLivedNativePort,
            processLaunchAllowedNow: launchAllowedNow,
            portLifecycleImplemented: launchAllowedNow
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
                productDeveloperPreviewAllowed
                    ? nil
                    : "Developer-preview product gate blocks native messaging.",
                trustedPolicyApproved
                    ? nil
                    : "Trusted native host approval is required.",
                userConsentSatisfied
                    ? nil
                    : "User consent is required for native host access.",
                authorization.requiresUserConsent && userConsentSatisfied == false
                    ? "User consent or product policy approval is required."
                    : nil,
                launchAllowedNow
                    ? nil
                    : "Native messaging runtime is blocked until every trusted-host gate passes.",
                launchAllowedNow
                    ? nil
                    : "Native host process launch is blocked.",
                input.operationKind == .longLivedNativePort && launchAllowedNow
                    ? nil
                    : "No native messaging Port is opened.",
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
            productGate: productGate,
            trustedHostPolicyRecord: trustedRecord,
            serviceWorkerKeepaliveImplication: keepalive,
            messageFramingPolicy: .chromeStdioJSON,
            portLifecycleContract: lifecycle,
            trustedHostPolicyApproved: trustedPolicyApproved,
            userConsentSatisfied: userConsentSatisfied,
            canConnectNativeNow:
                launchAllowedNow
                    && input.operationKind == .longLivedNativePort,
            canSendNativeMessageNow:
                launchAllowedNow
                    && input.operationKind == .oneShotNativeMessage,
            processLaunchAllowedNow: launchAllowedNow,
            nativeMessagingRuntimeImplemented: launchAllowedNow,
            canOpenPortNow:
                launchAllowedNow
                    && input.operationKind == .longLivedNativePort,
            canWakeServiceWorkerNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            blockers: blockers,
            diagnostics: uniqueSorted(
                hostLookup.diagnostics
                    + authorization.diagnostics
                    + productGate.diagnostics
                    + (trustedRecord?.diagnostics ?? [
                        "No trusted-host policy record was supplied.",
                    ])
                    + keepalive.blockers
                    + lifecycle.diagnostics
                    + [
                        "Operation \(input.operationKind.rawValue) is preflight-only.",
                        launchAllowedNow
                            ? "Trusted developer-preview native host launch preflight passed."
                            : "Trusted developer-preview native host launch preflight did not pass.",
                        "canConnectNativeNow=\(launchAllowedNow && input.operationKind == .longLivedNativePort).",
                        "canSendNativeMessageNow=\(launchAllowedNow && input.operationKind == .oneShotNativeMessage).",
                        "processLaunchAllowedNow=\(launchAllowedNow).",
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
    var trustedHostPolicyState: ChromeMV3NativeTrustedHostTrustState
    var trustedHostApprovalRequired: Bool
    var trustedHostApprovedForDeveloperPreview: Bool
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
    var trustedHostPolicyApproved: Bool
    var userConsentSatisfied: Bool
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
    var trustedHostPolicyApproved: Bool
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
    var hostDiscoveryPolicyReport:
        ChromeMV3NativeHostDiscoveryPolicyReport
    var hostLookupResult: ChromeMV3NativeHostLookupResult
    var hostManifestValidationSummary:
        ChromeMV3NativeHostManifestValidationSummary?
    var extensionToHostAuthorization:
        ChromeMV3NativeMessagingAuthorizationResult
    var trustedHostPolicyRecord:
        ChromeMV3NativeTrustedHostApprovalRecord?
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
            trustedHostPolicyApproved:
                longLivedPortPreflight.trustedHostPolicyApproved
                    || oneShotMessagePreflight.trustedHostPolicyApproved,
            canConnectNativeNow:
                longLivedPortPreflight.canConnectNativeNow,
            canSendNativeMessageNow:
                oneShotMessagePreflight.canSendNativeMessageNow,
            processLaunchAllowedNow: processLaunchAllowedNow,
            canOpenPortNow: canOpenPortNow,
            canWakeServiceWorkerNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            passwordManagerNativeMessagingReady:
                passwordManagerNativeMessagingSummary
                .passwordManagerNativeMessagingReady
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
        trustedHostPolicyRecord:
            ChromeMV3NativeTrustedHostApprovalRecord? = nil,
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
            trustedHostPolicyRecord: trustedHostPolicyRecord,
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
        trustedHostPolicyRecord:
            ChromeMV3NativeTrustedHostApprovalRecord? = nil,
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
            trustedHostPolicyRecord: trustedHostPolicyRecord,
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
        trustedHostPolicyRecord:
            ChromeMV3NativeTrustedHostApprovalRecord? = nil,
        passwordManagerLikeFixtureDetected: Bool = false,
        fileManager: FileManager = .default
    ) -> ChromeMV3NativeMessagingReadinessReport {
        let hostName = requestedHostName ?? "unknown.native.host"
        let expectedKnown = requestedHostName != nil
        let lookup = lookupPolicy.lookupHost(
            named: hostName,
            fileManager: fileManager
        )
        let discovery = ChromeMV3NativeHostDiscoveryPolicyReport.make(
            lookupPolicy: lookupPolicy,
            requestedHostNames: [hostName]
        )
        let longInput = ChromeMV3NativeMessagingPreflightInput(
            extensionID: extensionID,
            profileID: profileID,
            hostName: hostName,
            operationKind: .longLivedNativePort,
            sourceContext: .serviceWorker,
            permissionState: permissionState,
            productPolicy: productPolicy,
            trustedHostPolicyRecord: trustedHostPolicyRecord
        )
        let oneShotInput = ChromeMV3NativeMessagingPreflightInput(
            extensionID: extensionID,
            profileID: profileID,
            hostName: hostName,
            operationKind: .oneShotNativeMessage,
            sourceContext: .serviceWorker,
            permissionState: permissionState,
            productPolicy: productPolicy,
            trustedHostPolicyRecord: trustedHostPolicyRecord
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
            trustedRecord: trustedHostPolicyRecord,
            fixtureDetected: passwordManagerLikeFixtureDetected
        )
        let blockers = uniqueSorted(
            longPreflight.blockers
                + oneShotPreflight.blockers
                + password.blockers
                + [
                    "Native messaging readiness is false.",
                    longPreflight.processLaunchAllowedNow
                        || oneShotPreflight.processLaunchAllowedNow
                        ? "Native messaging readiness is developer-preview trusted-host scoped."
                        : "No native runtime execution is implemented.",
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
                trustedHostPolicyRecord?.trustState.rawValue
                    ?? "no-trusted-host-record",
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
            hostDiscoveryPolicyReport: discovery,
            hostLookupResult: lookup,
            hostManifestValidationSummary:
                lookup.manifest?.validationSummary,
            extensionToHostAuthorization:
                longPreflight.authorizationResult,
            trustedHostPolicyRecord: trustedHostPolicyRecord,
            longLivedPortPreflight: summary(longPreflight),
            oneShotMessagePreflight: summary(oneShotPreflight),
            messageFramingPolicy: .chromeStdioJSON,
            nativePortLifecycle: longPreflight.portLifecycleContract,
            serviceWorkerKeepaliveBlockers:
                longPreflight.serviceWorkerKeepaliveImplication.blockers,
            passwordManagerNativeMessagingSummary: password,
            canConnectNativeNow: longPreflight.canConnectNativeNow,
            canSendNativeMessageNow: oneShotPreflight.canSendNativeMessageNow,
            processLaunchAllowedNow:
                longPreflight.processLaunchAllowedNow
                    || oneShotPreflight.processLaunchAllowedNow,
            canOpenPortNow: longPreflight.canOpenPortNow,
            canWakeServiceWorkerNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            diagnostics: uniqueSorted(
                lookup.diagnostics
                    + discovery.diagnostics
                    + longPreflight.diagnostics
                    + oneShotPreflight.diagnostics
                    + [
                        "Native messaging security model is deterministic.",
                        longPreflight.processLaunchAllowedNow
                            || oneShotPreflight.processLaunchAllowedNow
                            ? "Host validation and trusted-host preflight passed for developer-preview fixture scope."
                            : "Host validation exists but host execution remains blocked.",
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
            trustedHostPolicyApproved:
                preflight.trustedHostPolicyApproved,
            userConsentSatisfied: preflight.userConsentSatisfied,
            canConnectNativeNow: preflight.canConnectNativeNow,
            canSendNativeMessageNow: preflight.canSendNativeMessageNow,
            processLaunchAllowedNow: preflight.processLaunchAllowedNow,
            canOpenPortNow: preflight.canOpenPortNow,
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
        trustedRecord: ChromeMV3NativeTrustedHostApprovalRecord?,
        fixtureDetected: Bool
    ) -> ChromeMV3PasswordManagerNativeMessagingSummary {
        let relevant = fixtureDetected || nativeMessagingPermissionDetected
        let trustedReady =
            trustedRecord?.trustedForDeveloperPreview == true
                && authorization.hasNativeMessagingPermission
                && authorization.authorizedByManifest
        return ChromeMV3PasswordManagerNativeMessagingSummary(
            nativeMessagingPermissionDetected:
                nativeMessagingPermissionDetected,
            expectedHostNameKnown: expectedHostNameKnown,
            expectedHostName: expectedHostName,
            hostManifestRequired: relevant,
            hostAuthorizationRequired: relevant,
            userConsentOrPolicyRequired:
                relevant && authorization.requiresUserConsent,
            trustedHostPolicyState:
                trustedRecord?.trustState ?? .unknown,
            trustedHostApprovalRequired:
                relevant && trustedRecord?.trustedForDeveloperPreview != true,
            trustedHostApprovedForDeveloperPreview:
                trustedRecord?.trustedForDeveloperPreview == true,
            nativePortRequiredForUnlockFillFlow: relevant,
            serviceWorkerKeepaliveNeededButBlocked:
                relevant && portLifecycle.keepaliveStartsNow == false,
            processLaunchImplemented: false,
            passwordManagerNativeMessagingReady: relevant && trustedReady,
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
                        trustedRecord?.trustedForDeveloperPreview == true
                            ? nil
                            : "Trusted-host approval is required.",
                        "A native messaging Port is required for unlock/fill flow.",
                        "Service-worker keepalive would be needed but is blocked.",
                        trustedReady
                            ? "Password-manager fixture has permission, allowed_origins, and trusted-host approval."
                            : "Password-manager native messaging readiness remains false.",
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

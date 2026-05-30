//
//  ChromeMV3NativeMessagingFixturePack.swift
//  Sumi
//
//  Deterministic local experimental native messaging fixture packs. Packs
//  describe or generate hosts only under explicit fixture roots and never
//  discover or launch real vendor native hosts.
//

import CryptoKit
import Foundation

enum ChromeMV3NativeMessagingFixtureMessageProtocol:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case disconnect
    case echo
    case error
    case malformed

    static func < (
        lhs: ChromeMV3NativeMessagingFixtureMessageProtocol,
        rhs: ChromeMV3NativeMessagingFixtureMessageProtocol
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var hostKind: ChromeMV3NativeMessagingFixtureHostKind {
        switch self {
        case .disconnect:
            return .disconnectAfterRead
        case .echo:
            return .echo
        case .error:
            return .errorResponse
        case .malformed:
            return .malformedFrame
        }
    }

    func hostName(baseHostName: String) -> String {
        switch self {
        case .echo:
            return baseHostName
        case .disconnect, .error, .malformed:
            return "\(baseHostName).\(rawValue)"
        }
    }
}

enum ChromeMV3NativeMessagingFixturePackGeneratedState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case generated
    case missingFixtureRoot
    case notConfigured
    case notGenerated

    static func < (
        lhs: ChromeMV3NativeMessagingFixturePackGeneratedState,
        rhs: ChromeMV3NativeMessagingFixturePackGeneratedState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3NativeMessagingFixturePackValidatedState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case invalid
    case notEvaluated
    case valid

    static func < (
        lhs: ChromeMV3NativeMessagingFixturePackValidatedState,
        rhs: ChromeMV3NativeMessagingFixturePackValidatedState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3NativeMessagingFixturePackCleanupState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case failed
    case notRequired
    case pending
    case removed

    static func < (
        lhs: ChromeMV3NativeMessagingFixturePackCleanupState,
        rhs: ChromeMV3NativeMessagingFixturePackCleanupState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3NativeMessagingFixturePackRecord:
    Codable,
    Equatable,
    Sendable
{
    var packID: String
    var targetID: String
    var hostName: String
    var fixtureRootPath: String
    var manifestPath: String?
    var executablePath: String?
    var resolvedExecutablePath: String?
    var allowedOrigins: [String]
    var messageProtocol: ChromeMV3NativeMessagingFixtureMessageProtocol
    var noNetworkInvariant: Bool
    var noCredentialsInvariant: Bool
    var generatedState: ChromeMV3NativeMessagingFixturePackGeneratedState
    var validatedState: ChromeMV3NativeMessagingFixturePackValidatedState
    var cleanupState: ChromeMV3NativeMessagingFixturePackCleanupState
    var manifestValidation: ChromeMV3NativeHostManifestValidationSummary?
    var executableInsideFixtureRoot: Bool
    var executableIsExecutable: Bool
    var diagnostics: [String]
}

struct ChromeMV3NativeMessagingFixturePack:
    Codable,
    Equatable,
    Sendable
{
    var packID: String
    var targetID: String
    var fixtureRootPath: String?
    var allowedOrigins: [String]
    var records: [ChromeMV3NativeMessagingFixturePackRecord]
    var noNetworkInvariant: Bool
    var noCredentialsInvariant: Bool
    var generatedState: ChromeMV3NativeMessagingFixturePackGeneratedState
    var validatedState: ChromeMV3NativeMessagingFixturePackValidatedState
    var cleanupState: ChromeMV3NativeMessagingFixturePackCleanupState
    var realVendorHostDiscoveryBlocked: Bool
    var arbitraryHostLaunchAllowed: Bool
    var diagnostics: [String]

    func record(
        for messageProtocol: ChromeMV3NativeMessagingFixtureMessageProtocol,
        baseHostName: String
    ) -> ChromeMV3NativeMessagingFixturePackRecord? {
        let expected = messageProtocol.hostName(baseHostName: baseHostName)
        return records.first {
            $0.messageProtocol == messageProtocol && $0.hostName == expected
        }
    }

    func record(
        hostName: String
    ) -> ChromeMV3NativeMessagingFixturePackRecord? {
        records.first { $0.hostName == hostName }
    }
}

enum ChromeMV3NativeMessagingFixturePackBuilder {
    static func writePack(
        targetID: String,
        fixtureRootURL: URL,
        baseHostName: String,
        extensionID: String,
        protocols: [ChromeMV3NativeMessagingFixtureMessageProtocol] = [.echo],
        fileManager: FileManager = .default
    ) throws -> ChromeMV3NativeMessagingFixturePack {
        let root = fixtureRootURL.standardizedFileURL
        let uniqueProtocols = Array(Set(protocols)).sorted()
        let packID = makePackID(
            targetID: targetID,
            fixtureRootPath: root.path,
            baseHostName: baseHostName,
            extensionID: extensionID,
            protocols: uniqueProtocols
        )

        var records: [ChromeMV3NativeMessagingFixturePackRecord] = []
        for messageProtocol in uniqueProtocols {
            let hostName = messageProtocol.hostName(baseHostName: baseHostName)
            let syntaxCheck = ChromeMV3NativeHostLookupPolicy
                .macOS(explicitTestRootPath: root.path)
                .lookupHost(named: hostName, fileManager: fileManager)
            guard syntaxCheck.status != .invalidHostName else {
                throw ChromeMV3NativeMessagingRuntimeError.make(
                    .invalidHostName,
                    [
                        "Fixture pack host \(hostName) is not a valid Chrome native messaging host name.",
                    ]
                )
            }

            _ = try ChromeMV3NativeMessagingFixtureHostBuilder.writeFixtureHost(
                kind: messageProtocol.hostKind,
                rootURL: root,
                hostName: hostName,
                extensionID: extensionID
            )
            let record = describeRecord(
                packID: packID,
                targetID: targetID,
                root: root,
                hostName: hostName,
                extensionID: extensionID,
                messageProtocol: messageProtocol,
                generatedState: .generated,
                fileManager: fileManager
            )
            records.append(record)
        }

        return pack(
            packID: packID,
            targetID: targetID,
            rootPath: root.path,
            records: records,
            diagnostics: [
                "Fixture pack generated deterministic native host manifests and scripts under an explicit fixture root.",
                "Fixture pack hosts are no-network and no-credential test executables.",
                "Real vendor host discovery and arbitrary host launch remain blocked.",
            ]
        )
    }

    static func describeExistingPack(
        targetID: String,
        fixtureRootPath: String?,
        hostNames: [String],
        extensionID: String,
        fileManager: FileManager = .default
    ) -> ChromeMV3NativeMessagingFixturePack {
        let uniqueHostNames = uniqueSortedFixturePack(hostNames)
        let rootPath = fixtureRootPath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .standardizedFileURL
                .path
        }
        let packID = makePackID(
            targetID: targetID,
            fixtureRootPath: rootPath ?? "not-configured",
            baseHostName: uniqueHostNames.first ?? "host-name-not-observable",
            extensionID: extensionID,
            protocols: [.echo]
        )
        guard let rootPath else {
            return pack(
                packID: packID,
                targetID: targetID,
                rootPath: nil,
                records: [],
                generatedState: .notConfigured,
                validatedState: .notEvaluated,
                diagnostics: [
                    "Fixture pack was not configured because no explicit fixture root path was supplied.",
                    "Real vendor host discovery remains blocked.",
                ]
            )
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootPath, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return pack(
                packID: packID,
                targetID: targetID,
                rootPath: rootPath,
                records: [],
                generatedState: .missingFixtureRoot,
                validatedState: .notEvaluated,
                diagnostics: [
                    "Fixture pack root is missing or is not a directory.",
                    "No real native host directories were scanned.",
                ]
            )
        }

        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            .standardizedFileURL
        let records = uniqueHostNames.map { hostName in
            describeRecord(
                packID: packID,
                targetID: targetID,
                root: root,
                hostName: hostName,
                extensionID: extensionID,
                messageProtocol: .echo,
                generatedState: .notGenerated,
                fileManager: fileManager
            )
        }
        return pack(
            packID: packID,
            targetID: targetID,
            rootPath: root.path,
            records: records,
            diagnostics: [
                "Fixture pack inspected exact host-name manifests under an explicit fixture root.",
                "Directory-wide native host discovery was not performed by the pack.",
                "Real vendor host launch remains blocked.",
            ]
        )
    }

    private static func describeRecord(
        packID: String,
        targetID: String,
        root: URL,
        hostName: String,
        extensionID: String,
        messageProtocol: ChromeMV3NativeMessagingFixtureMessageProtocol,
        generatedState: ChromeMV3NativeMessagingFixturePackGeneratedState,
        fileManager: FileManager
    ) -> ChromeMV3NativeMessagingFixturePackRecord {
        let lookupPolicy = ChromeMV3NativeHostLookupPolicy.macOS(
            explicitTestRootPath: root.path
        )
        let lookup = lookupPolicy.lookupHost(
            named: hostName,
            fileManager: fileManager
        )
        let manifest = lookup.manifest
        let resolvedExecutable = manifest?.path.map {
            URL(fileURLWithPath: $0)
                .resolvingSymlinksInPath()
                .standardizedFileURL
        }
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let executableInsideRoot = resolvedExecutable.map {
            $0.path == resolvedRoot.path
                || $0.path.hasPrefix(resolvedRoot.path + "/")
        } ?? false
        let executableIsExecutable = resolvedExecutable.map {
            fileManager.isExecutableFile(atPath: $0.path)
        } ?? false
        let expectedOriginID =
            ChromeMV3NativeMessagingAllowedOrigin
            .nativeMessagingOriginExtensionID(for: extensionID)
        let allowedOriginMatches: Bool
        if let manifest {
            allowedOriginMatches = manifest.allowedOrigins.contains {
                $0.extensionID == expectedOriginID
            }
        } else {
            allowedOriginMatches = false
        }
        let valid =
            lookup.status == .found
                && manifest?.isValid == true
                && executableInsideRoot
                && executableIsExecutable
                && allowedOriginMatches
        let manifestPath = root.appendingPathComponent("\(hostName).json").path
        let actualGeneratedState:
            ChromeMV3NativeMessagingFixturePackGeneratedState =
                fileManager.fileExists(atPath: manifestPath)
                    ? .generated : generatedState
        return ChromeMV3NativeMessagingFixturePackRecord(
            packID: packID,
            targetID: targetID,
            hostName: hostName,
            fixtureRootPath: root.path,
            manifestPath: manifest?.sourceLocation.manifestPath
                ?? manifestPath,
            executablePath: manifest?.path,
            resolvedExecutablePath: resolvedExecutable?.path,
            allowedOrigins:
                manifest?.allowedOrigins.map(\.rawValue).sorted() ?? [],
            messageProtocol: messageProtocol,
            noNetworkInvariant: true,
            noCredentialsInvariant: true,
            generatedState: actualGeneratedState,
            validatedState: valid ? .valid : .invalid,
            cleanupState: .notRequired,
            manifestValidation: manifest?.validationSummary,
            executableInsideFixtureRoot: executableInsideRoot,
            executableIsExecutable: executableIsExecutable,
            diagnostics:
                uniqueSortedFixturePack(
                    lookup.diagnostics + [
                        "Fixture pack record uses exact host-name manifest lookup only.",
                        "Allowed origin source is fixture manifest allowed_origins.",
                        "Host name source is explicit fixture pack metadata or reviewed package diagnostics.",
                        valid
                            ? "Fixture pack record validated successfully."
                            : "Fixture pack record is not launch-ready.",
                        "No network, credentials, vaults, accounts, tokens, or product storage are used by this fixture host.",
                    ]
                )
        )
    }

    private static func pack(
        packID: String,
        targetID: String,
        rootPath: String?,
        records: [ChromeMV3NativeMessagingFixturePackRecord],
        generatedState: ChromeMV3NativeMessagingFixturePackGeneratedState? = nil,
        validatedState: ChromeMV3NativeMessagingFixturePackValidatedState? = nil,
        diagnostics: [String]
    ) -> ChromeMV3NativeMessagingFixturePack {
        let generated =
            generatedState
                ?? (records.isEmpty
                    ? .notGenerated
                    : (records.allSatisfy { $0.generatedState == .generated }
                        ? .generated : .notGenerated))
        let validated =
            validatedState
                ?? (records.isEmpty
                    ? .notEvaluated
                    : (records.allSatisfy { $0.validatedState == .valid }
                        ? .valid : .invalid))
        return ChromeMV3NativeMessagingFixturePack(
            packID: packID,
            targetID: targetID,
            fixtureRootPath: rootPath,
            allowedOrigins:
                uniqueSortedFixturePack(records.flatMap(\.allowedOrigins)),
            records: records.sorted {
                if $0.messageProtocol != $1.messageProtocol {
                    return $0.messageProtocol < $1.messageProtocol
                }
                return $0.hostName < $1.hostName
            },
            noNetworkInvariant: true,
            noCredentialsInvariant: true,
            generatedState: generated,
            validatedState: validated,
            cleanupState: .notRequired,
            realVendorHostDiscoveryBlocked: true,
            arbitraryHostLaunchAllowed: false,
            diagnostics: uniqueSortedFixturePack(diagnostics)
        )
    }

    private static func makePackID(
        targetID: String,
        fixtureRootPath: String,
        baseHostName: String,
        extensionID: String,
        protocols: [ChromeMV3NativeMessagingFixtureMessageProtocol]
    ) -> String {
        let seed = [
            targetID,
            fixtureRootPath,
            baseHostName,
            extensionID,
            protocols.map(\.rawValue).sorted().joined(separator: ","),
        ].joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(seed.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "native-fixture-pack-\(String(hex.prefix(16)))"
    }
}

private func uniqueSortedFixturePack(_ values: [String]) -> [String] {
    Array(Set(values)).sorted()
}

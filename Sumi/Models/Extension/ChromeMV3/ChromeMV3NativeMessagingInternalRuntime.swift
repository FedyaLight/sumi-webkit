//
//  ChromeMV3NativeMessagingInternalRuntime.swift
//  Sumi
//
//  DEBUG/internal Chrome MV3 native messaging bridge MVP for explicit fixture
//  hosts only. This is not product native messaging support, does not scan
//  system host directories, and does not expose normal-tab runtime behavior.
//

import CryptoKit
import Foundation

enum ChromeMV3NativeMessagingRuntimeErrorCode:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case authorizationFailed
    case extensionDisabled
    case fixtureGateDisabled
    case hostCrashedOrExited
    case hostManifestMissing
    case invalidArguments
    case invalidExecutablePath
    case invalidFrame
    case invalidHostName
    case invalidJSON
    case missingNativeMessagingPermission
    case oversizedMessage
    case productPolicyBlocked
    case processLaunchFailed
    case portClosed
    case truncatedFrame
    case trustedHostApprovalRequired
    case trustedHostDenied
    case trustedHostRevoked
    case writeFailed

    static func < (
        lhs: ChromeMV3NativeMessagingRuntimeErrorCode,
        rhs: ChromeMV3NativeMessagingRuntimeErrorCode
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var lastErrorMessage: String {
        switch self {
        case .authorizationFailed:
            return "Access to the specified native messaging host is forbidden."
        case .extensionDisabled:
            return "Extensions are disabled; native messaging is unavailable."
        case .fixtureGateDisabled:
            return "Native messaging is unavailable outside the internal fixture gate."
        case .hostCrashedOrExited:
            return "Native host has exited."
        case .hostManifestMissing:
            return "Specified native messaging host not found."
        case .invalidArguments:
            return "Invalid native messaging arguments."
        case .invalidExecutablePath:
            return "Native messaging fixture host path is not allowed."
        case .invalidFrame:
            return "Error when communicating with the native messaging host."
        case .invalidHostName:
            return "Invalid native messaging host name specified."
        case .invalidJSON:
            return "Native messaging host returned malformed JSON."
        case .missingNativeMessagingPermission:
            return "nativeMessaging permission is missing."
        case .oversizedMessage:
            return "Native messaging message exceeds the allowed size."
        case .productPolicyBlocked:
            return "Native messaging is blocked by product policy."
        case .processLaunchFailed:
            return "Failed to start native messaging host."
        case .portClosed:
            return "Native messaging port is closed."
        case .truncatedFrame:
            return "Native host sent a truncated response."
        case .trustedHostApprovalRequired:
            return "Native messaging host requires developer-preview trusted-host approval."
        case .trustedHostDenied:
            return "Native messaging host was denied by developer-preview trusted-host policy."
        case .trustedHostRevoked:
            return "Native messaging host approval was revoked."
        case .writeFailed:
            return "Failed to write to native messaging host."
        }
    }
}

struct ChromeMV3NativeMessagingRuntimeError:
    Error,
    Codable,
    Equatable,
    Sendable
{
    var code: ChromeMV3NativeMessagingRuntimeErrorCode
    var message: String
    var diagnostics: [String]

    static func make(
        _ code: ChromeMV3NativeMessagingRuntimeErrorCode,
        _ diagnostics: [String] = []
    ) -> ChromeMV3NativeMessagingRuntimeError {
        ChromeMV3NativeMessagingRuntimeError(
            code: code,
            message: code.lastErrorMessage,
            diagnostics: uniqueSortedNative(diagnostics + [code.lastErrorMessage])
        )
    }
}

struct ChromeMV3NativeMessagingFrameCodecResult:
    Codable,
    Equatable,
    Sendable
{
    var succeeded: Bool
    var direction: ChromeMV3NativeMessagingFrameDirection
    var declaredPayloadLength: Int?
    var actualPayloadByteCount: Int?
    var maximumPayloadBytes: Int
    var frameByteCount: Int
    var message: ChromeMV3StorageValue?
    var frameData: Data?
    var validation:
        ChromeMV3NativeMessagingFrameValidation
    var error: ChromeMV3NativeMessagingRuntimeError?
    var diagnostics: [String]
}

enum ChromeMV3NativeMessagingFramingCodec {
    static func encodeOutboundMessage(
        _ message: ChromeMV3StorageValue,
        policy: ChromeMV3NativeMessagingFramingPolicy = .chromeStdioJSON
    ) -> ChromeMV3NativeMessagingFrameCodecResult {
        let direction = ChromeMV3NativeMessagingFrameDirection.outboundToHost
        let payload: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            payload = try encoder.encode(message)
        } catch {
            let validation = policy.validateFrame(
                declaredPayloadLength: nil,
                actualPayloadByteCount: nil,
                direction: direction
            )
            return ChromeMV3NativeMessagingFrameCodecResult(
                succeeded: false,
                direction: direction,
                declaredPayloadLength: nil,
                actualPayloadByteCount: nil,
                maximumPayloadBytes: policy.outboundHostMessageLimitBytes,
                frameByteCount: 0,
                message: nil,
                frameData: nil,
                validation: validation,
                error: .make(.invalidJSON, [error.localizedDescription]),
                diagnostics: [error.localizedDescription]
            )
        }

        let validation = policy.validateFrame(
            declaredPayloadLength: payload.count,
            actualPayloadByteCount: payload.count,
            direction: direction
        )
        guard validation.valid else {
            return ChromeMV3NativeMessagingFrameCodecResult(
                succeeded: false,
                direction: direction,
                declaredPayloadLength: payload.count,
                actualPayloadByteCount: payload.count,
                maximumPayloadBytes: policy.outboundHostMessageLimitBytes,
                frameByteCount: payload.count,
                message: nil,
                frameData: nil,
                validation: validation,
                error: .make(
                    .oversizedMessage,
                    validation.diagnostics.map(\.message)
                ),
                diagnostics: validation.diagnostics.map(\.message)
            )
        }

        var length = UInt32(payload.count)
        var frame = Data(bytes: &length, count: 4)
        frame.append(payload)
        return ChromeMV3NativeMessagingFrameCodecResult(
            succeeded: true,
            direction: direction,
            declaredPayloadLength: payload.count,
            actualPayloadByteCount: payload.count,
            maximumPayloadBytes: policy.outboundHostMessageLimitBytes,
            frameByteCount: frame.count,
            message: message,
            frameData: frame,
            validation: validation,
            error: nil,
            diagnostics:
                uniqueSortedNative(
                    validation.diagnostics.map(\.message)
                        + ["Native outbound frame encoded."]
                )
        )
    }

    static func decodeInboundFrame(
        _ frame: Data,
        policy: ChromeMV3NativeMessagingFramingPolicy = .chromeStdioJSON
    ) -> ChromeMV3NativeMessagingFrameCodecResult {
        let direction = ChromeMV3NativeMessagingFrameDirection.inboundFromHost
        guard frame.count >= 4 else {
            let validation = policy.validateFrame(
                declaredPayloadLength: nil,
                actualPayloadByteCount: frame.count,
                direction: direction
            )
            return ChromeMV3NativeMessagingFrameCodecResult(
                succeeded: false,
                direction: direction,
                declaredPayloadLength: nil,
                actualPayloadByteCount: frame.count,
                maximumPayloadBytes: policy.inboundHostMessageLimitBytes,
                frameByteCount: frame.count,
                message: nil,
                frameData: frame,
                validation: validation,
                error: .make(
                    .invalidFrame,
                    validation.diagnostics.map(\.message)
                ),
                diagnostics: validation.diagnostics.map(\.message)
            )
        }

        let declared = Int(decodeLength(from: frame.prefix(4)))
        let payload = frame.dropFirst(4)
        let validation = policy.validateFrame(
            declaredPayloadLength: declared,
            actualPayloadByteCount: payload.count,
            direction: direction
        )
        guard validation.valid else {
            let code: ChromeMV3NativeMessagingRuntimeErrorCode =
                declared > policy.inboundHostMessageLimitBytes
                ? .oversizedMessage
                : .invalidFrame
            return ChromeMV3NativeMessagingFrameCodecResult(
                succeeded: false,
                direction: direction,
                declaredPayloadLength: declared,
                actualPayloadByteCount: payload.count,
                maximumPayloadBytes: policy.inboundHostMessageLimitBytes,
                frameByteCount: frame.count,
                message: nil,
                frameData: frame,
                validation: validation,
                error: .make(code, validation.diagnostics.map(\.message)),
                diagnostics: validation.diagnostics.map(\.message)
            )
        }

        do {
            let message = try JSONDecoder().decode(
                ChromeMV3StorageValue.self,
                from: Data(payload)
            )
            return ChromeMV3NativeMessagingFrameCodecResult(
                succeeded: true,
                direction: direction,
                declaredPayloadLength: declared,
                actualPayloadByteCount: payload.count,
                maximumPayloadBytes: policy.inboundHostMessageLimitBytes,
                frameByteCount: frame.count,
                message: message,
                frameData: frame,
                validation: validation,
                error: nil,
                diagnostics:
                    uniqueSortedNative(
                        validation.diagnostics.map(\.message)
                            + ["Native inbound frame decoded."]
                    )
            )
        } catch {
            return ChromeMV3NativeMessagingFrameCodecResult(
                succeeded: false,
                direction: direction,
                declaredPayloadLength: declared,
                actualPayloadByteCount: payload.count,
                maximumPayloadBytes: policy.inboundHostMessageLimitBytes,
                frameByteCount: frame.count,
                message: nil,
                frameData: frame,
                validation: validation,
                error: .make(.invalidJSON, [error.localizedDescription]),
                diagnostics: [error.localizedDescription]
            )
        }
    }

    static func readInboundMessage(
        from handle: FileHandle,
        policy: ChromeMV3NativeMessagingFramingPolicy = .chromeStdioJSON
    ) -> ChromeMV3NativeMessagingFrameCodecResult {
        let direction = ChromeMV3NativeMessagingFrameDirection.inboundFromHost
        let header = handle.readData(ofLength: 4)
        guard header.count == 4 else {
            let validation = policy.validateFrame(
                declaredPayloadLength: nil,
                actualPayloadByteCount: header.count,
                direction: direction
            )
            return ChromeMV3NativeMessagingFrameCodecResult(
                succeeded: false,
                direction: direction,
                declaredPayloadLength: nil,
                actualPayloadByteCount: header.count,
                maximumPayloadBytes: policy.inboundHostMessageLimitBytes,
                frameByteCount: header.count,
                message: nil,
                frameData: header,
                validation: validation,
                error: .make(.hostCrashedOrExited, ["Host produced no frame header."]),
                diagnostics: ["Host produced no complete native messaging header."]
            )
        }

        let declared = Int(decodeLength(from: header))
        if declared > policy.inboundHostMessageLimitBytes {
            let validation = policy.validateFrame(
                declaredPayloadLength: declared,
                actualPayloadByteCount: declared,
                direction: direction
            )
            return ChromeMV3NativeMessagingFrameCodecResult(
                succeeded: false,
                direction: direction,
                declaredPayloadLength: declared,
                actualPayloadByteCount: nil,
                maximumPayloadBytes: policy.inboundHostMessageLimitBytes,
                frameByteCount: header.count,
                message: nil,
                frameData: header,
                validation: validation,
                error: .make(
                    .oversizedMessage,
                    validation.diagnostics.map(\.message)
                ),
                diagnostics: validation.diagnostics.map(\.message)
            )
        }

        let payload = handle.readData(ofLength: declared)
        guard payload.count == declared else {
            let validation = policy.validateFrame(
                declaredPayloadLength: declared,
                actualPayloadByteCount: payload.count,
                direction: direction
            )
            var frame = Data()
            frame.append(header)
            frame.append(payload)
            return ChromeMV3NativeMessagingFrameCodecResult(
                succeeded: false,
                direction: direction,
                declaredPayloadLength: declared,
                actualPayloadByteCount: payload.count,
                maximumPayloadBytes: policy.inboundHostMessageLimitBytes,
                frameByteCount: frame.count,
                message: nil,
                frameData: frame,
                validation: validation,
                error: .make(.truncatedFrame, validation.diagnostics.map(\.message)),
                diagnostics: validation.diagnostics.map(\.message)
            )
        }

        var frame = Data()
        frame.append(header)
        frame.append(payload)
        return decodeInboundFrame(frame, policy: policy)
    }

    private static func decodeLength(from data: Data.SubSequence) -> UInt32 {
        var bytes = [UInt8](data)
        while bytes.count < 4 {
            bytes.append(0)
        }
        return bytes.withUnsafeBufferPointer { pointer in
            var value: UInt32 = 0
            memcpy(&value, pointer.baseAddress, 4)
            return value
        }
    }
}

enum ChromeMV3NativeMessagingFixtureHostKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case crashEarlyExit
    case echo
    case invalidJSON
    case malformedFrame
    case oversizedResponse

    static func < (
        lhs: ChromeMV3NativeMessagingFixtureHostKind,
        rhs: ChromeMV3NativeMessagingFixtureHostKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3NativeMessagingFixtureHost:
    Codable,
    Equatable,
    Sendable
{
    var kind: ChromeMV3NativeMessagingFixtureHostKind
    var hostName: String
    var extensionID: String
    var rootPath: String
    var executablePath: String
    var manifestPath: String
    var interpreterPath: String
    var diagnostics: [String]
}

enum ChromeMV3NativeMessagingFixtureHostBuilder {
    static let passwordManagerFixtureHostName =
        "com.sumi.synthetic_password_manager"
    static let pythonInterpreterPath = "/usr/bin/python3"

    static func writeFixtureHost(
        kind: ChromeMV3NativeMessagingFixtureHostKind,
        rootURL: URL,
        hostName: String = passwordManagerFixtureHostName,
        extensionID: String
    ) throws -> ChromeMV3NativeMessagingFixtureHost {
        guard FileManager.default.isExecutableFile(
            atPath: pythonInterpreterPath
        ) else {
            throw ChromeMV3NativeMessagingRuntimeError.make(
                .processLaunchFailed,
                ["Fixture interpreter is not executable: \(pythonInterpreterPath)"]
            )
        }

        let root = rootURL.standardizedFileURL
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let executableURL = root.appendingPathComponent(
            "\(hostName)-\(kind.rawValue).py"
        )
        let manifestURL = root.appendingPathComponent("\(hostName).json")
        try scriptSource(kind: kind).write(
            to: executableURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        let manifestObject: [String: Any] = [
            "allowed_origins": [
                ChromeMV3NativeMessagingAllowedOrigin.originString(
                    extensionID: extensionID
                ),
            ],
            "description": "Sumi internal native messaging fixture \(kind.rawValue)",
            "name": hostName,
            "path": executableURL.path,
            "type": "stdio",
        ]
        let data = try JSONSerialization.data(
            withJSONObject: manifestObject,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: manifestURL)
        return ChromeMV3NativeMessagingFixtureHost(
            kind: kind,
            hostName: hostName,
            extensionID: extensionID,
            rootPath: root.path,
            executablePath: executableURL.path,
            manifestPath: manifestURL.path,
            interpreterPath: pythonInterpreterPath,
            diagnostics: [
                "Fixture host manifest and executable were written under the explicit fixture root.",
                "Interpreter path is explicit: \(pythonInterpreterPath).",
                "Fixture host does not access network, credentials, or product storage.",
            ]
        )
    }

    private static func scriptSource(
        kind: ChromeMV3NativeMessagingFixtureHostKind
    ) -> String {
        switch kind {
        case .echo:
            return """
            #!\(pythonInterpreterPath)
            import json
            import struct
            import sys

            origin = sys.argv[1] if len(sys.argv) > 1 else ""

            while True:
                header = sys.stdin.buffer.read(4)
                if not header:
                    break
                if len(header) != 4:
                    sys.exit(3)
                length = struct.unpack("<I", header)[0]
                payload = sys.stdin.buffer.read(length)
                if len(payload) != length:
                    sys.exit(4)
                request = json.loads(payload.decode("utf-8"))
                response = json.dumps(
                    {"ok": True, "echo": request, "origin": origin},
                    separators=(",", ":")
                ).encode("utf-8")
                sys.stdout.buffer.write(struct.pack("<I", len(response)) + response)
                sys.stdout.buffer.flush()
            """
        case .malformedFrame:
            return """
            #!\(pythonInterpreterPath)
            import struct
            import sys

            sys.stdout.buffer.write(struct.pack("<I", 8) + b"{}")
            sys.stdout.buffer.flush()
            """
        case .oversizedResponse:
            return """
            #!\(pythonInterpreterPath)
            import struct
            import sys

            sys.stdout.buffer.write(struct.pack("<I", 1048577))
            sys.stdout.buffer.flush()
            """
        case .crashEarlyExit:
            return """
            #!\(pythonInterpreterPath)
            import sys

            sys.exit(9)
            """
        case .invalidJSON:
            return """
            #!\(pythonInterpreterPath)
            import struct
            import sys

            payload = b"not-json"
            sys.stdout.buffer.write(struct.pack("<I", len(payload)) + payload)
            sys.stdout.buffer.flush()
            """
        }
    }
}

struct ChromeMV3NativeMessagingFixtureLaunchPolicyResult:
    Codable,
    Equatable,
    Sendable
{
    var hostName: String
    var executablePath: String?
    var resolvedExecutablePath: String?
    var allowedFixtureRootPaths: [String]
    var processLaunchAllowedForFixtureHost: Bool
    var processLaunchAllowedInProduct: Bool
    var nativeMessagingAvailableInProduct: Bool
    var trustedHostApprovedForDeveloperPreview: Bool
    var trustedHostApprovalState: ChromeMV3NativeTrustedHostTrustState
    var userConsentGrantedForTrustedHost: Bool
    var diagnostics: [String]
    var error: ChromeMV3NativeMessagingRuntimeError?
}

struct ChromeMV3NativeMessagingRuntimeOwnerConfiguration:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var explicitFixtureHostRootPaths: [String]
    var moduleState: ChromeMV3ProfileHostModuleState
    var explicitInternalNativeMessagingBridgeAllowed: Bool
    var permissionState: ChromeMV3NativeMessagingPermissionState
    var productPolicy: ChromeMV3NativeMessagingProductPolicy
    var trustedHostApprovalRecords: [ChromeMV3NativeTrustedHostApprovalRecord]
    var nativeMessagingAvailableInProduct: Bool
    var processLaunchAllowedInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var serviceWorkerWakeAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]

    var nativeMessagingAvailableInInternalFixture: Bool {
        moduleState == .enabled
            && explicitInternalNativeMessagingBridgeAllowed
            && explicitFixtureHostRootPaths.isEmpty == false
            && Self.debugFixtureBuildAllowsProcessLaunch
    }

    static var debugFixtureBuildAllowsProcessLaunch: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    static func internalFixture(
        extensionID: String,
        profileID: String,
        fixtureHostRootPaths: [String],
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        explicitInternalNativeMessagingBridgeAllowed: Bool = true,
        permissionState: ChromeMV3NativeMessagingPermissionState =
            .grantedByManifest,
        productPolicy: ChromeMV3NativeMessagingProductPolicy =
            .blockedRuntimeDefault,
        trustedHostApprovalRecords:
            [ChromeMV3NativeTrustedHostApprovalRecord] = []
    ) -> ChromeMV3NativeMessagingRuntimeOwnerConfiguration {
        ChromeMV3NativeMessagingRuntimeOwnerConfiguration(
            extensionID: extensionID,
            profileID: profileID,
            explicitFixtureHostRootPaths:
                fixtureHostRootPaths.map {
                    URL(fileURLWithPath: $0, isDirectory: true)
                        .standardizedFileURL
                        .path
                }.sorted(),
            moduleState: moduleState,
            explicitInternalNativeMessagingBridgeAllowed:
                explicitInternalNativeMessagingBridgeAllowed,
            permissionState: permissionState,
            productPolicy: productPolicy,
            trustedHostApprovalRecords:
                trustedHostApprovalRecords.sorted {
                    if $0.hostName != $1.hostName {
                        return $0.hostName < $1.hostName
                    }
                    return $0.approvalSequence < $1.approvalSequence
                },
            nativeMessagingAvailableInProduct: false,
            processLaunchAllowedInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            serviceWorkerWakeAvailable: false,
            runtimeLoadable: false,
            diagnostics: [
                "Native messaging owner is scoped to DEBUG/internal fixture roots.",
                "Product native messaging remains unavailable.",
                "Normal-tab runtime bridge remains unavailable.",
                "Service-worker wake remains unavailable.",
                "runtimeLoadable remains false.",
                "Trusted-host approval is required before any fixture host launch.",
                debugFixtureBuildAllowsProcessLaunch
                    ? "DEBUG build allows explicit fixture host launch after policy validation."
                    : "Non-DEBUG build blocks fixture host process launch.",
            ]
        )
    }
}

struct ChromeMV3NativeMessagingProcessLifecycleRecord:
    Codable,
    Equatable,
    Sendable
{
    var operationID: String
    var portID: String?
    var hostName: String
    var operationKind: ChromeMV3NativeMessagingOperationKind
    var processLaunchAttempted: Bool
    var processLaunchAllowedForFixtureHost: Bool
    var processLaunchAllowedInProduct: Bool
    var processStarted: Bool
    var messageSentCount: Int
    var messageReceivedCount: Int
    var disconnectReason: ChromeMV3NativeMessagingDisconnectReason?
    var hostExitStatus: Int32?
    var teardownResult: String
    var lastErrorCode: ChromeMV3NativeMessagingRuntimeErrorCode?
    var diagnostics: [String]
}

struct ChromeMV3NativeMessagingSendNativeMessageResult:
    Codable,
    Equatable,
    Sendable
{
    var operationID: String
    var hostName: String
    var succeeded: Bool
    var response: ChromeMV3StorageValue?
    var lastErrorMessage: String?
    var lastErrorCode: ChromeMV3NativeMessagingRuntimeErrorCode?
    var preflight: ChromeMV3NativeMessagingOperationPreflight
    var launchPolicy: ChromeMV3NativeMessagingFixtureLaunchPolicyResult
    var outboundFrame: ChromeMV3NativeMessagingFrameCodecResult?
    var inboundFrame: ChromeMV3NativeMessagingFrameCodecResult?
    var lifecycle: ChromeMV3NativeMessagingProcessLifecycleRecord
    var diagnostics: [String]
}

struct ChromeMV3NativeMessagingConnectNativeResult:
    Codable,
    Equatable,
    Sendable
{
    var operationID: String
    var portID: String?
    var hostName: String
    var succeeded: Bool
    var lastErrorMessage: String?
    var lastErrorCode: ChromeMV3NativeMessagingRuntimeErrorCode?
    var preflight: ChromeMV3NativeMessagingOperationPreflight
    var launchPolicy: ChromeMV3NativeMessagingFixtureLaunchPolicyResult
    var lifecycle: ChromeMV3NativeMessagingProcessLifecycleRecord
    var diagnostics: [String]
}

struct ChromeMV3NativeMessagingPortPostMessageResult:
    Codable,
    Equatable,
    Sendable
{
    var portID: String
    var hostName: String
    var succeeded: Bool
    var response: ChromeMV3StorageValue?
    var lastErrorMessage: String?
    var lastErrorCode: ChromeMV3NativeMessagingRuntimeErrorCode?
    var outboundFrame: ChromeMV3NativeMessagingFrameCodecResult?
    var inboundFrame: ChromeMV3NativeMessagingFrameCodecResult?
    var lifecycle: ChromeMV3NativeMessagingProcessLifecycleRecord
    var diagnostics: [String]
}

struct ChromeMV3NativeMessagingPortDisconnectResult:
    Codable,
    Equatable,
    Sendable
{
    var portID: String
    var hostName: String?
    var disconnected: Bool
    var reason: ChromeMV3NativeMessagingDisconnectReason
    var activePortCountAfterDisconnect: Int
    var lifecycle: ChromeMV3NativeMessagingProcessLifecycleRecord?
    var diagnostics: [String]
}

final class ChromeMV3NativeMessagingRuntimeOwner {
    let configuration: ChromeMV3NativeMessagingRuntimeOwnerConfiguration
    private var ports: [String: ChromeMV3NativeMessagingInternalPort] = [:]
    private(set) var lifecycleRecords:
        [ChromeMV3NativeMessagingProcessLifecycleRecord] = []

    init(configuration: ChromeMV3NativeMessagingRuntimeOwnerConfiguration) {
        self.configuration = configuration
    }

    var activePortCount: Int { ports.count }

    func lookupPolicy() -> ChromeMV3NativeHostLookupPolicy {
        var base = ChromeMV3NativeHostLookupPolicy.macOS(
            extensionModuleEnabled: configuration.moduleState == .enabled
        )
        let future = base.locations.filter {
            $0.lookupAllowedInThisModel == false
        }
        base.locations =
            configuration.explicitFixtureHostRootPaths
            .map { .explicitTestRoot(rootPath: $0) }
            + future
        return base
    }

    func sendNativeMessage(
        hostName: String,
        message: ChromeMV3StorageValue
    ) -> ChromeMV3NativeMessagingSendNativeMessageResult {
        let operationID = stableIDNative(
            prefix: "native-send",
            parts: [
                configuration.extensionID,
                configuration.profileID,
                hostName,
                (try? message.canonicalJSONString()) ?? "message",
            ]
        )
        let prepared = prepareLaunch(
            hostName: hostName,
            operationKind: .oneShotNativeMessage,
            operationID: operationID
        )
        let launch = prepared.launch
        guard let executablePath = launch.resolvedExecutablePath,
              prepared.error == nil
        else {
            let error = prepared.error ?? .make(.hostManifestMissing)
            let lifecycle = lifecycleRecord(
                operationID: operationID,
                portID: nil,
                hostName: hostName,
                operationKind: .oneShotNativeMessage,
                launchPolicy: launch,
                processLaunchAttempted: false,
                processStarted: false,
                messageSentCount: 0,
                messageReceivedCount: 0,
                disconnectReason: disconnectReason(for: error.code),
                hostExitStatus: nil,
                teardownResult: "noProcessStarted",
                error: error,
                diagnostics: prepared.diagnostics
            )
            lifecycleRecords.append(lifecycle)
            return ChromeMV3NativeMessagingSendNativeMessageResult(
                operationID: operationID,
                hostName: hostName,
                succeeded: false,
                response: nil,
                lastErrorMessage: error.message,
                lastErrorCode: error.code,
                preflight: prepared.preflight,
                launchPolicy: launch,
                outboundFrame: nil,
                inboundFrame: nil,
                lifecycle: lifecycle,
                diagnostics: prepared.diagnostics + error.diagnostics
            )
        }

        let process = ChromeMV3NativeMessagingFixtureProcess(
            executablePath: executablePath,
            origin: ChromeMV3NativeMessagingAllowedOrigin.originString(
                extensionID: configuration.extensionID
            )
        )
        var outbound: ChromeMV3NativeMessagingFrameCodecResult?
        var inbound: ChromeMV3NativeMessagingFrameCodecResult?
        var error: ChromeMV3NativeMessagingRuntimeError?
        var sent = 0
        var received = 0
        var processStarted = false
        var diagnostics = prepared.diagnostics

        do {
            try process.start()
            processStarted = true
            outbound = process.write(message)
            if outbound?.succeeded == true {
                sent = 1
                inbound = process.read()
                if inbound?.succeeded == true {
                    received = 1
                } else {
                    error = inbound?.error ?? .make(.invalidFrame)
                }
            } else {
                error = outbound?.error ?? .make(.writeFailed)
            }
        } catch let caughtError {
            let runtimeError =
                (caughtError as? ChromeMV3NativeMessagingRuntimeError)
                ?? .make(
                    .processLaunchFailed,
                    [caughtError.localizedDescription]
                )
            error = runtimeError
        }

        let teardown = process.terminate()
        diagnostics.append(contentsOf: teardown.diagnostics)
        let lifecycle = lifecycleRecord(
            operationID: operationID,
            portID: nil,
            hostName: hostName,
            operationKind: .oneShotNativeMessage,
            launchPolicy: launch,
            processLaunchAttempted: true,
            processStarted: processStarted,
            messageSentCount: sent,
            messageReceivedCount: received,
            disconnectReason: error.map { disconnectReason(for: $0.code) },
            hostExitStatus: teardown.exitStatus,
            teardownResult: teardown.result,
            error: error,
            diagnostics: diagnostics
        )
        lifecycleRecords.append(lifecycle)
        let succeeded = error == nil && inbound?.message != nil
        return ChromeMV3NativeMessagingSendNativeMessageResult(
            operationID: operationID,
            hostName: hostName,
            succeeded: succeeded,
            response: inbound?.message,
            lastErrorMessage: error?.message,
            lastErrorCode: error?.code,
            preflight: prepared.preflight,
            launchPolicy: launch,
            outboundFrame: outbound,
            inboundFrame: inbound,
            lifecycle: lifecycle,
            diagnostics: uniqueSortedNative(
                diagnostics
                    + (outbound?.diagnostics ?? [])
                    + (inbound?.diagnostics ?? [])
                    + (error?.diagnostics ?? [])
            )
        )
    }

    func connectNative(
        hostName: String
    ) -> ChromeMV3NativeMessagingConnectNativeResult {
        let operationID = stableIDNative(
            prefix: "native-connect",
            parts: [
                configuration.extensionID,
                configuration.profileID,
                hostName,
                String(ports.count),
            ]
        )
        let prepared = prepareLaunch(
            hostName: hostName,
            operationKind: .longLivedNativePort,
            operationID: operationID
        )
        let launch = prepared.launch
        guard let executablePath = launch.resolvedExecutablePath,
              prepared.error == nil
        else {
            let error = prepared.error ?? .make(.hostManifestMissing)
            let lifecycle = lifecycleRecord(
                operationID: operationID,
                portID: nil,
                hostName: hostName,
                operationKind: .longLivedNativePort,
                launchPolicy: launch,
                processLaunchAttempted: false,
                processStarted: false,
                messageSentCount: 0,
                messageReceivedCount: 0,
                disconnectReason: disconnectReason(for: error.code),
                hostExitStatus: nil,
                teardownResult: "noProcessStarted",
                error: error,
                diagnostics: prepared.diagnostics
            )
            lifecycleRecords.append(lifecycle)
            return ChromeMV3NativeMessagingConnectNativeResult(
                operationID: operationID,
                portID: nil,
                hostName: hostName,
                succeeded: false,
                lastErrorMessage: error.message,
                lastErrorCode: error.code,
                preflight: prepared.preflight,
                launchPolicy: launch,
                lifecycle: lifecycle,
                diagnostics: prepared.diagnostics + error.diagnostics
            )
        }

        let portID = stableIDNative(
            prefix: "native-port",
            parts: [operationID, hostName]
        )
        let process = ChromeMV3NativeMessagingFixtureProcess(
            executablePath: executablePath,
            origin: ChromeMV3NativeMessagingAllowedOrigin.originString(
                extensionID: configuration.extensionID
            )
        )
        var error: ChromeMV3NativeMessagingRuntimeError?
        var processStarted = false
        do {
            try process.start()
            processStarted = true
            ports[portID] = ChromeMV3NativeMessagingInternalPort(
                portID: portID,
                operationID: operationID,
                hostName: hostName,
                process: process,
                launchPolicy: launch
            )
        } catch let caughtError {
            let runtimeError =
                (caughtError as? ChromeMV3NativeMessagingRuntimeError)
                ?? .make(
                    .processLaunchFailed,
                    [caughtError.localizedDescription]
                )
            error = runtimeError
        }
        let lifecycle = lifecycleRecord(
            operationID: operationID,
            portID: portID,
            hostName: hostName,
            operationKind: .longLivedNativePort,
            launchPolicy: launch,
            processLaunchAttempted: true,
            processStarted: processStarted,
            messageSentCount: 0,
            messageReceivedCount: 0,
            disconnectReason: error.map { disconnectReason(for: $0.code) },
            hostExitStatus: process.exitStatusIfTerminated,
            teardownResult: error == nil ? "portOpen" : "launchFailed",
            error: error,
            diagnostics: prepared.diagnostics
        )
        lifecycleRecords.append(lifecycle)
        return ChromeMV3NativeMessagingConnectNativeResult(
            operationID: operationID,
            portID: error == nil ? portID : nil,
            hostName: hostName,
            succeeded: error == nil,
            lastErrorMessage: error?.message,
            lastErrorCode: error?.code,
            preflight: prepared.preflight,
            launchPolicy: launch,
            lifecycle: lifecycle,
            diagnostics: uniqueSortedNative(
                prepared.diagnostics + (error?.diagnostics ?? [])
            )
        )
    }

    func postMessage(
        portID: String,
        message: ChromeMV3StorageValue
    ) -> ChromeMV3NativeMessagingPortPostMessageResult {
        guard let port = ports[portID] else {
            let error = ChromeMV3NativeMessagingRuntimeError.make(.portClosed)
            let lifecycle = lifecycleRecord(
                operationID: portID,
                portID: portID,
                hostName: "unknown",
                operationKind: .longLivedNativePort,
                launchPolicy: nil,
                processLaunchAttempted: false,
                processStarted: false,
                messageSentCount: 0,
                messageReceivedCount: 0,
                disconnectReason: .nativeHostExited,
                hostExitStatus: nil,
                teardownResult: "portMissing",
                error: error,
                diagnostics: error.diagnostics
            )
            return ChromeMV3NativeMessagingPortPostMessageResult(
                portID: portID,
                hostName: "unknown",
                succeeded: false,
                response: nil,
                lastErrorMessage: error.message,
                lastErrorCode: error.code,
                outboundFrame: nil,
                inboundFrame: nil,
                lifecycle: lifecycle,
                diagnostics: error.diagnostics
            )
        }

        let result = port.postMessage(message)
        if result.succeeded == false {
            ports.removeValue(forKey: portID)
        }
        lifecycleRecords.append(result.lifecycle)
        return result
    }

    @discardableResult
    func disconnect(
        portID: String,
        reason: ChromeMV3NativeMessagingDisconnectReason = .nativeHostExited
    ) -> ChromeMV3NativeMessagingPortDisconnectResult {
        guard let port = ports.removeValue(forKey: portID) else {
            return ChromeMV3NativeMessagingPortDisconnectResult(
                portID: portID,
                hostName: nil,
                disconnected: false,
                reason: reason,
                activePortCountAfterDisconnect: ports.count,
                lifecycle: nil,
                diagnostics: ["Native messaging port was already closed."]
            )
        }
        let lifecycle = port.disconnect(reason: reason)
        lifecycleRecords.append(lifecycle)
        return ChromeMV3NativeMessagingPortDisconnectResult(
            portID: portID,
            hostName: port.hostName,
            disconnected: true,
            reason: reason,
            activePortCountAfterDisconnect: ports.count,
            lifecycle: lifecycle,
            diagnostics: lifecycle.diagnostics
        )
    }

    @discardableResult
    func tearDownForExtensionDisable()
        -> [ChromeMV3NativeMessagingPortDisconnectResult]
    {
        ports.keys.sorted().map {
            disconnect(portID: $0, reason: .extensionDisabled)
        }
    }

    @discardableResult
    func tearDownForProfileClose()
        -> [ChromeMV3NativeMessagingPortDisconnectResult]
    {
        ports.keys.sorted().map {
            disconnect(portID: $0, reason: .profileClosed)
        }
    }

    @discardableResult
    func tearDownForTrustedHostRevoke(
        hostName: String
    ) -> [ChromeMV3NativeMessagingPortDisconnectResult] {
        ports
            .filter { $0.value.hostName == hostName }
            .map(\.key)
            .sorted()
            .map {
                disconnect(portID: $0, reason: .permissionRevoked)
            }
    }

    private func prepareLaunch(
        hostName: String,
        operationKind: ChromeMV3NativeMessagingOperationKind,
        operationID: String
    ) -> (
        preflight: ChromeMV3NativeMessagingOperationPreflight,
        launch: ChromeMV3NativeMessagingFixtureLaunchPolicyResult,
        error: ChromeMV3NativeMessagingRuntimeError?,
        diagnostics: [String]
    ) {
        let policy = lookupPolicy()
        let lookup = policy.lookupHost(named: hostName)
        let trustedRecord = trustedHostRecord(
            hostName: hostName,
            manifestSHA256: lookup.manifest?.canonicalJSONSHA256
        )
        let preflight = ChromeMV3NativeMessagingPreflightEvaluator.evaluate(
            input: ChromeMV3NativeMessagingPreflightInput(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                hostName: hostName,
                operationKind: operationKind,
                sourceContext: .extensionPage,
                permissionState: configuration.permissionState,
                productPolicy: configuration.productPolicy,
                trustedHostPolicyRecord: trustedRecord
            ),
            lookupPolicy: policy,
            lookupResult: lookup
        )
        let launch = launchPolicyResult(
            hostName: hostName,
            manifest: preflight.hostLookupResult.manifest,
            trustedRecord: trustedRecord
        )
        var diagnostics = uniqueSortedNative(
            configuration.diagnostics
                + preflight.diagnostics
                + launch.diagnostics
                + (trustedRecord?.diagnostics ?? [
                    "No trusted-host approval record is available to the runtime owner.",
                ])
                + [
                    "Operation \(operationID) evaluated by the internal native messaging runtime owner.",
                    "Product/public native messaging remains unavailable.",
                ]
        )

        let error: ChromeMV3NativeMessagingRuntimeError?
        if configuration.moduleState != .enabled {
            error = .make(.extensionDisabled, diagnostics)
        } else if configuration.explicitInternalNativeMessagingBridgeAllowed == false
            || configuration.explicitFixtureHostRootPaths.isEmpty
            || ChromeMV3NativeMessagingRuntimeOwnerConfiguration
                .debugFixtureBuildAllowsProcessLaunch == false
        {
            error = .make(.fixtureGateDisabled, diagnostics)
        } else if preflight.hostLookupResult.status == .invalidHostName {
            error = .make(.invalidHostName, diagnostics)
        } else if preflight.hostLookupResult.status != .found {
            error = .make(.hostManifestMissing, diagnostics)
        } else if configuration.permissionState.hasPermission == false {
            error = .make(.missingNativeMessagingPermission, diagnostics)
        } else if preflight.authorizationResult.authorizedByManifest == false {
            error = .make(.authorizationFailed, diagnostics)
        } else if preflight.authorizationResult.blockedByPolicy {
            error = .make(.productPolicyBlocked, diagnostics)
        } else if trustedRecord?.trustState == .userDenied {
            error = .make(.trustedHostDenied, diagnostics)
        } else if trustedRecord?.trustState == .revoked {
            error = .make(.trustedHostRevoked, diagnostics)
        } else if launch.error?.code == .invalidExecutablePath {
            error = launch.error
        } else if preflight.trustedHostPolicyApproved == false {
            error = .make(.trustedHostApprovalRequired, diagnostics)
        } else if preflight.userConsentSatisfied == false {
            error = .make(.productPolicyBlocked, diagnostics)
        } else if launch.processLaunchAllowedForFixtureHost == false {
            error = launch.error ?? .make(.invalidExecutablePath, diagnostics)
        } else {
            error = nil
        }

        if preflight.authorizationResult.requiresUserConsent {
            diagnostics.append(
                "Product user consent would be required; no product consent is persisted by this fixture bridge."
            )
        }

        return (preflight, launch, error, uniqueSortedNative(diagnostics))
    }

    private func launchPolicyResult(
        hostName: String,
        manifest: ChromeMV3NativeHostManifest?,
        trustedRecord: ChromeMV3NativeTrustedHostApprovalRecord?
    ) -> ChromeMV3NativeMessagingFixtureLaunchPolicyResult {
        guard let manifest,
              let path = manifest.path
        else {
            return ChromeMV3NativeMessagingFixtureLaunchPolicyResult(
                hostName: hostName,
                executablePath: manifest?.path,
                resolvedExecutablePath: nil,
                allowedFixtureRootPaths:
                    configuration.explicitFixtureHostRootPaths,
                processLaunchAllowedForFixtureHost: false,
                processLaunchAllowedInProduct: false,
                nativeMessagingAvailableInProduct: false,
                trustedHostApprovedForDeveloperPreview: false,
                trustedHostApprovalState:
                    trustedRecord?.trustState ?? .unknown,
                userConsentGrantedForTrustedHost:
                    trustedRecord?.userConsentGranted ?? false,
                diagnostics: ["No manifest path is available for launch."],
                error: .make(.hostManifestMissing)
            )
        }

        let resolvedExecutable =
            URL(fileURLWithPath: path).resolvingSymlinksInPath()
            .standardizedFileURL
        let resolvedRoots =
            configuration.explicitFixtureHostRootPaths
            .map {
                URL(fileURLWithPath: $0, isDirectory: true)
                    .resolvingSymlinksInPath()
                    .standardizedFileURL
            }
        let underRoot = resolvedRoots.contains { root in
            resolvedExecutable.path == root.path
                || resolvedExecutable.path.hasPrefix(root.path + "/")
        }
        let executable = FileManager.default.isExecutableFile(
            atPath: resolvedExecutable.path
        )
        let sourceAllowed =
            manifest.sourceLocation.kind == .explicitTestRoot
                && manifest.sourceLocation.lookupAllowedInThisModel
        let nameMatches = manifest.name == hostName
        let trusted =
            trustedRecord?.hostName == hostName
                && trustedRecord?.extensionID == configuration.extensionID
                && trustedRecord?.profileID == configuration.profileID
                && trustedRecord?.manifestSHA256
                    == manifest.canonicalJSONSHA256
                && trustedRecord?.canLaunchTrustedFixtureHost == true
        let safetyAllowed = underRoot && executable && sourceAllowed && nameMatches
        let allowed = safetyAllowed && trusted
        let diagnostics = uniqueSortedNative([
            underRoot
                ? "Resolved host executable remains under an explicit fixture root."
                : "Resolved host executable escapes explicit fixture roots.",
            executable
                ? "Resolved host executable has executable permissions."
                : "Resolved host executable is missing or not executable.",
            sourceAllowed
                ? "Host manifest came from an explicit test root."
                : "Host manifest source is not an explicit test root.",
            nameMatches
                ? "Host manifest name matches requested host."
                : "Host manifest name does not match requested host.",
            trusted
                ? "Trusted-host approval record allows developer-preview fixture launch."
                : "Trusted-host approval record is missing, revoked, denied, stale, or not launchable.",
            "processLaunchAllowedInProduct remains false.",
            "nativeMessagingAvailableInProduct remains false.",
        ])
        return ChromeMV3NativeMessagingFixtureLaunchPolicyResult(
            hostName: hostName,
            executablePath: path,
            resolvedExecutablePath: allowed ? resolvedExecutable.path : nil,
            allowedFixtureRootPaths:
                resolvedRoots.map(\.path).sorted(),
            processLaunchAllowedForFixtureHost: allowed,
            processLaunchAllowedInProduct: false,
            nativeMessagingAvailableInProduct: false,
            trustedHostApprovedForDeveloperPreview: trusted,
            trustedHostApprovalState:
                trustedRecord?.trustState ?? .unknown,
            userConsentGrantedForTrustedHost:
                trustedRecord?.userConsentGranted ?? false,
            diagnostics: diagnostics,
            error:
                allowed
                    ? nil
                    : .make(
                        safetyAllowed
                            ? .trustedHostApprovalRequired
                            : .invalidExecutablePath,
                        diagnostics
                    )
        )
    }

    private func trustedHostRecord(
        hostName: String,
        manifestSHA256: String?
    ) -> ChromeMV3NativeTrustedHostApprovalRecord? {
        configuration.trustedHostApprovalRecords.last {
            $0.hostName == hostName
                && $0.extensionID == configuration.extensionID
                && $0.profileID == configuration.profileID
                && ($0.manifestSHA256 == manifestSHA256
                    || $0.trustState == .userDenied
                    || $0.trustState == .revoked)
        }
    }

    private func lifecycleRecord(
        operationID: String,
        portID: String?,
        hostName: String,
        operationKind: ChromeMV3NativeMessagingOperationKind,
        launchPolicy: ChromeMV3NativeMessagingFixtureLaunchPolicyResult?,
        processLaunchAttempted: Bool,
        processStarted: Bool,
        messageSentCount: Int,
        messageReceivedCount: Int,
        disconnectReason: ChromeMV3NativeMessagingDisconnectReason?,
        hostExitStatus: Int32?,
        teardownResult: String,
        error: ChromeMV3NativeMessagingRuntimeError?,
        diagnostics: [String]
    ) -> ChromeMV3NativeMessagingProcessLifecycleRecord {
        ChromeMV3NativeMessagingProcessLifecycleRecord(
            operationID: operationID,
            portID: portID,
            hostName: hostName,
            operationKind: operationKind,
            processLaunchAttempted: processLaunchAttempted,
            processLaunchAllowedForFixtureHost:
                launchPolicy?.processLaunchAllowedForFixtureHost ?? false,
            processLaunchAllowedInProduct: false,
            processStarted: processStarted,
            messageSentCount: messageSentCount,
            messageReceivedCount: messageReceivedCount,
            disconnectReason: disconnectReason,
            hostExitStatus: hostExitStatus,
            teardownResult: teardownResult,
            lastErrorCode: error?.code,
            diagnostics: uniqueSortedNative(
                diagnostics
                    + (error?.diagnostics ?? [])
                    + [
                        "Process lifecycle record is scoped to fixture native host execution.",
                        "No product native messaging launch is allowed.",
                    ]
            )
        )
    }

    private func disconnectReason(
        for errorCode: ChromeMV3NativeMessagingRuntimeErrorCode
    ) -> ChromeMV3NativeMessagingDisconnectReason {
        switch errorCode {
        case .authorizationFailed:
            return .authorizationFailed
        case .extensionDisabled:
            return .extensionDisabled
        case .hostManifestMissing, .invalidHostName:
            return .hostManifestMissing
        case .invalidFrame, .invalidJSON, .truncatedFrame:
            return .malformedFrame
        case .missingNativeMessagingPermission:
            return .permissionRevoked
        case .oversizedMessage:
            return .oversizedMessage
        case .hostCrashedOrExited, .processLaunchFailed, .writeFailed,
             .portClosed, .fixtureGateDisabled, .invalidArguments,
             .invalidExecutablePath, .productPolicyBlocked,
             .trustedHostApprovalRequired, .trustedHostDenied,
             .trustedHostRevoked:
            return .nativeHostExited
        }
    }
}

private final class ChromeMV3NativeMessagingInternalPort {
    let portID: String
    let operationID: String
    let hostName: String
    let process: ChromeMV3NativeMessagingFixtureProcess
    let launchPolicy: ChromeMV3NativeMessagingFixtureLaunchPolicyResult
    private var sentCount = 0
    private var receivedCount = 0
    private var closed = false

    init(
        portID: String,
        operationID: String,
        hostName: String,
        process: ChromeMV3NativeMessagingFixtureProcess,
        launchPolicy: ChromeMV3NativeMessagingFixtureLaunchPolicyResult
    ) {
        self.portID = portID
        self.operationID = operationID
        self.hostName = hostName
        self.process = process
        self.launchPolicy = launchPolicy
    }

    func postMessage(
        _ message: ChromeMV3StorageValue
    ) -> ChromeMV3NativeMessagingPortPostMessageResult {
        guard closed == false else {
            let error = ChromeMV3NativeMessagingRuntimeError.make(.portClosed)
            let lifecycle = lifecycle(
                disconnectReason: .nativeHostExited,
                teardownResult: "portClosed",
                error: error,
                diagnostics: error.diagnostics
            )
            return ChromeMV3NativeMessagingPortPostMessageResult(
                portID: portID,
                hostName: hostName,
                succeeded: false,
                response: nil,
                lastErrorMessage: error.message,
                lastErrorCode: error.code,
                outboundFrame: nil,
                inboundFrame: nil,
                lifecycle: lifecycle,
                diagnostics: error.diagnostics
            )
        }

        let outbound = process.write(message)
        guard outbound.succeeded else {
            closed = true
            let error = outbound.error ?? .make(.writeFailed)
            let teardown = process.terminate()
            let lifecycle = lifecycle(
                disconnectReason: .nativeHostExited,
                hostExitStatus: teardown.exitStatus,
                teardownResult: teardown.result,
                error: error,
                diagnostics: outbound.diagnostics + teardown.diagnostics
            )
            return ChromeMV3NativeMessagingPortPostMessageResult(
                portID: portID,
                hostName: hostName,
                succeeded: false,
                response: nil,
                lastErrorMessage: error.message,
                lastErrorCode: error.code,
                outboundFrame: outbound,
                inboundFrame: nil,
                lifecycle: lifecycle,
                diagnostics: lifecycle.diagnostics
            )
        }
        sentCount += 1
        let inbound = process.read()
        if inbound.succeeded {
            receivedCount += 1
        } else {
            closed = true
        }
        let error = inbound.error
        if error != nil {
            _ = process.terminate()
        }
        let lifecycle = lifecycle(
            disconnectReason: error.map { disconnectReason(for: $0.code) },
            hostExitStatus: process.exitStatusIfTerminated,
            teardownResult: error == nil ? "portOpen" : "portClosedAfterError",
            error: error,
            diagnostics: outbound.diagnostics + inbound.diagnostics
        )
        return ChromeMV3NativeMessagingPortPostMessageResult(
            portID: portID,
            hostName: hostName,
            succeeded: error == nil && inbound.message != nil,
            response: inbound.message,
            lastErrorMessage: error?.message,
            lastErrorCode: error?.code,
            outboundFrame: outbound,
            inboundFrame: inbound,
            lifecycle: lifecycle,
            diagnostics: lifecycle.diagnostics
        )
    }

    func disconnect(
        reason: ChromeMV3NativeMessagingDisconnectReason
    ) -> ChromeMV3NativeMessagingProcessLifecycleRecord {
        closed = true
        let teardown = process.terminate()
        return lifecycle(
            disconnectReason: reason,
            hostExitStatus: teardown.exitStatus,
            teardownResult: teardown.result,
            error: nil,
            diagnostics: teardown.diagnostics
        )
    }

    private func lifecycle(
        disconnectReason: ChromeMV3NativeMessagingDisconnectReason?,
        hostExitStatus: Int32? = nil,
        teardownResult: String,
        error: ChromeMV3NativeMessagingRuntimeError?,
        diagnostics: [String]
    ) -> ChromeMV3NativeMessagingProcessLifecycleRecord {
        ChromeMV3NativeMessagingProcessLifecycleRecord(
            operationID: operationID,
            portID: portID,
            hostName: hostName,
            operationKind: .longLivedNativePort,
            processLaunchAttempted: true,
            processLaunchAllowedForFixtureHost:
                launchPolicy.processLaunchAllowedForFixtureHost,
            processLaunchAllowedInProduct: false,
            processStarted: true,
            messageSentCount: sentCount,
            messageReceivedCount: receivedCount,
            disconnectReason: disconnectReason,
            hostExitStatus: hostExitStatus,
            teardownResult: teardownResult,
            lastErrorCode: error?.code,
            diagnostics: uniqueSortedNative(
                diagnostics
                    + (error?.diagnostics ?? [])
                    + [
                        "Native Port lifecycle is active only for fixture host scope.",
                        "Service-worker keepalive parity is not claimed.",
                    ]
            )
        )
    }

    private func disconnectReason(
        for code: ChromeMV3NativeMessagingRuntimeErrorCode
    ) -> ChromeMV3NativeMessagingDisconnectReason {
        switch code {
        case .invalidFrame, .invalidJSON, .truncatedFrame:
            return .malformedFrame
        case .oversizedMessage:
            return .oversizedMessage
        case .missingNativeMessagingPermission:
            return .permissionRevoked
        case .authorizationFailed:
            return .authorizationFailed
        case .extensionDisabled:
            return .extensionDisabled
        case .hostManifestMissing, .invalidHostName:
            return .hostManifestMissing
        case .fixtureGateDisabled, .hostCrashedOrExited, .invalidArguments,
             .invalidExecutablePath, .portClosed, .processLaunchFailed,
             .productPolicyBlocked, .trustedHostApprovalRequired,
             .trustedHostDenied, .trustedHostRevoked, .writeFailed:
            return .nativeHostExited
        }
    }
}

private final class ChromeMV3NativeMessagingFixtureProcess {
    struct Teardown: Equatable {
        var result: String
        var exitStatus: Int32?
        var diagnostics: [String]
    }

    let executablePath: String
    let origin: String
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private var started = false

    init(executablePath: String, origin: String) {
        self.executablePath = executablePath
        self.origin = origin
    }

    var exitStatusIfTerminated: Int32? {
        started && process.isRunning == false ? process.terminationStatus : nil
    }

    func start() throws {
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [origin]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        started = true
    }

    func write(
        _ message: ChromeMV3StorageValue
    ) -> ChromeMV3NativeMessagingFrameCodecResult {
        let frame = ChromeMV3NativeMessagingFramingCodec
            .encodeOutboundMessage(message)
        guard let data = frame.frameData, frame.succeeded else {
            return frame
        }
        do {
            try input.fileHandleForWriting.write(contentsOf: data)
            return frame
        } catch {
            var failed = frame
            failed.succeeded = false
            failed.error = .make(.writeFailed, [error.localizedDescription])
            failed.diagnostics.append(error.localizedDescription)
            return failed
        }
    }

    func read() -> ChromeMV3NativeMessagingFrameCodecResult {
        ChromeMV3NativeMessagingFramingCodec.readInboundMessage(
            from: output.fileHandleForReading
        )
    }

    func terminate() -> Teardown {
        try? input.fileHandleForWriting.close()
        try? output.fileHandleForReading.close()
        try? errors.fileHandleForReading.close()
        guard started else {
            return Teardown(
                result: "notStarted",
                exitStatus: nil,
                diagnostics: ["No fixture process was started."]
            )
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        return Teardown(
            result: "terminated",
            exitStatus: process.terminationStatus,
            diagnostics: [
                "Fixture process was terminated deterministically.",
            ]
        )
    }
}

struct ChromeMV3NativeMessagingImplementationReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var nativeMessagingAvailableInInternalFixture: Bool
    var nativeMessagingAvailableInProduct: Bool
    var processLaunchAllowedForFixtureHost: Bool
    var processLaunchAllowedInProduct: Bool
    var passwordManagerNativeMessagingReadyInFixture: Bool
    var passwordManagerProductRuntimeReady: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var serviceWorkerWakeAvailable: Bool
    var runtimeLoadable: Bool
}

struct ChromeMV3NativeMessagingImplementationReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var extensionID: String
    var profileID: String
    var fixtureHostRootPath: String
    var hostDiscoveryPolicyReport:
        ChromeMV3NativeHostDiscoveryPolicyReport
    var hostManifestLookupValidation:
        ChromeMV3NativeHostManifestValidationSummary?
    var extensionAuthorization:
        ChromeMV3NativeMessagingAuthorizationResult
    var trustedHostPolicyRecord:
        ChromeMV3NativeTrustedHostApprovalRecord
    var fixtureHostLaunchPolicy:
        ChromeMV3NativeMessagingFixtureLaunchPolicyResult
    var framingCodecResults: [ChromeMV3NativeMessagingFrameCodecResult]
    var sendNativeMessageResult:
        ChromeMV3NativeMessagingSendNativeMessageResult
    var connectNativeResult:
        ChromeMV3NativeMessagingConnectNativeResult
    var nativePortPostMessageResult:
        ChromeMV3NativeMessagingPortPostMessageResult?
    var nativePortDisconnectResult:
        ChromeMV3NativeMessagingPortDisconnectResult?
    var malformedFrameResult:
        ChromeMV3NativeMessagingSendNativeMessageResult?
    var oversizedInboundResult:
        ChromeMV3NativeMessagingSendNativeMessageResult?
    var crashEarlyExitResult:
        ChromeMV3NativeMessagingSendNativeMessageResult?
    var processLifecycleDiagnostics:
        [ChromeMV3NativeMessagingProcessLifecycleRecord]
    var securityBlockers: [String]
    var nativeMessagingAvailableInInternalFixture: Bool
    var nativeMessagingAvailableInProduct: Bool
    var processLaunchAllowedForFixtureHost: Bool
    var processLaunchAllowedInProduct: Bool
    var passwordManagerNativeMessagingReadyInFixture: Bool
    var passwordManagerProductRuntimeReady: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var serviceWorkerWakeAvailable: Bool
    var runtimeLoadable: Bool
    var documentationSources: [ChromeMV3ManifestRewritePreviewSource]
    var diagnostics: [String]

    var summary: ChromeMV3NativeMessagingImplementationReportSummary {
        ChromeMV3NativeMessagingImplementationReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            nativeMessagingAvailableInInternalFixture:
                nativeMessagingAvailableInInternalFixture,
            nativeMessagingAvailableInProduct: false,
            processLaunchAllowedForFixtureHost:
                processLaunchAllowedForFixtureHost,
            processLaunchAllowedInProduct: false,
            passwordManagerNativeMessagingReadyInFixture:
                passwordManagerNativeMessagingReadyInFixture,
            passwordManagerProductRuntimeReady: false,
            normalTabRuntimeBridgeAvailable: false,
            serviceWorkerWakeAvailable: false,
            runtimeLoadable: false
        )
    }
}

enum ChromeMV3NativeMessagingImplementationReportWriter {
    static let reportFileName =
        "runtime-native-messaging-implementation-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3NativeMessagingImplementationReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3NativeMessagingImplementationReport {
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

enum ChromeMV3NativeMessagingImplementationReportGenerator {
    static func makeReport(
        extensionID: String = "abcdefghijklmnopabcdefghijklmnop",
        profileID: String = "native-messaging-fixture-profile",
        fixtureHostRootURL: URL,
        hostName: String =
            ChromeMV3NativeMessagingFixtureHostBuilder
            .passwordManagerFixtureHostName,
        fileManager: FileManager = .default
    ) throws -> ChromeMV3NativeMessagingImplementationReport {
        _ = fileManager
        let root = fixtureHostRootURL.standardizedFileURL
        let echo = try ChromeMV3NativeMessagingFixtureHostBuilder
            .writeFixtureHost(
                kind: .echo,
                rootURL: root,
                hostName: hostName,
                extensionID: extensionID
            )
        let approvedRecord = trustedFixtureRecord(
            extensionID: extensionID,
            profileID: profileID,
            root: root,
            hostName: hostName
        )
        let owner = ChromeMV3NativeMessagingRuntimeOwner(
            configuration: .internalFixture(
                extensionID: extensionID,
                profileID: profileID,
                fixtureHostRootPaths: [root.path],
                trustedHostApprovalRecords: [approvedRecord]
            )
        )
        let send = owner.sendNativeMessage(
            hostName: hostName,
            message: .object(["hello": .string("sendNativeMessage")])
        )
        let connect = owner.connectNative(hostName: hostName)
        let post: ChromeMV3NativeMessagingPortPostMessageResult?
        let disconnect: ChromeMV3NativeMessagingPortDisconnectResult?
        if let portID = connect.portID {
            post = owner.postMessage(
                portID: portID,
                message: .object(["hello": .string("connectNative")])
            )
            disconnect = owner.disconnect(
                portID: portID,
                reason: .nativeHostExited
            )
        } else {
            post = nil
            disconnect = nil
        }

        let malformed = try variantSend(
            kind: .malformedFrame,
            root: root.appendingPathComponent("malformed", isDirectory: true),
            extensionID: extensionID,
            profileID: profileID,
            hostName: hostName
        )
        let oversized = try variantSend(
            kind: .oversizedResponse,
            root: root.appendingPathComponent("oversized", isDirectory: true),
            extensionID: extensionID,
            profileID: profileID,
            hostName: hostName
        )
        let crash = try variantSend(
            kind: .crashEarlyExit,
            root: root.appendingPathComponent("crash", isDirectory: true),
            extensionID: extensionID,
            profileID: profileID,
            hostName: hostName
        )
        let outbound = ChromeMV3NativeMessagingFramingCodec
            .encodeOutboundMessage(.object(["ok": .bool(true)]))
        let inbound = outbound.frameData.map {
            ChromeMV3NativeMessagingFramingCodec.decodeInboundFrame($0)
        }
        let lifecycle =
            owner.lifecycleRecords
            + [malformed, oversized, crash].map(\.lifecycle)
        let ready = send.succeeded
            && connect.succeeded
            && post?.succeeded == true
            && disconnect?.disconnected == true
        let reportID = stableIDNative(
            prefix: "runtime-native-messaging-implementation",
            parts: [
                extensionID,
                profileID,
                root.path,
                ready.description,
                echo.executablePath,
            ]
        )
        return ChromeMV3NativeMessagingImplementationReport(
            schemaVersion: 1,
            id: reportID,
            reportFileName:
                ChromeMV3NativeMessagingImplementationReportWriter
                .reportFileName,
            extensionID: extensionID,
            profileID: profileID,
            fixtureHostRootPath: root.path,
            hostDiscoveryPolicyReport:
                ChromeMV3NativeHostDiscoveryPolicyReport.make(
                    lookupPolicy: owner.lookupPolicy(),
                    requestedHostNames: [hostName]
                ),
            hostManifestLookupValidation:
                send.preflight.hostManifestValidationSummary,
            extensionAuthorization:
                send.preflight.authorizationResult,
            trustedHostPolicyRecord: approvedRecord,
            fixtureHostLaunchPolicy: send.launchPolicy,
            framingCodecResults: [outbound] + (inbound.map { [$0] } ?? []),
            sendNativeMessageResult: send,
            connectNativeResult: connect,
            nativePortPostMessageResult: post,
            nativePortDisconnectResult: disconnect,
            malformedFrameResult: malformed,
            oversizedInboundResult: oversized,
            crashEarlyExitResult: crash,
            processLifecycleDiagnostics: lifecycle,
            securityBlockers: [
                "Product native messaging remains unavailable.",
                "Only explicit fixture host roots are read.",
                "Arbitrary system native host manifests are not scanned.",
                "Normal-tab runtime bridge remains unavailable.",
                "Service-worker wake parity is not claimed.",
            ],
            nativeMessagingAvailableInInternalFixture: ready,
            nativeMessagingAvailableInProduct: false,
            processLaunchAllowedForFixtureHost:
                send.launchPolicy.processLaunchAllowedForFixtureHost,
            processLaunchAllowedInProduct: false,
            passwordManagerNativeMessagingReadyInFixture: ready,
            passwordManagerProductRuntimeReady: false,
            normalTabRuntimeBridgeAvailable: false,
            serviceWorkerWakeAvailable: false,
            runtimeLoadable: false,
            documentationSources: documentationSources(),
            diagnostics: uniqueSortedNative(
                echo.diagnostics
                    + send.diagnostics
                    + connect.diagnostics
                    + (post?.diagnostics ?? [])
                    + (disconnect?.diagnostics ?? [])
                    + [
                        "Internal fixture native messaging MVP report is deterministic.",
                        "This report does not claim Chrome native messaging parity.",
                    ]
            )
        )
    }

    private static func variantSend(
        kind: ChromeMV3NativeMessagingFixtureHostKind,
        root: URL,
        extensionID: String,
        profileID: String,
        hostName: String
    ) throws -> ChromeMV3NativeMessagingSendNativeMessageResult {
        _ = try ChromeMV3NativeMessagingFixtureHostBuilder.writeFixtureHost(
            kind: kind,
            rootURL: root,
            hostName: hostName,
            extensionID: extensionID
        )
        let approvedRecord = trustedFixtureRecord(
            extensionID: extensionID,
            profileID: profileID,
            root: root,
            hostName: hostName
        )
        let owner = ChromeMV3NativeMessagingRuntimeOwner(
            configuration: .internalFixture(
                extensionID: extensionID,
                profileID: profileID,
                fixtureHostRootPaths: [root.path],
                trustedHostApprovalRecords: [approvedRecord]
            )
        )
        return owner.sendNativeMessage(
            hostName: hostName,
            message: .object(["variant": .string(kind.rawValue)])
        )
    }

    private static func trustedFixtureRecord(
        extensionID: String,
        profileID: String,
        root: URL,
        hostName: String
    ) -> ChromeMV3NativeTrustedHostApprovalRecord {
        let lookupPolicy = ChromeMV3NativeHostLookupPolicy.macOS(
            explicitTestRootPath: root.path
        )
        return ChromeMV3NativeTrustedHostPolicyFactory
            .recordForExplicitDeveloperPreviewApproval(
                hostName: hostName,
                extensionID: extensionID,
                profileID: profileID,
                lookupPolicy: lookupPolicy,
                permissionState: .grantedByManifest,
                approvedRootPaths: [root.path],
                sequence: 1
            )
            .record
    }

    private static func documentationSources()
        -> [ChromeMV3ManifestRewritePreviewSource]
    {
        [
            source(
                title: "Chrome native messaging",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging",
                note: "Defines manifest format, allowed origins, host name rules, stdio framing, size limits, sendNativeMessage/connectNative host lifetime, and common errors."
            ),
            source(
                title: "Chrome runtime API native messaging",
                url: "https://developer.chrome.com/docs/extensions/reference/api/runtime",
                note: "Defines runtime.connectNative, runtime.sendNativeMessage, Port, permission, promise, and lastError behavior."
            ),
            source(
                title: "Chrome extension service-worker lifecycle",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle",
                note: "Defines native messaging Port keepalive behavior; this MVP records that service-worker wake parity remains unavailable."
            ),
            ChromeMV3ManifestRewritePreviewSource(
                kind: .currentSumiCode,
                title: "Sumi Chrome MV3 native messaging models",
                url: nil,
                note: "Internal fixture process launch is separated from product native messaging availability."
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

private func stableIDNative(prefix: String, parts: [String]) -> String {
    let seed = parts.joined(separator: "\u{1F}")
    let digest = SHA256.hash(data: Data(seed.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "\(prefix)-\(String(hex.prefix(16)))"
}

private func uniqueSortedNative(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}

//
//  SafariExtensionNativeMessagingRoutingProbe.swift
//  Sumi
//
//  Sanitized native-messaging delegate and routing diagnostics.
//  Never logs message bodies or credentials.
//

import Foundation

struct SafariExtensionNativeMessagingMessageShape: Equatable, Sendable {
    let container: String
    let topLevelKeys: [String]
    let typeKeys: [String]

    var keysForLog: String {
        topLevelKeys.isEmpty ? "-" : topLevelKeys.joined(separator: ",")
    }

    var typeKeysForLog: String {
        typeKeys.isEmpty ? "-" : typeKeys.joined(separator: ",")
    }
}

enum SafariExtensionNativeMessagingConnectionBucket: String, Codable, Sendable {
    case notAttempted
    case sendDelegateObserved
    case connectDelegateObserved
    case portSessionActive
    case portDisconnected
    case policyDenied
    case resolverNoMatch
    case companionProtocolUnknown
}

/// Real-runtime routing classification for delegate -> relay -> registry -> adapter probes.
enum SafariExtensionNativeMessagingRoutingBucket: String, Codable, Sendable, Equatable {
    case adapterSelectedRealSendMessage
    case adapterSelectedRealConnectNative
    case adapterNotSelectedIdentifierMismatch
    case adapterRegistryBypassed
    case fallbackBeforeRegistry
    case fallbackAfterRegistry
    case identifierUnknown
}

@MainActor
enum SafariExtensionNativeMessagingRoutingProbe {
    nonisolated static let safariContainingApplicationIdentifier = "application.id"

    nonisolated static func isSafariContainingApplicationRequest(
        _ applicationIdentifier: String?
    ) -> Bool {
        applicationIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines) == safariContainingApplicationIdentifier
    }

    nonisolated static func extensionIdBucket(_ extensionId: String?) -> String {
        SafariExtensionPermissionLifecycleDiagnostics.bucket(extensionId) ?? "unknown"
    }

    nonisolated static func profileIdBucket(_ profileId: UUID?) -> String {
        guard let profileId else { return "none" }
        return String(profileId.uuidString.prefix(8))
    }

    nonisolated static func sanitizedExtensionLabel(_ label: String?) -> String {
        guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines),
              label.isEmpty == false
        else { return "-" }

        let allowed = CharacterSet.alphanumerics
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: "._-"))
        let sanitized = String(
            label.unicodeScalars.map { scalar in
                allowed.contains(scalar) ? String(scalar) : "_"
            }.joined()
        )
        return String(sanitized.prefix(64))
    }

    nonisolated static func sanitizedMessageShape(
        for message: Any?
    ) -> SafariExtensionNativeMessagingMessageShape {
        guard let message else {
            return SafariExtensionNativeMessagingMessageShape(
                container: "nil",
                topLevelKeys: [],
                typeKeys: []
            )
        }

        if let object = message as? [String: Any] {
            return shape(forObjectKeys: Array(object.keys), container: "object")
        }

        if let object = message as? [AnyHashable: Any] {
            return shape(
                forObjectKeys: object.keys.compactMap { $0 as? String },
                container: "object"
            )
        }

        if let string = message as? String {
            return shapeForJSONString(string)
        }

        if message is [Any] {
            return SafariExtensionNativeMessagingMessageShape(
                container: "array",
                topLevelKeys: [],
                typeKeys: []
            )
        }

        return SafariExtensionNativeMessagingMessageShape(
            container: String(describing: type(of: message)),
            topLevelKeys: [],
            typeKeys: []
        )
    }

    static func classify(
        direction: SafariExtensionNativeMessagingDirection,
        applicationIdentifier: String?,
        resolvedHostBundleIdentifier: String?,
        adapter: SumiNativeMessagingProtocolAdapter?,
        adapterByApplicationIdentifier: SumiNativeMessagingProtocolAdapter?,
        registryLookupAttempted: Bool,
        fallbackReason: String?
    ) -> SafariExtensionNativeMessagingRoutingBucket {
        if adapter != nil {
            switch direction {
            case .send:
                return .adapterSelectedRealSendMessage
            case .connect, .portReceive, .portRelay:
                return .adapterSelectedRealConnectNative
            }
        }

        if registryLookupAttempted == false {
            if isIdentifierUnknown(applicationIdentifier: applicationIdentifier, resolvedHostBundleIdentifier: resolvedHostBundleIdentifier) {
                return .identifierUnknown
            }
            return .fallbackBeforeRegistry
        }

        if adapterByApplicationIdentifier != nil {
            return .adapterNotSelectedIdentifierMismatch
        }

        if isIdentifierUnknown(applicationIdentifier: applicationIdentifier, resolvedHostBundleIdentifier: resolvedHostBundleIdentifier) {
            return .identifierUnknown
        }

        return .fallbackAfterRegistry
    }

    static func logDelegateObserved(
        delegateMethod: String,
        direction: SafariExtensionNativeMessagingDirection,
        extensionId: String?,
        extensionDisplayName: String?,
        applicationIdentifier: String?,
        profileId: UUID?,
        messageShape: SafariExtensionNativeMessagingMessageShape? = nil
    ) {
        #if DEBUG || SUMI_DIAGNOSTICS
            guard RuntimeDiagnostics.isVerboseEnabled else { return }
            RuntimeDiagnostics.debug(category: "SafariNativeMessagingRouting") {
                """
                delegate=\(delegateMethod) observed \
                dir=\(direction.rawValue) \
                extBucket=\(extensionIdBucket(extensionId)) \
                extLabel=\(sanitizedExtensionLabel(extensionDisplayName)) \
                profile=\(profileIdBucket(profileId)) \
                appId=\(applicationIdentifier ?? "(nil)") \
                messageShape=\(messageShape?.container ?? "-") \
                messageKeys=\(messageShape?.keysForLog ?? "-") \
                messageTypeKeys=\(messageShape?.typeKeysForLog ?? "-") \
                relayEntered=true
                """
            }
        #else
            _ = (
                delegateMethod,
                direction,
                extensionId,
                extensionDisplayName,
                applicationIdentifier,
                profileId,
                messageShape
            )
        #endif
    }

    static func log(
        delegateMethod: String,
        direction: SafariExtensionNativeMessagingDirection,
        extensionId: String?,
        applicationIdentifier: String?,
        profileId: UUID?,
        resolvedHostBundleIdentifier: String?,
        registryLookupAttempted: Bool,
        registryLookupResult: Bool,
        adapter: SumiNativeMessagingProtocolAdapter?,
        routingBucket: SafariExtensionNativeMessagingRoutingBucket,
        fallbackReason: String?
    ) {
        #if DEBUG || SUMI_DIAGNOSTICS
            guard RuntimeDiagnostics.isVerboseEnabled else { return }
            RuntimeDiagnostics.debug(category: "SafariNativeMessagingRouting") {
                """
                delegate=\(delegateMethod) \
                dir=\(direction.rawValue) \
                extBucket=\(extensionIdBucket(extensionId)) \
                profile=\(profileIdBucket(profileId)) \
                appId=\(applicationIdentifier ?? "(nil)") \
                host=\(resolvedHostBundleIdentifier ?? "(nil)") \
                registryAttempted=\(registryLookupAttempted) \
                registryHit=\(registryLookupResult) \
                adapterSelected=\(adapter != nil) \
                adapterId=\(adapter?.protocolIdentifier ?? "-") \
                bucket=\(routingBucket.rawValue) \
                fallback=\(fallbackReason ?? "-")
                """
            }
        #else
            _ = (
                delegateMethod,
                direction,
                extensionId,
                applicationIdentifier,
                profileId,
                resolvedHostBundleIdentifier,
                registryLookupAttempted,
                registryLookupResult,
                adapter,
                routingBucket,
                fallbackReason
            )
        #endif
    }

    private static func isIdentifierUnknown(
        applicationIdentifier: String?,
        resolvedHostBundleIdentifier: String?
    ) -> Bool {
        let trimmed = applicationIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty && resolvedHostBundleIdentifier == nil {
            return true
        }
        if trimmed.isEmpty == false,
           SumiCompanionAppIdentityMetadata.isRecognizedPublicIdentity(trimmed) == false,
           resolvedHostBundleIdentifier == nil
        {
            return true
        }
        return false
    }

    private nonisolated static func shapeForJSONString(
        _ string: String
    ) -> SafariExtensionNativeMessagingMessageShape {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return SafariExtensionNativeMessagingMessageShape(
                container: "string",
                topLevelKeys: [],
                typeKeys: []
            )
        }

        if let dictionary = object as? [String: Any] {
            return shape(forObjectKeys: Array(dictionary.keys), container: "jsonStringObject")
        }
        if object is [Any] {
            return SafariExtensionNativeMessagingMessageShape(
                container: "jsonStringArray",
                topLevelKeys: [],
                typeKeys: []
            )
        }
        return SafariExtensionNativeMessagingMessageShape(
            container: "jsonStringScalar",
            topLevelKeys: [],
            typeKeys: []
        )
    }

    private nonisolated static func shape(
        forObjectKeys keys: [String],
        container: String
    ) -> SafariExtensionNativeMessagingMessageShape {
        let safeKeys = keys
            .map(sanitizedKey)
            .filter { $0.isEmpty == false }
            .sorted()
        let limitedKeys = Array(safeKeys.prefix(12))
        let typeKeys = limitedKeys.filter(isTypeLikeKey)
        return SafariExtensionNativeMessagingMessageShape(
            container: container,
            topLevelKeys: limitedKeys,
            typeKeys: typeKeys
        )
    }

    private nonisolated static func sanitizedKey(_ key: String) -> String {
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "._-"))
        let sanitized = String(
            key.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.map {
                allowed.contains($0) ? String($0) : "_"
            }.joined()
        )
        return String(sanitized.prefix(48))
    }

    private nonisolated static func isTypeLikeKey(_ key: String) -> Bool {
        switch key.lowercased() {
        case "type", "kind", "command", "action", "method", "request", "event", "operation":
            return true
        default:
            return false
        }
    }
}

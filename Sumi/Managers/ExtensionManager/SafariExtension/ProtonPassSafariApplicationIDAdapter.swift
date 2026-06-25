//
//  ProtonPassSafariApplicationIDAdapter.swift
//  Sumi
//
//  Minimal Safari application.id companion adapter for Proton Pass login state.
//

import AppKit
import Foundation
import OSLog

@MainActor
final class ProtonPassSafariApplicationIDAdapter: CompanionApplicationMessageBackend {
    let backendIdentifier = "sumi.proton-pass-safari.application-id"

    private let store: ProtonPassSafariCompanionStore
    private let clipboard: ProtonPassSafariClipboardAccessing

    init(
        store: ProtonPassSafariCompanionStore = KeychainProtonPassSafariCompanionStore(),
        clipboard: ProtonPassSafariClipboardAccessing = AppKitProtonPassSafariClipboard()
    ) {
        self.store = store
        self.clipboard = clipboard
    }

    func supports(context: CompanionApplicationMessageContext) -> Bool {
        guard SafariExtensionNativeMessagingRoutingProbe
            .isSafariContainingApplicationRequest(context.applicationIdentifier)
        else {
            return false
        }

        return ProtonNativeMessagingIdentifiers.isTrustedSafariExtensionIdentity(
            sourceBundlePath: context.installedExtension.sourceBundlePath
        )
    }

    func handle(
        request: CompanionApplicationMessageRequest,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        let messageShape = Self.sanitizedMessageShape(for: request.message)
        Self.logMessageShape(
            context: request.context,
            shape: messageShape,
            rejectionReason: nil
        )
        do {
            let payload = try Self.parsePayload(request.message, shape: messageShape)
            let value = try handle(
                payload: payload,
                context: request.context,
                messageShape: messageShape
            )
            Self.logHandledMessageShape(context: request.context, shape: messageShape)
            replyHandler(value, nil)
        } catch let error as CompanionApplicationMessageError {
            Self.logMessageShape(
                context: request.context,
                shape: messageShape,
                rejectionReason: Self.rejectionReason(for: error, shape: messageShape)
            )
            replyHandler(nil, error.relayError())
        } catch {
            Self.logMessageShape(
                context: request.context,
                shape: messageShape,
                rejectionReason: "secureStoreFailure"
            )
            replyHandler(nil, CompanionApplicationMessageError.secureStoreFailure.relayError())
        }
    }

    private func handle(
        payload: [String: Any],
        context: CompanionApplicationMessageContext,
        messageShape: ProtonPassSafariCompanionMessageShape
    ) throws -> Any? {
        if let environment = payload["environment"] {
            guard let environment = environment as? String else {
                throw CompanionApplicationMessageError.invalidPayload(messageShape)
            }
            var state = try loadState(context: context)
            state.environment = environment
            try saveState(state, context: context)
            return nil
        }

        if payload.keys.contains("credentials") {
            if payload["credentials"] is NSNull {
                try store.clearState(
                    profileId: context.profileId,
                    extensionId: context.extensionId
                )
                return nil
            }
            guard let rawCredentials = payload["credentials"] as? [String: Any] else {
                throw CompanionApplicationMessageError.invalidPayload(messageShape)
            }
            var state = try loadState(context: context)
            do {
                state.credentials = try Self.parseCredentials(rawCredentials)
            } catch is CompanionApplicationMessageError {
                throw CompanionApplicationMessageError.invalidPayload(messageShape)
            }
            try saveState(state, context: context)
            return nil
        }

        if let refresh = payload["refreshCredentials"] {
            guard let rawRefresh = refresh as? [String: Any],
                  let accessToken = rawRefresh["AccessToken"] as? String,
                  let refreshToken = rawRefresh["RefreshToken"] as? String
            else {
                throw CompanionApplicationMessageError.invalidPayload(messageShape)
            }
            var state = try loadState(context: context)
            guard var credentials = state.credentials else {
                throw CompanionApplicationMessageError.secureStateMissing
            }
            credentials.accessToken = accessToken
            credentials.refreshToken = refreshToken
            state.credentials = credentials
            try saveState(state, context: context)
            return nil
        }

        if payload.keys.contains("readFromClipboard") {
            guard payload["readFromClipboard"] is [String: Any] else {
                throw CompanionApplicationMessageError.invalidPayload(messageShape)
            }
            return clipboard.readString() ?? ""
        }

        if payload.keys.contains("writeToClipboard") {
            guard let rawWrite = payload["writeToClipboard"] as? [String: Any],
                  let content = rawWrite["Content"] as? String
            else {
                throw CompanionApplicationMessageError.invalidPayload(messageShape)
            }
            guard clipboard.writeString(content) else {
                throw CompanionApplicationMessageError.secureStoreFailure
            }
            return nil
        }

        Self.logUnsupportedMessageShape(context: context, shape: messageShape)
        throw CompanionApplicationMessageError.unsupportedMessageType(
            payload.keys.sorted().first,
            messageShape
        )
    }

    private func loadState(
        context: CompanionApplicationMessageContext
    ) throws -> ProtonPassSafariCompanionState {
        try store.loadState(
            profileId: context.profileId,
            extensionId: context.extensionId
        ) ?? ProtonPassSafariCompanionState(environment: nil, credentials: nil)
    }

    private func saveState(
        _ state: ProtonPassSafariCompanionState,
        context: CompanionApplicationMessageContext
    ) throws {
        try store.saveState(
            state,
            profileId: context.profileId,
            extensionId: context.extensionId
        )
    }

    static func parsePayload(_ message: Any) throws -> [String: Any] {
        try parsePayload(message, shape: sanitizedMessageShape(for: message))
    }

    static func parsePayload(
        _ message: Any,
        shape: ProtonPassSafariCompanionMessageShape
    ) throws -> [String: Any] {
        guard let string = message as? String,
              let data = string.data(using: .utf8)
        else {
            throw CompanionApplicationMessageError.invalidPayload(shape)
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CompanionApplicationMessageError.invalidPayload(shape)
        }
        guard let payload = object as? [String: Any] else {
            throw CompanionApplicationMessageError.invalidPayload(shape)
        }
        return payload
    }

    static func sanitizedMessageShape(
        for message: Any
    ) -> ProtonPassSafariCompanionMessageShape {
        if let object = message as? [String: Any] {
            return shape(
                payloadClass: "Dictionary",
                encoding: "object",
                keys: Array(object.keys)
            )
        }

        if let object = message as? [AnyHashable: Any] {
            return shape(
                payloadClass: "Dictionary",
                encoding: "object",
                keys: object.keys.compactMap { $0 as? String }
            )
        }

        if let string = message as? String {
            return shapeForString(string)
        }

        if message is [Any] {
            return shape(
                payloadClass: "Array",
                encoding: "array",
                keys: []
            )
        }

        if message is NSNull {
            return shape(
                payloadClass: "NSNull",
                encoding: "null",
                keys: []
            )
        }

        return shape(
            payloadClass: String(describing: type(of: message)),
            encoding: "unsupported",
            keys: []
        )
    }

    private static func shapeForString(
        _ string: String
    ) -> ProtonPassSafariCompanionMessageShape {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else {
            return shape(
                payloadClass: "String",
                encoding: "invalidJSONString",
                keys: [],
                parseFailureReason: "invalidJSONString"
            )
        }

        if let dictionary = object as? [String: Any] {
            return shape(
                payloadClass: "String",
                encoding: "jsonString",
                keys: Array(dictionary.keys)
            )
        }

        if let encodedString = object as? String,
           let encodedData = encodedString.data(using: .utf8),
           let nestedObject = try? JSONSerialization.jsonObject(with: encodedData),
           let dictionary = nestedObject as? [String: Any]
        {
            return shape(
                payloadClass: "String",
                encoding: "doubleEncodedJSONString",
                keys: Array(dictionary.keys)
            )
        }

        if object is [Any] {
            return shape(
                payloadClass: "String",
                encoding: "jsonStringArray",
                keys: []
            )
        }

        return shape(
            payloadClass: "String",
            encoding: "jsonStringScalar",
            keys: []
        )
    }

    private static func shape(
        payloadClass: String,
        encoding: String,
        keys: [String],
        parseFailureReason: String? = nil
    ) -> ProtonPassSafariCompanionMessageShape {
        let topLevelKeys = keys
            .map(sanitizedKey)
            .filter { $0.isEmpty == false }
            .sorted()
        let selectedTypes = contractMessageTypes.filter { topLevelKeys.contains($0) }
        return ProtonPassSafariCompanionMessageShape(
            payloadClass: payloadClass,
            encoding: encoding,
            topLevelKeys: Array(topLevelKeys.prefix(12)),
            selectedType: selectedTypes.count == 1 ? selectedTypes[0] : nil,
            matchedTypeCount: selectedTypes.count,
            parseFailureReason: parseFailureReason
        )
    }

    private static let contractMessageTypes = [
        "environment",
        "credentials",
        "refreshCredentials",
        "readFromClipboard",
        "writeToClipboard",
        "fetchRelatedOrigins",
    ]

    private static func sanitizedKey(_ key: String) -> String {
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "._-"))
        let sanitized = String(
            key.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.map {
                allowed.contains($0) ? String($0) : "_"
            }.joined()
        )
        return String(sanitized.prefix(48))
    }

    private static func rejectionReason(
        for error: CompanionApplicationMessageError,
        shape: ProtonPassSafariCompanionMessageShape
    ) -> String {
        switch error {
        case .invalidPayload:
            if shape.encoding == "invalidJSONString" { return "invalidJSONString" }
            if shape.encoding == "doubleEncodedJSONString" { return "doubleEncodedJSONString" }
            if shape.topLevelKeys.isEmpty { return "nonObjectPayload" }
            if shape.matchedTypeCount > 1 { return "ambiguousTopLevelKeys" }
            return "invalidPayload"
        case .unsupportedMessageType:
            if shape.matchedTypeCount > 1 { return "ambiguousTopLevelKeys" }
            if shape.selectedType == nil { return "unknownTopLevelKeys" }
            return "unsupportedMessageType"
        case .secureStateMissing:
            return "secureStateMissing"
        case .secureStoreFailure:
            return "secureStoreFailure"
        case .unsupportedApplicationId:
            return "unsupportedApplicationId"
        case .unsupportedExtension:
            return "unsupportedExtension"
        case .unsupportedBackend:
            return "unsupportedBackend"
        case .exactlyOnceReplyViolation:
            return "exactlyOnceReplyViolation"
        }
    }

    private static func logUnsupportedMessageShape(
        context: CompanionApplicationMessageContext,
        shape: ProtonPassSafariCompanionMessageShape
    ) {
        RuntimeDiagnostics.logger(category: "ProtonCompanion")
            .warning("\(unsupportedMessageLogLine(context: context, shape: shape), privacy: .public)")
    }

    private static func logHandledMessageShape(
        context: CompanionApplicationMessageContext,
        shape: ProtonPassSafariCompanionMessageShape
    ) {
        guard shape.selectedType == "readFromClipboard" else { return }
        RuntimeDiagnostics.logger(category: "ProtonCompanion")
            .info("\(handledMessageLogLine(context: context, shape: shape), privacy: .public)")
    }

    static func unsupportedMessageLogLine(
        context: CompanionApplicationMessageContext,
        shape: ProtonPassSafariCompanionMessageShape
    ) -> String {
        """
        ProtonCompanionUnsupported \
        payloadClass=\(shape.payloadClass) \
        parseMode=\(shape.parseMode) \
        topLevelKeys=\(shape.keysForLog) \
        selectedType=\(shape.selectedType ?? "-") \
        parseFailureReason=\(shape.parseFailureReason ?? "-") \
        profileBucket=\(SafariExtensionNativeMessagingRoutingProbe.profileIdBucket(context.profileId)) \
        extensionBucket=\(SafariExtensionNativeMessagingRoutingProbe.extensionIdBucket(context.extensionId))
        """
    }

    static func handledMessageLogLine(
        context: CompanionApplicationMessageContext,
        shape: ProtonPassSafariCompanionMessageShape
    ) -> String {
        """
        ProtonCompanionHandled \
        selectedType=\(shape.selectedType ?? "-") \
        result=success \
        profileBucket=\(SafariExtensionNativeMessagingRoutingProbe.profileIdBucket(context.profileId)) \
        extensionBucket=\(SafariExtensionNativeMessagingRoutingProbe.extensionIdBucket(context.extensionId))
        """
    }

    private static func logMessageShape(
        context: CompanionApplicationMessageContext,
        shape: ProtonPassSafariCompanionMessageShape,
        rejectionReason: String?
    ) {
        #if DEBUG || SUMI_DIAGNOSTICS
            guard RuntimeDiagnostics.isVerboseEnabled else { return }
            let prefix = rejectionReason == nil ? "messageShape" : "parseFailure"
            RuntimeDiagnostics.debug(category: "ProtonCompanion") {
                """
                ProtonCompanion \(prefix) \
                extBucket=\(SafariExtensionNativeMessagingRoutingProbe.extensionIdBucket(context.extensionId)) \
                profile=\(SafariExtensionNativeMessagingRoutingProbe.profileIdBucket(context.profileId)) \
                appId=\(context.applicationIdentifier) \
                payloadClass=\(shape.payloadClass) \
                encoding=\(shape.encoding) \
                topLevelKeys=\(shape.keysForLog) \
                selectedType=\(shape.selectedType ?? "-") \
                reason=\(rejectionReason ?? "-") \
                parseFailureReason=\(shape.parseFailureReason ?? "-")
                """
            }
        #else
            _ = (context, shape, rejectionReason)
        #endif
    }

    static func parseCredentials(_ raw: [String: Any]) throws -> ProtonPassSafariCredentials {
        guard let uid = raw["UID"] as? String,
              let accessToken = raw["AccessToken"] as? String,
              let refreshToken = raw["RefreshToken"] as? String,
              let userId = raw["UserID"] as? String
        else {
            throw CompanionApplicationMessageError.invalidPayload()
        }
        return ProtonPassSafariCredentials(
            uid: uid,
            accessToken: accessToken,
            refreshToken: refreshToken,
            userId: userId
        )
    }
}

@MainActor
protocol ProtonPassSafariClipboardAccessing: AnyObject {
    func readString() -> String?
    func writeString(_ string: String) -> Bool
}

@MainActor
final class AppKitProtonPassSafariClipboard: ProtonPassSafariClipboardAccessing {
    func readString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    func writeString(_ string: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(string, forType: .string)
    }
}

struct ProtonPassSafariCompanionMessageShape: Equatable, Sendable {
    let payloadClass: String
    let encoding: String
    let topLevelKeys: [String]
    let selectedType: String?
    let matchedTypeCount: Int
    let parseFailureReason: String?

    var parseMode: String { encoding }

    var keysForLog: String {
        topLevelKeys.isEmpty ? "[]" : "[\(topLevelKeys.joined(separator: ","))]"
    }

    var errorUserInfo: [String: Any] {
        var userInfo: [String: Any] = [
            "SumiCompanionPayloadClass": payloadClass,
            "SumiCompanionParseMode": parseMode,
            "SumiCompanionTopLevelKeys": topLevelKeys,
        ]
        if let selectedType {
            userInfo["SumiCompanionSelectedType"] = selectedType
        }
        if let parseFailureReason {
            userInfo["SumiCompanionParseFailureReason"] = parseFailureReason
        }
        return userInfo
    }
}

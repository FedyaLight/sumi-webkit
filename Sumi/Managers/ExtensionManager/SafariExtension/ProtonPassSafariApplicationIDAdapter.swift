//
//  ProtonPassSafariApplicationIDAdapter.swift
//  Sumi
//
//  Minimal Safari application.id companion adapter for Proton Pass login state.
//

import Foundation

@MainActor
final class ProtonPassSafariApplicationIDAdapter: CompanionApplicationMessageBackend {
    let backendIdentifier = "sumi.proton-pass-safari.application-id"

    private let store: ProtonPassSafariCompanionStore

    init(store: ProtonPassSafariCompanionStore = KeychainProtonPassSafariCompanionStore()) {
        self.store = store
    }

    func supports(context: CompanionApplicationMessageContext) -> Bool {
        guard SafariExtensionNativeMessagingRoutingProbe
            .isSafariContainingApplicationRequest(context.applicationIdentifier)
        else {
            return false
        }

        return ProtonNativeMessagingIdentifiers.isSafariExtensionIdentity(
            sourceBundlePath: context.installedExtension.sourceBundlePath
        )
    }

    func handle(
        request: CompanionApplicationMessageRequest,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        do {
            let payload = try Self.parsePayload(request.message)
            try handle(payload: payload, context: request.context)
            replyHandler(nil, nil)
        } catch let error as CompanionApplicationMessageError {
            replyHandler(nil, error.relayError())
        } catch {
            replyHandler(nil, CompanionApplicationMessageError.secureStoreFailure.relayError())
        }
    }

    private func handle(
        payload: [String: Any],
        context: CompanionApplicationMessageContext
    ) throws {
        if let environment = payload["environment"] {
            guard let environment = environment as? String else {
                throw CompanionApplicationMessageError.invalidPayload
            }
            var state = try loadState(context: context)
            state.environment = environment
            try saveState(state, context: context)
            return
        }

        if payload.keys.contains("credentials") {
            if payload["credentials"] is NSNull {
                try store.clearState(
                    profileId: context.profileId,
                    extensionId: context.extensionId
                )
                return
            }
            guard let rawCredentials = payload["credentials"] as? [String: Any] else {
                throw CompanionApplicationMessageError.invalidPayload
            }
            var state = try loadState(context: context)
            state.credentials = try Self.parseCredentials(rawCredentials)
            try saveState(state, context: context)
            return
        }

        if let refresh = payload["refreshCredentials"] {
            guard let rawRefresh = refresh as? [String: Any],
                  let accessToken = rawRefresh["AccessToken"] as? String,
                  let refreshToken = rawRefresh["RefreshToken"] as? String
            else {
                throw CompanionApplicationMessageError.invalidPayload
            }
            var state = try loadState(context: context)
            guard var credentials = state.credentials else {
                throw CompanionApplicationMessageError.secureStateMissing
            }
            credentials.accessToken = accessToken
            credentials.refreshToken = refreshToken
            state.credentials = credentials
            try saveState(state, context: context)
            return
        }

        throw CompanionApplicationMessageError.unsupportedMessageType(
            payload.keys.sorted().first
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
        guard let string = message as? String,
              let data = string.data(using: .utf8)
        else {
            throw CompanionApplicationMessageError.invalidPayload
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CompanionApplicationMessageError.invalidPayload
        }
        guard let payload = object as? [String: Any] else {
            throw CompanionApplicationMessageError.invalidPayload
        }
        return payload
    }

    static func parseCredentials(_ raw: [String: Any]) throws -> ProtonPassSafariCredentials {
        guard let uid = raw["UID"] as? String,
              let accessToken = raw["AccessToken"] as? String,
              let refreshToken = raw["RefreshToken"] as? String,
              let userId = raw["UserID"] as? String
        else {
            throw CompanionApplicationMessageError.invalidPayload
        }
        return ProtonPassSafariCredentials(
            uid: uid,
            accessToken: accessToken,
            refreshToken: refreshToken,
            userId: userId
        )
    }
}

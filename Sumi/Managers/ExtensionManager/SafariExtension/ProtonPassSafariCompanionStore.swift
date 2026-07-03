//
//  ProtonPassSafariCompanionStore.swift
//  Sumi
//
//  Profile-scoped secure state for Sumi's Proton Pass Safari companion adapter.
//

import Foundation
import OSLog
import Security

struct ProtonPassSafariCredentials: Codable, Equatable {
    var uid: String
    var accessToken: String
    var refreshToken: String
    var userId: String
}

struct ProtonPassSafariCompanionState: Codable, Equatable {
    var environment: String?
    var credentials: ProtonPassSafariCredentials?
}

protocol ProtonPassSafariCompanionStore: AnyObject {
    func loadState(profileId: UUID?, extensionId: String) throws -> ProtonPassSafariCompanionState?
    func saveState(
        _ state: ProtonPassSafariCompanionState,
        profileId: UUID?,
        extensionId: String
    ) throws
    func clearState(profileId: UUID?, extensionId: String) throws
}

final class KeychainProtonPassSafariCompanionStore: ProtonPassSafariCompanionStore {
    private static let logger = Logger.sumi(category: "ProtonCompanion")
    private let service = "\(SumiAppIdentity.bundleIdentifier).proton-pass-safari-companion"

    /// Keychain items are protected by the writing binary's code signature.
    /// Debug builds are ad-hoc signed, so every rebuild orphans the previous
    /// item: reads and updates fail with an authorization-family status even
    /// though the item exists. Treat the orphaned item as absent (the
    /// extension re-sends credentials on the next login/refresh) instead of
    /// failing the whole native-messaging pipeline.
    private static func isSignatureInvalidatedStatus(_ status: OSStatus) -> Bool {
        status == errSecAuthFailed
            || status == errSecInteractionNotAllowed
            || status == errSecMissingEntitlement
            || status == errSecNotAvailable
    }

    func loadState(
        profileId: UUID?,
        extensionId: String
    ) throws -> ProtonPassSafariCompanionState? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(profileId: profileId, extensionId: extensionId),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        if Self.isSignatureInvalidatedStatus(status) {
            Self.logger.warning(
                "Proton companion keychain read denied (status \(status, privacy: .public)); treating stored state as absent"
            )
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data
        else {
            Self.logger.error(
                "Proton companion keychain read failed (status \(status, privacy: .public))"
            )
            throw CompanionApplicationMessageError.secureStoreFailure
        }
        return try JSONDecoder().decode(ProtonPassSafariCompanionState.self, from: data)
    }

    func saveState(
        _ state: ProtonPassSafariCompanionState,
        profileId: UUID?,
        extensionId: String
    ) throws {
        let data = try JSONEncoder().encode(state)
        let account = account(profileId: profileId, extensionId: extensionId)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            guard Self.isSignatureInvalidatedStatus(updateStatus) else {
                Self.logger.error(
                    "Proton companion keychain update failed (status \(updateStatus, privacy: .public))"
                )
                throw CompanionApplicationMessageError.secureStoreFailure
            }
            // Self-heal: replace the item orphaned by a code-signature change.
            Self.logger.warning(
                "Proton companion keychain update denied (status \(updateStatus, privacy: .public)); replacing orphaned item"
            )
            SecItemDelete(query as CFDictionary)
        }

        var addQuery = query
        addQuery.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            Self.logger.error(
                "Proton companion keychain add failed (status \(addStatus, privacy: .public))"
            )
            throw CompanionApplicationMessageError.secureStoreFailure
        }
    }

    func clearState(profileId: UUID?, extensionId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(profileId: profileId, extensionId: extensionId),
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess
            || status == errSecItemNotFound
            || Self.isSignatureInvalidatedStatus(status)
        else {
            Self.logger.error(
                "Proton companion keychain delete failed (status \(status, privacy: .public))"
            )
            throw CompanionApplicationMessageError.secureStoreFailure
        }
    }

    private func account(profileId: UUID?, extensionId: String) -> String {
        let profile = profileId?.uuidString.lowercased() ?? "profileless"
        return "\(profile):\(extensionId)"
    }
}

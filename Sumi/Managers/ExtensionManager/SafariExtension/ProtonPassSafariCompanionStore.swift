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

enum ProtonPassSafariProfileRetirementError: Error, Equatable {
    case accountEnumerationFailed(OSStatus)
    case malformedAccountEnumeration
    case accountDeletionFailed(String, OSStatus)
    case deletionVerificationFailed
}

final class KeychainProtonPassSafariCompanionStore: ProtonPassSafariCompanionStore {
    struct ProfileRetirementOperations {
        let accountsForService: (String) throws -> [String]
        let deleteAccount: (String, String) throws -> Void

        static var live: ProfileRetirementOperations {
            ProfileRetirementOperations(
                accountsForService: { service in
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecReturnAttributes as String: true,
                    kSecMatchLimit as String: kSecMatchLimitAll,
                ]
                var result: CFTypeRef?
                let status = SecItemCopyMatching(
                    query as CFDictionary,
                    &result
                )
                if status == errSecItemNotFound {
                    return []
                }
                guard status == errSecSuccess else {
                    throw ProtonPassSafariProfileRetirementError
                        .accountEnumerationFailed(status)
                }
                guard let attributes = result as? [[String: Any]] else {
                    throw ProtonPassSafariProfileRetirementError
                        .malformedAccountEnumeration
                }
                return try attributes.map { item in
                    guard let account = item[kSecAttrAccount as String] as? String else {
                        throw ProtonPassSafariProfileRetirementError
                            .malformedAccountEnumeration
                    }
                    return account
                }
                },
                deleteAccount: { service, account in
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account,
                ]
                let status = SecItemDelete(query as CFDictionary)
                guard status == errSecSuccess || status == errSecItemNotFound else {
                    throw ProtonPassSafariProfileRetirementError
                        .accountDeletionFailed(account, status)
                }
                }
            )
        }
    }

    private static let logger = Logger.sumi(category: "ProtonCompanion")
    private let service: String
    private let profileRetirementOperations: ProfileRetirementOperations

    init(
        service: String = "\(SumiAppIdentity.bundleIdentifier).proton-pass-safari-companion",
        profileRetirementOperations: ProfileRetirementOperations = .live
    ) {
        self.service = service
        self.profileRetirementOperations = profileRetirementOperations
    }

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

    func deleteProfileData(profileID: UUID) throws {
        let prefix = "\(profileID.uuidString.lowercased()):"
        let accounts = try profileRetirementOperations.accountsForService(
            service
        )
        for account in accounts where account.hasPrefix(prefix) {
            try profileRetirementOperations.deleteAccount(service, account)
        }

        let remainingAccounts = try profileRetirementOperations
            .accountsForService(service)
        guard remainingAccounts.contains(where: { $0.hasPrefix(prefix) }) == false else {
            throw ProtonPassSafariProfileRetirementError
                .deletionVerificationFailed
        }
    }

    private func account(profileId: UUID?, extensionId: String) -> String {
        let profile = profileId?.uuidString.lowercased() ?? "profileless"
        return "\(profile):\(extensionId)"
    }
}

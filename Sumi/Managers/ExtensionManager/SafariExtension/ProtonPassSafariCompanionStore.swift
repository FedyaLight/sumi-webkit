//
//  ProtonPassSafariCompanionStore.swift
//  Sumi
//
//  Profile-scoped secure state for Sumi's Proton Pass Safari companion adapter.
//

import Foundation
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
    private let service = "\(SumiAppIdentity.bundleIdentifier).proton-pass-safari-companion"

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
        guard status == errSecSuccess,
              let data = result as? Data
        else {
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
        guard updateStatus == errSecItemNotFound else {
            throw CompanionApplicationMessageError.secureStoreFailure
        }

        var addQuery = query
        addQuery.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
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
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CompanionApplicationMessageError.secureStoreFailure
        }
    }

    private func account(profileId: UUID?, extensionId: String) -> String {
        let profile = profileId?.uuidString.lowercased() ?? "profileless"
        return "\(profile):\(extensionId)"
    }
}

final class InMemoryProtonPassSafariCompanionStore: ProtonPassSafariCompanionStore {
    private var states: [String: ProtonPassSafariCompanionState] = [:]
    var shouldFail = false

    func loadState(
        profileId: UUID?,
        extensionId: String
    ) throws -> ProtonPassSafariCompanionState? {
        if shouldFail { throw CompanionApplicationMessageError.secureStoreFailure }
        return states[key(profileId: profileId, extensionId: extensionId)]
    }

    func saveState(
        _ state: ProtonPassSafariCompanionState,
        profileId: UUID?,
        extensionId: String
    ) throws {
        if shouldFail { throw CompanionApplicationMessageError.secureStoreFailure }
        states[key(profileId: profileId, extensionId: extensionId)] = state
    }

    func clearState(profileId: UUID?, extensionId: String) throws {
        if shouldFail { throw CompanionApplicationMessageError.secureStoreFailure }
        states.removeValue(forKey: key(profileId: profileId, extensionId: extensionId))
    }

    private func key(profileId: UUID?, extensionId: String) -> String {
        "\(profileId?.uuidString.lowercased() ?? "profileless"):\(extensionId)"
    }
}

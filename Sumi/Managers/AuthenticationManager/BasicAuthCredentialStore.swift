//
//  BasicAuthCredentialStore.swift
//  Sumi
//
//

import Foundation

#if canImport(Security)
import Security
#endif

struct BasicAuthCredentialKey: Hashable, Sendable {
    private static let accountPrefix = "v2"

    let scheme: String?
    let host: String
    let port: Int
    let realm: String?
    let authenticationMethod: String
    let profilePartitionId: String
    let isEphemeralProfile: Bool
    let websiteDataStoreIdentifier: String?

    init?(
        protectionSpace: URLProtectionSpace,
        profileId: UUID?,
        isEphemeralProfile: Bool,
        websiteDataStoreIdentifier: UUID?
    ) {
        guard let profileId else { return nil }

        let host = Self.normalizedHost(protectionSpace.host)
        guard !host.isEmpty else { return nil }

        self.scheme = protectionSpace.protocol.map { $0.lowercased() }
        self.host = host
        self.port = protectionSpace.port
        self.realm = protectionSpace.realm
        self.authenticationMethod = protectionSpace.authenticationMethod.lowercased()
        self.profilePartitionId = profileId.uuidString.lowercased()
        self.isEphemeralProfile = isEphemeralProfile
        self.websiteDataStoreIdentifier = websiteDataStoreIdentifier?.uuidString.lowercased()
    }

    var account: String {
        [
            Self.accountPrefix,
            "scheme=\(Self.encodeOptional(scheme))",
            "host=\(Self.encode(host))",
            "port=\(port)",
            "realm=\(Self.encodeOptional(realm))",
            "method=\(Self.encode(authenticationMethod))",
            "profile=\(Self.encode(profilePartitionId))",
            "ephemeral=\(isEphemeralProfile ? "1" : "0")",
            "store=\(Self.encodeOptional(websiteDataStoreIdentifier))"
        ].joined(separator: "|")
    }

    static func host(fromAccount account: String) -> String? {
        guard account.hasPrefix("\(accountPrefix)|") else {
            let host = normalizedHost(account)
            return host.isEmpty ? nil : host
        }

        for component in account.split(separator: "|") {
            guard component.hasPrefix("host=") else { continue }
            return decode(String(component.dropFirst("host=".count))).flatMap {
                let host = normalizedHost($0)
                return host.isEmpty ? nil : host
            }
        }
        return nil
    }

    private static func normalizedHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func encode(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
    }

    private static func decode(_ value: String) -> String? {
        guard let data = Data(base64Encoded: value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func encodeOptional(_ value: String?) -> String {
        guard let value else { return "nil" }
        return "value:\(encode(value))"
    }
}

/// Simple persistence layer for HTTP basic-auth credentials keyed by protection space.
/// Uses the keychain to keep secrets off disk and available across launches.
@MainActor
final class BasicAuthCredentialStore {
    struct StoredCredential {
        let username: String
        let password: String
    }

    private let service: String

    init(service: String = "com.sumi.basicAuth") {
        self.service = service
    }

    func credential(for key: BasicAuthCredentialKey) -> StoredCredential? {
        let account = key.account

        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else { return nil }
        guard let data = item as? Data else { return nil }

        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            return StoredCredential(
                username: payload.username,
                password: payload.password
            )
        } catch {
            // If decoding fails, remove the corrupt record so future prompts can succeed.
            _ = deleteCredential(for: key)
            return nil
        }
        #else
        return nil
        #endif
    }

    @discardableResult
    func saveCredential(_ credential: StoredCredential, for key: BasicAuthCredentialKey) -> Bool {
        let account = key.account

        #if canImport(Security)
        do {
            let data = try JSONEncoder().encode(Payload(username: credential.username, password: credential.password))

            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]

            let attributes: [String: Any] = [kSecValueData as String: data]

            let status: OSStatus
            if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
                status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            } else {
                var insert = query
                insert[kSecValueData as String] = data
                status = SecItemAdd(insert as CFDictionary, nil)
            }

            guard status == errSecSuccess else { return false }
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    @discardableResult
    func deleteCredential(for key: BasicAuthCredentialKey) -> Bool {
        let account = key.account

        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
        #else
        return false
        #endif
    }

    func allCredentialHosts() -> Set<String> {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return [] }
        let attributes = item as? [[String: Any]] ?? []
        return Set(attributes.compactMap {
            guard let account = $0[kSecAttrAccount as String] as? String else { return nil }
            return BasicAuthCredentialKey.host(fromAccount: account)
        })
        #else
        return []
        #endif
    }
}

private struct Payload: Codable {
    let username: String
    let password: String
}

extension BasicAuthCredentialStore.StoredCredential {
    var asURLCredential: URLCredential {
        URLCredential(user: username, password: password, persistence: .forSession)
    }
}

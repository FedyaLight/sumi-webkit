import CommonCrypto
import Foundation
import Security

/// Decrypts Chromium's `encrypted_value` cookie blobs.
///
/// Chromium derives an AES key from a random password it keeps in the login
/// keychain under "<Browser> Safe Storage". That keychain item's access control
/// lists only the source browser, so macOS shows an authorization prompt the
/// first time Sumi reads it — and the user may refuse. Every failure here is
/// therefore reportable and skippable, never fatal.
///
/// CommonCrypto rather than CryptoKit: CryptoKit offers neither PBKDF2 nor
/// AES-CBC, both of which this format requires.
struct SumiChromiumSafeStorageDecryptor {
    enum DecryptionError: LocalizedError, Equatable {
        case keychainUnavailable(OSStatus)
        case appBoundEncryption
        case unsupportedVersion(String)

        var errorDescription: String? {
            switch self {
            case .keychainUnavailable:
                return "Sumi could not read the browser's cookie key from your keychain."
            case .appBoundEncryption:
                return "These cookies are locked to the browser that created them."
            case let .unsupportedVersion(prefix):
                return "Unsupported cookie encryption (\(prefix))."
            }
        }
    }

    private static let salt = "saltysalt"
    private static let iterations: UInt32 = 1003
    private static let keyLength = 16
    /// Chromium's fixed IV: sixteen spaces.
    private static let initializationVector = [UInt8](repeating: 0x20, count: 16)

    /// Supplies the raw keychain password. Injected so tests never touch the
    /// real keychain.
    var keyProvider: (String, String) -> Result<String, DecryptionError>

    init(
        keyProvider: @escaping (String, String) -> Result<String, DecryptionError> = Self.keychainPassword
    ) {
        self.keyProvider = keyProvider
    }

    /// Reads the browser's storage password and stretches it into the AES key.
    func derivedKey(service: String, account: String) -> Result<[UInt8], DecryptionError> {
        switch keyProvider(service, account) {
        case let .failure(error):
            return .failure(error)
        case let .success(password):
            var key = [UInt8](repeating: 0, count: Self.keyLength)
            let saltBytes = Array(Self.salt.utf8)
            let passwordBytes = Array(password.utf8)
            let status = CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                password,
                passwordBytes.count,
                saltBytes,
                saltBytes.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                Self.iterations,
                &key,
                Self.keyLength
            )
            guard status == kCCSuccess else {
                return .failure(.keychainUnavailable(OSStatus(status)))
            }
            return .success(key)
        }
    }

    /// Decrypts one `encrypted_value`. `host` is used to strip the domain hash
    /// that Chromium started prepending in M124.
    func decrypt(_ blob: Data, key: [UInt8], host: String) -> Result<String, DecryptionError> {
        guard blob.count > 3 else { return .success("") }
        let prefix = String(decoding: blob.prefix(3), as: UTF8.self)
        switch prefix {
        case "v10", "v11":
            break
        case "v20":
            // App-bound encryption; the key never leaves the owning browser.
            return .failure(.appBoundEncryption)
        default:
            // No recognised prefix means the value was never encrypted.
            return .success(String(decoding: blob, as: UTF8.self))
        }

        let body = Array(blob.dropFirst(3))
        var output = [UInt8](repeating: 0, count: body.count + kCCBlockSizeAES128)
        var decryptedCount = 0
        let status = CCCrypt(
            CCOperation(kCCDecrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(0), // no padding option: Chromium pads with PKCS7 manually
            key,
            Self.keyLength,
            Self.initializationVector,
            body,
            body.count,
            &output,
            output.count,
            &decryptedCount
        )
        guard status == kCCSuccess, decryptedCount > 0 else {
            return .failure(.unsupportedVersion(prefix))
        }

        var plaintext = Data(output.prefix(decryptedCount))
        plaintext = Self.strippingPKCS7(plaintext)
        plaintext = Self.strippingDomainHash(plaintext, host: host)
        return .success(String(decoding: plaintext, as: UTF8.self))
    }

    /// Chromium M124 and later prefix the plaintext with a SHA-256 of the
    /// cookie's host. Detected by comparing rather than assumed by version, so
    /// both old and new rows decode from the same database.
    static func strippingDomainHash(_ data: Data, host: String) -> Data {
        guard data.count > 32 else { return data }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        let hostBytes = Array(host.utf8)
        CC_SHA256(hostBytes, CC_LONG(hostBytes.count), &hash)
        guard data.prefix(32).elementsEqual(hash) else { return data }
        return Data(data.dropFirst(32))
    }

    private static func strippingPKCS7(_ data: Data) -> Data {
        guard let pad = data.last, pad > 0, pad <= 16, data.count >= Int(pad) else { return data }
        return Data(data.dropLast(Int(pad)))
    }

    static func keychainPassword(service: String, account: String) -> Result<String, DecryptionError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8)
        else {
            return .failure(.keychainUnavailable(status))
        }
        return .success(password)
    }
}

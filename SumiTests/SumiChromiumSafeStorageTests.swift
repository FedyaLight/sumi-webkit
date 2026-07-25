import CommonCrypto
import CryptoKit
import XCTest

@testable import Sumi

/// The keychain is never touched here: the key provider is injected, so these
/// tests exercise the crypto and the version handling rather than macOS.
final class SumiChromiumSafeStorageTests: XCTestCase {
    private static let password = "peanuts"
    private let host = "example.com"

    func testDecryptsV10Payload() throws {
        let decryptor = SumiChromiumSafeStorageDecryptor { _, _ in .success(Self.password) }
        let key = try key(from: decryptor)
        let blob = encrypt("session-token", key: key, version: "v10")

        XCTAssertEqual(try value(decryptor.decrypt(blob, key: key, host: host)), "session-token")
    }

    /// Chrome M124 and later prepend a SHA-256 of the cookie's host.
    func testStripsTheDomainHashChromeAddsSinceM124() throws {
        let decryptor = SumiChromiumSafeStorageDecryptor { _, _ in .success(Self.password) }
        let key = try key(from: decryptor)
        var plaintext = Data(SHA256.hash(data: Data(host.utf8)))
        plaintext.append(Data("session-token".utf8))
        let blob = encrypt(plaintext, key: key, version: "v10")

        XCTAssertEqual(try value(decryptor.decrypt(blob, key: key, host: host)), "session-token")
    }

    /// A value that merely happens to start with 32 bytes must not be truncated
    /// just because the domain-hash rule exists.
    func testLeavesAValueIntactWhenThePrefixIsNotTheDomainHash() throws {
        let decryptor = SumiChromiumSafeStorageDecryptor { _, _ in .success(Self.password) }
        let key = try key(from: decryptor)
        let long = String(repeating: "a", count: 48)
        let blob = encrypt(long, key: key, version: "v10")

        XCTAssertEqual(try value(decryptor.decrypt(blob, key: key, host: host)), long)
    }

    /// App-bound values belong to the browser that wrote them and must be
    /// reported as skipped, not silently mangled.
    func testReportsAppBoundEncryptionRatherThanGuessing() throws {
        let decryptor = SumiChromiumSafeStorageDecryptor { _, _ in .success(Self.password) }
        let key = try key(from: decryptor)
        var blob = Data("v20".utf8)
        blob.append(Data(repeating: 0xAB, count: 32))

        guard case let .failure(error) = decryptor.decrypt(blob, key: key, host: host) else {
            return XCTFail("expected app-bound encryption to be reported")
        }
        XCTAssertEqual(error, .appBoundEncryption)
    }

    func testTreatsAnUnprefixedValueAsPlaintext() throws {
        let decryptor = SumiChromiumSafeStorageDecryptor { _, _ in .success(Self.password) }
        let key = try key(from: decryptor)

        XCTAssertEqual(
            try value(decryptor.decrypt(Data("plain-value".utf8), key: key, host: host)),
            "plain-value"
        )
    }

    /// Refusing the keychain prompt is an ordinary outcome, not a crash.
    func testReportsAKeychainRefusalInsteadOfFailingHard() {
        let decryptor = SumiChromiumSafeStorageDecryptor { _, _ in
            .failure(.keychainUnavailable(errSecAuthFailed))
        }

        guard case let .failure(error) = decryptor.derivedKey(service: "Chrome Safe Storage", account: "Chrome") else {
            return XCTFail("expected a keychain failure")
        }
        XCTAssertEqual(error, .keychainUnavailable(errSecAuthFailed))
    }

    /// Chromium's parameters are fixed; a change here silently breaks every
    /// imported session, so they are pinned.
    func testDerivesTheKeyWithChromiumsFixedParameters() throws {
        let decryptor = SumiChromiumSafeStorageDecryptor { _, _ in .success(Self.password) }
        let derived = try key(from: decryptor)

        var expected = [UInt8](repeating: 0, count: 16)
        let salt = Array("saltysalt".utf8)
        _ = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            Self.password,
            Self.password.utf8.count,
            salt,
            salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
            1003,
            &expected,
            16
        )
        XCTAssertEqual(derived, expected)
    }

    // MARK: - Helpers

    private func key(from decryptor: SumiChromiumSafeStorageDecryptor) throws -> [UInt8] {
        switch decryptor.derivedKey(service: "Chrome Safe Storage", account: "Chrome") {
        case let .success(key): return key
        case let .failure(error): throw error
        }
    }

    private func value(_ result: Result<String, SumiChromiumSafeStorageDecryptor.DecryptionError>) throws -> String {
        switch result {
        case let .success(value): return value
        case let .failure(error): throw error
        }
    }

    private func encrypt(_ plaintext: String, key: [UInt8], version: String) -> Data {
        encrypt(Data(plaintext.utf8), key: key, version: version)
    }

    /// Mirrors Chromium's writer: AES-128-CBC, a sixteen-space IV, PKCS7 by hand.
    private func encrypt(_ plaintext: Data, key: [UInt8], version: String) -> Data {
        var padded = Array(plaintext)
        let pad = 16 - (padded.count % 16)
        padded.append(contentsOf: [UInt8](repeating: UInt8(pad), count: pad))

        var output = [UInt8](repeating: 0, count: padded.count + kCCBlockSizeAES128)
        var encryptedCount = 0
        _ = CCCrypt(
            CCOperation(kCCEncrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(0),
            key,
            16,
            [UInt8](repeating: 0x20, count: 16),
            padded,
            padded.count,
            &output,
            output.count,
            &encryptedCount
        )
        return Data(version.utf8) + Data(output.prefix(encryptedCount))
    }
}

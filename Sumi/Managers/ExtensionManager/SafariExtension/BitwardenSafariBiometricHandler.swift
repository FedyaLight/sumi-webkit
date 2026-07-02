//
//  BitwardenSafariBiometricHandler.swift
//  Sumi
//
//  Local biometric unlock for the Bitwarden Safari extension, matching
//  bitwarden/clients `SafariWebExtensionHandler`. In Safari these native
//  messages are served by the extension's own app-extension handler using the
//  local keychain and Touch ID — never by launching the desktop app. Sumi is
//  the WebKit host, so it reimplements the same local protocol.
//

import Foundation
import LocalAuthentication
import Security

/// Performs the Touch ID / biometric prompt for Bitwarden unlock commands.
@MainActor
protocol BitwardenBiometricAuthenticating: AnyObject {
    /// Whether biometric hardware is available (ignoring lockout).
    func isBiometricsAvailable() -> Bool

    /// `canEvaluatePolicy` succeeds or fails only due to biometry lockout —
    /// used by `unlockWithBiometricsForUser` before prompting.
    func canEvaluateIgnoringLockout() -> Bool

    /// Evaluates an access-control-gated biometric operation, returning whether
    /// the user authenticated successfully.
    func evaluate(
        reason: String,
        flags: SecAccessControlCreateFlags
    ) async -> Bool
}

/// Reads the Bitwarden browser biometric user key from the keychain.
@MainActor
protocol BitwardenBiometricKeychainReading: AnyObject {
    /// Returns the stored user key for `userId`, or `nil` when biometric unlock
    /// has not been provisioned. Mirrors the extension handler's lookup of
    /// service `Bitwarden_biometric`, account `{userId}_user_biometric`, then
    /// the legacy `key` account.
    func userKey(userId: String) -> String?
}

@MainActor
final class SystemBitwardenBiometricAuthenticator: BitwardenBiometricAuthenticating {
    func isBiometricsAvailable() -> Bool {
        var error: NSError?
        let context = LAContext()
        let canEvaluate = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
        if let error, error.code != LAError.biometryLockout.rawValue {
            return false
        }
        return canEvaluate || error?.code == LAError.biometryLockout.rawValue
    }

    func canEvaluateIgnoringLockout() -> Bool {
        var error: NSError?
        LAContext().canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
        if let error, error.code != LAError.biometryLockout.rawValue {
            return false
        }
        return true
    }

    func evaluate(
        reason: String,
        flags: SecAccessControlCreateFlags
    ) async -> Bool {
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            flags,
            nil
        ) else {
            return false
        }
        let context = LAContext()
        return await withCheckedContinuation { continuation in
            context.evaluateAccessControl(
                accessControl,
                operation: .useKeySign,
                localizedReason: reason
            ) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}

@MainActor
final class SystemBitwardenBiometricKeychain: BitwardenBiometricKeychainReading {
    func userKey(userId: String) -> String? {
        readKey(account: "\(userId)_user_biometric") ?? readKey(account: "key")
    }

    private func readKey(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: BitwardenSafariOneShotHandler.biometricKeychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        // The extension handler strips wrapping quotes before returning the key.
        return string.replacingOccurrences(of: "\"", with: "")
    }
}

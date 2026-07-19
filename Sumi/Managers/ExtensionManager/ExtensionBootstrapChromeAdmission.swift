import Foundation
import WebKit

enum ExtensionActivationCause: String, Codable, Hashable, Sendable {
    case installation
    case update
    case profileAttachment
    case userEnable
}

@MainActor
final class ExtensionGlobalInstallLedger {
    struct Claim: Equatable {
        let admitsBootstrapChrome: Bool
        let ownerProfileID: UUID
    }

    private struct Entry: Codable {
        let version: String
        let ownerProfileID: UUID
    }

    private static let storageKey =
        "\(SumiAppIdentity.bundleIdentifier).extensions.globalInstallLedger.v1"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func claim(
        identity: String,
        version: String,
        profileID: UUID,
        cause: ExtensionActivationCause = .installation
    ) -> Claim {
        var entries = readEntries()
        if let entry = entries[identity], entry.version == version {
            return Claim(
                admitsBootstrapChrome: false,
                ownerProfileID: entry.ownerProfileID
            )
        }

        let admitsBootstrapChrome = cause != .profileAttachment
        entries[identity] = Entry(
            version: version,
            ownerProfileID: profileID
        )
        writeEntries(entries)
        return Claim(
            admitsBootstrapChrome: admitsBootstrapChrome,
            ownerProfileID: profileID
        )
    }

    func remove(identity: String) {
        var entries = readEntries()
        entries.removeValue(forKey: identity)
        writeEntries(entries)
    }

    private func readEntries() -> [String: Entry] {
        guard let data = userDefaults.data(forKey: Self.storageKey) else { return [:] }
        do {
            return try JSONDecoder().decode([String: Entry].self, from: data)
        } catch {
            return [:]
        }
    }

    private func writeEntries(_ entries: [String: Entry]) {
        guard entries.isEmpty == false else {
            userDefaults.removeObject(forKey: Self.storageKey)
            return
        }
        do {
            let data = try JSONEncoder().encode(entries)
            userDefaults.set(data, forKey: Self.storageKey)
        } catch {
            return
        }
    }
}

@MainActor
final class ExtensionBootstrapChromeAdmission {
    struct Scope: Hashable {
        let cause: ExtensionActivationCause
        let admitsBootstrapChrome: Bool
        fileprivate let id: UUID
        fileprivate let extensionIdentity: String
        fileprivate let profileID: UUID
    }

    private let ledger: ExtensionGlobalInstallLedger
    private var activeScopes: [String: Scope] = [:]

    init(ledger: ExtensionGlobalInstallLedger = ExtensionGlobalInstallLedger()) {
        self.ledger = ledger
    }

    func begin(
        extensionIdentity: String,
        version: String,
        profileID: UUID,
        cause: ExtensionActivationCause
    ) -> Scope {
        let claim = ledger.claim(
            identity: extensionIdentity,
            version: version,
            profileID: profileID,
            cause: cause
        )
        let scope = Scope(
            cause: cause,
            admitsBootstrapChrome: claim.admitsBootstrapChrome,
            id: UUID(),
            extensionIdentity: extensionIdentity,
            profileID: profileID
        )
        activeScopes[key(extensionIdentity, profileID)] = scope
        return scope
    }

    func finish(_ scope: Scope) {
        let key = key(scope.extensionIdentity, scope.profileID)
        guard activeScopes[key] == scope else { return }
        activeScopes.removeValue(forKey: key)
    }

    func finishBootstrap(
        extensionIdentity: String,
        profileID: UUID
    ) {
        activeScopes.removeValue(forKey: key(extensionIdentity, profileID))
    }

    func admitsChrome(
        evidence: ExtensionControllerCallbackEvidence,
        hasUserGesture: Bool
    ) -> Bool {
        admitsChrome(
            extensionIdentity: evidence.extensionID,
            profileID: evidence.profileID,
            hasUserGesture: hasUserGesture
        )
    }

    func admitsChrome(
        extensionIdentity: String,
        profileID: UUID,
        hasUserGesture: Bool
    ) -> Bool {
        let scopeKey = key(extensionIdentity, profileID)
        guard let active = activeScopes[scopeKey] else {
            return true
        }
        if hasUserGesture {
            activeScopes.removeValue(forKey: scopeKey)
            return true
        }
        return active.admitsBootstrapChrome
    }

    func isActiveGlobalBootstrapOwner(
        evidence: ExtensionControllerCallbackEvidence
    ) -> Bool {
        activeScopes[key(evidence.extensionID, evidence.profileID)]?
            .admitsBootstrapChrome == true
    }

    func removeFromLedger(extensionIdentity: String) {
        activeScopes = activeScopes.filter { $0.value.extensionIdentity != extensionIdentity }
        ledger.remove(identity: extensionIdentity)
    }

    func retire(extensionIdentity: String, profileID: UUID) {
        activeScopes.removeValue(forKey: key(extensionIdentity, profileID))
    }

    private func key(_ extensionIdentity: String, _ profileID: UUID) -> String {
        extensionIdentity + ":" + profileID.uuidString
    }
}

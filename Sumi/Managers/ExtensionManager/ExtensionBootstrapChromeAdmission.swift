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

    private static let documentKey = "extensions.install-ledger"

    private let database: SumiDatabase?
    private var memoryEntries: [String: Entry] = [:]

    init(database: SumiDatabase? = nil) {
        self.database = database
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
        guard let database else { return memoryEntries }
        do {
            return try database.read {
                try $0.documents.value(
                    [String: Entry].self,
                    forKey: Self.documentKey
                ) ?? [:]
            }
        } catch {
            return [:]
        }
    }

    private func writeEntries(_ entries: [String: Entry]) {
        guard let database else {
            memoryEntries = entries
            return
        }
        do {
            try database.transaction {
                if entries.isEmpty {
                    try $0.documents.delete(key: Self.documentKey)
                } else {
                    try $0.documents.save(
                        entries,
                        forKey: Self.documentKey
                    )
                }
            }
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
        let enforcesBootstrapAdmission: Bool
        fileprivate let id: UUID
        fileprivate let extensionIdentity: String
        fileprivate let profileID: UUID
    }

    private let ledger: ExtensionGlobalInstallLedger
    private var activeScopes: [String: Scope] = [:]

    init(
        ledger: ExtensionGlobalInstallLedger = ExtensionGlobalInstallLedger()
    ) {
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
            // A profile attachment or a user enable can start ordinary
            // extension runtime work. WebKit does not label those callbacks
            // as onboarding, so suppressing them would also suppress normal
            // tabs.create/windows.create calls.
            enforcesBootstrapAdmission: cause == .installation
                || cause == .update,
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
        guard active.enforcesBootstrapAdmission else {
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

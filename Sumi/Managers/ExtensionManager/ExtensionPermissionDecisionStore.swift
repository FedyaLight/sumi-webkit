import Foundation
import OSLog
import WebKit

/// Owns persisted per-profile extension permission decisions: lookup with
/// expiry, persistence, replay onto loaded contexts, and prompt dedupe keys.
@available(macOS 15.5, *)
@MainActor
final class ExtensionPermissionDecisionStore {
    private static let log = Logger.sumi(category: "Extensions")
    private static let documentKey = "extensions.permission-decisions"

    private let database: SumiDatabase
    private let profileRuntime: ExtensionProfileRuntime

    init(
        database: SumiDatabase,
        profileRuntime: ExtensionProfileRuntime
    ) {
        self.database = database
        self.profileRuntime = profileRuntime
    }

    func storedExtensionPermissionDecision(
        extensionId: String,
        profileId: UUID,
        targetKind: ExtensionManager.ExtensionPermissionTargetKind,
        target: String
    ) -> ExtensionManager.ExtensionStoredPermissionDecision? {
        let key = extensionPermissionDecisionKey(
            extensionId: extensionId,
            profileId: profileId,
            targetKind: targetKind,
            target: target
        )
        var records = loadStoredExtensionPermissionDecisions()
        guard let record = records[key] else { return nil }
        if record.isExpired() {
            records.removeValue(forKey: key)
            saveStoredExtensionPermissionDecisions(records)
            return nil
        }
        return record
    }

    func persistExtensionPermissionDecision(
        extensionId: String,
        profileId: UUID,
        targetKind: ExtensionManager.ExtensionPermissionTargetKind,
        target: String,
        state: ExtensionManager.ExtensionStoredPermissionState,
        expiresAt: Date?
    ) {
        let key = extensionPermissionDecisionKey(
            extensionId: extensionId,
            profileId: profileId,
            targetKind: targetKind,
            target: target
        )
        var records = loadStoredExtensionPermissionDecisions()
        records[key] = ExtensionManager.ExtensionStoredPermissionDecision(
            profileId: profileId.uuidString.lowercased(),
            extensionId: extensionId,
            targetKind: targetKind,
            target: normalizedExtensionPermissionTarget(target, kind: targetKind),
            state: state,
            expiresAt: expiresAt,
            updatedAt: Date()
        )
        saveStoredExtensionPermissionDecisions(records)
    }

    @discardableResult
    func removeDecisions(for extensionId: String) -> Bool {
        let records = loadStoredExtensionPermissionDecisions()
        let retained = records.filter {
            $0.value.extensionId != extensionId
        }
        guard retained.count != records.count else { return true }
        return saveStoredExtensionPermissionDecisions(retained)
    }

    func applyStoredExtensionPermissionDecisions(
        to extensionContext: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID
    ) {
        var records = loadStoredExtensionPermissionDecisions()
        var didDropExpired = false
        let profileKey = profileId.uuidString.lowercased()

        for (key, record) in records {
            guard record.profileId == profileKey,
                  record.extensionId == extensionId
            else { continue }
            if record.isExpired() {
                records.removeValue(forKey: key)
                didDropExpired = true
                continue
            }
            guard record.targetKind != .matchPattern else {
                continue
            }
            applyStoredExtensionPermissionDecision(record, to: extensionContext)
        }

        if didDropExpired {
            saveStoredExtensionPermissionDecisions(records)
        }
    }

    func permissionPromptDedupeKey(
        extensionContext: WKWebExtensionContext,
        targets: [String]
    ) -> String? {
        guard let identity = profileRuntime.exactContextIdentity(
            for: extensionContext
        ) else {
            return nil
        }
        return permissionPromptDedupeKey(
            profileKey: identity.profileId.uuidString.lowercased(),
            extensionKey: identity.extensionId,
            targets: targets
        )
    }

    func permissionPromptDedupeKey(
        profileID: UUID,
        extensionID: String,
        targets: [String]
    ) -> String {
        permissionPromptDedupeKey(
            profileKey: profileID.uuidString.lowercased(),
            extensionKey: extensionID,
            targets: targets
        )
    }

    private func permissionPromptDedupeKey(
        profileKey: String,
        extensionKey: String,
        targets: [String]
    ) -> String {
        let targetKey = targets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.isEmpty == false }
            .sorted()
            .joined(separator: ",")
        return "\(profileKey)|\(extensionKey)|\(targetKey)"
    }

    private func applyStoredExtensionPermissionDecision(
        _ record: ExtensionManager.ExtensionStoredPermissionDecision,
        to extensionContext: WKWebExtensionContext
    ) {
        let status: WKWebExtensionContext.PermissionStatus =
            record.state == .allowed ? .grantedExplicitly : .deniedExplicitly

        switch record.targetKind {
        case .permission:
            let permission = WKWebExtension.Permission(rawValue: record.target)
            extensionContext.setPermissionStatus(
                status,
                for: permission,
                expirationDate: record.expiresAt
            )
        case .matchPattern:
            guard let matchPattern = SafariExtensionMatchPatternDiagnostics.make(
                record.target,
                purpose: "storedPermissionDecision.apply"
            ) else { return }
            extensionContext.setPermissionStatus(
                status,
                for: matchPattern,
                expirationDate: record.expiresAt
            )
        }
    }

    private func extensionPermissionDecisionKey(
        extensionId: String,
        profileId: UUID,
        targetKind: ExtensionManager.ExtensionPermissionTargetKind,
        target: String
    ) -> String {
        [
            profileId.uuidString.lowercased(),
            extensionId,
            targetKind.rawValue,
            normalizedExtensionPermissionTarget(target, kind: targetKind),
        ].joined(separator: "|")
    }

    private func normalizedExtensionPermissionTarget(
        _ target: String,
        kind: ExtensionManager.ExtensionPermissionTargetKind
    ) -> String {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .permission:
            return trimmed
        case .matchPattern:
            return SafariExtensionMatchPatternDiagnostics.normalizedStringOrOriginal(
                trimmed,
                purpose: "storedPermissionDecision.normalize"
            )
        }
    }

    private func loadStoredExtensionPermissionDecisions()
        -> [String: ExtensionManager.ExtensionStoredPermissionDecision] {
        do {
            return try database.read {
                try $0.documents.value(
                    [String: ExtensionManager.ExtensionStoredPermissionDecision]
                        .self,
                    forKey: Self.documentKey
                ) ?? [:]
            }
        } catch {
            Self.log.error("Failed to load persisted extension permission decisions: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    @discardableResult
    private func saveStoredExtensionPermissionDecisions(
        _ decisions: [String: ExtensionManager.ExtensionStoredPermissionDecision]
    ) -> Bool {
        do {
            try database.transaction {
                try $0.documents.save(
                    decisions,
                    forKey: Self.documentKey
                )
            }
        } catch {
            Self.log.error("Failed to persist extension permission decisions: \(error.localizedDescription, privacy: .public)")
            return false
        }
        return true
    }
}

import Foundation
import WebKit

/// Owns persisted per-profile extension permission decisions: lookup with
/// expiry, persistence, replay onto loaded contexts, and prompt dedupe keys.
@available(macOS 15.5, *)
@MainActor
final class ExtensionPermissionDecisionStoreOwner {
    struct Dependencies {
        let preferences: UserDefaults
        let extensionID: @MainActor (WKWebExtensionContext) -> String?
        let profileId: @MainActor (WKWebExtensionContext) -> UUID?
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
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
    ) -> String {
        let profileKey = dependencies.profileId(extensionContext)?.uuidString.lowercased()
            ?? "unknown-profile"
        let extensionKey = dependencies.extensionID(extensionContext)
            ?? extensionContext.uniqueIdentifier
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
            guard let matchPattern = try? WKWebExtension.MatchPattern(
                string: record.target
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
            guard let matchPattern = try? WKWebExtension.MatchPattern(string: trimmed) else {
                return trimmed
            }
            return matchPattern.string
        }
    }

    private func loadStoredExtensionPermissionDecisions()
        -> [String: ExtensionManager.ExtensionStoredPermissionDecision] {
        guard let data = dependencies.preferences.data(
            forKey: ExtensionManager.extensionPermissionDecisionsStorageKey
        ),
              let decoded = try? JSONDecoder().decode(
                  [String: ExtensionManager.ExtensionStoredPermissionDecision].self,
                  from: data
              )
        else {
            return [:]
        }
        return decoded
    }

    private func saveStoredExtensionPermissionDecisions(
        _ decisions: [String: ExtensionManager.ExtensionStoredPermissionDecision]
    ) {
        guard let data = try? JSONEncoder().encode(decisions) else { return }
        dependencies.preferences.set(
            data,
            forKey: ExtensionManager.extensionPermissionDecisionsStorageKey
        )
    }
}

@available(macOS 15.5, *)
extension ExtensionPermissionDecisionStoreOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            preferences: manager.extensionPreferences,
            extensionID: { [weak manager] extensionContext in
                manager?.extensionID(for: extensionContext)
            },
            profileId: { [weak manager] extensionContext in
                manager?.profileId(for: extensionContext)
            }
        )
    }
}

// MARK: - ExtensionManager facade

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func storedExtensionPermissionDecision(
        extensionId: String,
        profileId: UUID,
        targetKind: ExtensionPermissionTargetKind,
        target: String
    ) -> ExtensionStoredPermissionDecision? {
        permissionDecisionStoreOwner.storedExtensionPermissionDecision(
            extensionId: extensionId,
            profileId: profileId,
            targetKind: targetKind,
            target: target
        )
    }

    func persistExtensionPermissionDecision(
        extensionId: String,
        profileId: UUID,
        targetKind: ExtensionPermissionTargetKind,
        target: String,
        state: ExtensionStoredPermissionState,
        expiresAt: Date?
    ) {
        permissionDecisionStoreOwner.persistExtensionPermissionDecision(
            extensionId: extensionId,
            profileId: profileId,
            targetKind: targetKind,
            target: target,
            state: state,
            expiresAt: expiresAt
        )
    }

    func applyStoredExtensionPermissionDecisions(
        to extensionContext: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID
    ) {
        permissionDecisionStoreOwner.applyStoredExtensionPermissionDecisions(
            to: extensionContext,
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func permissionPromptDedupeKey(
        extensionContext: WKWebExtensionContext,
        targets: [String]
    ) -> String {
        permissionDecisionStoreOwner.permissionPromptDedupeKey(
            extensionContext: extensionContext,
            targets: targets
        )
    }
}

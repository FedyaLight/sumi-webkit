//
//  ExtensionManager+Store.swift
//  Sumi
//
//  Persistence and record-resolution helpers for Sumi's WebExtension runtime.
//

import Foundation
import SwiftData
import WebKit

@available(macOS 15.5, *)
enum PinnedToolbarSlot: Identifiable {
    case sumiScriptsManager
    case webExtension(InstalledExtension)

    var id: String {
        switch self {
        case .sumiScriptsManager:
            return SumiScriptsToolbarConstants.nativeToolbarItemID
        case .webExtension(let ext):
            return ext.id
        }
    }
}

@available(macOS 15.5, *)
extension ExtensionManager {
    fileprivate static let pinnedToolbarExtensionIDsStorageKey =
        "\(SumiAppIdentity.bundleIdentifier).extensions.toolbarPinnedIDsByProfile"
    fileprivate static let globalPinnedToolbarProfileKey = "__global__"

    func persist(record: InstalledExtension) throws {
        if let existing = try extensionEntity(for: record.id) {
            update(existing, from: record)
        } else {
            context.insert(ExtensionEntity(record: record))
        }
        try context.save()
    }

    func extensionEntity(for id: String) throws -> ExtensionEntity? {
        try context.fetch(FetchDescriptor<ExtensionEntity>()).first(where: { $0.id == id })
    }

    func sortInstalledExtensions() {
        installedExtensions.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func upsertInstalledExtension(_ record: InstalledExtension) {
        if let index = installedExtensions.firstIndex(where: { $0.id == record.id }) {
            installedExtensions[index] = record
        } else {
            installedExtensions.append(record)
        }
        sortInstalledExtensions()
        reconcilePinnedToolbarExtensions()
    }

    func isPinnedToToolbar(_ extensionId: String) -> Bool {
        pinnedToolbarExtensionIDs.contains(extensionId)
    }

    func pinToToolbar(_ extensionId: String) {
        updatePinnedToolbarExtensionIDs { ids in
            guard ids.contains(extensionId) == false else { return }
            ids.append(extensionId)
        }
    }

    func unpinFromToolbar(_ extensionId: String) {
        updatePinnedToolbarExtensionIDs { ids in
            ids.removeAll { $0 == extensionId }
        }
    }

    func reloadPinnedToolbarExtensionsForCurrentProfile() {
        let profileKey = Self.pinnedToolbarProfileKey(for: currentProfileId)
        pinnedToolbarExtensionIDs = Self.normalizedPinnedToolbarExtensionIDs(
            pinnedToolbarExtensionIDsByProfile[profileKey] ?? []
        )
    }

    func reconcilePinnedToolbarExtensions() {
        let installedIDs = Set(installedExtensions.map(\.id))
        let sumiSlot = SumiScriptsToolbarConstants.nativeToolbarItemID
        guard installedIDs.isEmpty == false else {
            updatePinnedToolbarExtensionIDs { ids in
                ids.removeAll { $0 != sumiSlot }
            }
            return
        }

        updatePinnedToolbarExtensionIDs { ids in
            ids.removeAll { id in
                if id == sumiSlot { return false }
                return installedIDs.contains(id) == false
            }
        }
    }

    /// Ordered toolbar buttons: built-in SumiScripts slot (when enabled) + pinned extensions.
    func orderedPinnedToolbarSlots(
        enabledExtensions: [InstalledExtension],
        sumiScriptsManagerEnabled: Bool
    ) -> [PinnedToolbarSlot] {
        let enabledByID = Dictionary(
            uniqueKeysWithValues: enabledExtensions
                .filter(\.isEnabled)
                .filter(\.hasAction)
                .map { ($0.id, $0) }
        )
        let normalizedPinnedIDs =
            Self.normalizedPinnedToolbarExtensionIDs(pinnedToolbarExtensionIDs)

        if normalizedPinnedIDs.isEmpty {
            var slots: [PinnedToolbarSlot] = []
            if sumiScriptsManagerEnabled {
                slots.append(.sumiScriptsManager)
            }
            slots.append(
                contentsOf: enabledExtensions
                    .filter(\.isEnabled)
                    .filter(\.hasAction)
                    .map { .webExtension($0) }
            )
            return slots
        }

        return normalizedPinnedIDs.compactMap { id -> PinnedToolbarSlot? in
            if id == SumiScriptsToolbarConstants.nativeToolbarItemID {
                return sumiScriptsManagerEnabled ? .sumiScriptsManager : nil
            }
            guard let ext = enabledByID[id] else { return nil }
            return .webExtension(ext)
        }
    }

    private func updatePinnedToolbarExtensionIDs(_ update: (inout [String]) -> Void) {
        let profileKey = Self.pinnedToolbarProfileKey(for: currentProfileId)
        var ids = pinnedToolbarExtensionIDsByProfile[profileKey] ?? []
        update(&ids)

        let normalized = Self.normalizedPinnedToolbarExtensionIDs(ids)
        pinnedToolbarExtensionIDsByProfile[profileKey] = normalized
        pinnedToolbarExtensionIDs = normalized
        persistPinnedToolbarExtensionIDsByProfile()
    }

    private func persistPinnedToolbarExtensionIDsByProfile() {
        guard
            let data = try? JSONEncoder().encode(pinnedToolbarExtensionIDsByProfile)
        else {
            return
        }

        UserDefaults.standard.set(
            data,
            forKey: Self.pinnedToolbarExtensionIDsStorageKey
        )
    }

    static func loadPinnedToolbarExtensionIDsByProfile() -> [String: [String]] {
        guard
            let data = UserDefaults.standard.data(
                forKey: pinnedToolbarExtensionIDsStorageKey
            ),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else {
            return [:]
        }

        return decoded.mapValues(Self.normalizedPinnedToolbarExtensionIDs)
    }

    static func pinnedToolbarProfileKey(for profileId: UUID?) -> String {
        profileId?.uuidString.lowercased() ?? globalPinnedToolbarProfileKey
    }

    static func normalizedPinnedToolbarExtensionIDs(
        _ ids: [String]
    ) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for id in ids {
            let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.isEmpty == false, seen.insert(normalized).inserted else {
                continue
            }
            result.append(normalized)
        }

        return result
    }

    func update(
        _ entity: ExtensionEntity,
        from record: InstalledExtension
    ) {
        entity.name = record.name
        entity.version = record.version
        entity.manifestVersion = record.manifestVersion
        entity.extensionDescription = record.description
        entity.isEnabled = record.isEnabled
        entity.installDate = record.installDate
        entity.lastUpdateDate = record.lastUpdateDate
        entity.packagePath = record.packagePath
        entity.iconPath = record.iconPath
        entity.sourceKindRawValue = record.sourceKind.rawValue
        entity.backgroundModelRawValue = record.backgroundModel.rawValue
        entity.incognitoModeRawValue = record.incognitoMode.rawValue
        entity.sourcePathFingerprint = record.sourcePathFingerprint
        entity.manifestRootFingerprint = record.manifestRootFingerprint
        entity.sourceBundlePath = record.sourceBundlePath
        entity.optionsPagePath = record.optionsPagePath
        entity.defaultPopupPath = record.defaultPopupPath
        entity.hasBackground = record.hasBackground
        entity.hasAction = record.hasAction
        entity.hasOptionsPage = record.hasOptionsPage
        entity.hasContentScripts = record.hasContentScripts
        entity.hasExtensionPages = record.hasExtensionPages
        entity.broadScope = record.activationSummary.broadScope
        entity.activationSummaryJSON = record.encodedActivationSummary
        entity.manifestSnapshotJSON = record.encodedManifestSnapshot
    }

    func refreshedRecord(
        for entity: ExtensionEntity,
        manifest: [String: Any]
    ) throws -> InstalledExtension {
        let sourceKind = WebExtensionSourceKind(rawValue: entity.sourceKindRawValue) ?? .directory
        return try makeInstalledRecord(
            extensionId: entity.id,
            manifest: manifest,
            extensionRoot: URL(fileURLWithPath: entity.packagePath),
            isEnabled: entity.isEnabled,
            sourceKind: sourceKind,
            sourceBundlePath: entity.sourceBundlePath,
            sourceFingerprintURL: URL(fileURLWithPath: entity.sourceBundlePath),
            existingEntity: entity
        )
    }

    func makeInstalledRecord(
        extensionId: String,
        manifest: [String: Any],
        extensionRoot: URL,
        isEnabled: Bool,
        sourceKind: WebExtensionSourceKind,
        sourceBundlePath: String,
        sourceFingerprintURL: URL,
        existingEntity: ExtensionEntity?
    ) throws -> InstalledExtension {
        let installDate = existingEntity?.installDate ?? Date()
        let lastUpdateDate = Date()
        let backgroundModel = ExtensionUtils.backgroundModel(from: manifest)
        let optionsPagePath = ExtensionUtils.storedOptionsPagePath(
            from: manifest,
            in: extensionRoot
        )
        let defaultPopupPath = ExtensionUtils.defaultPopupPath(from: manifest)
        let manifestActivationSummary = ExtensionUtils.activationSummary(from: manifest)
        let activationSummary = ExtensionActivationSummary(
            matchPatternStrings: manifestActivationSummary.matchPatternStrings,
            broadScope: manifestActivationSummary.broadScope,
            hasContentScripts: manifestActivationSummary.hasContentScripts,
            hasAction: manifestActivationSummary.hasAction,
            hasOptionsPage: optionsPagePath != nil,
            hasExtensionPages: optionsPagePath != nil || defaultPopupPath != nil
        )
        let incognitoMode = try IncognitoExtensionMode.fromManifest(manifest)

        let localizedName = ExtensionUtils.localizedString(
            manifest["name"] as? String,
            in: extensionRoot
        ) ?? (manifest["name"] as? String) ?? "Unknown Extension"
        let localizedDescription = ExtensionUtils.localizedString(
            manifest["description"] as? String,
            in: extensionRoot
        ) ?? (manifest["description"] as? String)

        return InstalledExtensionRecord(
            id: extensionId,
            name: localizedName,
            version: manifest["version"] as? String ?? "1.0",
            manifestVersion: manifest["manifest_version"] as? Int ?? 3,
            description: localizedDescription,
            isEnabled: isEnabled,
            installDate: installDate,
            lastUpdateDate: lastUpdateDate,
            packagePath: extensionRoot.path,
            iconPath: ExtensionUtils.iconPath(in: extensionRoot, manifest: manifest),
            sourceKind: sourceKind,
            backgroundModel: backgroundModel,
            incognitoMode: incognitoMode,
            sourcePathFingerprint: ExtensionUtils.normalizePathFingerprint(sourceFingerprintURL),
            manifestRootFingerprint: ExtensionUtils.fingerprint(
                fileAt: extensionRoot.appendingPathComponent("manifest.json")
            ),
            sourceBundlePath: sourceBundlePath,
            optionsPagePath: optionsPagePath,
            defaultPopupPath: defaultPopupPath,
            hasBackground: backgroundModel != .none,
            hasAction: activationSummary.hasAction,
            hasOptionsPage: activationSummary.hasOptionsPage,
            hasContentScripts: activationSummary.hasContentScripts,
            hasExtensionPages: activationSummary.hasExtensionPages,
            activationSummary: activationSummary,
            manifest: manifest
        )
    }

    func extensionID(
        for extensionContext: WKWebExtensionContext
    ) -> String? {
        for contexts in extensionContextsByProfile.values {
            if let match = contexts.first(where: { $0.value === extensionContext })?.key {
                return match
            }
        }
        return nil
    }

    func storedExtensionPermissionDecision(
        extensionId: String,
        profileId: UUID,
        targetKind: ExtensionPermissionTargetKind,
        target: String
    ) -> ExtensionStoredPermissionDecision? {
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
        targetKind: ExtensionPermissionTargetKind,
        target: String,
        state: ExtensionStoredPermissionState,
        expiresAt: Date?
    ) {
        let key = extensionPermissionDecisionKey(
            extensionId: extensionId,
            profileId: profileId,
            targetKind: targetKind,
            target: target
        )
        var records = loadStoredExtensionPermissionDecisions()
        records[key] = ExtensionStoredPermissionDecision(
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
        let profileKey = profileId(for: extensionContext)?.uuidString.lowercased()
            ?? "unknown-profile"
        let extensionKey = extensionID(for: extensionContext)
            ?? extensionContext.uniqueIdentifier
        let targetKey = targets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.isEmpty == false }
            .sorted()
            .joined(separator: ",")
        return "\(profileKey)|\(extensionKey)|\(targetKey)"
    }

    func hostMatchPatternString(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(),
              host.isEmpty == false
        else {
            return nil
        }
        return "\(scheme)://\(host)/*"
    }

    private func applyStoredExtensionPermissionDecision(
        _ record: ExtensionStoredPermissionDecision,
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
        targetKind: ExtensionPermissionTargetKind,
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
        kind: ExtensionPermissionTargetKind
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
        -> [String: ExtensionStoredPermissionDecision]
    {
        guard let data = UserDefaults.standard.data(
            forKey: Self.extensionPermissionDecisionsStorageKey
        ),
              let decoded = try? JSONDecoder().decode(
                  [String: ExtensionStoredPermissionDecision].self,
                  from: data
              )
        else {
            return [:]
        }
        return decoded
    }

    private func saveStoredExtensionPermissionDecisions(
        _ decisions: [String: ExtensionStoredPermissionDecision]
    ) {
        guard let data = try? JSONEncoder().encode(decisions) else { return }
        UserDefaults.standard.set(
            data,
            forKey: Self.extensionPermissionDecisionsStorageKey
        )
    }

    func computeOptionsPageURL(
        for extensionContext: WKWebExtensionContext
    ) -> URL? {
        guard let extensionId = extensionID(for: extensionContext),
              let installedExtension = installedExtensions.first(where: { $0.id == extensionId })
        else {
            return nil
        }

        let extensionRoot = URL(
            fileURLWithPath: installedExtension.packagePath,
            isDirectory: true
        ).resolvingSymlinksInPath().standardizedFileURL
        let manifest = loadedExtensionManifests[extensionId] ?? installedExtension.manifest

        let pagePath: String?
        if let persistedPath = installedExtension.optionsPagePath,
           let normalizedPath = ExtensionUtils.existingValidatedOptionsPagePath(
               persistedPath,
               in: extensionRoot
           )
        {
            pagePath = normalizedPath
        } else if let declaredPath = ExtensionUtils.optionsPagePath(from: manifest),
                  let normalizedPath = ExtensionUtils.existingValidatedOptionsPagePath(
                      declaredPath,
                      in: extensionRoot
                  )
        {
            pagePath = normalizedPath
        } else {
            pagePath = ExtensionUtils.storedOptionsPagePath(
                from: manifest,
                in: extensionRoot
            )
        }

        guard let pagePath else { return nil }
        return ExtensionUtils.url(
            extensionContext.baseURL,
            appendingManifestRelativePath: pagePath
        )
    }
}

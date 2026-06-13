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

    func extensionResourcesRoot(
        sourceKind: WebExtensionSourceKind,
        packagePath: String,
        sourceBundlePath: String
    ) throws -> URL {
        if sourceKind == .safariAppExtension {
            guard let appexURL = SafariAppExtensionResources.installedAppexBundleURL(
                sourceKind: sourceKind,
                sourceBundlePath: sourceBundlePath
            ) else {
                throw ExtensionError.installationFailed(
                    "Installed Safari app extension bundle is unavailable"
                )
            }
            return try SafariAppExtensionResources.resourcesRoot(in: appexURL)
        }

        return URL(fileURLWithPath: packagePath, isDirectory: true)
    }

    func extensionResourcesRoot(for entity: ExtensionEntity) throws -> URL {
        let sourceKind = WebExtensionSourceKind(rawValue: entity.sourceKindRawValue) ?? .directory
        return try extensionResourcesRoot(
            sourceKind: sourceKind,
            packagePath: entity.packagePath,
            sourceBundlePath: entity.sourceBundlePath
        )
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
        let extensionRoot = try extensionResourcesRoot(
            sourceKind: sourceKind,
            packagePath: entity.packagePath,
            sourceBundlePath: entity.sourceBundlePath
        )
        return try makeInstalledRecord(
            extensionId: entity.id,
            manifest: manifest,
            extensionRoot: extensionRoot,
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

    func ownerExtensionID(
        extensionContext: WKWebExtensionContext? = nil,
        openerTab: Tab? = nil,
        extensionOwnedSourceURL: URL? = nil
    ) -> String? {
        if let extensionContext,
           let extensionId = extensionID(for: extensionContext)
        {
            return extensionId
        }

        if let override = openerTab?.webExtensionContextOverride,
           let extensionId = extensionID(for: override)
        {
            return extensionId
        }

        for candidate in [extensionOwnedSourceURL, openerTab?.url] {
            guard let url = candidate,
                  ExtensionUtils.isExtensionOwnedURL(url),
                  let host = url.host,
                  host.isEmpty == false
            else {
                continue
            }
            return host
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

    func siteAccessPolicy(
        extensionId: String,
        profileId: UUID
    ) -> SafariExtensionSiteAccessPolicy {
        let key = extensionSiteAccessPolicyKey(
            extensionId: extensionId,
            profileId: profileId
        )
        var policies = loadStoredExtensionSiteAccessPolicies()
        if let stored = policies[key] {
            let normalized = stored.normalized()
            if normalized != stored {
                policies[key] = normalized
                saveStoredExtensionSiteAccessPolicies(policies)
            }
            return normalized
        }

        let policy = SafariExtensionSiteAccessPolicy.defaultPolicy(
            extensionId: extensionId,
            profileId: profileId,
            seededRules: migratedSiteAccessRules(
                extensionId: extensionId,
                profileId: profileId
            )
        )
        policies[key] = policy
        saveStoredExtensionSiteAccessPolicies(policies)
        return policy
    }

    func setDefaultSiteAccess(
        _ access: SafariExtensionSiteAccessLevel,
        extensionId: String,
        profileId: UUID
    ) {
        updateSiteAccessPolicy(
            extensionId: extensionId,
            profileId: profileId
        ) { policy in
            policy.defaultAccess = access
            policy.updatedAt = Date()
        }
        applySiteAccessPolicyToLoadedContext(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func setPrivateBrowsingAccess(
        _ isAllowed: Bool,
        extensionId: String,
        profileId: UUID
    ) {
        updateSiteAccessPolicy(
            extensionId: extensionId,
            profileId: profileId
        ) { policy in
            policy.privateAccessAllowed = isAllowed
            policy.updatedAt = Date()
        }
        applySiteAccessPolicyToLoadedContext(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func setConfiguredSiteAccess(
        _ access: SafariExtensionSiteAccessLevel,
        extensionId: String,
        profileId: UUID,
        matchPatternString: String,
        expiresAt: Date? = nil
    ) {
        let normalizedPattern =
            SafariExtensionSiteAccessPolicy.normalizedMatchPatternString(
                matchPatternString
            )
        guard normalizedPattern.isEmpty == false else { return }

        updateSiteAccessPolicy(
            extensionId: extensionId,
            profileId: profileId
        ) { policy in
            policy.siteRules.removeAll { $0.matchPattern == normalizedPattern }
            policy.siteRules.append(
                SafariExtensionSiteAccessRule(
                    matchPattern: normalizedPattern,
                    access: access,
                    expiresAt: expiresAt,
                    updatedAt: Date()
                )
            )
            policy.siteRules = SafariExtensionSiteAccessPolicy
                .normalizedRules(policy.siteRules)
            policy.updatedAt = Date()
        }
        applySiteAccessPolicyToLoadedContext(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func setCurrentSiteAccess(
        _ access: SafariExtensionSiteAccessLevel,
        extensionId: String,
        profileId: UUID,
        url: URL
    ) {
        guard let patternString = hostMatchPatternString(for: url) else { return }
        setConfiguredSiteAccess(
            access,
            extensionId: extensionId,
            profileId: profileId,
            matchPatternString: patternString
        )
    }

    func configuredSiteAccessLevel(
        for url: URL,
        extensionId: String,
        profileId: UUID
    ) -> SafariExtensionSiteAccessLevel {
        siteAccessPolicy(
            extensionId: extensionId,
            profileId: profileId
        ).accessLevel(for: url)
    }

    func configuredSiteAccessLevel(
        for matchPattern: WKWebExtension.MatchPattern,
        extensionId: String,
        profileId: UUID
    ) -> SafariExtensionSiteAccessLevel {
        siteAccessPolicy(
            extensionId: extensionId,
            profileId: profileId
        ).accessLevel(for: matchPattern)
    }

    func applyConfiguredSiteAccessPolicy(
        to extensionContext: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID,
        webExtension: WKWebExtension,
        manifest: [String: Any]? = nil
    ) {
        let policy = siteAccessPolicy(
            extensionId: extensionId,
            profileId: profileId
        )
        SafariExtensionPermissionLifecycleDiagnostics.logContextApplication(
            SafariExtensionContextApplicationSnapshot(
                contextLoaded: extensionContext.isLoaded,
                extensionBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(extensionId),
                profileBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(profileId),
                controllerBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                    extensionContext.webExtensionController.map { String(describing: ObjectIdentifier($0)) }
                ),
                appliedBeforeNavigation: nil,
                permissionAPIPath: .global,
                persistedPolicyDivergenceObserved: nil
            )
        )
        let installedExtension = installedExtensions.first { $0.id == extensionId }
        extensionContext.hasAccessToPrivateData =
            policy.privateAccessAllowed
            && (installedExtension?.incognitoMode.allowsPrivateAccess ?? true)
        extensionContext.hasRequestedOptionalAccessToAllHosts =
            policy.hasRequestedOptionalAccessToAllHosts

        let declaredPatterns = declaredSiteAccessMatchPatterns(
            for: webExtension,
            manifest: manifest
        )
        if let manifest {
            let surfaces = SafariExtensionManifestAccessSurfaces.from(manifest: manifest)
            SafariExtensionPermissionLifecycleDiagnostics.logPolicySnapshot(
                SafariExtensionPolicySnapshot(
                    extensionEnabled: installedExtension?.isEnabled ?? true,
                    extensionBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(extensionId),
                    profileBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(profileId),
                    tabBucket: nil,
                    isPrivate: extensionContext.hasAccessToPrivateData,
                    originHost: nil,
                    decisionSource: policy.defaultAccess.diagnosticDecisionSource,
                    declaredSurfaces: [
                        surfaces.contentScriptHosts.isEmpty ? nil : .contentScripts,
                        surfaces.hostPermissionHosts.isEmpty ? nil : .hostPermissions,
                        surfaces.optionalPermissionHosts.isEmpty ? nil : .optionalPermissions,
                        surfaces.externallyConnectableHosts.isEmpty ? nil : .externallyConnectable,
                    ].compactMap { $0 },
                    externallyConnectableReportedSeparately: true
                )
            )
        }
        let declaresAllHosts = declaredPatterns.contains {
            $0 == WKWebExtension.MatchPattern.allHostsAndSchemes()
                || $0 == WKWebExtension.MatchPattern.allURLs()
        }
        let policyAllowsAllHosts =
            (policy.defaultAccess == .allow && declaresAllHosts)
            || policy.siteRules.contains {
                $0.access == .allow && Self.isAllHostsMatchPatternString($0.matchPattern)
            }
        if policyAllowsAllHosts {
            extensionContext.hasRequestedOptionalAccessToAllHosts = true
        }
        for matchPattern in declaredPatterns {
            extensionContext.setPermissionStatus(.unknown, for: matchPattern)
        }

        switch policy.defaultAccess {
        case .allow:
            for matchPattern in declaredPatterns {
                extensionContext.setPermissionStatus(
                    .grantedExplicitly,
                    for: matchPattern
                )
            }
        case .deny:
            for matchPattern in declaredPatterns {
                extensionContext.setPermissionStatus(
                    .deniedExplicitly,
                    for: matchPattern
                )
            }
        case .ask:
            break
        }

        for rule in policy.rulesByIncreasingSpecificity {
            guard let matchPattern = try? WKWebExtension.MatchPattern(
                string: rule.matchPattern
            )
            else {
                continue
            }
            extensionContext.setPermissionStatus(
                rule.access.status,
                for: matchPattern,
                expirationDate: rule.expiresAt
            )
        }
    }

    func declaredSiteAccessMatchPatterns(
        for webExtension: WKWebExtension,
        manifest: [String: Any]? = nil
    ) -> Set<WKWebExtension.MatchPattern> {
        var matchPatterns = webExtension.requestedPermissionMatchPatterns
            .union(webExtension.allRequestedMatchPatterns)
            .union(webExtension.optionalPermissionMatchPatterns)
        if let manifest {
            let rawSiteAccessPatterns = rawManifestSiteAccessMatchPatterns(
                from: manifest
            )
            let externalMessagingOnlyPatterns = rawManifestExternalMessagingMatchPatterns(
                from: manifest
            ).subtracting(rawSiteAccessPatterns)
            matchPatterns.formUnion(rawSiteAccessPatterns)
            matchPatterns.subtract(externalMessagingOnlyPatterns)
        }
        return matchPatterns
    }

    private func rawManifestSiteAccessMatchPatterns(
        from manifest: [String: Any]
    ) -> Set<WKWebExtension.MatchPattern> {
        let permissions = manifestStringArray(from: manifest["permissions"])
        let optionalPermissions = manifestStringArray(from: manifest["optional_permissions"])
        let contentScriptMatches =
            (manifest["content_scripts"] as? [[String: Any]] ?? [])
                .flatMap { manifestStringArray(from: $0["matches"]) }

        let patternStrings =
            manifestStringArray(from: manifest["host_permissions"])
            + manifestStringArray(from: manifest["optional_host_permissions"])
            + permissions.filter(Self.isManifestHostPermissionPattern)
            + optionalPermissions.filter(Self.isManifestHostPermissionPattern)
            + contentScriptMatches

        return Set(
            patternStrings.compactMap {
                try? WKWebExtension.MatchPattern(string: $0)
            }
        )
    }

    private func rawManifestExternalMessagingMatchPatterns(
        from manifest: [String: Any]
    ) -> Set<WKWebExtension.MatchPattern> {
        let patternStrings =
            (manifest["externally_connectable"] as? [String: Any])
                .map { manifestStringArray(from: $0["matches"]) } ?? []

        return Set(
            patternStrings.compactMap {
                try? WKWebExtension.MatchPattern(string: $0)
            }
        )
    }

    private static func isManifestHostPermissionPattern(_ value: String) -> Bool {
        value == "<all_urls>"
            || value.hasPrefix("http://")
            || value.hasPrefix("https://")
            || value.hasPrefix("*://")
    }

    private static func isAllHostsMatchPatternString(_ value: String) -> Bool {
        guard let matchPattern = try? WKWebExtension.MatchPattern(string: value) else {
            return false
        }
        return matchPattern == WKWebExtension.MatchPattern.allHostsAndSchemes()
            || matchPattern == WKWebExtension.MatchPattern.allURLs()
    }

    private func manifestStringArray(from value: Any?) -> [String] {
        value as? [String] ?? []
    }

    func grantSiteAccess(
        to url: URL,
        in extensionContext: WKWebExtensionContext,
        extensionId: String?,
        profileId: UUID?,
        expirationDate: Date? = nil,
        persistPolicy: Bool = true
    ) {
        if let patternString = hostMatchPatternString(for: url),
           let matchPattern = try? WKWebExtension.MatchPattern(
               string: patternString
           )
        {
            extensionContext.setPermissionStatus(
                .grantedExplicitly,
                for: matchPattern,
                expirationDate: expirationDate
            )
            if persistPolicy, let extensionId, let profileId {
                setConfiguredSiteAccess(
                    .allow,
                    extensionId: extensionId,
                    profileId: profileId,
                    matchPatternString: patternString,
                    expiresAt: expirationDate
                )
            }
        }
        extensionContext.setPermissionStatus(
            .grantedExplicitly,
            for: url,
            expirationDate: expirationDate
        )
    }

    func denySiteAccess(
        to url: URL,
        in extensionContext: WKWebExtensionContext,
        extensionId: String?,
        profileId: UUID?,
        persistPolicy: Bool = true
    ) {
        if let patternString = hostMatchPatternString(for: url),
           let matchPattern = try? WKWebExtension.MatchPattern(
               string: patternString
           )
        {
            extensionContext.setPermissionStatus(
                .deniedExplicitly,
                for: matchPattern,
                expirationDate: nil
            )
            if persistPolicy, let extensionId, let profileId {
                setConfiguredSiteAccess(
                    .deny,
                    extensionId: extensionId,
                    profileId: profileId,
                    matchPatternString: patternString,
                    expiresAt: nil
                )
            }
        }
        extensionContext.setPermissionStatus(
            .deniedExplicitly,
            for: url,
            expirationDate: nil
        )
    }

    private func updateSiteAccessPolicy(
        extensionId: String,
        profileId: UUID,
        update: (inout SafariExtensionSiteAccessPolicy) -> Void
    ) {
        let key = extensionSiteAccessPolicyKey(
            extensionId: extensionId,
            profileId: profileId
        )
        var policies = loadStoredExtensionSiteAccessPolicies()
        var policy = policies[key] ?? SafariExtensionSiteAccessPolicy.defaultPolicy(
            extensionId: extensionId,
            profileId: profileId,
            seededRules: migratedSiteAccessRules(
                extensionId: extensionId,
                profileId: profileId
            )
        )
        update(&policy)
        policies[key] = policy.normalized()
        saveStoredExtensionSiteAccessPolicies(policies)
    }

    private func applySiteAccessPolicyToLoadedContext(
        extensionId: String,
        profileId: UUID
    ) {
        guard let extensionContext = getExtensionContext(
            for: extensionId,
            profileId: profileId
        ) else {
            return
        }
        applyConfiguredSiteAccessPolicy(
            to: extensionContext,
            extensionId: extensionId,
            profileId: profileId,
            webExtension: extensionContext.webExtension,
            manifest: loadedExtensionManifests[extensionId]
                ?? installedExtensions.first { $0.id == extensionId }?.manifest
        )
        SafariExtensionPermissionLifecycleDiagnostics.logReloadRebuild(
            SafariExtensionReloadRebuildSnapshot(
                triggerReason: "ExtensionManager.siteAccessPolicyChanged",
                profileBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(profileId),
                tabBucket: nil,
                host: nil,
                userActionCaused: false,
                action: .rebindOnly
            )
        )
        reconcileOpenTabsAfterExtensionContextLoad(
            reason: "ExtensionManager.siteAccessPolicyChanged",
            profileId: profileId
        )
    }

    private func migratedSiteAccessRules(
        extensionId: String,
        profileId: UUID
    ) -> [SafariExtensionSiteAccessRule] {
        let profileKey = profileId.uuidString.lowercased()
        return loadStoredExtensionPermissionDecisions().values.compactMap { record in
            guard record.profileId == profileKey,
                  record.extensionId == extensionId,
                  record.targetKind == .matchPattern,
                  record.isExpired() == false
            else {
                return nil
            }
            return SafariExtensionSiteAccessRule(
                matchPattern: record.target,
                access: record.state == .allowed ? .allow : .deny,
                expiresAt: record.expiresAt,
                updatedAt: record.updatedAt
            )
        }
    }

    private func extensionSiteAccessPolicyKey(
        extensionId: String,
        profileId: UUID
    ) -> String {
        "\(profileId.uuidString.lowercased())|\(extensionId)"
    }

    private func loadStoredExtensionSiteAccessPolicies()
        -> [String: SafariExtensionSiteAccessPolicy]
    {
        guard let data = UserDefaults.standard.data(
            forKey: Self.extensionSiteAccessStorageKey
        ),
              let decoded = try? JSONDecoder().decode(
                  [String: SafariExtensionSiteAccessPolicy].self,
                  from: data
              )
        else {
            return [:]
        }
        return decoded
    }

    private func saveStoredExtensionSiteAccessPolicies(
        _ policies: [String: SafariExtensionSiteAccessPolicy]
    ) {
        guard let data = try? JSONEncoder().encode(policies) else { return }
        UserDefaults.standard.set(
            data,
            forKey: Self.extensionSiteAccessStorageKey
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

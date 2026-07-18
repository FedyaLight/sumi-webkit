import Foundation
import SumiDomain

struct SumiImportPlanBuilder {
    static let maxEssentialsPerProfile = 12

    private let isProfileIdentityAllowed: (UUID) -> Bool

    init(isProfileIdentityAllowed: @escaping (UUID) -> Bool = { _ in true }) {
        self.isProfileIdentityAllowed = isProfileIdentityAllowed
    }

    func makePlan(request: SumiImportRequest, baseline: SumiPortableData) -> SumiImportPlan {
        var warnings: [String] = []
        let runtimeCategories = request.categories.subtracting([.bookmarks])
        guard !runtimeCategories.isEmpty else {
            return SumiImportPlan(
                baseline: baseline,
                targetRuntimeData: baseline,
                bookmarkMutation: bookmarkMutation(for: request, baseline: baseline),
                categories: request.categories,
                mode: request.mode,
                warnings: []
            )
        }
        var output = baseline
        clearReplacedCategories(request.categories, in: &output, mode: request.mode)

        let profileIDsBySource = makeProfileIdentityMapping(
            request: request,
            baseline: baseline
        )
        let identity = SumiImportIdentityResolver(
            sourceKind: request.sourceKind,
            mode: request.mode,
            importsProfiles: request.categories.contains(.profiles),
            importsSpaces: request.categories.contains(.spaces),
            importsFolders: request.categories.contains(.folders),
            profileIDsBySource: profileIDsBySource,
            fallbackProfileId: output.profiles.first?.id,
            fallbackSpaceId: output.spaces.first?.id
        )

        mergeProfiles(request, identity: identity, into: &output)
        ensureProfile(in: &output, identity: identity)
        mergeSpaces(request, identity: identity, into: &output)
        ensureSpace(in: &output, identity: identity)
        mergeFolders(request, identity: identity, into: &output)
        mergeEssentials(request, identity: identity, into: &output, warnings: &warnings)
        mergePinnedLaunchers(request, identity: identity, into: &output, warnings: &warnings)
        mergeRegularTabs(request, identity: identity, into: &output, warnings: &warnings)

        output.bookmarks = baseline.bookmarks
        output = SumiImportDataNormalizer.normalize(output)

        let baselineProfileIDs = Set(baseline.profiles.compactMap { UUID(uuidString: $0.id) })
        let targetProfileIDs = Set(output.profiles.compactMap { UUID(uuidString: $0.id) })
        let replacesProfiles = request.mode == .replace
            && request.categories.contains(.profiles)
        let transition = SumiImportProfileTransition(
            sourceToTargetProfileID: profileIDsBySource,
            createdProfileIDs: targetProfileIDs.subtracting(baselineProfileIDs),
            retiringProfileIDs: replacesProfiles
                ? baselineProfileIDs.subtracting(targetProfileIDs)
                : [],
            fallbackProfileID: output.profiles.first.flatMap { UUID(uuidString: $0.id) }
        )

        return SumiImportPlan(
            baseline: baseline,
            targetRuntimeData: output,
            bookmarkMutation: bookmarkMutation(for: request, baseline: baseline),
            categories: request.categories,
            mode: request.mode,
            warnings: warnings,
            profileTransition: transition
        )
    }

    private func makeProfileIdentityMapping(
        request: SumiImportRequest,
        baseline: SumiPortableData
    ) -> [String: String] {
        guard request.categories.contains(.profiles) else { return [:] }
        let incoming = request.data.profiles.sorted(by: stableIndexOrder)
        let existing = baseline.profiles.sorted(by: stableIndexOrder)
        var mapping: [String: String] = [:]
        var usedTargetIDs: Set<String> = []

        if request.mode == .replace {
            let existingIDs = Set(existing.map(\.id))
            for profile in incoming where existingIDs.contains(profile.id) {
                mapping[profile.id] = profile.id
                usedTargetIDs.insert(profile.id)
            }

            var reusableIDs = existing.map(\.id).filter { !usedTargetIDs.contains($0) }
            for profile in incoming where mapping[profile.id] == nil {
                if !reusableIDs.isEmpty {
                    let reused = reusableIDs.removeFirst()
                    mapping[profile.id] = reused
                    usedTargetIDs.insert(reused)
                } else {
                    let created = availableImportedProfileID(
                        source: profile.id,
                        sourceKind: request.sourceKind,
                        mode: request.mode,
                        excluding: usedTargetIDs
                    )
                    mapping[profile.id] = created
                    usedTargetIDs.insert(created)
                }
            }
            return mapping
        }

        for profile in incoming {
            let created = availableImportedProfileID(
                source: profile.id,
                sourceKind: request.sourceKind,
                mode: request.mode,
                excluding: usedTargetIDs
            )
            mapping[profile.id] = created
            usedTargetIDs.insert(created)
        }
        return mapping
    }

    private func availableImportedProfileID(
        source: String,
        sourceKind: SumiImportSourceKind,
        mode: SumiImportApplyMode,
        excluding: Set<String>
    ) -> String {
        let resolver = SumiImportIdentityResolver(
            sourceKind: sourceKind,
            mode: mode,
            importsProfiles: true,
            importsSpaces: false,
            importsFolders: false,
            profileIDsBySource: [:],
            fallbackProfileId: nil,
            fallbackSpaceId: nil
        )
        for attempt in 0..<128 {
            let candidateSource = attempt == 0 ? source : "\(source)|retry:\(attempt)"
            let candidate = resolver.importedId(.profile, source: candidateSource)
            if !excluding.contains(candidate),
               let id = UUID(uuidString: candidate),
               isProfileIdentityAllowed(id) {
                return candidate
            }
        }
        return resolver.importedId(.profile, source: "\(source)|fallback")
    }

    private func clearReplacedCategories(
        _ categories: Set<SumiImportCategory>,
        in data: inout SumiPortableData,
        mode: SumiImportApplyMode
    ) {
        guard mode == .replace else { return }
        if categories.contains(.profiles) { data.profiles.removeAll() }
        if categories.contains(.spaces) { data.spaces.removeAll() }
        if categories.contains(.themes) {
            data.spaces = data.spaces.map { space in
                var copy = space
                copy.themeDataBase64 = nil
                copy.color = nil
                copy.colors = nil
                copy.themeOpacity = nil
                return copy
            }
        }
        if categories.contains(.folders) { data.folders.removeAll() }
        if categories.contains(.essentials) { data.essentials.removeAll() }
        if categories.contains(.pinnedLaunchers) { data.pinnedLaunchers.removeAll() }
        if categories.contains(.regularTabs) { data.regularTabs.removeAll() }
    }

    private func mergeProfiles(
        _ request: SumiImportRequest,
        identity: SumiImportIdentityResolver,
        into data: inout SumiPortableData
    ) {
        guard request.categories.contains(.profiles) else { return }
        for profile in request.data.profiles.sorted(by: stableIndexOrder) {
            let id = identity.profileId(profile.id)
            guard !data.profiles.contains(where: { $0.id == id }) else { continue }
            data.profiles.append(SumiPortableProfile(
                id: id,
                name: uniqueName(profile.name, existing: data.profiles.map(\.name)),
                index: data.profiles.count
            ))
        }
    }

    private func ensureProfile(
        in data: inout SumiPortableData,
        identity: SumiImportIdentityResolver
    ) {
        guard data.profiles.isEmpty else { return }
        data.profiles.append(SumiPortableProfile(
            id: identity.fallbackId(.profile),
            name: "Default",
            index: 0
        ))
    }

    private func mergeSpaces(
        _ request: SumiImportRequest,
        identity: SumiImportIdentityResolver,
        into data: inout SumiPortableData
    ) {
        if request.categories.contains(.spaces) {
            for space in request.data.spaces.sorted(by: stableIndexOrder) {
                let id = identity.importedId(.space, source: space.id)
                guard !data.spaces.contains(where: { $0.id == id }) else { continue }
                data.spaces.append(SumiPortableSpace(
                    id: id,
                    name: uniqueName(space.name, existing: data.spaces.map(\.name)),
                    icon: space.icon,
                    index: data.spaces.count,
                    profileId: space.profileId.map(identity.profileId(_:)) ?? data.profiles.first?.id,
                    themeDataBase64: request.categories.contains(.themes) ? space.themeDataBase64 : nil,
                    color: request.categories.contains(.themes) ? space.color : nil,
                    colors: request.categories.contains(.themes) ? space.colors : nil,
                    themeOpacity: request.categories.contains(.themes) ? space.themeOpacity : nil
                ))
            }
        } else if request.categories.contains(.themes) {
            let incomingById = Dictionary(
                request.data.spaces.map {
                    (identity.importedId(.space, source: $0.id), $0)
                },
                uniquingKeysWith: { first, _ in first }
            )
            data.spaces = data.spaces.map { space in
                guard let imported = incomingById[space.id] else { return space }
                var copy = space
                copy.themeDataBase64 = imported.themeDataBase64
                copy.color = imported.color
                copy.colors = imported.colors
                copy.themeOpacity = imported.themeOpacity
                return copy
            }
        }
    }

    private func ensureSpace(
        in data: inout SumiPortableData,
        identity: SumiImportIdentityResolver
    ) {
        guard data.spaces.isEmpty else { return }
        data.spaces.append(SumiPortableSpace(
            id: identity.fallbackId(.space),
            name: "Space",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            index: 0,
            profileId: data.profiles.first?.id,
            themeDataBase64: nil,
            color: nil
        ))
    }

    private func mergeFolders(
        _ request: SumiImportRequest,
        identity: SumiImportIdentityResolver,
        into data: inout SumiPortableData
    ) {
        guard request.categories.contains(.folders) else { return }
        for folder in request.data.folders.sorted(by: stableIndexOrder) {
            guard let id = identity.folderId(folder.id),
                  !data.folders.contains(where: { $0.id == id }) else { continue }
            let spaceId = identity.spaceId(folder.spaceId)
            guard data.spaces.contains(where: { $0.id == spaceId }) else { continue }
            let parentId = folder.parentFolderId.flatMap(identity.folderId(_:))
            data.folders.append(SumiPortableFolder(
                id: id,
                name: uniqueFolderName(
                    folder.name,
                    spaceId: spaceId,
                    parentFolderId: parentId,
                    existing: data.folders
                ),
                icon: folder.icon,
                colorHex: folder.colorHex,
                spaceId: spaceId,
                parentFolderId: parentId,
                isOpen: folder.isOpen,
                index: folder.index,
                sourcePath: folder.sourcePath
            ))
        }
    }

    private func mergeEssentials(
        _ request: SumiImportRequest,
        identity: SumiImportIdentityResolver,
        into data: inout SumiPortableData,
        warnings: inout [String]
    ) {
        guard request.categories.contains(.essentials) else { return }
        var invalidCount = 0
        for launcher in request.data.essentials.sorted(by: stableIndexOrder) {
            guard URL(string: launcher.urlString) != nil else {
                invalidCount += 1
                continue
            }
            var imported = remappedLauncher(
                launcher,
                kind: .essential,
                identity: identity,
                data: data
            )
            imported.spaceId = nil
            imported.folderId = nil
            imported.profileId = launcher.profileId.map(identity.profileId(_:)) ?? data.profiles.first?.id
            data.essentials.append(imported)
        }
        appendInvalidURLWarning(count: invalidCount, category: "essentials", to: &warnings)

        var demoted: [SumiPortableLauncher] = []
        enforceEssentialLimit(in: &data, identity: identity, demoted: &demoted)
        if !demoted.isEmpty {
            warnings.append("\(demoted.count) essentials exceeded Sumi's 12-item profile limit and were imported as space-pinned launchers.")
        }
    }

    private func mergePinnedLaunchers(
        _ request: SumiImportRequest,
        identity: SumiImportIdentityResolver,
        into data: inout SumiPortableData,
        warnings: inout [String]
    ) {
        guard request.categories.contains(.pinnedLaunchers) else { return }
        var invalidCount = 0
        for launcher in request.data.pinnedLaunchers.sorted(by: stableIndexOrder) {
            guard URL(string: launcher.urlString) != nil else {
                invalidCount += 1
                continue
            }
            data.pinnedLaunchers.append(remappedLauncher(
                launcher,
                kind: .pinnedLauncher,
                identity: identity,
                data: data
            ))
        }
        appendInvalidURLWarning(count: invalidCount, category: "pinned launchers", to: &warnings)
    }

    private func mergeRegularTabs(
        _ request: SumiImportRequest,
        identity: SumiImportIdentityResolver,
        into data: inout SumiPortableData,
        warnings: inout [String]
    ) {
        guard request.categories.contains(.regularTabs) else { return }
        var invalidCount = 0
        for tab in request.data.regularTabs.sorted(by: stableIndexOrder) {
            guard URL(string: tab.urlString) != nil else {
                invalidCount += 1
                continue
            }
            let spaceId = identity.spaceId(tab.spaceId)
            guard data.spaces.contains(where: { $0.id == spaceId }) else { continue }
            data.regularTabs.append(SumiPortableRegularTab(
                id: identity.importedId(.regularTab, source: tab.id),
                title: tab.title,
                urlString: tab.urlString,
                index: tab.index,
                spaceId: spaceId,
                profileId: tab.profileId.map(identity.profileId(_:)),
                folderId: tab.folderId.flatMap(identity.folderId(_:))
            ))
        }
        appendInvalidURLWarning(count: invalidCount, category: "regular tabs", to: &warnings)
    }

    private func remappedLauncher(
        _ launcher: SumiPortableLauncher,
        kind: SumiImportIdentityResolver.EntityKind,
        identity: SumiImportIdentityResolver,
        data: SumiPortableData
    ) -> SumiPortableLauncher {
        let spaceId = launcher.spaceId.map(identity.spaceId(_:))
            ?? launcher.sourceSpaceId.map(identity.spaceId(_:))
            ?? data.spaces.first?.id
        let profileId = launcher.profileId.map(identity.profileId(_:))
        return SumiPortableLauncher(
            id: identity.importedId(kind, source: launcher.id),
            title: launcher.title,
            urlString: launcher.urlString,
            index: launcher.index,
            profileId: profileId,
            executionProfileId: launcher.executionProfileId.map(identity.profileId(_:)) ?? profileId,
            spaceId: spaceId,
            folderId: launcher.folderId.flatMap(identity.folderId(_:)),
            iconAsset: launcher.iconAsset,
            sourceSpaceId: spaceId
        )
    }

    private func enforceEssentialLimit(
        in data: inout SumiPortableData,
        identity: SumiImportIdentityResolver,
        demoted: inout [SumiPortableLauncher]
    ) {
        let grouped = Dictionary(grouping: data.essentials, by: { $0.profileId ?? "" })
        var kept: [SumiPortableLauncher] = []
        for key in grouped.keys.sorted() {
            let launchers = (grouped[key] ?? []).sorted(by: stableIndexOrder)
            kept.append(contentsOf: launchers.prefix(Self.maxEssentialsPerProfile))
            demoted.append(contentsOf: launchers.dropFirst(Self.maxEssentialsPerProfile).map { launcher in
                var copy = launcher
                copy.id = identity.importedId(.demotedEssential, source: launcher.id)
                copy.profileId = nil
                copy.spaceId = launcher.sourceSpaceId ?? data.spaces.first?.id
                copy.folderId = nil
                return copy
            })
        }
        data.essentials = kept
        data.pinnedLaunchers.append(contentsOf: demoted)
    }

    private func bookmarkMutation(
        for request: SumiImportRequest,
        baseline: SumiPortableData
    ) -> SumiImportBookmarkMutation {
        guard request.categories.contains(.bookmarks) else { return .none }
        switch request.mode {
        case .merge:
            return .merge(request.data.bookmarks)
        case .replace:
            return request.data.bookmarks == baseline.bookmarks
                ? .none
                : .replace(request.data.bookmarks)
        }
    }

    private func appendInvalidURLWarning(
        count: Int,
        category: String,
        to warnings: inout [String]
    ) {
        guard count > 0 else { return }
        warnings.append("Skipped \(count) \(category) with invalid URLs.")
    }

    private func uniqueName(_ base: String, existing: [String]) -> String {
        let root = base.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Imported"
        let existingNames = Set(existing)
        guard existingNames.contains(root) else { return root }
        var suffix = 2
        while existingNames.contains("\(root) (\(suffix))") { suffix += 1 }
        return "\(root) (\(suffix))"
    }

    private func uniqueFolderName(
        _ base: String,
        spaceId: String,
        parentFolderId: String?,
        existing: [SumiPortableFolder]
    ) -> String {
        uniqueName(
            base,
            existing: existing.filter {
                $0.spaceId == spaceId && $0.parentFolderId == parentFolderId
            }.map(\.name)
        )
    }

    private func stableIndexOrder<T: SumiIndexedPortableRecord>(_ lhs: T, _ rhs: T) -> Bool {
        if lhs.portableIndex != rhs.portableIndex {
            return lhs.portableIndex < rhs.portableIndex
        }
        return lhs.id < rhs.id
    }
}

private protocol SumiIndexedPortableRecord: Identifiable where ID == String {
    var portableIndex: Int { get }
}

extension SumiPortableProfile: SumiIndexedPortableRecord { var portableIndex: Int { index } }
extension SumiPortableSpace: SumiIndexedPortableRecord { var portableIndex: Int { index } }
extension SumiPortableFolder: SumiIndexedPortableRecord { var portableIndex: Int { index } }
extension SumiPortableLauncher: SumiIndexedPortableRecord { var portableIndex: Int { index } }
extension SumiPortableRegularTab: SumiIndexedPortableRecord { var portableIndex: Int { index } }

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

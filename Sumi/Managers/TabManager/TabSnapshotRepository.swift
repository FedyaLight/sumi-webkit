import Foundation
import SwiftData
import OSLog

// MARK: - Tab Repository

/// Serializes SwiftData tab persistence writes and keeps recovery-only
/// in-memory backups for explicit full reconciles.
actor TabSnapshotRepository {
    private let container: ModelContainer
    private static let log = Logger.sumi(category: "TabPersistence")

    // Lightweight, in-memory backup of the most recent full reconcile payload.
    // Recovery paths may use this if the primary full reconcile fails mid-flight.
    private var lastBackupJSON: Data?

    enum PersistenceError: Error {
        case concurrencyConflict
        case dataCorruption
        case storageFailure
        case rollbackFailed
        case invalidModelState
    }

    init(container: ModelContainer) {
        self.container = container
    }

    struct SnapshotTab: Codable, Sendable {
        let id: UUID
        let urlString: String
        let name: String
        let index: Int
        let spaceId: UUID?
        let isPinned: Bool
        let isSpacePinned: Bool
        let profileId: UUID?
        let folderId: UUID?
        let iconAsset: String?
        let currentURLString: String?
        let canGoBack: Bool
        let canGoForward: Bool
    }

    struct SnapshotFolder: Codable, Sendable {
        let id: UUID
        let name: String
        let icon: String
        let color: String
        let spaceId: UUID
        let isOpen: Bool
        let index: Int
    }

    struct SnapshotSpace: Codable, Sendable {
        let id: UUID
        let name: String
        let icon: String
        let index: Int
        let gradientData: Data?
        let workspaceThemeData: Data?
        let profileId: UUID?
    }

    struct SnapshotState: Codable, Sendable {
        let currentTabID: UUID?
        let currentSpaceID: UUID?
    }

    struct Snapshot: Codable, Sendable {
        let spaces: [SnapshotSpace]
        let tabs: [SnapshotTab]
        let folders: [SnapshotFolder]
        let state: SnapshotState
    }

    struct StructuralDelta: Sendable {
        let spaces: [SnapshotSpace]
        let tabs: [SnapshotTab]
        let folders: [SnapshotFolder]
        let deletedSpaceIds: Set<UUID>
        let deletedTabIds: Set<UUID>
        let deletedFolderIds: Set<UUID>
        let state: SnapshotState
    }

    struct RuntimeTabState: Sendable {
        let id: UUID
        let urlString: String
        let currentURLString: String?
        let name: String
        let canGoBack: Bool
        let canGoForward: Bool
    }

    private var latestGeneration: Int = 0

    func persistFullReconcile(snapshot: Snapshot, generation: Int) async -> Bool {
        let signpostState = PerformanceTrace.beginInterval("TabSnapshotRepository.persistFullReconcile")
        defer {
            PerformanceTrace.endInterval("TabSnapshotRepository.persistFullReconcile", signpostState)
        }

        if generation < self.latestGeneration {
            Self.log.debug("[persistFullReconcile] Skipping stale snapshot generation=\(generation) < latest=\(self.latestGeneration)")
            return false
        }
        self.latestGeneration = generation
        do {
            try createDataSnapshot(snapshot)
            try await performFullReconcile(snapshot)
            return true
        } catch {
            let classified = classify(error)
            Self.log.error("[persistFullReconcile] Full reconcile failed (\(String(describing: classified), privacy: .public)): \(String(describing: error), privacy: .public)")

            do {
                try await performBestEffortPersistence(snapshot)
                Self.log.notice("[persistFullReconcile] Recovery fallback succeeded after full reconcile failure")
                return false
            } catch {
                Self.log.fault("[persistFullReconcile] Recovery fallback failed: \(String(describing: error), privacy: .public). Attempting backup recovery…")
                do {
                    try await recoverFromBackup()
                    Self.log.notice("[persistFullReconcile] Recovered from in-memory backup payload")
                    return false
                } catch {
                    Self.log.fault("[persistFullReconcile] Backup recovery failed: \(String(describing: error), privacy: .public)")
                    return false
                }
            }
        }
    }

    func persistIncremental(delta: StructuralDelta, generation: Int) async -> Bool {
        let signpostState = PerformanceTrace.beginInterval("TabSnapshotRepository.persistIncremental")
        defer {
            PerformanceTrace.endInterval("TabSnapshotRepository.persistIncremental", signpostState)
        }

        if generation < self.latestGeneration {
            Self.log.debug("[persistIncremental] Skipping stale generation=\(generation) < latest=\(self.latestGeneration)")
            return false
        }
        self.latestGeneration = generation

        do {
            try await performIncrementalPersistence(delta)
            return true
        } catch {
            let classified = classify(error)
            Self.log.error("[persistIncremental] Failed (\(String(describing: classified), privacy: .public)): \(String(describing: error), privacy: .public)")
            return false
        }
    }

    func persistSelectionOnly(currentTabID: UUID?, currentSpaceID: UUID?) async {
        let signpostState = PerformanceTrace.beginInterval("TabSnapshotRepository.persistSelectionOnly")
        defer {
            PerformanceTrace.endInterval("TabSnapshotRepository.persistSelectionOnly", signpostState)
        }

        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        do {
            try upsertState(
                in: ctx,
                state: SnapshotState(currentTabID: currentTabID, currentSpaceID: currentSpaceID)
            )
            try ctx.save()
        } catch {
            Self.log.error("[persistSelection] Failed: \(String(describing: error), privacy: .public)")
        }
    }

    func persistRuntimeStates(_ runtimeStates: [RuntimeTabState]) async {
        let signpostState = PerformanceTrace.beginInterval("TabSnapshotRepository.persistRuntimeStates")
        defer {
            PerformanceTrace.endInterval("TabSnapshotRepository.persistRuntimeStates", signpostState)
        }

        let latestByTabID = Dictionary(runtimeStates.map { ($0.id, $0) }) { _, latest in latest }
        let deduplicatedStates = latestByTabID.values.sorted {
            $0.id.uuidString < $1.id.uuidString
        }
        guard deduplicatedStates.isEmpty == false else { return }

        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        do {
            var didUpdate = false
            for runtimeState in deduplicatedStates {
                let tabID = runtimeState.id
                let predicate = #Predicate<TabEntity> { $0.id == tabID }
                guard let existing = try ctx.fetch(FetchDescriptor<TabEntity>(predicate: predicate)).first else {
                    continue
                }

                applyRuntimeState(runtimeState, to: existing)
                didUpdate = true
            }

            if didUpdate {
                try ctx.save()
            }
        } catch {
            Self.log.error(
                "[persistRuntimeStates] Failed for count=\(deduplicatedStates.count, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func performIncrementalPersistence(_ delta: StructuralDelta) async throws {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        try PerformanceTrace.withInterval("TabSnapshotRepository.incremental.validateInput") {
            try validateDelta(delta)
        }

        try PerformanceTrace.withInterval("TabSnapshotRepository.incremental.deleteSpaces") {
            do {
                for spaceId in delta.deletedSpaceIds {
                    for tab in try fetchTabs(in: ctx, spaceId: spaceId) {
                        ctx.delete(tab)
                    }
                    for folder in try fetchFolders(in: ctx, spaceId: spaceId) {
                        ctx.delete(folder)
                    }
                    if let space = try fetchSpace(in: ctx, id: spaceId) {
                        ctx.delete(space)
                    }
                }
            } catch {
                throw classify(error)
            }
        }

        let upsertTabIds = Set(delta.tabs.map(\.id))
        try PerformanceTrace.withInterval("TabSnapshotRepository.incremental.deleteTabs") {
            do {
                for tabId in delta.deletedTabIds.subtracting(upsertTabIds) {
                    if let tab = try fetchTab(in: ctx, id: tabId) {
                        ctx.delete(tab)
                    }
                }
            } catch {
                throw classify(error)
            }
        }

        let upsertFolderIds = Set(delta.folders.map(\.id))
        try PerformanceTrace.withInterval("TabSnapshotRepository.incremental.deleteFolders") {
            do {
                for folderId in delta.deletedFolderIds.subtracting(upsertFolderIds) {
                    if let folder = try fetchFolder(in: ctx, id: folderId) {
                        ctx.delete(folder)
                    }
                }
            } catch {
                throw classify(error)
            }
        }

        try PerformanceTrace.withInterval("TabSnapshotRepository.incremental.upsertSpaces") {
            do {
                for space in delta.spaces {
                    let existing = try fetchSpace(in: ctx, id: space.id)
                    upsertSpace(in: ctx, space, existing: existing)
                }
            } catch {
                throw classify(error)
            }
        }

        try PerformanceTrace.withInterval("TabSnapshotRepository.incremental.upsertFolders") {
            do {
                for folder in delta.folders {
                    let existing = try fetchFolder(in: ctx, id: folder.id)
                    upsertFolder(in: ctx, folder, existing: existing)
                }
            } catch {
                throw classify(error)
            }
        }

        try PerformanceTrace.withInterval("TabSnapshotRepository.incremental.upsertTabs") {
            do {
                for tab in delta.tabs {
                    let existing = try fetchTab(in: ctx, id: tab.id)
                    upsertTab(in: ctx, tab, existing: existing)
                }
            } catch {
                throw classify(error)
            }
        }

        try PerformanceTrace.withInterval("TabSnapshotRepository.incremental.upsertState") {
            do {
                try upsertState(in: ctx, state: delta.state)
            } catch {
                throw classify(error)
            }
        }

        try PerformanceTrace.withInterval("TabSnapshotRepository.incremental.save") {
            do {
                try ctx.save()
            } catch {
                throw classify(error)
            }
        }
    }

    private func performFullReconcile(_ snapshot: Snapshot) async throws {
        let signpostState = PerformanceTrace.beginInterval("TabSnapshotRepository.performFullReconcile")
        defer {
            PerformanceTrace.endInterval(
                "TabSnapshotRepository.performFullReconcile",
                signpostState
            )
        }

        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        try PerformanceTrace.withInterval("TabSnapshotRepository.fullReconcile.validateInput") {
            try validateInput(snapshot)
        }

        let existingTabsById: [UUID: TabEntity] = try PerformanceTrace.withInterval(
            "TabSnapshotRepository.fullReconcile.fetchTabs"
        ) {
            do {
                let all = try ctx.fetch(FetchDescriptor<TabEntity>())
                let keepIDs = Set(snapshot.tabs.map { $0.id })
                for entity in all where !keepIDs.contains(entity.id) {
                    ctx.delete(entity)
                }
                return Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
            } catch {
                throw classify(error)
            }
        }

        PerformanceTrace.withInterval("TabSnapshotRepository.fullReconcile.upsertTabs") {
            for tab in snapshot.tabs {
                upsertTab(in: ctx, tab, existing: existingTabsById[tab.id])
            }
        }

        let existingFoldersById: [UUID: FolderEntity] = try PerformanceTrace.withInterval(
            "TabSnapshotRepository.fullReconcile.fetchFolders"
        ) {
            do {
                let allFolders = try ctx.fetch(FetchDescriptor<FolderEntity>())
                let keep = Set(snapshot.folders.map { $0.id })
                for entity in allFolders where !keep.contains(entity.id) {
                    ctx.delete(entity)
                }
                return Dictionary(allFolders.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
            } catch {
                throw classify(error)
            }
        }

        PerformanceTrace.withInterval("TabSnapshotRepository.fullReconcile.upsertFolders") {
            for folder in snapshot.folders {
                upsertFolder(in: ctx, folder, existing: existingFoldersById[folder.id])
            }
        }

        let existingSpacesById: [UUID: SpaceEntity] = try PerformanceTrace.withInterval(
            "TabSnapshotRepository.fullReconcile.fetchSpaces"
        ) {
            do {
                let allSpaces = try ctx.fetch(FetchDescriptor<SpaceEntity>())
                let keep = Set(snapshot.spaces.map { $0.id })
                for entity in allSpaces where !keep.contains(entity.id) {
                    ctx.delete(entity)
                }
                return Dictionary(allSpaces.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
            } catch {
                throw classify(error)
            }
        }

        PerformanceTrace.withInterval("TabSnapshotRepository.fullReconcile.upsertSpaces") {
            for space in snapshot.spaces {
                upsertSpace(in: ctx, space, existing: existingSpacesById[space.id])
            }
        }

        try PerformanceTrace.withInterval("TabSnapshotRepository.fullReconcile.upsertState") {
            do {
                try upsertState(in: ctx, state: snapshot.state)
            } catch {
                throw classify(error)
            }
        }

        try PerformanceTrace.withInterval("TabSnapshotRepository.fullReconcile.save") {
            do {
                try ctx.save()
            } catch {
                throw classify(error)
            }
        }

        PerformanceTrace.withInterval("TabSnapshotRepository.fullReconcile.validateIntegrity") {
            do {
                try validateDataIntegrity(in: ctx, snapshot: snapshot)
            } catch {
                Self.log.error("[persist] Post-save integrity validation reported issues: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func upsertTab(in ctx: ModelContext, _ tab: SnapshotTab, existing: TabEntity? = nil) {
        if let existing {
            existing.urlString = tab.urlString
            existing.name = tab.name
            existing.isPinned = tab.isPinned
            existing.isSpacePinned = tab.isSpacePinned
            existing.index = tab.index
            existing.spaceId = tab.spaceId
            existing.profileId = tab.profileId
            existing.folderId = tab.folderId
            existing.iconAsset = tab.iconAsset
            existing.currentURLString = tab.currentURLString
            existing.canGoBack = tab.canGoBack
            existing.canGoForward = tab.canGoForward
        } else {
            let entity = TabEntity(
                id: tab.id,
                urlString: tab.urlString,
                name: tab.name,
                isPinned: tab.isPinned,
                isSpacePinned: tab.isSpacePinned,
                index: tab.index,
                spaceId: tab.spaceId,
                profileId: tab.profileId,
                folderId: tab.folderId,
                iconAsset: tab.iconAsset,
                currentURLString: tab.currentURLString,
                canGoBack: tab.canGoBack,
                canGoForward: tab.canGoForward
            )
            ctx.insert(entity)
        }
    }

    private func applyRuntimeState(_ runtimeState: RuntimeTabState, to existing: TabEntity) {
        existing.urlString = runtimeState.urlString
        existing.currentURLString = runtimeState.currentURLString
        existing.name = runtimeState.name
        existing.canGoBack = runtimeState.canGoBack
        existing.canGoForward = runtimeState.canGoForward
    }

    private func upsertFolder(in ctx: ModelContext, _ folder: SnapshotFolder, existing: FolderEntity? = nil) {
        let normalizedIcon = SumiZenFolderIconCatalog.normalizedFolderIconValue(folder.icon)
        if let existing {
            existing.name = folder.name
            existing.icon = normalizedIcon
            existing.color = folder.color
            existing.spaceId = folder.spaceId
            existing.isOpen = folder.isOpen
            existing.index = folder.index
        } else {
            let entity = FolderEntity(
                id: folder.id,
                name: folder.name,
                icon: normalizedIcon,
                color: folder.color,
                spaceId: folder.spaceId,
                isOpen: folder.isOpen,
                index: folder.index
            )
            ctx.insert(entity)
        }
    }

    private func upsertSpace(in ctx: ModelContext, _ space: SnapshotSpace, existing: SpaceEntity? = nil) {
        if let existing {
            existing.name = space.name
            existing.icon = space.icon
            existing.index = space.index
            if let data = space.gradientData {
                existing.gradientData = data
            }
            existing.workspaceThemeData = space.workspaceThemeData
            existing.profileId = space.profileId
        } else {
            let entity = SpaceEntity(
                id: space.id,
                name: space.name,
                icon: space.icon,
                index: space.index,
                gradientData: space.gradientData ?? (SpaceGradient.default.encoded ?? Data()),
                workspaceThemeData: space.workspaceThemeData,
                profileId: space.profileId
            )
            ctx.insert(entity)
        }
    }

    private func upsertState(in ctx: ModelContext, state snapshotState: SnapshotState) throws {
        let states = try ctx.fetch(FetchDescriptor<TabsStateEntity>())
        let state = states.first ?? {
            let entity = TabsStateEntity(currentTabID: nil, currentSpaceID: nil)
            ctx.insert(entity)
            return entity
        }()
        state.currentTabID = snapshotState.currentTabID
        state.currentSpaceID = snapshotState.currentSpaceID
    }

    private func fetchTab(in ctx: ModelContext, id: UUID) throws -> TabEntity? {
        let tabId = id
        let predicate = #Predicate<TabEntity> { $0.id == tabId }
        return try ctx.fetch(FetchDescriptor<TabEntity>(predicate: predicate)).first
    }

    private func fetchFolder(in ctx: ModelContext, id: UUID) throws -> FolderEntity? {
        let folderId = id
        let predicate = #Predicate<FolderEntity> { $0.id == folderId }
        return try ctx.fetch(FetchDescriptor<FolderEntity>(predicate: predicate)).first
    }

    private func fetchSpace(in ctx: ModelContext, id: UUID) throws -> SpaceEntity? {
        let spaceId = id
        let predicate = #Predicate<SpaceEntity> { $0.id == spaceId }
        return try ctx.fetch(FetchDescriptor<SpaceEntity>(predicate: predicate)).first
    }

    private func fetchTabs(in ctx: ModelContext, spaceId: UUID) throws -> [TabEntity] {
        let targetSpaceId = spaceId
        let predicate = #Predicate<TabEntity> { $0.spaceId == targetSpaceId }
        return try ctx.fetch(FetchDescriptor<TabEntity>(predicate: predicate))
    }

    private func fetchFolders(in ctx: ModelContext, spaceId: UUID) throws -> [FolderEntity] {
        let targetSpaceId = spaceId
        let predicate = #Predicate<FolderEntity> { $0.spaceId == targetSpaceId }
        return try ctx.fetch(FetchDescriptor<FolderEntity>(predicate: predicate))
    }

    private func createDataSnapshot(_ snapshot: Snapshot) throws {
        #if DEBUG
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.lastBackupJSON = try encoder.encode(snapshot)
        #else
        self.lastBackupJSON = try JSONEncoder().encode(snapshot)
        #endif
    }

    private func recoverFromBackup() async throws {
        guard let data = lastBackupJSON else { return }
        let decoder = JSONDecoder()
        let snapshot = try decoder.decode(Snapshot.self, from: data)
        try await performBestEffortPersistence(snapshot)
    }

    /// Recovery-only fallback used after a full reconcile failure.
    private func performBestEffortPersistence(_ snapshot: Snapshot) async throws {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        let existingTabsById: [UUID: TabEntity]
        do {
            let all = try ctx.fetch(FetchDescriptor<TabEntity>())
            existingTabsById = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
            let keepIDs = Set(snapshot.tabs.map { $0.id })
            for entity in all where !keepIDs.contains(entity.id) {
                ctx.delete(entity)
            }
        } catch {
            throw classify(error)
        }

        for tab in snapshot.tabs {
            upsertTab(in: ctx, tab, existing: existingTabsById[tab.id])
        }

        let existingFoldersById: [UUID: FolderEntity]
        do {
            let allFolders = try ctx.fetch(FetchDescriptor<FolderEntity>())
            existingFoldersById = Dictionary(allFolders.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
            let keep = Set(snapshot.folders.map { $0.id })
            for entity in allFolders where !keep.contains(entity.id) {
                ctx.delete(entity)
            }
        } catch {
            throw classify(error)
        }

        for folder in snapshot.folders {
            upsertFolder(in: ctx, folder, existing: existingFoldersById[folder.id])
        }

        let existingSpacesById: [UUID: SpaceEntity]
        do {
            let allSpaces = try ctx.fetch(FetchDescriptor<SpaceEntity>())
            existingSpacesById = Dictionary(allSpaces.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
            let keep = Set(snapshot.spaces.map { $0.id })
            for entity in allSpaces where !keep.contains(entity.id) {
                ctx.delete(entity)
            }
        } catch {
            throw classify(error)
        }

        for space in snapshot.spaces {
            upsertSpace(in: ctx, space, existing: existingSpacesById[space.id])
        }

        do {
            try upsertState(in: ctx, state: snapshot.state)
        } catch {
            throw classify(error)
        }
        do {
            try ctx.save()
        } catch {
            throw classify(error)
        }
    }

    private func validateDelta(_ delta: StructuralDelta) throws {
        if delta.tabs.contains(where: { $0.index < 0 })
            || delta.folders.contains(where: { $0.index < 0 })
            || delta.spaces.contains(where: { $0.index < 0 })
        {
            throw PersistenceError.invalidModelState
        }

        let tabIDs = Set(delta.tabs.map(\.id))
        if tabIDs.count != delta.tabs.count {
            throw PersistenceError.invalidModelState
        }

        let folderIDs = Set(delta.folders.map(\.id))
        if folderIDs.count != delta.folders.count {
            throw PersistenceError.invalidModelState
        }

        let spaceIDs = Set(delta.spaces.map(\.id))
        if spaceIDs.count != delta.spaces.count {
            throw PersistenceError.invalidModelState
        }

        for tab in delta.tabs {
            if tab.isPinned && tab.isSpacePinned {
                throw PersistenceError.invalidModelState
            }
            if tab.isPinned && tab.spaceId != nil {
                throw PersistenceError.invalidModelState
            }
            if tab.isSpacePinned && tab.spaceId == nil {
                throw PersistenceError.invalidModelState
            }
            if let spaceId = tab.spaceId, delta.deletedSpaceIds.contains(spaceId) {
                throw PersistenceError.invalidModelState
            }
        }

        for folder in delta.folders where delta.deletedSpaceIds.contains(folder.spaceId) {
            throw PersistenceError.invalidModelState
        }
    }

    private func validateInput(_ snapshot: Snapshot) throws {
        if snapshot.tabs.contains(where: { $0.index < 0 }) {
            throw PersistenceError.invalidModelState
        }
        let tabIDs = Set(snapshot.tabs.map { $0.id })
        if tabIDs.count != snapshot.tabs.count {
            throw PersistenceError.invalidModelState
        }
        let spaceIDs = Set(snapshot.spaces.map { $0.id })
        if spaceIDs.count != snapshot.spaces.count {
            throw PersistenceError.invalidModelState
        }

        for tab in snapshot.tabs {
            if let spaceId = tab.spaceId, !spaceIDs.contains(spaceId) {
                throw PersistenceError.invalidModelState
            }
            if tab.isPinned && tab.isSpacePinned {
                throw PersistenceError.invalidModelState
            }
            if tab.isPinned && tab.spaceId != nil {
                throw PersistenceError.invalidModelState
            }
            if tab.isSpacePinned && tab.spaceId == nil {
                throw PersistenceError.invalidModelState
            }
        }

        for space in snapshot.spaces where space.profileId == nil {
            Self.log.debug("[validate] Space missing profileId: \(space.id.uuidString, privacy: .public)")
        }
    }

    private func validateDataIntegrity(in ctx: ModelContext, snapshot: Snapshot) throws {
        do {
            let tabs: [TabEntity] = try ctx.fetch(FetchDescriptor<TabEntity>())
            let spaces: [SpaceEntity] = try ctx.fetch(FetchDescriptor<SpaceEntity>())
            let spaceIDs = Set(spaces.map { $0.id })
            for tab in tabs {
                if let spaceId = tab.spaceId, !spaceIDs.contains(spaceId) {
                    throw PersistenceError.dataCorruption
                }
            }
        } catch {
            throw classify(error)
        }
    }

    private func classify(_ error: Error) -> PersistenceError {
        let ns = error as NSError
        let domain = ns.domain.lowercased()
        let description = (ns.userInfo[NSLocalizedDescriptionKey] as? String)?.lowercased()
            ?? ns.localizedDescription.lowercased()

        if domain.contains("swiftdata") || domain.contains("coredata") {
            if description.contains("conflict")
                || description.contains("busy")
                || description.contains("locked")
            {
                return .concurrencyConflict
            }
            if description.contains("corrupt") || description.contains("malformed") {
                return .dataCorruption
            }
            if description.contains("rollback") {
                return .rollbackFailed
            }
            return .storageFailure
        }
        return .storageFailure
    }
}

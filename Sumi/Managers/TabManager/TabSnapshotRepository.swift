import Foundation
import SwiftData
import OSLog

// MARK: - Tab Repository

/// Serializes all SwiftData writes for Tab snapshots and provides
/// a best-effort atomic save using a child ModelContext pattern.
actor TabSnapshotRepository {
    private let container: ModelContainer
    private static let log = Logger.sumi(category: "TabPersistence")

    // Lightweight, in-memory backup of the most recent snapshot
    // to allow quick recovery if atomic operations fail mid-flight.
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

    struct SnapshotTab: Codable {
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

    struct SnapshotFolder: Codable {
        let id: UUID
        let name: String
        let icon: String
        let color: String
        let spaceId: UUID
        let isOpen: Bool
        let index: Int
    }

    struct SnapshotSpace: Codable {
        let id: UUID
        let name: String
        let icon: String
        let index: Int
        let gradientData: Data?
        let workspaceThemeData: Data?
        let activeTabId: UUID?
        let profileId: UUID?
    }

    struct SnapshotState: Codable {
        let currentTabID: UUID?
        let currentSpaceID: UUID?
    }

    struct Snapshot: Codable {
        let spaces: [SnapshotSpace]
        let tabs: [SnapshotTab]
        let folders: [SnapshotFolder]
        let state: SnapshotState
    }

    struct RuntimeTabState {
        let id: UUID
        let urlString: String
        let currentURLString: String?
        let name: String
        let canGoBack: Bool
        let canGoForward: Bool
    }

    private var latestGeneration: Int = 0

    func persist(snapshot: Snapshot, generation: Int) async -> Bool {
        if generation < self.latestGeneration {
            Self.log.debug("[persist] Skipping stale snapshot generation=\(generation) < latest=\(self.latestGeneration)")
            return false
        }
        self.latestGeneration = generation
        do {
            try createDataSnapshot(snapshot)
            try await performAtomicPersistence(snapshot)
            return true
        } catch {
            let classified = classify(error)
            Self.log.error("[persist] Atomic persistence failed (\(String(describing: classified), privacy: .public)): \(String(describing: error), privacy: .public)")

            do {
                try await performBestEffortPersistence(snapshot)
                Self.log.notice("[persist] Fallback persistence succeeded after atomic failure")
                return false
            } catch {
                Self.log.fault("[persist] Fallback persistence failed: \(String(describing: error), privacy: .public). Attempting recovery from backup…")
                do {
                    try await recoverFromBackup()
                    Self.log.notice("[persist] Recovered from in-memory backup snapshot")
                    return false
                } catch {
                    Self.log.fault("[persist] Backup recovery failed: \(String(describing: error), privacy: .public)")
                    return false
                }
            }
        }
    }

    func persistSelectionOnly(currentTabID: UUID?, currentSpaceID: UUID?) async {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        do {
            let states = try ctx.fetch(FetchDescriptor<TabsStateEntity>())
            guard let state = states.first else { return }
            state.currentTabID = currentTabID
            state.currentSpaceID = currentSpaceID
            try ctx.save()
        } catch {
            Self.log.error("[persistSelection] Failed: \(String(describing: error), privacy: .public)")
        }
    }

    func persistRuntimeState(_ runtimeState: RuntimeTabState) async {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        do {
            let tabID = runtimeState.id
            let predicate = #Predicate<TabEntity> { $0.id == tabID }
            guard let existing = try ctx.fetch(FetchDescriptor<TabEntity>(predicate: predicate)).first else {
                return
            }

            existing.urlString = runtimeState.urlString
            existing.currentURLString = runtimeState.currentURLString
            existing.name = runtimeState.name
            existing.canGoBack = runtimeState.canGoBack
            existing.canGoForward = runtimeState.canGoForward
            try ctx.save()
        } catch {
            Self.log.error(
                "[persistRuntimeState] Failed for tab=\(runtimeState.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func performAtomicPersistence(_ snapshot: Snapshot) async throws {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        try validateInput(snapshot)

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
            let states = try ctx.fetch(FetchDescriptor<TabsStateEntity>())
            let state = states.first ?? {
                let entity = TabsStateEntity(currentTabID: nil, currentSpaceID: nil)
                ctx.insert(entity)
                return entity
            }()
            state.currentTabID = snapshot.state.currentTabID
            state.currentSpaceID = snapshot.state.currentSpaceID
        } catch {
            throw classify(error)
        }

        do {
            try ctx.save()
        } catch {
            throw classify(error)
        }

        do {
            try validateDataIntegrity(in: ctx, snapshot: snapshot)
        } catch {
            Self.log.error("[persist] Post-save integrity validation reported issues: \(String(describing: error), privacy: .public)")
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
            let states = try ctx.fetch(FetchDescriptor<TabsStateEntity>())
            let state = states.first ?? {
                let entity = TabsStateEntity(currentTabID: nil, currentSpaceID: nil)
                ctx.insert(entity)
                return entity
            }()
            state.currentTabID = snapshot.state.currentTabID
            state.currentSpaceID = snapshot.state.currentSpaceID
        } catch {
            throw classify(error)
        }
        do {
            try ctx.save()
        } catch {
            throw classify(error)
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

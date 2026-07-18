import Foundation
import SumiDomain

enum SumiImportTransactionPhase: String, Codable, CaseIterable, Sendable {
    case prepared
    case runtimeCommitted
    case bookmarksCommitted
    case retiringProfiles
    case compensating
    case compensatingProfiles
    case completed

    func canTransition(to phase: Self) -> Bool {
        switch (self, phase) {
        case (.prepared, .runtimeCommitted),
             (.prepared, .compensating),
             (.runtimeCommitted, .bookmarksCommitted),
             (.runtimeCommitted, .compensating),
             (.bookmarksCommitted, .compensating),
             (.bookmarksCommitted, .retiringProfiles),
             (.bookmarksCommitted, .completed),
             (.retiringProfiles, .completed),
             (.compensating, .compensatingProfiles),
             (.compensating, .completed):
            true
        case (.compensatingProfiles, .completed):
            true
        default:
            false
        }
    }
}

struct SumiImportTransactionJournalRecord: Codable, Equatable, Sendable {
    static let currentVersion = 2

    let version: Int
    var phase: SumiImportTransactionPhase
    let baseline: SumiPortableData
    let targetRuntimeData: SumiPortableData
    let runtimeCheckpoint: SumiImportDurableRuntimeCheckpoint?
    let bookmarkCheckpoint: SumiImportBookmarkCheckpoint?
    let preRestoreBackupURL: URL?
    let profileTransition: SumiImportProfileTransition

    init(
        phase: SumiImportTransactionPhase,
        baseline: SumiPortableData,
        targetRuntimeData: SumiPortableData,
        runtimeCheckpoint: SumiImportDurableRuntimeCheckpoint?,
        bookmarkCheckpoint: SumiImportBookmarkCheckpoint?,
        preRestoreBackupURL: URL?,
        profileTransition: SumiImportProfileTransition = .none
    ) {
        version = Self.currentVersion
        self.phase = phase
        self.baseline = baseline
        self.targetRuntimeData = targetRuntimeData
        self.runtimeCheckpoint = runtimeCheckpoint
        self.bookmarkCheckpoint = bookmarkCheckpoint
        self.preRestoreBackupURL = preRestoreBackupURL
        self.profileTransition = profileTransition
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case phase
        case baseline
        case targetRuntimeData
        case runtimeCheckpoint
        case bookmarkCheckpoint
        case preRestoreBackupURL
        case profileTransition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        phase = try container.decode(SumiImportTransactionPhase.self, forKey: .phase)
        baseline = try container.decode(SumiPortableData.self, forKey: .baseline)
        targetRuntimeData = try container.decode(
            SumiPortableData.self,
            forKey: .targetRuntimeData
        )
        runtimeCheckpoint = try container.decodeIfPresent(
            SumiImportDurableRuntimeCheckpoint.self,
            forKey: .runtimeCheckpoint
        )
        bookmarkCheckpoint = try container.decodeIfPresent(
            SumiImportBookmarkCheckpoint.self,
            forKey: .bookmarkCheckpoint
        )
        preRestoreBackupURL = try container.decodeIfPresent(
            URL.self,
            forKey: .preRestoreBackupURL
        )
        profileTransition = try container.decodeIfPresent(
            SumiImportProfileTransition.self,
            forKey: .profileTransition
        ) ?? .none
    }
}

struct SumiImportDurableRuntimeCheckpoint: Codable, Equatable, Sendable {
    let currentProfileID: UUID?
    let currentSpaceID: UUID?
    let currentTabID: UUID?
    let pendingPinnedWithoutProfile: [Pin]
    let splitGroups: [SplitGroup]

    @MainActor
    init(_ state: SumiImportRuntimeState) {
        currentProfileID = state.currentProfile?.id
        currentSpaceID = state.currentSpace?.id
        currentTabID = state.currentTab?.id
        pendingPinnedWithoutProfile = state.pendingPinnedWithoutProfile.map(Pin.init)
        splitGroups = state.splitGroups
    }

    @MainActor
    func applying(to state: SumiImportRuntimeState) -> SumiImportRuntimeState {
        let currentProfile = currentProfileID.flatMap { id in
            state.profiles.first { $0.id == id }
        } ?? state.profiles.first
        let currentSpace = currentSpaceID.flatMap { id in
            state.spaces.first { $0.id == id }
        } ?? state.spaces.first
        let currentTab = currentTabID.flatMap { id in
            state.tabsBySpace.values.lazy.joined().first { $0.id == id }
        } ?? currentSpace.flatMap { state.tabsBySpace[$0.id]?.first }

        return SumiImportRuntimeState(
            profiles: state.profiles,
            currentProfile: currentProfile,
            spaces: state.spaces,
            tabsBySpace: state.tabsBySpace,
            foldersBySpace: state.foldersBySpace,
            pinnedByProfile: state.pinnedByProfile,
            spacePinnedShortcuts: state.spacePinnedShortcuts,
            pendingPinnedWithoutProfile: pendingPinnedWithoutProfile.map { $0.makePin() },
            splitGroups: splitGroups,
            currentSpace: currentSpace,
            currentTab: currentTab
        )
    }

    struct Pin: Codable, Equatable, Sendable {
        let id: UUID
        let role: ShortcutPinRole
        let profileID: UUID?
        let executionProfileID: UUID?
        let spaceID: UUID?
        let index: Int
        let folderID: UUID?
        let launchURL: URL
        let title: String
        let iconAsset: String?

        @MainActor
        init(_ pin: ShortcutPin) {
            id = pin.id
            role = pin.role
            profileID = pin.profileId
            executionProfileID = pin.executionProfileId
            spaceID = pin.spaceId
            index = pin.index
            folderID = pin.folderId
            launchURL = pin.launchURL
            title = pin.title
            iconAsset = pin.iconAsset
        }

        @MainActor
        func makePin() -> ShortcutPin {
            ShortcutPin(
                id: id,
                role: role,
                profileId: profileID,
                executionProfileId: executionProfileID,
                spaceId: spaceID,
                index: index,
                folderId: folderID,
                launchURL: launchURL,
                title: title,
                iconAsset: iconAsset
            )
        }
    }
}

struct SumiImportBookmarkCheckpoint: Codable, Equatable, Sendable {
    private let root: Node

    init(_ snapshot: SumiBookmarksSnapshot) {
        root = Node(snapshot.root)
    }

    func makeSnapshot() -> SumiBookmarksSnapshot {
        let rootEntity = root.makeEntity()
        var entitiesByID: [String: SumiBookmarkEntity] = [:]
        var flattenedFolders: [SumiBookmarkFolder] = []
        Self.index(
            rootEntity,
            depth: 0,
            entitiesByID: &entitiesByID,
            flattenedFolders: &flattenedFolders
        )
        return SumiBookmarksSnapshot(
            root: rootEntity,
            flattenedFolders: flattenedFolders,
            entitiesByID: entitiesByID
        )
    }

    private static func index(
        _ entity: SumiBookmarkEntity,
        depth: Int,
        entitiesByID: inout [String: SumiBookmarkEntity],
        flattenedFolders: inout [SumiBookmarkFolder]
    ) {
        entitiesByID[entity.id] = entity
        if entity.kind == .folder {
            flattenedFolders.append(
                SumiBookmarkFolder(id: entity.id, title: entity.title, depth: depth)
            )
        }
        for child in entity.children {
            index(
                child,
                depth: depth + 1,
                entitiesByID: &entitiesByID,
                flattenedFolders: &flattenedFolders
            )
        }
    }

    private struct Node: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable {
            case bookmark
            case folder

            init(_ kind: SumiBookmarkEntityKind) {
                switch kind {
                case .bookmark: self = .bookmark
                case .folder: self = .folder
                }
            }

            var bookmarkKind: SumiBookmarkEntityKind {
                switch self {
                case .bookmark: .bookmark
                case .folder: .folder
                }
            }
        }

        let id: String
        let kind: Kind
        let title: String
        let url: URL?
        let parentID: String?
        let parentTitle: String?
        let children: [Node]
        let childBookmarkCount: Int

        init(_ entity: SumiBookmarkEntity) {
            id = entity.id
            kind = Kind(entity.kind)
            title = entity.title
            url = entity.url
            parentID = entity.parentID
            parentTitle = entity.parentTitle
            children = entity.children.map(Node.init)
            childBookmarkCount = entity.childBookmarkCount
        }

        func makeEntity() -> SumiBookmarkEntity {
            SumiBookmarkEntity(
                id: id,
                kind: kind.bookmarkKind,
                title: title,
                url: url,
                parentID: parentID,
                parentTitle: parentTitle,
                children: children.map { $0.makeEntity() },
                childBookmarkCount: childBookmarkCount
            )
        }
    }
}

protocol SumiImportTransactionJournal: Sendable {
    func load() async throws -> SumiImportTransactionJournalRecord?
    func save(_ record: SumiImportTransactionJournalRecord) async throws
    func clear() async throws
}

enum SumiImportTransactionJournalError: LocalizedError {
    case applicationSupportUnavailable
    case unsupportedVersion(Int)
    case invalidTransition(
        from: SumiImportTransactionPhase,
        to: SumiImportTransactionPhase
    )
    case refusingToClearUncompleted(SumiImportTransactionPhase)
    case invalidCompletedTombstone(SumiImportTransactionPhase)

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            "Application Support is unavailable for the durable import journal."
        case .unsupportedVersion(let version):
            "The pending import journal uses unsupported version \(version)."
        case .invalidTransition(let from, let to):
            "The import journal cannot transition from \(from.rawValue) to \(to.rawValue)."
        case .refusingToClearUncompleted(let phase):
            "The import journal cannot clear unresolved phase \(phase.rawValue)."
        case .invalidCompletedTombstone(let phase):
            "The import journal cleanup marker contains unresolved phase \(phase.rawValue)."
        }
    }
}

struct SumiImportTransactionJournalFileFailure: LocalizedError {
    let operationError: Error
    let cleanupErrors: [Error]

    var errorDescription: String? {
        let cleanupDescription = cleanupErrors
            .map(\.localizedDescription)
            .joined(separator: "; ")
        return "Import journal operation failed: \(operationError.localizedDescription) Cleanup also reported \(cleanupErrors.count) error(s): \(cleanupDescription)"
    }
}

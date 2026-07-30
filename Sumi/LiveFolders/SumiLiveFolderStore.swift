import Foundation

actor SumiLiveFolderStore {
    private static let documentKey = "live-folders.state"
    private let database: SumiDatabase?
    private var memoryState = SumiLiveFolderDiskState.empty

    init(database: SumiDatabase? = nil) {
        self.database = database
    }

    enum StoreError: Error {
        case verificationFailed
    }

    func load() throws -> SumiLiveFolderDiskState {
        guard let database else { return memoryState }
        return try database.read {
            try $0.documents.value(
                SumiLiveFolderDiskState.self,
                forKey: Self.documentKey
            ) ?? .empty
        }
    }

    func save(_ state: SumiLiveFolderDiskState) throws {
        guard let database else {
            memoryState = state
            return
        }
        try database.transaction {
            try $0.documents.save(state, forKey: Self.documentKey)
        }
    }

    func deleteSources(inFolderIDs folderIDs: Set<UUID>) throws {
        guard !folderIDs.isEmpty else { return }
        try save(try load().removingSources(inFolderIDs: folderIDs))
    }

    func verifyDurableState() throws {
        let state = try load()
        try save(state)
        guard try load() == state else {
            throw StoreError.verificationFailed
        }
    }
}

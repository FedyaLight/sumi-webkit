import Foundation

struct TabPersistenceCodec: Sendable {
    func encodeSnapshot(_ snapshot: TabPersistenceSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        #if DEBUG
        encoder.outputFormatting = [.sortedKeys]
        #endif
        return try encoder.encode(snapshot)
    }

    func decodeSnapshot(from data: Data) throws -> TabPersistenceSnapshot {
        try JSONDecoder().decode(TabPersistenceSnapshot.self, from: data)
    }

    func encodeSplitGroups(_ splitGroups: [SplitGroup]) throws -> Data {
        try JSONEncoder().encode(SplitGroup.sanitized(splitGroups))
    }

    func decodeSplitGroups(from data: Data) throws -> [SplitGroup] {
        try JSONDecoder().decode([SplitGroup].self, from: data)
    }
}

enum TabPersistenceErrorClassifier {
    static func classify(_ error: Error) -> TabPersistenceError {
        if let persistenceError = error as? TabPersistenceError {
            return persistenceError
        }

        let nsError = error as NSError
        let domain = nsError.domain.lowercased()
        let description = (nsError.userInfo[NSLocalizedDescriptionKey] as? String)?.lowercased()
            ?? nsError.localizedDescription.lowercased()

        guard domain.contains("swiftdata") || domain.contains("coredata") else {
            return .storageFailure
        }
        if description.contains("conflict")
            || description.contains("busy")
            || description.contains("locked") {
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
}

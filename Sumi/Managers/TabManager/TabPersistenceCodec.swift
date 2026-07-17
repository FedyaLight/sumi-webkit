import Foundation
import SumiDomain

struct DecodedSplitGroupArchive {
    let groups: [SumiDomain.SplitGroup]
    let discardedEntryCount: Int
}

private struct SplitGroupArchiveV2: Encodable {
    static let schemaVersion = 2

    let groups: [SumiDomain.SplitGroup]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case groups
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .schemaVersion)
        try container.encode(groups, forKey: .groups)
    }
}

private struct SplitGroupArchivePayload: Decodable {
    let groups: [SumiDomain.SplitGroup]
    let discardedEntryCount: Int

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case groups
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(
            Int.self,
            forKey: .schemaVersion
        )
        guard schemaVersion == SplitGroupArchiveV2.schemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription:
                    "Unsupported split group archive schema version \(schemaVersion)."
            )
        }
        let decodedGroups = try container.decode(
            LossySplitGroupArray.self,
            forKey: .groups
        )
        groups = decodedGroups.groups
        discardedEntryCount = decodedGroups.discardedEntryCount
    }
}

/// Advances through the archive one complete JSON value at a time, so a
/// malformed group cannot make its valid siblings unreadable. `SplitGroup`'s
/// decoder remains the per-entry domain validator.
private struct LossySplitGroupArray: Decodable {
    let groups: [SumiDomain.SplitGroup]
    let discardedEntryCount: Int

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var groups: [SumiDomain.SplitGroup] = []
        var discardedEntryCount = 0

        while !container.isAtEnd {
            let entryDecoder = try container.superDecoder()
            do {
                groups.append(
                    try SumiDomain.SplitGroup(from: entryDecoder)
                )
            } catch {
                discardedEntryCount += 1
            }
        }

        self.groups = groups
        self.discardedEntryCount = discardedEntryCount
    }
}

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

    func encodeSplitGroups(
        _ splitGroups: [SumiDomain.SplitGroup]
    ) throws -> Data {
        let encoder = JSONEncoder()
        #if DEBUG
        encoder.outputFormatting = [.sortedKeys]
        #endif
        return try encoder.encode(
            SplitGroupArchiveV2(
                groups: SumiDomain.SplitGroup.sanitized(splitGroups)
            )
        )
    }

    func decodeSplitGroupArchive(
        from data: Data
    ) throws -> DecodedSplitGroupArchive {
        let payload = try JSONDecoder().decode(
            SplitGroupArchivePayload.self,
            from: data
        )
        return DecodedSplitGroupArchive(
            groups: payload.groups,
            discardedEntryCount: payload.discardedEntryCount
        )
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

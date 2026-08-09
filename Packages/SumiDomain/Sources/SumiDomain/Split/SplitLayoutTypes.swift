import Foundation

public enum SplitAxis: String, Codable, Hashable, Sendable {
    case row
    case column
}

public enum SplitLayoutKind: String, Codable, CaseIterable, Hashable, Sendable {
    case grid
    case vertical
    case horizontal

    public var primaryAxis: SplitAxis {
        switch self {
        case .grid, .vertical:
            return .row
        case .horizontal:
            return .column
        }
    }
}

public enum SplitDropSide: String, Codable, Hashable, Sendable {
    case left
    case right
    case top
    case bottom
    case center

    public var insertionAxis: SplitAxis? {
        switch self {
        case .left, .right:
            return .row
        case .top, .bottom:
            return .column
        case .center:
            return nil
        }
    }

    public var insertsBeforeTarget: Bool {
        self == .left || self == .top
    }
}

/// Durable placement of a split group in the browser's shared structure.
public enum SplitGroupContainer: Hashable, Sendable {
    case regularTabs(spaceId: UUID?)
    case favoriteSidebar(profileId: UUID?, index: Int?)
    case shortcutSidebar(
        spaceId: UUID,
        profileId: UUID?,
        folderId: UUID?,
        index: Int?
    )

    private enum CodingKeys: String, CodingKey {
        case kind
        case spaceId
        case profileId
        case folderId
        case index
    }

    private enum Kind: String, Codable {
        case regularTabs
        case favoriteSidebar
        case shortcutSidebar

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if value == "essentialSidebar" {
                self = .favoriteSidebar
                return
            }
            guard let kind = Self(rawValue: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported split group container: \(value)"
                )
            }
            self = kind
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    public var spaceId: UUID? {
        switch self {
        case .regularTabs(let spaceId):
            return spaceId
        case .favoriteSidebar:
            return nil
        case .shortcutSidebar(let spaceId, _, _, _):
            return spaceId
        }
    }

    public var isShortcutSidebar: Bool {
        switch self {
        case .shortcutSidebar, .favoriteSidebar:
            return true
        case .regularTabs:
            return false
        }
    }

    public var shortcutSidebarFolderId: UUID? {
        guard case .shortcutSidebar(_, _, let folderId, _) = self else {
            return nil
        }
        return folderId
    }

    public var shortcutSidebarIndex: Int? {
        guard case .shortcutSidebar(_, _, _, let index) = self else {
            return nil
        }
        return index
    }
}

extension SplitGroupContainer: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .regularTabs:
            self = .regularTabs(
                spaceId: try container.decodeIfPresent(UUID.self, forKey: .spaceId)
            )
        case .favoriteSidebar:
            self = .favoriteSidebar(
                profileId: try container.decodeIfPresent(UUID.self, forKey: .profileId),
                index: try container.decodeIfPresent(Int.self, forKey: .index)
            )
        case .shortcutSidebar:
            self = .shortcutSidebar(
                spaceId: try container.decode(UUID.self, forKey: .spaceId),
                profileId: try container.decodeIfPresent(UUID.self, forKey: .profileId),
                folderId: try container.decodeIfPresent(UUID.self, forKey: .folderId),
                index: try container.decodeIfPresent(Int.self, forKey: .index)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .regularTabs(let spaceId):
            try container.encode(Kind.regularTabs, forKey: .kind)
            try container.encodeIfPresent(spaceId, forKey: .spaceId)
        case .favoriteSidebar(let profileId, let index):
            try container.encode(Kind.favoriteSidebar, forKey: .kind)
            try container.encodeIfPresent(profileId, forKey: .profileId)
            try container.encodeIfPresent(index, forKey: .index)
        case .shortcutSidebar(let spaceId, let profileId, let folderId, let index):
            try container.encode(Kind.shortcutSidebar, forKey: .kind)
            try container.encode(spaceId, forKey: .spaceId)
            try container.encodeIfPresent(profileId, forKey: .profileId)
            try container.encodeIfPresent(folderId, forKey: .folderId)
            try container.encodeIfPresent(index, forKey: .index)
        }
    }
}

import Foundation

/// Stable identity stored in a split layout.
///
/// A shortcut member is identified by its durable pin, never by a
/// window-local live tab created to present that pin.
public enum SplitMemberID: Hashable, Sendable {
    case regularTab(UUID)
    case shortcutPin(UUID)

    private enum CodingKeys: String, CodingKey {
        case kind
        case id
    }

    private enum Kind: String, Codable {
        case regularTab
        case shortcutPin
    }
}

extension SplitMemberID: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let id = try container.decode(UUID.self, forKey: .id)
        switch kind {
        case .regularTab:
            self = .regularTab(id)
        case .shortcutPin:
            self = .shortcutPin(id)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .regularTab(let id):
            try container.encode(Kind.regularTab, forKey: .kind)
            try container.encode(id, forKey: .id)
        case .shortcutPin(let id):
            try container.encode(Kind.shortcutPin, forKey: .kind)
            try container.encode(id, forKey: .id)
        }
    }
}

/// Durable launcher placement restored when a shortcut leaves a split group.
public enum SplitShortcutReturnPlacement: Hashable, Sendable {
    case essential(profileId: UUID?, index: Int)
    case spacePinned(spaceId: UUID, folderId: UUID?, index: Int)
    case generatedSpacePinnedFromRegular(spaceId: UUID, index: Int)

    private enum CodingKeys: String, CodingKey {
        case kind
        case profileId
        case spaceId
        case folderId
        case index
    }

    private enum Kind: String, Codable {
        case essential
        case spacePinned
        case generatedSpacePinnedFromRegular
    }
}

extension SplitShortcutReturnPlacement: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .essential:
            self = .essential(
                profileId: try container.decodeIfPresent(UUID.self, forKey: .profileId),
                index: try container.decode(Int.self, forKey: .index)
            )
        case .spacePinned:
            self = .spacePinned(
                spaceId: try container.decode(UUID.self, forKey: .spaceId),
                folderId: try container.decodeIfPresent(UUID.self, forKey: .folderId),
                index: try container.decode(Int.self, forKey: .index)
            )
        case .generatedSpacePinnedFromRegular:
            self = .generatedSpacePinnedFromRegular(
                spaceId: try container.decode(UUID.self, forKey: .spaceId),
                index: try container.decode(Int.self, forKey: .index)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .essential(let profileId, let index):
            try container.encode(Kind.essential, forKey: .kind)
            try container.encodeIfPresent(profileId, forKey: .profileId)
            try container.encode(index, forKey: .index)
        case .spacePinned(let spaceId, let folderId, let index):
            try container.encode(Kind.spacePinned, forKey: .kind)
            try container.encode(spaceId, forKey: .spaceId)
            try container.encodeIfPresent(folderId, forKey: .folderId)
            try container.encode(index, forKey: .index)
        case .generatedSpacePinnedFromRegular(let spaceId, let index):
            try container.encode(Kind.generatedSpacePinnedFromRegular, forKey: .kind)
            try container.encode(spaceId, forKey: .spaceId)
            try container.encode(index, forKey: .index)
        }
    }
}

/// One durable split leaf and the metadata needed to restore it.
public struct SplitMember: Codable, Hashable, Sendable {
    public let memberID: SplitMemberID
    public let returnPlacement: SplitShortcutReturnPlacement?

    private enum CodingKeys: String, CodingKey {
        case memberID
        case returnPlacement
    }

    public init?(
        memberID: SplitMemberID,
        returnPlacement: SplitShortcutReturnPlacement?
    ) {
        switch memberID {
        case .regularTab:
            guard returnPlacement == nil else { return nil }
        case .shortcutPin:
            guard returnPlacement != nil else { return nil }
        }
        self.init(
            validatedMemberID: memberID,
            returnPlacement: returnPlacement
        )
    }

    public static func regularTab(_ id: UUID) -> SplitMember {
        SplitMember(
            validatedMemberID: .regularTab(id),
            returnPlacement: nil
        )
    }

    public static func shortcutPin(
        _ id: UUID,
        returnPlacement: SplitShortcutReturnPlacement
    ) -> SplitMember {
        SplitMember(
            validatedMemberID: .shortcutPin(id),
            returnPlacement: returnPlacement
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let memberID = try container.decode(SplitMemberID.self, forKey: .memberID)
        let returnPlacement = try container.decodeIfPresent(
            SplitShortcutReturnPlacement.self,
            forKey: .returnPlacement
        )
        guard let member = SplitMember(
            memberID: memberID,
            returnPlacement: returnPlacement
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .returnPlacement,
                in: container,
                debugDescription: "Regular split members cannot have a shortcut return placement, and shortcut members require one."
            )
        }
        self = member
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(memberID, forKey: .memberID)
        try container.encodeIfPresent(returnPlacement, forKey: .returnPlacement)
    }

    private init(
        validatedMemberID: SplitMemberID,
        returnPlacement: SplitShortcutReturnPlacement?
    ) {
        memberID = validatedMemberID
        self.returnPlacement = returnPlacement
    }
}

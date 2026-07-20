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

public extension SplitMemberID {
    /// The split tree stores typed member identity directly. This spelling is
    /// retained as a convenience for call sites that operate on layout leaves.
    var memberID: SplitMemberID { self }

    var isShortcutPin: Bool {
        if case .shortcutPin = self { return true }
        return false
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

/// A split leaf is only a durable identity. Placement belongs to the actual
/// tab or launcher collection that owns the group.
public typealias SplitMember = SplitMemberID

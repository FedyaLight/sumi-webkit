import Foundation

struct ExtensionRuntimeResidencyState {
    struct ScopedKey: Hashable {
        let profileId: UUID
        let extensionId: String

        var rawValue: String {
            "\(profileId.uuidString):\(extensionId)"
        }

        init(profileId: UUID, extensionId: String) {
            self.profileId = profileId
            self.extensionId = extensionId
        }

        init?(rawValue: String) {
            let parts = rawValue.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  let profileId = UUID(uuidString: String(parts[0]))
            else {
                return nil
            }
            self.profileId = profileId
            self.extensionId = String(parts[1])
        }
    }

    private(set) var liveContextKeys: [ScopedKey] = []

    static func scopedKey(extensionId: String, profileId: UUID) -> String {
        ScopedKey(profileId: profileId, extensionId: extensionId).rawValue
    }

    static func parseScopedKey(_ rawValue: String) -> ScopedKey? {
        ScopedKey(rawValue: rawValue)
    }

    mutating func touch(extensionId: String, profileId: UUID) {
        touch(ScopedKey(profileId: profileId, extensionId: extensionId))
    }

    mutating func remove(extensionId: String, profileId: UUID) {
        remove(ScopedKey(profileId: profileId, extensionId: extensionId))
    }

    mutating func remove(extensionId: String) {
        liveContextKeys.removeAll { $0.extensionId == extensionId }
    }

    mutating func removeAll() {
        liveContextKeys.removeAll()
    }

    mutating func touchAndEvictionCandidates(
        loadedContextCount: Int,
        limit: Int,
        keepingExtensionId: String,
        keepingProfileId: UUID
    ) -> [ScopedKey] {
        let keepKey = ScopedKey(
            profileId: keepingProfileId,
            extensionId: keepingExtensionId
        )
        touch(keepKey)

        guard loadedContextCount > limit else { return [] }

        return Array(
            liveContextKeys
                .lazy
                .filter { $0 != keepKey }
                .prefix(loadedContextCount - limit)
        )
    }

    private mutating func touch(_ key: ScopedKey) {
        remove(key)
        liveContextKeys.append(key)
    }

    private mutating func remove(_ key: ScopedKey) {
        liveContextKeys.removeAll { $0 == key }
    }
}

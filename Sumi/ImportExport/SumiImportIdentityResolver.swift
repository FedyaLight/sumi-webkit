import CryptoKit
import Foundation

struct SumiImportIdentityResolver {
    enum EntityKind: String {
        case profile
        case space
        case folder
        case essential
        case pinnedLauncher
        case regularTab
        case demotedEssential
    }

    let sourceKind: SumiImportSourceKind
    let mode: SumiImportApplyMode
    let importsProfiles: Bool
    let importsSpaces: Bool
    let importsFolders: Bool
    let fallbackProfileId: String?
    let fallbackSpaceId: String?

    func profileId(_ source: String) -> String {
        importsProfiles ? importedId(.profile, source: source) : fallbackProfileId ?? fallbackId(.profile)
    }

    func spaceId(_ source: String) -> String {
        importsSpaces ? importedId(.space, source: source) : fallbackSpaceId ?? fallbackId(.space)
    }

    func folderId(_ source: String) -> String? {
        importsFolders ? importedId(.folder, source: source) : nil
    }

    func importedId(_ kind: EntityKind, source: String) -> String {
        if mode == .replace, let uuid = UUID(uuidString: source) {
            return uuid.uuidString
        }
        return deterministicUUID(kind: kind, source: source).uuidString
    }

    func fallbackId(_ kind: EntityKind) -> String {
        deterministicUUID(kind: kind, source: "fallback").uuidString
    }

    private func deterministicUUID(kind: EntityKind, source: String) -> UUID {
        let identity = "com.sumi.import|\(sourceKind.rawValue)|\(kind.rawValue)|\(source)"
        var bytes = Array(SHA256.hash(data: Data(identity.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

import Foundation

struct SumiMozillaContainerIdentity: Equatable, Sendable {
    var id: Int
    var name: String
}

/// Reads the user-facing contextual identities shared by Firefox and Zen.
///
/// Cookie databases are intentionally not consulted here. `containers.json`
/// owns container identity; scanning `cookies.sqlite` as well duplicated I/O
/// and made profile discovery depend on whether a container happened to have a
/// surviving cookie.
enum SumiMozillaContainerCatalog {
    static func read(profileURL: URL) throws -> [SumiMozillaContainerIdentity] {
        let data = try Data(
            contentsOf: profileURL.appendingPathComponent("containers.json")
        )
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let identities = root["identities"] as? [[String: Any]]
        else {
            throw SumiImportExportError.unsupportedFile(
                "containers.json does not contain contextual identities."
            )
        }

        return identities.compactMap { identity in
            guard let id = identity["userContextId"] as? Int,
                  id > 0,
                  id < 1_000_000,
                  identity["public"] as? Bool != false
            else {
                return nil
            }
            let localizationID = (identity["l10nID"] as? String)
                ?? (identity["l10nId"] as? String)
            guard localizationID?.hasPrefix("userContextIdInternal") != true else {
                return nil
            }
            return SumiMozillaContainerIdentity(
                id: id,
                name: SumiImportTextNormalization.mozillaContainerName(
                    name: identity["name"] as? String,
                    localizationID: localizationID,
                    fallback: "Container \(id)"
                )
            )
        }
        .sorted { $0.id < $1.id }
    }
}

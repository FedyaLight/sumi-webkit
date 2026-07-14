import Foundation
import SumiDomain

enum GeneralSearchEngineMutation {
    static func upserting(
        _ engine: SumiSearchEngine,
        in engines: [SumiSearchEngine]
    ) -> [SumiSearchEngine] {
        var updated = engines
        if let index = updated.firstIndex(where: { $0.id == engine.id }) {
            updated[index] = engine
        } else {
            updated.append(engine)
        }
        return updated
    }

    static func settingTabSearch(
        _ isEnabled: Bool,
        for engineID: String,
        in engines: [SumiSearchEngine]
    ) -> [SumiSearchEngine] {
        guard let index = engines.firstIndex(where: { $0.id == engineID }) else {
            return engines
        }

        var updated = engines
        updated[index].tabSearchEnabled = isEnabled
        return updated
    }

    static func removing(
        engineID: String,
        from engines: [SumiSearchEngine]
    ) -> [SumiSearchEngine]? {
        guard engines.count > 1,
              engines.contains(where: { $0.id == engineID })
        else {
            return nil
        }

        return engines.filter { $0.id != engineID }
    }

    static func moving(
        _ move: ReorderMove<String>,
        in engines: [SumiSearchEngine]
    ) -> [SumiSearchEngine] {
        var updated = engines
        guard let sourceIndex = updated.firstIndex(where: { $0.id == move.id }) else {
            return engines
        }

        let moved = updated.remove(at: sourceIndex)
        let targetIndex = min(max(move.targetIndex, 0), updated.count)
        updated.insert(moved, at: targetIndex)
        return updated
    }
}

struct SearchEngineEditorInput: Equatable {
    let engineID: String?
    let name: String
    let domain: String
    let searchURLTemplate: String
    let colorHex: String
    let tabSearchEnabled: Bool

    var validationMessage: String? {
        guard !trimmedName.isEmpty else { return "Name is required." }
        guard normalizedTemplate.contains(SumiSearchEngine.queryToken) else {
            return "Search URL must contain {query} where the query should go."
        }
        guard let sampleURL,
              let scheme = sampleURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              sampleURL.host?.isEmpty == false
        else {
            return "Enter a valid http or https search URL."
        }
        guard !resolvedDomain.isEmpty else { return "Domain is required." }
        return nil
    }

    var previewURLString: String? {
        guard validationMessage == nil else { return nil }
        return engine(id: engineID ?? "preview")?
            .searchURL(for: "sumi browser")?
            .absoluteString
    }

    func engine(id: String) -> SumiSearchEngine? {
        guard validationMessage == nil else { return nil }
        return SumiSearchEngine(
            id: id,
            name: trimmedName,
            domain: resolvedDomain,
            searchURLTemplate: normalizedTemplate,
            colorHex: colorHex,
            tabSearchEnabled: tabSearchEnabled
        )
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDomain: String {
        domain.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedTemplate: String {
        SumiSearchEngine.normalizedTemplate(searchURLTemplate)
    }

    private var sampleURL: URL? {
        let template = SumiURLNormalization.normalizedSearchEngineTemplate(normalizedTemplate)
        let sampleString = template.replacingOccurrences(
            of: SumiSearchEngine.queryToken,
            with: "sumi"
        )
        return URL(string: sampleString)
    }

    private var resolvedDomain: String {
        trimmedDomain.isEmpty ? sampleURL?.host ?? "" : trimmedDomain
    }
}

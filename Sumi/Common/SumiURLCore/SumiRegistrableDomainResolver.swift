import Foundation
import URLPredictor

protocol SumiRegistrableDomainResolving {
    func registrableDomain(forHost host: String?) -> String?
}

struct SumiRegistrableDomainResolver: SumiRegistrableDomainResolving {
    private static let publicSuffixes: Set<String> = {
        guard let pslString = try? Classifier.getPSLData() else { return [] }

        var suffixes: [String] = []
        pslString.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("//") else { return }
            suffixes.append(trimmed)
        }
        return Set(suffixes)
    }()

    init() {}

    func registrableDomain(forHost host: String?) -> String? {
        guard let domain = domain(host), !Self.publicSuffixes.contains(domain) else { return nil }
        return domain
    }

    private func domain(_ host: String?) -> String? {
        guard let host else { return nil }

        let parts = host.components(separatedBy: ".").reversed()
        var stack = ""
        var knownSuffixFound = false

        for part in parts {
            stack = stack.isEmpty ? part : part + "." + stack
            if Self.publicSuffixes.contains(stack) {
                knownSuffixFound = true
            } else if knownSuffixFound {
                break
            }
        }

        return knownSuffixFound ? stack : nil
    }
}

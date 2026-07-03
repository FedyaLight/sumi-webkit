import Foundation
import URLPredictor

/// Single app-side adapter over the vendored DDG URLPredictor package.
enum SumiURLClassifier {
    enum Decision: Equatable {
        case navigate(URL)
        case search(String)
    }

    static func classify(_ input: String) -> Decision? {
        do {
            switch try Classifier.classify(input: input) {
            case .navigate(let url):
                return .navigate(url)
            case .search(let query):
                return .search(query)
            }
        } catch {
            RuntimeDiagnostics.debug(
                "URLPredictor failed to classify input: \(error.localizedDescription)",
                category: "URLClassifier"
            )
            return nil
        }
    }

    static func publicSuffixList() -> String? {
        do {
            return try Classifier.getPSLData()
        } catch {
            RuntimeDiagnostics.debug(
                "URLPredictor failed to load Public Suffix List: \(error.localizedDescription)",
                category: "URLClassifier"
            )
            return nil
        }
    }
}

protocol SumiRegistrableDomainResolving: Sendable {
    func registrableDomain(forHost host: String?) -> String?
}

struct SumiRegistrableDomainResolver: SumiRegistrableDomainResolving {
    private static let publicSuffixes: Set<String> = {
        guard let pslString = SumiURLClassifier.publicSuffixList() else { return [] }

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

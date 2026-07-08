import Foundation

/// Single app-side facade for omnibar URL-vs-search classification.
enum SumiURLClassifier {
    enum Decision: Equatable {
        case navigate(URL)
        case search(String)
    }

    /// Typing in the omnibar re-classifies the same input several times per
    /// keystroke (suggestions + normalization); remember the last decision.
    private static let memo = SumiLastDecisionMemo()

    static func classify(_ input: String) -> Decision? {
        if let cached = memo.decision(for: input) {
            return cached
        }

        let decision: Decision
        switch SumiAddressBarClassifier.classify(input) {
        case .navigate(let url):
            decision = .navigate(url)
        case .search(let query):
            decision = .search(query)
        }
        memo.remember(input: input, decision: decision)
        return decision
    }
}

private final class SumiLastDecisionMemo: @unchecked Sendable {
    private let lock = NSLock()
    private var entry: (input: String, decision: SumiURLClassifier.Decision)?

    func decision(for input: String) -> SumiURLClassifier.Decision? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry, entry.input == input else { return nil }
        return entry.decision
    }

    func remember(input: String, decision: SumiURLClassifier.Decision) {
        lock.lock()
        entry = (input, decision)
        lock.unlock()
    }
}

protocol SumiRegistrableDomainResolving: Sendable {
    func registrableDomain(forHost host: String?) -> String?
}

struct SumiRegistrableDomainResolver: SumiRegistrableDomainResolving {
    init() {}

    func registrableDomain(forHost host: String?) -> String? {
        SumiPublicSuffixList.bundled.registrableDomain(forHost: host)
    }
}

import Foundation

/// Canonical deterministic entry point for omnibar URL-vs-search classification.
public enum SumiURLClassifier {
    public enum Decision: Equatable {
        case navigate(URL)
        case search(String)
    }

    /// Typing in the omnibar re-classifies the same input several times per
    /// keystroke (suggestions + normalization); remember the last decision.
    private static let memo = SumiLastDecisionMemo()

    public static func classify(_ input: String) -> Decision? {
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

/// A one-entry, lock-protected implementation cache for a deterministic pure
/// classifier. The cache is bounded and output-transparent: reference identity
/// can only avoid recomputation and can never change the classification result.
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

public protocol SumiRegistrableDomainResolving: Sendable {
    func registrableDomain(forHost host: String?) -> String?
}

public struct SumiRegistrableDomainResolver: SumiRegistrableDomainResolving {
    public init() {}

    public func registrableDomain(forHost host: String?) -> String? {
        SumiPublicSuffixList.bundled.registrableDomain(forHost: host)
    }
}

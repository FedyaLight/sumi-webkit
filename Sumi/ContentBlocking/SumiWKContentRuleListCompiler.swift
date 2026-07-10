import Foundation
import WebKit

protocol SumiContentRuleListCompiling: AnyObject, Sendable {
    @MainActor
    func lookUpContentRuleList(forIdentifier identifier: String) async -> WKContentRuleList?

    @MainActor
    func canLookUpContentRuleList(forIdentifier identifier: String) async -> Bool

    @MainActor
    func compileContentRuleList(
        forIdentifier identifier: String,
        encodedContentRuleList: String
    ) async throws -> WKContentRuleList

    @MainActor
    func availableContentRuleListIdentifiers() async -> [String]

    @MainActor
    func removeContentRuleList(forIdentifier identifier: String) async throws
}

/// The only adapter in this pipeline that talks directly to
/// `WKContentRuleListStore`.
final class SumiWKContentRuleListCompiler:
    SumiContentRuleListCompiling,
    @unchecked Sendable
{
    private let storeOverride: WKContentRuleListStore?

    init(store: WKContentRuleListStore? = nil) {
        storeOverride = store
    }

    @MainActor
    func lookUpContentRuleList(
        forIdentifier identifier: String
    ) async -> WKContentRuleList? {
        let store = store
        return await withCheckedContinuation { continuation in
            store.lookUpContentRuleList(forIdentifier: identifier) { ruleList, _ in
                continuation.resume(returning: ruleList)
            }
        }
    }

    @MainActor
    func canLookUpContentRuleList(forIdentifier identifier: String) async -> Bool {
        await lookUpContentRuleList(forIdentifier: identifier) != nil
    }

    @MainActor
    func compileContentRuleList(
        forIdentifier identifier: String,
        encodedContentRuleList: String
    ) async throws -> WKContentRuleList {
        let store = store
        return try await withCheckedThrowingContinuation { continuation in
            store.compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: encodedContentRuleList
            ) { ruleList, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let ruleList {
                    continuation.resume(returning: ruleList)
                } else {
                    continuation.resume(
                        throwing: SumiContentBlockingCompilationError
                            .missingCompiledRuleList(identifier)
                    )
                }
            }
        }
    }

    @MainActor
    func availableContentRuleListIdentifiers() async -> [String] {
        let store = store
        return await withCheckedContinuation { continuation in
            store.getAvailableContentRuleListIdentifiers { identifiers in
                continuation.resume(returning: identifiers ?? [])
            }
        }
    }

    @MainActor
    func removeContentRuleList(forIdentifier identifier: String) async throws {
        let store = store
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            store.removeContentRuleList(forIdentifier: identifier) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    @MainActor
    private var store: WKContentRuleListStore {
        storeOverride ?? Self.defaultStore()
    }

    @MainActor
    private static func defaultStore() -> WKContentRuleListStore {
        #if DEBUG
            if let testStore = xctestProcessIsolatedStore() {
                return testStore
            }
        #endif
        return WKContentRuleListStore.default()
    }

    #if DEBUG
        @MainActor
        private static func xctestProcessIsolatedStore() -> WKContentRuleListStore? {
            let environment = ProcessInfo.processInfo.environment
            guard environment["XCTestConfigurationFilePath"] != nil else {
                return nil
            }
            let storeURL = URL(
                fileURLWithPath: NSTemporaryDirectory(),
                isDirectory: true
            )
            .appendingPathComponent(
                "SumiContentRuleListStore-XCTest",
                isDirectory: true
            )
            .appendingPathComponent(
                "\(ProcessInfo.processInfo.processIdentifier)",
                isDirectory: true
            )
            do {
                try FileManager.default.createDirectory(
                    at: storeURL,
                    withIntermediateDirectories: true
                )
            } catch {
                RuntimeDiagnostics.debug(category: "SafariContentBlocker") {
                    "Could not create isolated XCTest content rule list store: \(error.localizedDescription)"
                }
                return nil
            }
            return WKContentRuleListStore(url: storeURL)
        }
    #endif
}

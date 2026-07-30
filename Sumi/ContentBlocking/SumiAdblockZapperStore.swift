import Foundation
import OSLog
import SumiDomain
import WebKit

@MainActor
final class SumiAdblockZapperStore {
    private static let log = Logger.sumi(category: "ContentBlocking")
    private static let documentKey = "adblock.zapper-states"

    struct State: Codable, Equatable {
        var rules: [String]
        var disabled: Bool

        static let empty = State(rules: [], disabled: false)
    }

    private struct Scope {
        static let persistentPrefix = "persistent:"
        static let ephemeralPrefix = "ephemeral:"

        let storageKey: String
        let isEphemeral: Bool

        init?(
            profilePartitionId: String,
            isEphemeralProfile: Bool
        ) {
            let normalizedProfileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
            guard !normalizedProfileId.isEmpty else { return nil }

            self.storageKey = "\(isEphemeralProfile ? Self.ephemeralPrefix : Self.persistentPrefix)\(normalizedProfileId)"
            self.isEphemeral = isEphemeralProfile
        }
    }

    private let database: SumiDatabase?
    private let profileReferenceAdmission: ProfileReferenceAdmissionLedger
    private var statesByScopeAndHost: [String: [String: State]]
    private let persistentStateWasReadable: Bool
    private var retiredPersistentProfileIDs: Set<String> = []

    init(
        database: SumiDatabase? = nil,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger =
            .failClosed()
    ) {
        self.database = database
        self.profileReferenceAdmission = profileReferenceAdmission
        let loaded = Self.loadPersistentStates(from: database)
        self.statesByScopeAndHost = loaded.states
        self.persistentStateWasReadable = loaded.wasReadable
    }

    func state(
        forHost host: String,
        profilePartitionId: String,
        isEphemeralProfile: Bool
    ) -> State {
        guard let scope = Scope(
            profilePartitionId: profilePartitionId,
            isEphemeralProfile: isEphemeralProfile
        ) else {
            return .empty
        }
        guard acceptsReference(
            profilePartitionId: profilePartitionId,
            isEphemeralProfile: isEphemeralProfile
        ) else { return .empty }

        let normalizedHost = normalizedHost(host)
        guard !normalizedHost.isEmpty else { return .empty }
        return statesByScopeAndHost[scope.storageKey]?[normalizedHost] ?? .empty
    }

    func setRules(
        _ rules: [String],
        forHost host: String,
        profilePartitionId: String,
        isEphemeralProfile: Bool
    ) {
        updateState(
            forHost: host,
            profilePartitionId: profilePartitionId,
            isEphemeralProfile: isEphemeralProfile
        ) { state in
            state.rules = Self.normalizedRules(rules)
        }
    }

    func appendRule(
        _ rule: String,
        forHost host: String,
        profilePartitionId: String,
        isEphemeralProfile: Bool
    ) {
        let normalizedRule = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRule.isEmpty else { return }
        updateState(
            forHost: host,
            profilePartitionId: profilePartitionId,
            isEphemeralProfile: isEphemeralProfile
        ) { state in
            guard !state.rules.contains(normalizedRule) else { return }
            state.rules.append(normalizedRule)
        }
    }

    func setEnabled(
        _ isEnabled: Bool,
        forHost host: String,
        profilePartitionId: String,
        isEphemeralProfile: Bool
    ) {
        updateState(
            forHost: host,
            profilePartitionId: profilePartitionId,
            isEphemeralProfile: isEphemeralProfile
        ) { state in
            state.disabled = !isEnabled
        }
    }

    func deleteProfileData(profileID: UUID) throws {
        retiredPersistentProfileIDs.insert(
            SumiPermissionKey.normalizedProfilePartitionId(profileID.uuidString)
        )
        guard persistentStateWasReadable else {
            throw SumiAdblockZapperStoreError.unreadablePersistentState
        }
        guard let scope = Scope(
            profilePartitionId: profileID.uuidString,
            isEphemeralProfile: false
        ), statesByScopeAndHost[scope.storageKey] != nil else {
            return
        }
        var candidate = statesByScopeAndHost
        candidate.removeValue(forKey: scope.storageKey)
        try persistForProfileCleanup(candidate)
        statesByScopeAndHost = candidate
    }

    /// Drops a private partition's in-memory Zapper state. Ephemeral scopes are
    /// never persisted, so there is nothing to write and nothing to verify.
    func discardPrivatePartition(profileID: UUID) {
        guard let scope = Scope(
            profilePartitionId: profileID.uuidString,
            isEphemeralProfile: true
        ) else {
            return
        }
        statesByScopeAndHost.removeValue(forKey: scope.storageKey)
    }

    private func updateState(
        forHost host: String,
        profilePartitionId: String,
        isEphemeralProfile: Bool,
        mutate: (inout State) -> Void
    ) {
        guard let scope = Scope(
            profilePartitionId: profilePartitionId,
            isEphemeralProfile: isEphemeralProfile
        ) else {
            return
        }
        guard acceptsReference(
            profilePartitionId: profilePartitionId,
            isEphemeralProfile: isEphemeralProfile
        ) else { return }
        guard scope.isEphemeral || persistentStateWasReadable else {
            Self.log.error(
                "Rejected persistent Zapper mutation because the stored baseline is unreadable."
            )
            return
        }

        let normalizedHost = normalizedHost(host)
        guard !normalizedHost.isEmpty else { return }

        var candidate = statesByScopeAndHost
        var hostStates = candidate[scope.storageKey] ?? [:]
        var state = hostStates[normalizedHost] ?? .empty
        mutate(&state)
        if state == .empty {
            hostStates.removeValue(forKey: normalizedHost)
        } else {
            hostStates[normalizedHost] = state
        }
        if hostStates.isEmpty {
            candidate.removeValue(forKey: scope.storageKey)
        } else {
            candidate[scope.storageKey] = hostStates
        }
        if !scope.isEphemeral {
            do {
                try persistPersistentStates(candidate)
            } catch {
                Self.log.error(
                    "Failed to persist adblock zapper state: \(error.localizedDescription, privacy: .public)"
                )
                return
            }
        }
        statesByScopeAndHost = candidate
    }

    private func normalizedHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    private func acceptsReference(
        profilePartitionId: String,
        isEphemeralProfile: Bool
    ) -> Bool {
        guard isEphemeralProfile == false else { return true }
        let profileID = SumiPermissionKey.normalizedProfilePartitionId(
            profilePartitionId
        )
        guard retiredPersistentProfileIDs.contains(profileID) == false else {
            return false
        }
        guard let uuid = UUID(uuidString: profileID) else { return false }
        return profileReferenceAdmission.isReferenceAllowed(uuid)
    }

    private func persistPersistentStates(
        _ candidate: [String: [String: State]]
    ) throws {
        let persistentStates = candidate.filter { scopeKey, _ in
            scopeKey.hasPrefix(Scope.persistentPrefix)
        }
        try database?.transaction {
            if persistentStates.isEmpty {
                try $0.documents.delete(key: Self.documentKey)
            } else {
                try $0.documents.save(
                    persistentStates,
                    forKey: Self.documentKey
                )
            }
        }
    }

    private func persistForProfileCleanup(
        _ candidate: [String: [String: State]]
    ) throws {
        let persistentStates = candidate.filter { scopeKey, _ in
            scopeKey.hasPrefix(Scope.persistentPrefix)
        }
        guard let database else { return }
        do {
            try database.transaction {
                if persistentStates.isEmpty {
                    try $0.documents.delete(key: Self.documentKey)
                } else {
                    try $0.documents.save(
                        persistentStates,
                        forKey: Self.documentKey
                    )
                }
            }
        } catch {
            throw SumiAdblockZapperStoreError.persistenceVerificationFailed
        }
    }

    private static func loadPersistentStates(
        from database: SumiDatabase?
    ) -> (states: [String: [String: State]], wasReadable: Bool) {
        guard let database else {
            return ([:], true)
        }
        let decoded: [String: [String: State]]
        do {
            decoded = try database.read {
                try $0.documents.value(
                    [String: [String: State]].self,
                    forKey: documentKey
                )
            } ?? [:]
        } catch {
            log.error("Failed to decode adblock zapper state: \(error.localizedDescription, privacy: .public)")
            return ([:], false)
        }
        return (decoded.filter { scopeKey, _ in
            scopeKey.hasPrefix(Scope.persistentPrefix)
        }, true)
    }

    private static func normalizedRules(_ rules: [String]) -> [String] {
        var seen = Set<String>()
        return rules.compactMap { rule in
            let trimmedRule = rule.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedRule.isEmpty,
                  seen.insert(trimmedRule).inserted
            else {
                return nil
            }
            return trimmedRule
        }
    }
}

enum SumiAdblockZapperStoreError: Error, Equatable {
    case unreadablePersistentState
    case persistenceVerificationFailed
}

@MainActor
enum SumiAdblockZapperInjector {
    private static let log = Logger.sumi(category: "ContentBlocking")
    private static let styleElementID = "sumi-adblock-zapper-style"

    // Web views whose current document may contain zapper styles/attributes.
    // Lets the common no-rules case skip the per-navigation JavaScript
    // round-trip entirely; an empty apply/clear only runs as cleanup after a
    // non-empty apply.
    private static let webViewsWithAppliedRules = NSMapTable<WKWebView, NSNumber>
        .weakToStrongObjects()

    // Test seam: replaced in unit tests to observe evaluations without a
    // live web content process.
    static var evaluateScript: (WKWebView, String) -> Void = { webView, script in
        webView.evaluateJavaScript(script) { _, _ in }
    }

    static func resetForTesting() {
        webViewsWithAppliedRules.removeAllObjects()
        evaluateScript = { webView, script in
            webView.evaluateJavaScript(script) { _, _ in }
        }
    }

    static func applySavedRules(
        to webView: WKWebView,
        host: String,
        profilePartitionId: String,
        isEphemeralProfile: Bool,
        store: SumiAdblockZapperStore
    ) {
        let state = store.state(
            forHost: host,
            profilePartitionId: profilePartitionId,
            isEphemeralProfile: isEphemeralProfile
        )
        let rules = state.disabled ? [] : state.rules
        if rules.isEmpty {
            clearAppliedRules(to: webView)
            return
        }
        webViewsWithAppliedRules.setObject(NSNumber(value: true), forKey: webView)
        evaluateScript(webView, applyRulesScript(rules: rules))
    }

    static func clearAppliedRules(to webView: WKWebView) {
        guard webViewsWithAppliedRules.object(forKey: webView)?.boolValue == true else {
            return
        }
        webViewsWithAppliedRules.removeObject(forKey: webView)
        evaluateScript(webView, applyRulesScript(rules: []))
    }

    static func activateElementPicker(
        in webView: WKWebView,
        host: String,
        profilePartitionId: String,
        isEphemeralProfile: Bool,
        store: SumiAdblockZapperStore
    ) async -> Bool {
        let session = SumiElementZapperSession(
            webView: webView,
            configuration: .contentBlocker,
            onSelected: { selector in
                store.appendRule(
                    selector,
                    forHost: host,
                    profilePartitionId: profilePartitionId,
                    isEphemeralProfile: isEphemeralProfile
                )
                SumiAdblockZapperInjector.applySavedRules(
                    to: webView,
                    host: host,
                    profilePartitionId: profilePartitionId,
                    isEphemeralProfile: isEphemeralProfile,
                    store: store
                )
            }
        )
        return await session.start()
    }

    fileprivate static func applyRulesScript(rules: [String]) -> String {
        let rulesLiteral = jsonLiteral(rules)
        return #"""
        (() => {
            const id = "\#(styleElementID)";
            const selectors = \#(rulesLiteral);
            const hiddenSelector = "[data-sumi-adblock-zapper-hidden]";
            function restoreInlineHides() {
                document.querySelectorAll(hiddenSelector).forEach((element) => {
                    const previousDisplay = element.getAttribute("data-sumi-adblock-zapper-display-value");
                    const previousPriority = element.getAttribute("data-sumi-adblock-zapper-display-priority") || "";
                    if (previousDisplay) {
                        element.style.setProperty("display", previousDisplay, previousPriority);
                    } else {
                        element.style.removeProperty("display");
                    }
                    element.removeAttribute("data-sumi-adblock-zapper-hidden");
                    element.removeAttribute("data-sumi-adblock-zapper-display-value");
                    element.removeAttribute("data-sumi-adblock-zapper-display-priority");
                });
            }

            let style = document.getElementById(id);
            restoreInlineHides();
            if (!selectors.length) {
                if (style) { style.remove(); }
                return true;
            }
            if (!style) {
                style = document.createElement("style");
                style.id = id;
                style.setAttribute("data-sumi-adblock-zapper", "true");
                (document.head || document.documentElement).appendChild(style);
            }
            while (style.sheet && style.sheet.cssRules.length) {
                style.sheet.deleteRule(0);
            }
            for (const selector of selectors) {
                try {
                    style.sheet.insertRule(`${selector}{display:none!important}`, style.sheet.cssRules.length);
                } catch (_) {}
                try {
                    document.querySelectorAll(selector).forEach((element) => {
                        if (!element.hasAttribute("data-sumi-adblock-zapper-hidden")) {
                            element.setAttribute("data-sumi-adblock-zapper-hidden", "true");
                            element.setAttribute(
                                "data-sumi-adblock-zapper-display-value",
                                element.style.getPropertyValue("display")
                            );
                            element.setAttribute(
                                "data-sumi-adblock-zapper-display-priority",
                                element.style.getPropertyPriority("display")
                            );
                        }
                        element.style.setProperty("display", "none", "important");
                    });
                } catch (_) {}
            }
            return true;
        })();
        """#
    }

    private static func jsonLiteral<T: Encodable>(_ value: T) -> String {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            Self.log.error("Failed to encode adblock zapper JavaScript literal: \(error.localizedDescription, privacy: .public)")
            return "null"
        }
        guard let string = String(data: data, encoding: .utf8) else {
            Self.log.error("Failed to convert adblock zapper JavaScript literal to UTF-8")
            return "null"
        }
        return string
    }
}

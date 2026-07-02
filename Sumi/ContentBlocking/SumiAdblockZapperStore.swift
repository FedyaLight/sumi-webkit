import Foundation
import WebKit

@MainActor
final class SumiAdblockZapperStore {
    struct State: Codable, Equatable {
        var rules: [String]
        var disabled: Bool

        static let empty = State(rules: [], disabled: false)
    }

    static let shared = SumiAdblockZapperStore()

    private enum DefaultsKey {
        static let statesByPersistentProfileAndHost = "settings.adblock.zapper.statesByPersistentProfileAndHost.v1"
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

    private let userDefaults: UserDefaults
    private var statesByScopeAndHost: [String: [String: State]]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.statesByScopeAndHost = Self.loadPersistentStates(from: userDefaults)
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

        let normalizedHost = normalizedHost(host)
        guard !normalizedHost.isEmpty else { return }

        var hostStates = statesByScopeAndHost[scope.storageKey] ?? [:]
        var state = hostStates[normalizedHost] ?? .empty
        mutate(&state)
        if state == .empty {
            hostStates.removeValue(forKey: normalizedHost)
        } else {
            hostStates[normalizedHost] = state
        }
        if hostStates.isEmpty {
            statesByScopeAndHost.removeValue(forKey: scope.storageKey)
        } else {
            statesByScopeAndHost[scope.storageKey] = hostStates
        }
        if !scope.isEphemeral {
            savePersistentStates()
        }
    }

    private func normalizedHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    private func savePersistentStates() {
        let persistentStates = statesByScopeAndHost.filter { scopeKey, _ in
            scopeKey.hasPrefix(Scope.persistentPrefix)
        }
        guard !persistentStates.isEmpty else {
            userDefaults.removeObject(forKey: DefaultsKey.statesByPersistentProfileAndHost)
            return
        }
        guard let data = try? JSONEncoder().encode(persistentStates) else { return }
        userDefaults.set(data, forKey: DefaultsKey.statesByPersistentProfileAndHost)
    }

    private static func loadPersistentStates(from userDefaults: UserDefaults) -> [String: [String: State]] {
        guard let data = userDefaults.data(forKey: DefaultsKey.statesByPersistentProfileAndHost),
              let decoded = try? JSONDecoder().decode([String: [String: State]].self, from: data)
        else { return [:] }
        return decoded.filter { scopeKey, _ in
            scopeKey.hasPrefix(Scope.persistentPrefix)
        }
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

@MainActor
enum SumiAdblockZapperInjector {
    private static let styleElementID = "sumi-adblock-zapper-style"

    static func applySavedRules(
        to webView: WKWebView,
        host: String,
        profilePartitionId: String,
        isEphemeralProfile: Bool,
        store: SumiAdblockZapperStore? = nil
    ) {
        let store = store ?? .shared
        let state = store.state(
            forHost: host,
            profilePartitionId: profilePartitionId,
            isEphemeralProfile: isEphemeralProfile
        )
        let rules = state.disabled ? [] : state.rules
        webView.evaluateJavaScript(applyRulesScript(rules: rules)) { _, _ in }
    }

    static func clearAppliedRules(to webView: WKWebView) {
        webView.evaluateJavaScript(applyRulesScript(rules: [])) { _, _ in }
    }

    static func activateElementPicker(
        in webView: WKWebView,
        host: String,
        profilePartitionId: String,
        isEphemeralProfile: Bool,
        store: SumiAdblockZapperStore? = nil
    ) async -> Bool {
        let store = store ?? .shared
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
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8)
        else { return "null" }
        return string
    }
}

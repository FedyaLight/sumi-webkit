import WebKit

@MainActor
final class SumiNormalTabUserScripts {
    private struct UserScriptSignature: Equatable {
        let typeName: String
        let source: String
        let injectionTime: WKUserScriptInjectionTime
        let forMainFrameOnly: Bool
        let requiresRunInPageContentWorld: Bool
        let messageNames: [String]
    }

    let faviconScripts = SumiFaviconUserScripts()
    private let transientChromeInteractionShieldUserScript = SumiTransientChromeInteractionShieldUserScript()
    private var contentBlockingUserScripts: [SumiPageScript]
    private var staticManagedUserScripts: [SumiPageScript]
    private var navigationUserScripts: [SumiPageScript]
    private var staticManagedUserScriptSignature: [UserScriptSignature]
    private var navigationUserScriptSignature: [UserScriptSignature]
    private var cachedStaticUserScripts: [SumiPageScript]?
    private var cachedUserScripts: [SumiPageScript]?
    private var cachedStaticWKUserScripts: [WKUserScript]?
    private var cachedNavigationWKUserScripts: [WKUserScript]?
    private var cachedWKUserScripts: [WKUserScript]?
    private(set) var staticScriptsRevision = 0
    private(set) var scriptsRevision = 0

    init(
        contentBlockingUserScripts: [SumiPageScript] = [],
        managedUserScripts: [SumiPageScript] = []
    ) {
        self.contentBlockingUserScripts = contentBlockingUserScripts
        self.staticManagedUserScripts = []
        self.navigationUserScripts = managedUserScripts
        self.staticManagedUserScriptSignature = []
        self.navigationUserScriptSignature = Self.signature(
            for: managedUserScripts
        )
    }

    init(
        contentBlockingUserScripts: [SumiPageScript] = [],
        staticManagedUserScripts: [SumiPageScript],
        navigationUserScripts: [SumiPageScript]
    ) {
        self.contentBlockingUserScripts = contentBlockingUserScripts
        self.staticManagedUserScripts = staticManagedUserScripts
        self.navigationUserScripts = navigationUserScripts
        self.staticManagedUserScriptSignature = Self.signature(
            for: staticManagedUserScripts
        )
        self.navigationUserScriptSignature = Self.signature(
            for: navigationUserScripts
        )
    }

    var staticUserScripts: [SumiPageScript] {
        if let cachedStaticUserScripts {
            return cachedStaticUserScripts
        }

        let scripts = [transientChromeInteractionShieldUserScript]
            + contentBlockingUserScripts
            + faviconScripts.userScripts
            + staticManagedUserScripts
        cachedStaticUserScripts = scripts
        return scripts
    }

    var userScripts: [SumiPageScript] {
        if let cachedUserScripts {
            return cachedUserScripts
        }

        let scripts = staticUserScripts + navigationUserScripts
        cachedUserScripts = scripts
        return scripts
    }

    func replaceManagedUserScripts(_ userScripts: [SumiPageScript]) {
        navigationUserScripts = userScripts
        navigationUserScriptSignature = Self.signature(for: userScripts)
        cachedUserScripts = nil
        cachedNavigationWKUserScripts = nil
        cachedWKUserScripts = nil
        scriptsRevision += 1
    }

    @discardableResult
    func replaceManagedUserScriptsIfChanged(_ userScripts: [SumiPageScript]) -> Bool {
        let signature = Self.signature(for: userScripts)
        guard signature != navigationUserScriptSignature else {
            return false
        }

        navigationUserScripts = userScripts
        navigationUserScriptSignature = signature
        cachedUserScripts = nil
        cachedNavigationWKUserScripts = nil
        cachedWKUserScripts = nil
        scriptsRevision += 1
        return true
    }

    @discardableResult
    func replaceUserScriptPlanIfChanged(
        staticManagedUserScripts: [SumiPageScript],
        navigationUserScripts: [SumiPageScript]
    ) -> Bool {
        let staticSignature = Self.signature(for: staticManagedUserScripts)
        let navigationSignature = Self.signature(for: navigationUserScripts)
        let staticChanged =
            staticSignature != staticManagedUserScriptSignature
        let navigationChanged =
            navigationSignature != navigationUserScriptSignature
        guard staticChanged || navigationChanged else { return false }

        if staticChanged {
            self.staticManagedUserScripts = staticManagedUserScripts
            staticManagedUserScriptSignature = staticSignature
            cachedStaticUserScripts = nil
            cachedStaticWKUserScripts = nil
            staticScriptsRevision += 1
        }
        if navigationChanged {
            self.navigationUserScripts = navigationUserScripts
            navigationUserScriptSignature = navigationSignature
            cachedNavigationWKUserScripts = nil
            scriptsRevision += 1
        }
        cachedUserScripts = nil
        cachedWKUserScripts = nil
        return true
    }

    func loadWKUserScripts() async -> [WKUserScript] {
        preparedWKUserScripts()
    }

    func preparedWKUserScripts() -> [WKUserScript] {
        if let cachedWKUserScripts {
            return cachedWKUserScripts
        }
        let scripts = userScripts.map(SumiPageScriptBuilder.makeWKUserScript)
        cachedWKUserScripts = scripts
        return scripts
    }

    func preparedStaticWKUserScripts() -> [WKUserScript] {
        if let cachedStaticWKUserScripts {
            return cachedStaticWKUserScripts
        }
        let scripts = staticUserScripts.map(SumiPageScriptBuilder.makeWKUserScript)
        cachedStaticWKUserScripts = scripts
        return scripts
    }

    func preparedNavigationWKUserScripts() -> [WKUserScript] {
        if let cachedNavigationWKUserScripts {
            return cachedNavigationWKUserScripts
        }
        let scripts = navigationUserScripts.map(
            SumiPageScriptBuilder.makeWKUserScript
        )
        cachedNavigationWKUserScripts = scripts
        return scripts
    }

    var navigationScriptsHaveMessageHandlers: Bool {
        navigationUserScripts.contains { $0.messageNames.isEmpty == false }
    }

    private static func signature(for userScripts: [SumiPageScript]) -> [UserScriptSignature] {
        userScripts.map { userScript in
            UserScriptSignature(
                typeName: String(describing: type(of: userScript)),
                source: userScript.source,
                injectionTime: userScript.injectionTime,
                forMainFrameOnly: userScript.forMainFrameOnly,
                requiresRunInPageContentWorld: userScript.requiresRunInPageContentWorld,
                messageNames: userScript.messageNames
            )
        }
    }
}

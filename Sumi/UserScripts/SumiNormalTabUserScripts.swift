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
    private let backgroundVideoOptimizationUserScript = SumiBackgroundVideoOptimizationUserScript()
    private let backgroundVideoOptimizationSubframeStubUserScript =
        SumiBackgroundVideoOptimizationSubframeStubUserScript()
    private var contentBlockingUserScripts: [SumiPageScript]
    private var managedUserScripts: [SumiPageScript]
    private var managedUserScriptSignature: [UserScriptSignature]
    private var cachedUserScripts: [SumiPageScript]?
    private(set) var scriptsRevision = 0

    init(
        contentBlockingUserScripts: [SumiPageScript] = [],
        managedUserScripts: [SumiPageScript] = []
    ) {
        self.contentBlockingUserScripts = contentBlockingUserScripts
        self.managedUserScripts = managedUserScripts
        self.managedUserScriptSignature = Self.signature(for: managedUserScripts)
    }

    var userScripts: [SumiPageScript] {
        if let cachedUserScripts {
            return cachedUserScripts
        }

        let scripts = [transientChromeInteractionShieldUserScript]
            + [backgroundVideoOptimizationUserScript]
            + [backgroundVideoOptimizationSubframeStubUserScript]
            + contentBlockingUserScripts
            + faviconScripts.userScripts
            + managedUserScripts
        cachedUserScripts = scripts
        return scripts
    }

    func replaceManagedUserScripts(_ userScripts: [SumiPageScript]) {
        managedUserScripts = userScripts
        managedUserScriptSignature = Self.signature(for: userScripts)
        cachedUserScripts = nil
        scriptsRevision += 1
    }

    @discardableResult
    func replaceManagedUserScriptsIfChanged(_ userScripts: [SumiPageScript]) -> Bool {
        let signature = Self.signature(for: userScripts)
        guard signature != managedUserScriptSignature else {
            return false
        }

        managedUserScripts = userScripts
        managedUserScriptSignature = signature
        cachedUserScripts = nil
        scriptsRevision += 1
        return true
    }

    func loadWKUserScripts() async -> [WKUserScript] {
        let scriptsToLoad = userScripts
        var scripts: [WKUserScript] = []
        scripts.reserveCapacity(scriptsToLoad.count)
        for userScript in scriptsToLoad {
            scripts.append(SumiPageScriptBuilder.makeWKUserScript(from: userScript))
        }
        return scripts
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

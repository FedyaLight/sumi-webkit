import WebKit

@MainActor
final class SumiNormalTabUserScripts: SumiUserScriptsProvider {
    private struct UserScriptSignature: Equatable {
        let typeName: String
        let source: String
        let injectionTime: WKUserScriptInjectionTime
        let forMainFrameOnly: Bool
        let requiresRunInPageContentWorld: Bool
        let messageNames: [String]
    }

    let faviconScripts = SumiDDGFaviconUserScripts()
    private let transientChromeInteractionShieldUserScript = SumiTransientChromeInteractionShieldUserScript()
    private var contentBlockingUserScripts: [SumiUserScript]
    private var managedUserScripts: [SumiUserScript]
    private var managedUserScriptSignature: [UserScriptSignature]
    private(set) var scriptsRevision = 0

    init(
        contentBlockingUserScripts: [SumiUserScript] = [],
        managedUserScripts: [SumiUserScript] = []
    ) {
        self.contentBlockingUserScripts = contentBlockingUserScripts
        self.managedUserScripts = managedUserScripts
        self.managedUserScriptSignature = Self.signature(for: managedUserScripts)
    }

    var userScripts: [SumiUserScript] {
        [transientChromeInteractionShieldUserScript] + contentBlockingUserScripts + faviconScripts.userScripts + managedUserScripts
    }

    func replaceManagedUserScripts(_ userScripts: [SumiUserScript]) {
        managedUserScripts = userScripts
        managedUserScriptSignature = Self.signature(for: userScripts)
        scriptsRevision += 1
    }

    @discardableResult
    func replaceManagedUserScriptsIfChanged(_ userScripts: [SumiUserScript]) -> Bool {
        let signature = Self.signature(for: userScripts)
        guard signature != managedUserScriptSignature else {
            return false
        }

        managedUserScripts = userScripts
        managedUserScriptSignature = signature
        scriptsRevision += 1
        return true
    }

    func loadWKUserScripts() async -> [WKUserScript] {
        var scripts: [WKUserScript] = []
        scripts.reserveCapacity(userScripts.count)
        for userScript in userScripts {
            scripts.append(SumiUserScriptBuilder.makeWKUserScript(from: userScript))
        }
        return scripts
    }

    private static func signature(for userScripts: [SumiUserScript]) -> [UserScriptSignature] {
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
